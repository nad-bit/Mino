import Foundation

class GitHubAPI {
    static let shared = GitHubAPI()
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.httpRequestTimeoutSeconds
        config.timeoutIntervalForResource = Constants.httpRequestTimeoutSeconds * 2
        config.httpAdditionalHeaders = ["User-Agent": Constants.userAgent]
        self.session = URLSession(configuration: config)
    }
    
    func fetchRepoInfo(repo: String) async -> RepoInfo {
        var requestHeaders: [String: String] = [
            "Accept": "application/vnd.github.html+json"
        ]
        
        if let token = ConfigManager.shared.token {
            requestHeaders["Authorization"] = "Bearer \(token)"
        }
        
        do {
            // Try Releases first
            let releaseData = try await fetchRelease(repo: repo, headers: requestHeaders)
            return releaseData
        } catch {
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
        } else if httpResponse.statusCode != 200 {
            let msg = Translations.get("apiHttpError").format(with: ["code": "\(httpResponse.statusCode)"])
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let version = json?["tag_name"] as? String
        let date = json?["published_at"] as? String
        
        // Prioritize the pre-rendered HTML if we requested it, fallback to raw body
        // Treat empty/whitespace-only content as nil so the UI shows "no notes" instead of a blank window
        let rawBody = json?["body_html"] as? String ?? json?["body"] as? String
        var body = rawBody?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rawBody : nil
        
        // GitHub's web UI shows the tag commit message when the release body is empty.
        // Replicate that behavior: fetch the commit pointed to by the tag for its message.
        if body == nil, let tagName = version {
            body = try? await fetchTagCommitMessage(repo: repo, tag: tagName, headers: headers)
        }
        
        if version != nil && date != nil {
            return RepoInfo(name: repo, version: version, date: date, body: body)
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
        } else if httpResponse.statusCode != 200 {
            let msg = Translations.get("apiHttpError").format(with: ["code": "\(httpResponse.statusCode)"])
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        guard let firstCommit = jsonArray?.first,
              let sha = firstCommit["sha"] as? String,
              let commitInfo = firstCommit["commit"] as? [String: Any],
              let authorInfo = commitInfo["author"] as? [String: Any],
              let date = authorInfo["date"] as? String,
              let message = commitInfo["message"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        
        let shortSha = String(sha.prefix(7))
        return RepoInfo(name: repo, version: shortSha, date: date, body: message)
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
