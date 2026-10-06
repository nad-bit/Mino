import Foundation
import AppKit
import CryptoKit

public struct RateLimitInfo: Equatable {
    public let limit: Int
    public let remaining: Int
    public let resetDate: Date
    public let hasToken: Bool
    
    public var currentRemaining: Int {
        if Date() >= resetDate {
            return limit
        }
        return remaining
    }
    
    public init(limit: Int, remaining: Int, resetDate: Date, hasToken: Bool) {
        self.limit = limit
        self.remaining = remaining
        self.resetDate = resetDate
        self.hasToken = hasToken
    }
}

class GitHubAPI {
    static let shared = GitHubAPI()
    /// Shared across the module so GitHubAuth and RepoCoordinator
    /// reuse the same cache-disabled, timeout-configured session
    /// instead of falling back to URLSession.shared.
    private let sessionLock = NSLock()
    private var _session: URLSession
    
    var session: URLSession {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return _session
    }
    
    // MARK: - Rate Limit Tracking
    private let rateLimitLock = NSLock()
    private var windowRateLimits: [Date: RateLimitInfo] = [:]
    private var latestObservedRateLimit: RateLimitInfo?
    
    // MARK: - Conditional Requests (ETag) Cache
    private let etagLock = NSLock()
    private var etagsByRepo: [String: String] = [:]
    
    func etag(for key: String) -> String? {
        etagLock.lock()
        defer { etagLock.unlock() }
        return etagsByRepo[key]
    }
    
    func setETag(_ etag: String?, for key: String) {
        etagLock.lock()
        defer { etagLock.unlock() }
        if let etag = etag {
            etagsByRepo[key] = etag
        } else {
            etagsByRepo.removeValue(forKey: key)
        }
    }
    
    func allETags() -> [String: String] {
        etagLock.lock()
        defer { etagLock.unlock() }
        return etagsByRepo
    }
    
    func loadETags(_ etags: [String: String]) {
        etagLock.lock()
        defer { etagLock.unlock() }
        etagsByRepo = etags
    }
    
    func clearETags() {
        etagLock.lock()
        defer { etagLock.unlock() }
        etagsByRepo.removeAll()
        ConfigManager.shared.clearDiskCache()
    }
    
    func clearRateLimits() {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        windowRateLimits.removeAll()
        latestObservedRateLimit = nil
        clearETags()
    }
    
    var currentRateLimit: RateLimitInfo? {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        let now = Date()
        let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasToken = token != nil && !token!.isEmpty
        
        // Clean expired windows AND windows from a mismatched auth state (e.g. 60 vs 5000)
        windowRateLimits = windowRateLimits.filter { (resetDate, info) in
            resetDate > now && info.hasToken == hasToken
        }
        
        // Return the most constrained active sample matching current auth state, or latest matching sample
        if let active = windowRateLimits.values.min(by: { $0.remaining < $1.remaining }) {
            return active
        }
        if let latest = latestObservedRateLimit, latest.hasToken == hasToken {
            return latest
        }
        return nil
    }
    
