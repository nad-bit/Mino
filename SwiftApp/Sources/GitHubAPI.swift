import Foundation

class GitHubAPI {
    static let shared = GitHubAPI()
    /// Shared across the module so GitHubAuth and RepoCoordinator
    /// reuse the same cache-disabled, timeout-configured session
    /// instead of falling back to URLSession.shared.
    private(set) var session: URLSession
    
    private init() {
        self.session = URLSession(configuration: GitHubAPI.makeConfiguration())
    }
    
    private static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.httpRequestTimeoutSeconds
        config.timeoutIntervalForResource = Constants.httpRequestTimeoutSeconds * 2
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
    }
    
    /// Generic data fetch for non-GitHub API calls (e.g. Homebrew formulae API).
    /// Routes through the same cache-disabled session.
    func data(from url: URL) async throws -> (Data, URLResponse) {
        return try await session.data(from: url)
    }
    
    func fetchRepoInfo(repo: String, hasExistingRelease: Bool = false) async -> RepoInfo {
        var requestHeaders: [String: String] = [:]
        
        if let token = ConfigManager.shared.token {
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
        
        if httpResponse.statusCode == 404 {
            throw NSError(domain: "GitHubAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiRepoNotFound")])
        } else if httpResponse.statusCode == 403 {
            throw NSError(domain: "GitHubAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiRateLimit")])
        } else if httpResponse.statusCode == 429 {
            throw NSError(domain: "GitHubAPI", code: 429, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiTooManyRequests")])
        } else if httpResponse.statusCode != 200 {
            let msg = Translations.get("apiHttpError").format(with: ["code": "\(httpResponse.statusCode)"])
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let version = json?["tag_name"] as? String
        let date = json?["published_at"] as? String
        
        if version != nil && date != nil {
            return RepoInfo(name: repo, version: version, date: date)
        } else {
            throw URLError(.cannotParseResponse)
        }
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
        
        if httpResponse.statusCode == 404 {
            throw NSError(domain: "GitHubAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiRepoNotFound")])
        } else if httpResponse.statusCode == 403 {
            throw NSError(domain: "GitHubAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiRateLimit")])
        } else if httpResponse.statusCode == 429 {
            throw NSError(domain: "GitHubAPI", code: 429, userInfo: [NSLocalizedDescriptionKey: Translations.get("apiTooManyRequests")])
        } else if httpResponse.statusCode != 200 {
            let msg = Translations.get("apiHttpError").format(with: ["code": "\(httpResponse.statusCode)"])
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        guard let firstCommit = jsonArray?.first,
              let sha = firstCommit["sha"] as? String,
              let commitInfo = firstCommit["commit"] as? [String: Any],
              let authorInfo = commitInfo["author"] as? [String: Any],
              let date = authorInfo["date"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        
        let shortSha = String(sha.prefix(7))
        return RepoInfo(name: repo, version: shortSha, date: date)
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
            "Accept": "application/vnd.github.html+json"
        ]
        if let token = ConfigManager.shared.token {
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
                    
                    // Surface rate limit errors to the user
                    if httpResponse.statusCode == 403 {
                        return Translations.get("apiRateLimit")
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
                
                if httpResponse.statusCode == 403 {
                    return Translations.get("apiRateLimit")
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
    
    /// Fetches the repository's native topics (tags) from GitHub to enable hashtag filtering.
    func fetchRepoTags(repo: String) async -> [String]? {
        guard let url = URL(string: "\(Constants.githubAPIBaseURL)/repos/\(repo)") else { return nil }
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
                return json?["topics"] as? [String]
            }
        } catch {
            print("Failed to fetch topics for \(repo): \(error)")
        }
        return nil
    }
}
