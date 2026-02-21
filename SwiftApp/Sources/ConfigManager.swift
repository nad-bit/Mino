import Foundation
import Security

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configDir: URL
    private let configFile: URL
    var config: AppConfig
    var token: String?
    
    private let keychainService = "GitHub Watcher"
    private let keychainAccount = "github_token"
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        configDir = homeDir.appendingPathComponent(".config/GitHubWatcher")
        configFile = configDir.appendingPathComponent("repos.json")
        
        self.config = AppConfig()
        self.loadConfig()
    }
    
    func loadConfig() {
        if FileManager.default.fileExists(atPath: configFile.path) {
            do {
                let data = try Data(contentsOf: configFile)
                // Attempt to decode. If parsing fails, fall back to defaults.
                // We must handle the old "string" repos.json format migration if needed,
                // but Decoder is safer. For simplicity, assume new structured format or fallback.
                let decoder = JSONDecoder()
                if let decoded = try? decoder.decode(AppConfig.self, from: data) {
                    self.config = decoded
                }
            } catch {
                print("Failed to load config: \(error)")
            }
        } else {
            // First time, save defaults
            saveConfig()
        }
        
        // Load token from Keychain
        self.token = getTokenFromKeychain()
    }
    
    func saveConfig() {
        do {
            if !FileManager.default.fileExists(atPath: configDir.path) {
                try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configFile)
        } catch {
            print("Failed to save config: \(error)")
        }
    }
    
    // MARK: - Keychain Methods
    
    func saveTokenToKeychain(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        
        // Delete existing item if any
        let queryDelete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(queryDelete as CFDictionary)
        
        // Add new item
        let queryAdd: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(queryAdd as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func getTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess,
           let data = item as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        return nil
    }
    
    func deleteTokenFromKeychain() -> Bool {
        let queryDelete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(queryDelete as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