    func recordRateLimit(from response: HTTPURLResponse, wasAuthenticated: Bool? = nil) {
        // Discard 401 Unauthorized responses so rejected tokens never poison rate limit views
        if response.statusCode == 401 { return }
        
        guard let limitStr = response.value(forHTTPHeaderField: "x-ratelimit-limit"), let limit = Int(limitStr),
              let remainingStr = response.value(forHTTPHeaderField: "x-ratelimit-remaining"), let remaining = Int(remainingStr),
              let resetStr = response.value(forHTTPHeaderField: "x-ratelimit-reset"), let resetEpoch = Double(resetStr) else {
            return
        }
        let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTokenConfigured = token != nil && !token!.isEmpty
        
        // Genuine GitHub authenticated REST rate limits are strictly > 60 (standard 5,000 or 15,000).
        // Responses with limit <= 60 represent the unauthenticated public IP pool.
        let isAuthResponse = (limit > 60) && (wasAuthenticated ?? true)
        
        // If the response authentication status doesn't match current configuration,
        // ignore it so public requests don't corrupt authenticated views or vice versa.
        if hasTokenConfigured != isAuthResponse {
            return
        }
        
        let resetDate = Date(timeIntervalSince1970: resetEpoch)
        let info = RateLimitInfo(limit: limit, remaining: remaining, resetDate: resetDate, hasToken: isAuthResponse)
        
        rateLimitLock.lock()
        let now = Date()
        // Purge expired or mismatched samples
        windowRateLimits = windowRateLimits.filter { $0.key > now && $0.value.hasToken == isAuthResponse }
        
        latestObservedRateLimit = info
        if resetDate > now {
            if let existing = windowRateLimits[resetDate] {
                // The lower remaining count always reflects actual consumption within the same window
                if remaining < existing.remaining {
                    windowRateLimits[resetDate] = info
                }
            } else {
                windowRateLimits[resetDate] = info
            }
        }
        let currentBest = windowRateLimits.values.min(by: { $0.remaining < $1.remaining }) ?? info
        rateLimitLock.unlock()
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("RateLimitUpdated"), object: currentBest)
        }
    }
    
    func parse403Error(response: HTTPURLResponse, data: Data) -> NSError {
        // 1. Primary rate limit: x-ratelimit-remaining is explicitly 0
        if let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining"), remaining == "0" {
            return NSError(domain: "GitHubAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiRateLimit")])
        }
        
        // 2. Otherwise inspect GitHub's JSON error payload
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String {
            let lower = message.lowercased()
            if lower.contains("secondary rate limit") {
                return NSError(domain: "GitHubAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiSecondaryRateLimit")])
            } else if lower.contains("saml") {
                return NSError(domain: "GitHubAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "SAML SSO: " + Translations.get("apiForbidden")])
            }
        }
        
        // 3. Fallback for repository-level access denied / permission / private
        return NSError(domain: "GitHubAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiForbidden")])
    }
    
    // MARK: - Image Cache & Fetching
    
    private let ramImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 30
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB RAM limit
        return cache
    }()
    
    private var diskCacheDirectory: URL? = {
        let fileManager = FileManager.default
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let releaseImagesDir = cacheDir.appendingPathComponent("com.nad.mino/ReleaseImages", isDirectory: true)
            try? fileManager.createDirectory(at: releaseImagesDir, withIntermediateDirectories: true)
            return releaseImagesDir
        }
        return nil
    }()
    
    private func diskCacheURL(for urlString: String) -> URL? {
        guard let dir = diskCacheDirectory else { return nil }
        let hash = SHA256.hash(data: Data(urlString.utf8)).map { String(format: "%02x", $0) }.joined()
        let rawExt = (urlString as NSString).pathExtension.lowercased()
        let cleanExt = rawExt.components(separatedBy: "?").first ?? ""
        let ext = (cleanExt.isEmpty || cleanExt.count > 4) ? "png" : cleanExt
        let safeName = "\(hash).\(ext)"
        return dir.appendingPathComponent(safeName)
    }
    
    /// Checks ONLY the in-memory RAM cache (instant, zero I/O, safe for MainActor).
    func getRAMCachedImage(from urlString: String) -> NSImage? {
        let key = urlString as NSString
        return ramImageCache.object(forKey: key)
    }
    
    /// Synchronously checks RAM and Disk cache for an image.
    /// Returns the NSImage if cached, or nil if network download is required.
    func getCachedImage(from urlString: String) -> NSImage? {
        let key = urlString as NSString
        if let cached = ramImageCache.object(forKey: key) {
            return cached
        }
        if let fileURL = diskCacheURL(for: urlString),
           let data = try? Data(contentsOf: fileURL),
           let image = GitHubAPI.safeDecodeImage(from: data) {
            let cost = Int(image.size.width * image.size.height * 4)
            ramImageCache.setObject(image, forKey: key, cost: cost)
            return image
        }
        return nil
    }
    
    /// Synchronously returns local disk cache file URL if cached on disk, nil otherwise.
    /// Fast file existence check (metadata only) without reading or decoding image bytes.
    func getCachedLocalImageURL(from urlString: String) -> URL? {
        guard let fileURL = diskCacheURL(for: urlString),
              FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }
    
    /// Strict exact allowlist for hosts eligible to receive sensitive tokens.
    /// Eliminates wildcard trusts (*.github.com / *.githubusercontent.com) for defense-in-depth.
    static let exactTrustedHosts: Set<String> = [
        "api.github.com",
        "github.com",
        "raw.githubusercontent.com"
    ]
    
    /// Validates whether a host is strictly in the trusted GitHub host allowlist.
    static func isTrustedGitHubHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return exactTrustedHosts.contains(host)
    }
    
    /// Safely inspects image dimensions and pixels via CGImageSource before full bitmap allocation
    /// to prevent decompression bomb memory spikes. Enforces max dimension <= 4096px and max pixels <= 16 MP.
    /// Also supports vector image formats (SVG) with payload size guards and PDF bounding checks across all pages.
    static func safeDecodeImage(from data: Data, maxPixelDimension: CGFloat = 4096, maxPixelArea: CGFloat = 16_777_216) -> NSImage? {
        // 1. Check raster image formats (PNG, JPEG, GIF, TIFF, WebP) via CGImageSource
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let width = properties[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
            
            guard width > 0, height > 0,
                  width <= maxPixelDimension,
                  height <= maxPixelDimension,
                  (width * height) <= maxPixelArea else {
                return nil
            }
            return NSImage(data: data)
        }
        
        // 2. Check vector formats (SVG, PDF) natively decodable by NSImage.
        // Limit raw payload size to 2 MB for vector/XML data.
        if data.count <= 2 * 1024 * 1024 {
            // Guard: Scan XML/SVG data for dangerous entity expansion or external doctype across the entire payload
            if let fullText = String(data: data, encoding: .utf8)?.lowercased() {
                if fullText.contains("<!entity") || (fullText.contains("<!doctype") && fullText.contains("system")) {
                    return nil
                }
            }
            
            // For PDF data, inspect page count and bounding boxes of all pages before rendering
            if data.starts(with: [0x25, 0x50, 0x44, 0x46]) /* %PDF */ {
                guard let provider = CGDataProvider(data: data as CFData),
                      let pdfDoc = CGPDFDocument(provider) else {
                    return nil
                }
                let pageCount = pdfDoc.numberOfPages
                // Limit page count for vector icons/badges to prevent multi-page resource exhaustion
                guard pageCount > 0 && pageCount <= 10 else {
                    return nil
                }
                for pageNum in 1...pageCount {
                    guard let page = pdfDoc.page(at: pageNum) else { return nil }
                    let box = page.getBoxRect(.mediaBox)
                    guard box.width > 0, box.height > 0,
                          box.width <= maxPixelDimension,
                          box.height <= maxPixelDimension,
                          (box.width * box.height) <= maxPixelArea else {
                        return nil
                    }
                }
            }
            
            if let image = NSImage(data: data) {
                let width = image.size.width
                let height = image.size.height
                if width > 0, height > 0,
                   width <= maxPixelDimension,
                   height <= maxPixelDimension,
                   (width * height) <= maxPixelArea {
                    return image
                }
            }
        }
        
        return nil
    }
    
    /// Calculates the total disk space occupied by the image cache in bytes.
    func getDiskCacheSize() -> Int64 {
        guard let dir = diskCacheDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    /// Clears all in-memory and on-disk cached images.
    func clearDiskAndMemoryCache() {
        ramImageCache.removeAllObjects()
        guard let dir = diskCacheDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return
        }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
    
    /// Prunes the disk image cache to stay within limits (max total size 150 MB and max age 30 days).
    /// Evicts oldest accessed/modified files first (LRU).
    func pruneDiskCacheIfNeeded() {
        guard let dir = diskCacheDirectory else { return }
        Task.detached(priority: .background) {
            let fileManager = FileManager.default
            let maxCacheSizeBytes: Int64 = 150 * 1024 * 1024 // 150 MB
            let maxAgeSeconds: TimeInterval = 30 * 86400 // 30 days
            let expirationDate = Date().addingTimeInterval(-maxAgeSeconds)
            
            let resourceKeys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .contentAccessDateKey]
            guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: resourceKeys, options: .skipsHiddenFiles) else {
                return
            }
            
            struct CachedFileInfo {
                let url: URL
                let size: Int64
                let lastAccessDate: Date
            }
            
            var fileInfos: [CachedFileInfo] = []
            var totalSize: Int64 = 0
            
            for fileURL in files {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                      let size = resourceValues.fileSize else { continue }
                
                let date = resourceValues.contentAccessDate ?? resourceValues.contentModificationDate ?? Date.distantPast
                let fileSize = Int64(size)
                
                // Immediately delete files older than 30 days
                if date < expirationDate {
                    try? fileManager.removeItem(at: fileURL)
                    continue
                }
                
                totalSize += fileSize
                fileInfos.append(CachedFileInfo(url: fileURL, size: fileSize, lastAccessDate: date))
            }
            
            // If total cache size exceeds quota, sort oldest first and delete until under 80% of limit
            if totalSize > maxCacheSizeBytes {
                let targetSize = Int64(Double(maxCacheSizeBytes) * 0.8)
                fileInfos.sort { $0.lastAccessDate < $1.lastAccessDate }
                
                for info in fileInfos {
                    if totalSize <= targetSize { break }
                    try? fileManager.removeItem(at: info.url)
                    totalSize -= info.size
                }
            }
        }
    }
    
    /// Fetches an image (with authentication) and saves it to local disk cache,
    /// returning the file:// URL so WebKit/Cocoa HTML parsers can render it natively from disk.
    func fetchLocalImageURL(from urlString: String) async -> URL? {
        let key = urlString as NSString
        guard let fileURL = diskCacheURL(for: urlString) else { return nil }
        
        // 1. If file already exists on disk and is a valid image
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let image = GitHubAPI.safeDecodeImage(from: data) {
            let cost = Int(image.size.width * image.size.height * 4)
            ramImageCache.setObject(image, forKey: key, cost: cost)
            return fileURL
        }
        
        // 2. Download asynchronously. Remote images are public CDN assets and must NOT receive Authorization headers.
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            // Limit image size to 10 MB and validate dimensions to prevent decompression bombs
            let maxImageBytes = 10 * 1024 * 1024
            guard data.count <= maxImageBytes,
                  let image = GitHubAPI.safeDecodeImage(from: data) else {
                return nil
            }
            
            // Save to Disk cache
            try? data.write(to: fileURL, options: .atomic)
            
            // Save to RAM cache
            let cost = Int(image.size.width * image.size.height * 4)
            ramImageCache.setObject(image, forKey: key, cost: cost)
            
            return fileURL
        } catch {
            return nil
        }
    }
    
    /// Fetches an image asynchronously leveraging a 2-tier cache (RAM NSCache + Disk Cache).
    func fetchImage(from urlString: String) async -> NSImage? {
        let key = urlString as NSString
        if let cached = ramImageCache.object(forKey: key) {
            return cached
        }
        if let _ = await fetchLocalImageURL(from: urlString) {
            return ramImageCache.object(forKey: key)
        }
        return nil
    }
    
    private init() {
        self._session = URLSession(configuration: GitHubAPI.makeConfiguration())
        self.pruneDiskCacheIfNeeded()
    }
    
    private static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.httpRequestTimeoutSeconds
        config.timeoutIntervalForResource = Constants.httpRequestTimeoutSeconds
        config.httpAdditionalHeaders = ["User-Agent": Constants.userAgent]
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }
    
    /// Invalidates the current session (releasing keep-alive connection pools,
    /// TLS session tickets, and internal credential caches accumulated over
    /// multiple refresh cycles) and creates a fresh replacement.
    func resetSession() {
        sessionLock.lock()
        let oldSession = _session
        _session = URLSession(configuration: GitHubAPI.makeConfiguration())
        sessionLock.unlock()
        oldSession.finishTasksAndInvalidate()
        pruneDiskCacheIfNeeded()
    }
    
    /// Generic data fetch for non-GitHub API calls (e.g. Homebrew formulae API).
    /// Routes through the same cache-disabled session.
    func data(from url: URL) async throws -> (Data, URLResponse) {
        return try await session.data(from: url)
    }
    
    func fetchRepoInfo(repo: String, hasExistingRelease: Bool = false, hasExistingCommit: Bool = false, checkETag: Bool = true) async -> RepoInfo {
        var requestHeaders: [String: String] = [:]
        
        if let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            requestHeaders["Authorization"] = "Bearer \(token)"
        }
        
        // ETag conditional request is ONLY valid if caller has existing cached release/commit data to merge with.
        // If neither exists (e.g. newly added repository or unpopulated cache),
        // we MUST fetch the full payload (checkETag = false) so version, assets, and body are populated.
        let shouldCheckReleaseETag = checkETag && hasExistingRelease
        let shouldCheckCommitETag = checkETag && hasExistingCommit
        
        do {
            // Try Releases first
            let releaseData = try await fetchRelease(repo: repo, headers: requestHeaders, checkETag: shouldCheckReleaseETag)
            return releaseData
        } catch let releaseError as NSError {
            // If a 404 occurs and we already had a valid release version cached,
            // don’t fall back to commits — the 404 may be a false negative from the
            // unauthenticated API (e.g. org repos). Return the error instead so the
            // existing cache entry is preserved by triggerFullRefresh.
            if releaseError.code == 404 && hasExistingRelease {
                return RepoInfo(name: repo, error: releaseError.localizedDescription, errorCode: releaseError.code)
            }
            
            // Only fall back to commits if the release wasn't found (404)
            // (i.e. the repo exists but hasn't published formal releases).
            // For other HTTP errors (401, 403, 429, 5xx) or network errors,
            // commits fetch would fail identically and waste rate limit.
            if releaseError.code != 404 {
                return RepoInfo(name: repo, error: releaseError.localizedDescription, errorCode: releaseError.code)
            }
            
            do {
                // Try Commits fallback with conditional ETag check if we have existing commit data
                let commitData = try await fetchCommits(repo: repo, headers: requestHeaders, checkETag: shouldCheckCommitETag)
                return commitData
            } catch let commitError as NSError {
                // If both fail, return the descriptive localized error message and original code
                return RepoInfo(name: repo, error: commitError.localizedDescription, errorCode: commitError.code)
            } catch {
                return RepoInfo(name: repo, error: error.localizedDescription, errorCode: (error as NSError).code)
            }
        }
    }
    
    private func fetchRelease(repo: String, headers: [String: String], checkETag: Bool = true) async throws -> RepoInfo {
        guard let url = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)/releases/latest") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        if checkETag, let etag = etag(for: repo) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let wasAuth = headers["Authorization"] != nil
        recordRateLimit(from: httpResponse, wasAuthenticated: wasAuth)
        
        if httpResponse.statusCode == 304 {
            if !checkETag {
                // If 304 was unexpectedly returned without checkETag, clear ETag and retry cleanly
                setETag(nil, for: repo)
                return try await fetchRelease(repo: repo, headers: headers, checkETag: false)
            }
            var notModifiedInfo = RepoInfo(name: repo)
            notModifiedInfo.isNotModified = true
            return notModifiedInfo
        }
        
        if httpResponse.statusCode == 404 {
            setETag(nil, for: repo)
            throw NSError(domain: "GitHubAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiRepoNotFound")])
        } else if httpResponse.statusCode == 403 {
            throw parse403Error(response: httpResponse, data: data)
        } else if httpResponse.statusCode == 429 {
            throw NSError(domain: "GitHubAPI", code: 429, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiTooManyRequests")])
        } else if httpResponse.statusCode != 200 {
            let msg = Translations.get("apiHttpError").format(with: ["code": "\(httpResponse.statusCode)"])
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
            setETag(etag, for: repo)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let version = json?["tag_name"] as? String
        let date = json?["published_at"] as? String
        let body = json?["body"] as? String
        let assets = json != nil ? GitHubAPI.parseReleaseAssets(from: json!, repo: repo, tag: version, releaseBody: body) : nil
        
        if version != nil && date != nil {
            return RepoInfo(name: repo, version: version, date: date, body: body, assets: assets)
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
    
    /// Validates and extracts a canonical 64-character SHA-256 hex digest from a GitHub asset digest string.
    /// Supports GitHub digest formats (e.g. "sha256:<hex>" or bare 64-char hex string).
    static func parseDigest(_ rawDigest: String?) -> String? {
        guard let raw = rawDigest?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        var candidate = raw
        if candidate.lowercased().hasPrefix("sha256:") {
            candidate = String(candidate.dropFirst("sha256:".count))
        } else if candidate.lowercased().hasPrefix("sha-256:") {
            candidate = String(candidate.dropFirst("sha-256:".count))
        }
        candidate = candidate.lowercased()
        if candidate.count == 64 && candidate.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil {
            return candidate
        }
        return nil
    }
    
    static func parseReleaseAssets(from json: [String: Any], repo: String, tag: String?, releaseBody: String? = nil) -> [ReleaseAsset] {
        var result: [ReleaseAsset] = []
        let bodyText = releaseBody ?? json["body"] as? String ?? ""
        let checksums = Utils.extractChecksums(from: bodyText)
        
        // 1. User-uploaded release assets
        if let assetsArray = json["assets"] as? [[String: Any]] {
            for assetDict in assetsArray {
                guard let name = assetDict["name"] as? String,
                      let downloadURL = assetDict["browser_download_url"] as? String else { continue }
                let size = assetDict["size"] as? Int64
                
                // Priority 1: GitHub official asset digest (e.g. "sha256:4f3b...")
                let officialSHA = GitHubAPI.parseDigest(assetDict["digest"] as? String)
                // Priority 2: Release notes body checksum fallback
                let expectedSHA = officialSHA ?? checksums[name.lowercased()]
                
                result.append(ReleaseAsset(name: name, size: size, downloadURL: downloadURL, isSourceArchive: false, expectedSHA256: expectedSHA))
            }
        }
        
        // 2. GitHub auto-generated Source Code archives (zip & tar.gz)
        let tagOrHead = tag ?? json["tag_name"] as? String ?? "HEAD"
        let zipURL = json["zipball_url"] as? String ?? "https://github.com/\(repo)/archive/refs/tags/\(tagOrHead).zip"
        let tarURL = json["tarball_url"] as? String ?? "https://github.com/\(repo)/archive/refs/tags/\(tagOrHead).tar.gz"
        
        result.append(ReleaseAsset(name: "Source code (zip)", size: nil, downloadURL: zipURL, isSourceArchive: true))
        result.append(ReleaseAsset(name: "Source code (tar.gz)", size: nil, downloadURL: tarURL, isSourceArchive: true))
        
        return result
    }
    
    private func fetchCommits(repo: String, headers: [String: String], checkETag: Bool = true) async throws -> RepoInfo {
        guard let url = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)/commits?per_page=1") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let commitsETagKey = "\(repo)#commits"
        if checkETag, let etag = etag(for: commitsETagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let wasAuth = headers["Authorization"] != nil
        recordRateLimit(from: httpResponse, wasAuthenticated: wasAuth)
        
        if httpResponse.statusCode == 304 {
            if !checkETag {
                setETag(nil, for: commitsETagKey)
                return try await fetchCommits(repo: repo, headers: headers, checkETag: false)
            }
            var notModifiedInfo = RepoInfo(name: repo)
            notModifiedInfo.isNotModified = true
            return notModifiedInfo
        }
        
        if httpResponse.statusCode == 404 {
            setETag(nil, for: commitsETagKey)
            throw NSError(domain: "GitHubAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiRepoNotFound")])
        } else if httpResponse.statusCode == 403 {
            throw parse403Error(response: httpResponse, data: data)
        } else if httpResponse.statusCode == 429 {
            throw NSError(domain: "GitHubAPI", code: 429, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiTooManyRequests")])
        } else if httpResponse.statusCode != 200 {
            let msg = Translations.get("apiHttpError").format(with: ["code": "\(httpResponse.statusCode)"])
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
            setETag(etag, for: commitsETagKey)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let firstCommit = json?.first
        let sha = firstCommit?["sha"] as? String
        let shortVersion = sha != nil ? String(sha!.prefix(7)) : nil
        let commitObj = firstCommit?["commit"] as? [String: Any]
        let committer = commitObj?["committer"] as? [String: Any]
        let date = committer?["date"] as? String
        let commitMsg = commitObj?["message"] as? String
        
        if shortVersion != nil && date != nil {
            return RepoInfo(name: repo, version: shortVersion, date: date, body: commitMsg)
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
    
    /// Fetches the commit message associated with a tag.
    /// GitHub shows this on the release page when the release body is empty.
    /// Supports both lightweight tags (commit) and annotated tags (tag → commit).
    private func fetchTagCommitMessage(repo: String, tag: String, headers: [String: String]) async throws -> String? {
        // 1. Resolve the tag ref to get the object it points to
        guard let refURL = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)/git/ref/tags/\(tag)") else { return nil }
        var refRequest = URLRequest(url: refURL)
        headers.forEach { refRequest.setValue($1, forHTTPHeaderField: $0) }
        
        let (refData, refResponse) = try await session.data(for: refRequest)
        guard (refResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        let refJSON = try JSONSerialization.jsonObject(with: refData) as? [String: Any]
        guard let object = refJSON?["object"] as? [String: Any],
              let objectType = object["type"] as? String,
              let objectSHA = object["sha"] as? String else { return nil }
        
        // 2. If it's an annotated tag, dereference to get the commit SHA
        var commitSHA = objectSHA
        if objectType == "tag" {
            guard let tagURL = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)/git/tags/\(objectSHA)") else { return nil }
            var tagRequest = URLRequest(url: tagURL)
            headers.forEach { tagRequest.setValue($1, forHTTPHeaderField: $0) }
            
            let (tagData, tagResponse) = try await session.data(for: tagRequest)
            guard (tagResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            
            let tagJSON = try JSONSerialization.jsonObject(with: tagData) as? [String: Any]
            // Annotated tags may have their own message — prefer that
            if let tagMessage = tagJSON?["message"] as? String,
               !tagMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return tagMessage
            }
            // Otherwise dereference to the commit
            if let target = tagJSON?["object"] as? [String: Any],
               let targetSHA = target["sha"] as? String {
                commitSHA = targetSHA
            }
        }
        
        // 3. Fetch the commit and return its message
        guard let commitURL = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)/git/commits/\(commitSHA)") else { return nil }
        var commitRequest = URLRequest(url: commitURL)
        headers.forEach { commitRequest.setValue($1, forHTTPHeaderField: $0) }
        
        let (commitData, commitResponse) = try await session.data(for: commitRequest)
        guard (commitResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        let commitJSON = try JSONSerialization.jsonObject(with: commitData) as? [String: Any]
        let message = commitJSON?["message"] as? String
        
        // Only return if there's meaningful content
        guard let msg = message, !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return msg
    }
    
    /// Fetches the release notes body for a single repo on demand.
    /// Requests pre-rendered HTML from GitHub for rich formatting.
    /// When a version tag is provided, fetches the body for that specific release
    /// to ensure consistency with the version displayed in the menu.
    /// Returns the body text, an error message for display, or nil if no content found.
    func fetchReleaseBody(repo: String, version: String? = nil) async -> String? {
        var headers: [String: String] = [
            "Accept": "application/vnd.github.v3+json"
        ]
        if let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        
        // 1. Try the pinned version first (matches what the menu displays)
        if let tag = version {
            let endpoint = "\(Constants.githubAPIBaseURL)/repos/\(repo)/releases/tags/\(tag)"
            if let url = URL(string: endpoint) {
                var request = URLRequest(url: url)
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
                
                if let (data, response) = try? await session.data(for: request),
                   let httpResponse = response as? HTTPURLResponse {
                    let wasAuth = headers["Authorization"] != nil
                    recordRateLimit(from: httpResponse, wasAuthenticated: wasAuth)
                    
                    // Surface descriptive errors to the user
                    if httpResponse.statusCode == 403 {
                        return parse403Error(response: httpResponse, data: data).localizedDescription
                    } else if httpResponse.statusCode == 429 {
                        return Translations.get("apiTooManyRequests")
                    }
                    
                    if httpResponse.statusCode == 200,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        let rawBody = json["body_html"] as? String ?? json["body"] as? String
                        if let body = rawBody, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return body
                        }
                        
                        // GitHub shows the tag commit message when body is empty
                        if let tagName = json["tag_name"] as? String {
                            return try? await fetchTagCommitMessage(repo: repo, tag: tagName, headers: headers)
                        }
                    }
                }
            }
        }
        
        // 2. Fallback: fetch the latest commit message (for repos tracked by commit SHA)
        if let url = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)/commits?per_page=1") {
            var request = URLRequest(url: url)
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            
            if let (data, response) = try? await session.data(for: request),
               let httpResponse = response as? HTTPURLResponse {
                let wasAuth = headers["Authorization"] != nil
                recordRateLimit(from: httpResponse, wasAuthenticated: wasAuth)
                
                if httpResponse.statusCode == 403 {
                    return parse403Error(response: httpResponse, data: data).localizedDescription
                } else if httpResponse.statusCode == 429 {
                    return Translations.get("apiTooManyRequests")
                }
                
                if httpResponse.statusCode == 200,
                   let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstCommit = jsonArray.first,
                   let commitInfo = firstCommit["commit"] as? [String: Any],
                   let message = commitInfo["message"] as? String,
                   !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return message
                }
            }
        }
        
        return nil
    }
    
    /// Fetches release body AND parsed release assets in a single network request.
    func fetchReleaseDetails(repo: String, version: String? = nil) async -> (body: String?, assets: [ReleaseAsset]?) {
        var headers: [String: String] = [
            "Accept": "application/vnd.github.v3+json"
        ]
        var wasAuth = false
        if let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
            wasAuth = true
        }
        
        if let tag = version {
            let endpoint = "\(Constants.githubAPIBaseURL)/repos/\(repo)/releases/tags/\(tag)"
            if let url = URL(string: endpoint) {
                var request = URLRequest(url: url)
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
                
                if let (data, response) = try? await session.data(for: request),
                   let httpResponse = response as? HTTPURLResponse {
                    recordRateLimit(from: httpResponse, wasAuthenticated: wasAuth)
                    
                    if httpResponse.statusCode == 403 {
                        return (parse403Error(response: httpResponse, data: data).localizedDescription, nil)
                    } else if httpResponse.statusCode == 429 {
                        return (Translations.get("apiTooManyRequests"), nil)
                    }
                    
                    if httpResponse.statusCode == 200,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let rawBody = json["body_html"] as? String ?? json["body"] as? String
                        let assets = GitHubAPI.parseReleaseAssets(from: json, repo: repo, tag: tag, releaseBody: rawBody)
                        if let body = rawBody, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return (body, assets)
                        }
                        
                        if let tagName = json["tag_name"] as? String {
                            let msg = try? await fetchTagCommitMessage(repo: repo, tag: tagName, headers: headers)
                            return (msg, assets)
                        }
                        return (nil, assets)
                    }
                }
            }
        }
        
        let fallbackBody = await fetchReleaseBody(repo: repo, version: version)
        return (fallbackBody, nil)
    }
    
    /// Delegate enforcing defense-in-depth credential stripping on HTTP redirects.
    private final class SafeDownloadRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            var redirectedRequest = request
            if let host = request.url?.host?.lowercased(), !GitHubAPI.isTrustedGitHubHost(host) {
                // Strip Authorization header when redirected outside exact trusted hosts (e.g. AWS S3 CDN)
                redirectedRequest.setValue(nil, forHTTPHeaderField: "Authorization")
            }
            completionHandler(redirectedRequest)
        }
    }
    
    // MARK: - Dedicated Download Session
    private let downloadSessionLock = NSLock()
    private var _downloadSession: URLSession?
    private let downloadDelegate = SafeDownloadRedirectDelegate()
    
    private var downloadSession: URLSession {
        downloadSessionLock.lock()
        defer { downloadSessionLock.unlock() }
        if let session = _downloadSession {
            return session
        }
        let dlConfig = URLSessionConfiguration.default
        dlConfig.timeoutIntervalForRequest = 300
        dlConfig.timeoutIntervalForResource = 3600
        dlConfig.httpAdditionalHeaders = ["User-Agent": Constants.userAgent]
        let newSession = URLSession(configuration: dlConfig, delegate: downloadDelegate, delegateQueue: nil)
        _downloadSession = newSession
        return newSession
    }
    
    /// Downloads a release asset to destinationURL reporting progress callbacks (bytesReceived, totalBytes),
    /// while calculating its SHA-256 digest in real-time streaming mode and verifying integrity against expectedSHA256 if supplied.
    @discardableResult
    func downloadAsset(urlString: String, destinationURL: URL, expectedSHA256: String? = nil, progress: @escaping (Int64, Int64) -> Void) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
        
        if let host = url.host?.lowercased(),
           GitHubAPI.isTrustedGitHubHost(host),
           let token = ConfigManager.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (bytes, response) = try await downloadSession.bytes(for: request, delegate: downloadDelegate)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "DownloadError", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
        
        let totalBytes = httpResponse.expectedContentLength // -1 if unknown
        
        let fileManager = FileManager.default
        let parentDir = destinationURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        let tempURL = parentDir.appendingPathComponent(".download_\(UUID().uuidString).tmp")
        fileManager.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        
        defer {
            try? handle.close()
            if fileManager.fileExists(atPath: tempURL.path) {
                try? fileManager.removeItem(at: tempURL)
            }
        }
        
        var receivedBytes: Int64 = 0
        let bufferSize = 65_536
        var buffer = Data()
        buffer.reserveCapacity(bufferSize)
        var hasher = SHA256()
        
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= bufferSize {
                handle.write(buffer)
                hasher.update(data: buffer)
                receivedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(receivedBytes, totalBytes)
            }
        }
        
        // Flush remaining bytes
        if !buffer.isEmpty {
            handle.write(buffer)
            hasher.update(data: buffer)
            receivedBytes += Int64(buffer.count)
        }
        
        try handle.close()
        let computedDigest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        
        if let expected = expectedSHA256?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty {
            if computedDigest.lowercased() != expected {
                if fileManager.fileExists(atPath: tempURL.path) {
                    try? fileManager.removeItem(at: tempURL)
                }
                throw NSError(domain: "IntegrityError", code: -42, userInfo: [
                    NSLocalizedDescriptionKey: "SHA-256 integrity verification failed: expected \(expected), but got \(computedDigest)"
                ])
            }
        }
        
        progress(receivedBytes, totalBytes > 0 ? totalBytes : receivedBytes)
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        return computedDigest
    }
    
    func validateToken(_ token: String) async -> Bool {
        guard !token.isEmpty else { return true }
        
        guard let url = URL(string: "\(Constants.githubAPIBaseURL)/rate_limit") else { return false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            print("Token validation network error: \(error)")
        }
        return false
    }
    
    /// Fetches the repository's native topics (tags) and description from GitHub.
    /// Both fields come from the same `/repos/{owner}/{repo}` endpoint, so a
    /// single call populates hashtag filtering and the About line in Notes.
    func fetchRepoTags(repo: String) async -> (tags: [String]?, description: String?) {
        guard let url = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)") else { return (nil, nil) }
        var request = URLRequest(url: url)
        
        // Custom accept header was historically needed for topics, still recommended by GitHub API spec
        request.setValue("application/vnd.github.mercy-preview+json", forHTTPHeaderField: "Accept")
        if let token = ConfigManager.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let wasAuth = request.value(forHTTPHeaderField: "Authorization") != nil
                recordRateLimit(from: httpResponse, wasAuthenticated: wasAuth)
                if httpResponse.statusCode == 200 {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let topics = json?["topics"] as? [String]
                    let description = json?["description"] as? String
                    return (topics, description)
                }
            }
        } catch {
            print("Failed to fetch topics for \(repo): \(error)")
        }
        return (nil, nil)
    }
}
