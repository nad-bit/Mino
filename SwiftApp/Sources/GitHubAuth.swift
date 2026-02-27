import Foundation
import Cocoa

@MainActor
class GitHubAuth {
    static let shared = GitHubAuth()
    
    struct DeviceCodeResponse: Codable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let expiresIn: Int
        let interval: Int
        
        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }
    }
    
    struct TokenResponse: Codable {
        let accessToken: String?
        let error: String?
        let errorDescription: String?
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case error
            case errorDescription = "error_description"
        }
    }
    
    private var isPolling = false
    
    func requestDeviceCode() async throws -> DeviceCodeResponse {
        guard let url = URL(string: "https://github.com/login/device/code") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["client_id": Constants.githubClientID, "scope": "repo"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }
    
    func pollForToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> String? {
        isPolling = true
        let expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": Constants.githubClientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        while isPolling && Date() < expirationDate {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            if let token = response.accessToken {
                isPolling = false
                return token
            }
            
            if response.error == "authorization_pending" {
                // Wait and try again
                try await Task.sleep(nanoseconds: UInt64((interval + 1) * 1_000_000_000))
            } else if response.error == "slow_down" {
                try await Task.sleep(nanoseconds: UInt64((interval + 5) * 1_000_000_000))
            } else if response.error == "expired_token" {
                isPolling = false
                throw NSError(domain: "GitHubAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Code expired. Please try again."])
            } else {
                // Other error, abort
                isPolling = false
                throw NSError(domain: "GitHubAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: response.errorDescription ?? "Unknown error"])
            }
        }
        
        isPolling = false
        return nil
    }
    
    func cancelPolling() {
        isPolling = false
    }
}
