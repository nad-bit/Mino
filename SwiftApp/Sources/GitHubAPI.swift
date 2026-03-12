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
            throw NSError(domain: "GitHubAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "Repository not found or private."])
        } else if httpResponse.statusCode == 403 {
            throw NSError(domain: "GitHubAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "API rate limit exceeded."])
        } else if httpResponse.statusCode != 200 {
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let version = json?["tag_name"] as? String
        let date = json?["published_at"] as? String
        
        // Prioritize the pre-rendered HTML if we requested it, fallback to raw body
        let body = json?["body_html"] as? String ?? json?["body"] as? String ?? ""
        
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
            throw NSError(domain: "GitHubAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "Repository not found or private."])
        } else if httpResponse.statusCode == 403 {
            throw NSError(domain: "GitHubAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "API rate limit exceeded."])
        } else if httpResponse.statusCode != 200 {
            throw NSError(domain: "GitHubAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode)"])
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
}
