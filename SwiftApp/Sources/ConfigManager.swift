import Foundation
import Security

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configDir: URL
    private let configFile: URL
    private let backupConfigFile: URL
    
    private let lock = NSRecursiveLock()
    private var _config: AppConfig
    private var _token: String?
    
    var config: AppConfig {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _config
        }
        set {
            lock.lock()
            _config = newValue
            lock.unlock()
        }
    }
    
    var token: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _token
        }
        set {
            lock.lock()
            _token = newValue
            lock.unlock()
        }
    }
    
    private let keychainService = "Mino"
    private let keychainAccount = "github_token"
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        configDir = homeDir.appendingPathComponent(".config/Mino")
        configFile = configDir.appendingPathComponent("repos.json")
        backupConfigFile = configDir.appendingPathComponent("repos.json.bak")
        
        self._config = AppConfig()
        self.loadConfig()
    }
    
    func loadConfig() {
        var loadedSuccessfully = false
        let decoder = JSONDecoder()
        
        if FileManager.default.fileExists(atPath: configFile.path) {
            do {
                let data = try Data(contentsOf: configFile)
                if let decoded = try? decoder.decode(AppConfig.self, from: data) {
                    self.config = decoded
                    loadedSuccessfully = true
                    // Sync backup with valid config
                    try? data.write(to: backupConfigFile, options: .atomic)
                } else {
                    print("⚠️ [ConfigManager] Failed to parse \(configFile.path). Attempting recovery from backup...")
                    // Attempt backup recovery
                    if FileManager.default.fileExists(atPath: backupConfigFile.path),
                       let backupData = try? Data(contentsOf: backupConfigFile),
                       let backupDecoded = try? decoder.decode(AppConfig.self, from: backupData) {
                        self.config = backupDecoded
                        loadedSuccessfully = true
                        print("✅ [ConfigManager] Successfully recovered configuration from backup.")
                    } else {
                        print("❌ [ConfigManager] Failed to recover from backup. Preserving corrupt file to prevent data loss.")
                        let timestamp = Int(Date().timeIntervalSince1970)
                        let corruptFile = configDir.appendingPathComponent("repos.json.corrupt.\(timestamp)")
                        try? FileManager.default.copyItem(at: configFile, to: corruptFile)
                    }
                }
            } catch {
                print("Failed to read config file: \(error)")
            }
        } else {
            // First time run: no config exists yet, so saving defaults is safe
            loadedSuccessfully = true
            saveConfig()
        }
        
        // Only modify and persist downloadPath if we successfully loaded/initialized
        // to avoid accidentally overwriting a corrupted config file with empty defaults!
        if loadedSuccessfully {
            if self.config.downloadPath == nil {
                self.config.downloadPath = "~/Desktop"
                saveConfig()
            }
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
            
            // If current configFile exists and is valid, back it up before replacing
            if FileManager.default.fileExists(atPath: configFile.path) {
                try? FileManager.default.removeItem(at: backupConfigFile)
                try? FileManager.default.copyItem(at: configFile, to: backupConfigFile)
            }
            
            // Write atomically to prevent partial writes / truncation corruption
            try data.write(to: configFile, options: .atomic)
        } catch {
            print("Failed to save config: \(error)")
        }
        
        NotificationCenter.default.post(name: Notification.Name("ConfigChanged"), object: nil)
    }
    
    // MARK: - Keychain Methods
    
    func saveTokenToKeychain(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        } else if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        
        return false
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
