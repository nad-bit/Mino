import Foundation

class HomebrewManager {
    static let shared = HomebrewManager()
    
    var brewPath: String? {
        for path in Constants.homebrewPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    func listCasks() async -> [String] {
        guard let path = brewPath else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["list", "--casks"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8) {
                            let casks = output.components(separatedBy: .newlines).filter { !$0.isEmpty }.sorted()
                            continuation.resume(returning: casks)
                            return
                        }
                    }
                } catch {
                    print("Error running brew list: \(error)")
                }
                continuation.resume(returning: [])
            }
        }
    }
    
    func infoForCask(cask: String) async -> String? {
        guard let path = brewPath else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["info", "--cask", "--json=v2", cask]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8) {
                            continuation.resume(returning: output)
                            return
                        }
                    }
                } catch {
                     print("Error running brew info: \(error)")
                }
                continuation.resume(returning: nil)
            }
        }
    }
    
    func installCask(cask: String) async -> (success: Bool, message: String) {
        guard let path = brewPath else { return (false, "Homebrew not found") }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["install", "--cask", "--no-quarantine", cask]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                let errorPipe = Pipe()
                process.standardError = errorPipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let stdout = String(data: outData, encoding: .utf8) ?? ""
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    
                    let allOutput = (stdout + stderr).lowercased()
                    
                    if process.terminationStatus == 0 {
                        let isAlreadyInstalled = allOutput.contains("already installed")
                        if isAlreadyInstalled {
                            continuation.resume(returning: (true, "alreadyInstalled"))
                        } else {
                            continuation.resume(returning: (true, "installComplete"))
                        }
                    } else {
                        continuation.resume(returning: (false, stderr))
                    }
                    
                } catch {
                    continuation.resume(returning: (false, error.localizedDescription))
                }
            }
        }
    }
    
    func findCaskForRepo(repoName: String) async -> String? {
        guard let path = brewPath else { return nil }
        
        let shortName = repoName.split(separator: "/").last.map { String($0) } ?? repoName
        let repoUrlPattern = "github.com/\(repoName)".lowercased()
        
        // 1. Search candidates
        let candidates = await brewSearch(term: shortName)
        guard !candidates.isEmpty else { return nil }
        
        // 2. Info mapping
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["info", "--cask", "--json=v2"] + candidates
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let casks = json["casks"] as? [[String: Any]] {
                            
                            for cask in casks {
                                let hp = (cask["homepage"] as? String ?? "").lowercased()
                                let url = (cask["url"] as? String ?? "").lowercased()
                                if let token = cask["token"] as? String {
                                    if hp.contains(repoUrlPattern) || url.contains(repoUrlPattern) {
                                        continuation.resume(returning: token)
                                        return
                                    }
                                }
                            }
                        }
                    }
                } catch {}
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func brewSearch(term: String) async -> [String] {
        guard let path = brewPath else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["search", "--cask", term]
                let pipe = Pipe()
                process.standardOutput = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8) {
                            let results = output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                            continuation.resume(returning: results)
                            return
                        }
                    }
                } catch {}
                continuation.resume(returning: [])
            }
        }
    }
}
