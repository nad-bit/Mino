import Foundation
import AppKit

public struct RateLimitInfo: Equatable {
    public let limit: Int
    public let remaining: Int
    public let resetDate: Date
    public let hasToken: Bool
    
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
    private(set) var session: URLSession
    
    // MARK: - Rate Limit Tracking
    private(set) var currentRateLimit: RateLimitInfo?
    
    func recordRateLimit(from response: HTTPURLResponse) {
        guard let limitStr = response.value(forHTTPHeaderField: "x-ratelimit-limit"), let limit = Int(limitStr),
              let remainingStr = response.value(forHTTPHeaderField: "x-ratelimit-remaining"), let remaining = Int(remainingStr),
              let resetStr = response.value(forHTTPHeaderField: "x-ratelimit-reset"), let resetEpoch = Double(resetStr) else {
            return
        }
        let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasToken = token != nil && !token!.isEmpty
        let info = RateLimitInfo(limit: limit, remaining: remaining, resetDate: Date(timeIntervalSince1970: resetEpoch), hasToken: hasToken)
        self.currentRateLimit = info
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("RateLimitUpdated"), object: info)
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
        let hash = abs(urlString.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) })
        let rawExt = (urlString as NSString).pathExtension.lowercased()
        let cleanExt = rawExt.components(separatedBy: "?").first ?? ""
        let ext = (cleanExt.isEmpty || cleanExt.count > 4) ? "png" : cleanExt
        let safeName = "\(hash).\(ext)"
        return dir.appendingPathComponent(safeName)
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
    
    /// Synchronously returns local disk cache file URL if cached, nil otherwise.
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
    /// Also supports vector image formats (SVG) with payload size guards.
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
        // Limit raw payload size to 2 MB for vector/XML data to prevent XML entity expansion or excessive parsing.
        if data.count <= 2 * 1024 * 1024,
           let image = NSImage(data: data) {
            let width = image.size.width
            let height = image.size.height
            if width > 0, height > 0,
               width <= maxPixelDimension,
               height <= maxPixelDimension,
               (width * height) <= maxPixelArea {
                return image
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
        if let localURL = await fetchLocalImageURL(from: urlString),
           let data = try? Data(contentsOf: localURL) {
            return GitHubAPI.safeDecodeImage(from: data)
        }
        return nil
    }
    
    private init() {
        self.session = URLSession(configuration: GitHubAPI.makeConfiguration())
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
        session.finishTasksAndInvalidate()
        session = URLSession(configuration: GitHubAPI.makeConfiguration())
        pruneDiskCacheIfNeeded()
    }
    
    /// Generic data fetch for non-GitHub API calls (e.g. Homebrew formulae API).
    /// Routes through the same cache-disabled session.
    func data(from url: URL) async throws -> (Data, URLResponse) {
        return try await session.data(from: url)
    }
    
    func fetchRepoInfo(repo: String, hasExistingRelease: Bool = false) async -> RepoInfo {
        var requestHeaders: [String: String] = [:]
        
        if let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            requestHeaders["Authorization"] = "Bearer \(token)"
        }
        
        do {
            // Try Releases first
            let releaseData = try await fetchRelease(repo: repo, headers: requestHeaders)
            return releaseData
        } catch let releaseError as NSError {
            // If a 404 occurs and we already had a valid release version cached,
            // don’t fall back to commits — the 404 may be a false negative from the
            // unauthenticated API (e.g. org repos). Return the error instead so the
            // existing cache entry is preserved by triggerFullRefresh.
            if releaseError.code == 404 && hasExistingRelease {
                return RepoInfo(name: repo, error: releaseError.localizedDescription)
            }
            
            do {
                // Try Commits fallback
                let commitData = try await fetchCommits(repo: repo, headers: requestHeaders)
                return commitData
            } catch let commitError {
                // If both fail, return the descriptive localized error message
                return RepoInfo(name: repo, error: commitError.localizedDescription)
            }
        }
    }
    
    private func fetchRelease(repo: String, headers: [String: String]) async throws -> RepoInfo {
        guard let url = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)/releases/latest") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        recordRateLimit(from: httpResponse)
        
        if httpResponse.statusCode == 404 {
            throw NSError(domain: "GitHubAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiRepoNotFound")])
        } else if httpResponse.statusCode == 403 {
            throw parse403Error(response: httpResponse, data: data)
        } else if httpResponse.statusCode == 429 {
            throw NSError(domain: "GitHubAPI", code: 429, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiTooManyRequests")])
        } else if httpResponse.statusCode != 200 {
            let msg = Translations.get("apiHttpError").format(with: ["code": "\(httpResponse.statusCode)"])
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let version = json?["tag_name"] as? String
        let date = json?["published_at"] as? String
        let body = json?["body"] as? String
        let assets = json != nil ? GitHubAPI.parseReleaseAssets(from: json!, repo: repo, tag: version) : nil
        
        if version != nil && date != nil {
            return RepoInfo(name: repo, version: version, date: date, body: body, assets: assets)
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
    
    static func parseReleaseAssets(from json: [String: Any], repo: String, tag: String?) -> [ReleaseAsset] {
        var result: [ReleaseAsset] = []
        
        // 1. User-uploaded release assets
        if let assetsArray = json["assets"] as? [[String: Any]] {
            for assetDict in assetsArray {
                guard let name = assetDict["name"] as? String,
                      let downloadURL = assetDict["browser_download_url"] as? String else { continue }
                let size = assetDict["size"] as? Int64
                result.append(ReleaseAsset(name: name, size: size, downloadURL: downloadURL, isSourceArchive: false))
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
    
    private func fetchCommits(repo: String, headers: [String: String]) async throws -> RepoInfo {
        guard let url = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)/commits?per_page=1") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        recordRateLimit(from: httpResponse)
        
        if httpResponse.statusCode == 404 {
            throw NSError(domain: "GitHubAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiRepoNotFound")])
        } else if httpResponse.statusCode == 403 {
            throw parse403Error(response: httpResponse, data: data)
        } else if httpResponse.statusCode == 429 {
            throw NSError(domain: "GitHubAPI", code: 429, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiTooManyRequests")])
        } else if httpResponse.statusCode != 200 {
            let msg = Translations.get("apiHttpError").format(with: ["code": "\(httpResponse.statusCode)"])
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
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
                    recordRateLimit(from: httpResponse)
                    
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
                recordRateLimit(from: httpResponse)
                
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
        if let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        
        if let tag = version {
            let endpoint = "\(Constants.githubAPIBaseURL)/repos/\(repo)/releases/tags/\(tag)"
            if let url = URL(string: endpoint) {
                var request = URLRequest(url: url)
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
                
                if let (data, response) = try? await session.data(for: request),
                   let httpResponse = response as? HTTPURLResponse {
                    recordRateLimit(from: httpResponse)
                    
                    if httpResponse.statusCode == 403 {
                        return (parse403Error(response: httpResponse, data: data).localizedDescription, nil)
                    } else if httpResponse.statusCode == 429 {
                        return (Translations.get("apiTooManyRequests"), nil)
                    }
                    
                    if httpResponse.statusCode == 200,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let assets = GitHubAPI.parseReleaseAssets(from: json, repo: repo, tag: tag)
                        let rawBody = json["body_html"] as? String ?? json["body"] as? String
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
    
    /// Downloads a release asset to destinationURL reporting progress callbacks (bytesReceived, totalBytes).
    func downloadAsset(urlString: String, destinationURL: URL, progress: @escaping (Int64, Int64) -> Void) async throws {
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
        
        // Dedicated session with generous timeouts for large file downloads
        let dlConfig = URLSessionConfiguration.default
        dlConfig.timeoutIntervalForRequest = 300
        dlConfig.timeoutIntervalForResource = 3600
        dlConfig.httpAdditionalHeaders = ["User-Agent": Constants.userAgent]
        let dlSession = URLSession(configuration: dlConfig)
        defer { dlSession.finishTasksAndInvalidate() }
        
        let (bytes, response) = try await dlSession.bytes(for: request)
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
        
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= bufferSize {
                handle.write(buffer)
                receivedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(receivedBytes, totalBytes)
            }
        }
        
        // Flush remaining bytes
        if !buffer.isEmpty {
            handle.write(buffer)
            receivedBytes += Int64(buffer.count)
        }
        
        try handle.close()
        progress(receivedBytes, totalBytes > 0 ? totalBytes : receivedBytes)
        
        try fileManager.moveItem(at: tempURL, to: destinationURL)
    }
    
    func validateToken(_ token: String) async -> Bool {
        guard !token.isEmpty else { return true }
        
        guard let url = URL(string: "\(Constants.githubAPIBaseURL)/user") else { return false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
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
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let topics = json?["topics"] as? [String]
                let description = json?["description"] as? String
                return (topics, description)
            }
        } catch {
            print("Failed to fetch topics for \(repo): \(error)")
        }
        return (nil, nil)
    }
}
