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
                // Use `reinstall` so aborted sudo stubs don't trick Homebrew into "already installed".
                process.arguments = ["reinstall", "--cask", cask]
                
                let pipeOut = Pipe()
                process.standardOutput = pipeOut
                let pipeErr = Pipe()
                process.standardError = pipeErr
                
                var allOutput = ""
                let outputLock = NSLock()
                var requiresSudo = false
                
                let readGroup = DispatchGroup()
                
                let outHandler: (FileHandle, DispatchGroup) -> Void = { fileHandle, group in
                    let data = fileHandle.availableData
                    if data.isEmpty {
                        fileHandle.readabilityHandler = nil
                        group.leave()
                        return
                    }
                    if let str = String(data: data, encoding: .utf8) {
                        outputLock.lock()
                        allOutput += str.lowercased()
                        let currentOutput = allOutput
                        outputLock.unlock()
                        
                        if currentOutput.contains("password:") || currentOutput.contains("sudo") {
                            requiresSudo = true
                            if process.isRunning {
                                process.terminate()
                            }
                        }
                    }
                }
                
                readGroup.enter()
                pipeOut.fileHandleForReading.readabilityHandler = { fh in
                    outHandler(fh, readGroup)
                }
                
                readGroup.enter()
                pipeErr.fileHandleForReading.readabilityHandler = { fh in
                    outHandler(fh, readGroup)
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    // Cancel readability handlers
                    pipeOut.fileHandleForReading.readabilityHandler = nil
                    pipeErr.fileHandleForReading.readabilityHandler = nil
                    
                    // We don't strictly wait on the readGroup here to avoid deadlocks
                    // as we already have the output we need in allOutput
                    
                    outputLock.lock()
                    let finalOutput = allOutput
                    outputLock.unlock()
                    
                    if requiresSudo {
                        continuation.resume(returning: (false, "requires_sudo"))
                        return
                    }
                    
                    if process.terminationStatus == 0 {
                        let isAlreadyInstalled = finalOutput.contains("already installed")
                        if isAlreadyInstalled {
                            continuation.resume(returning: (true, "alreadyInstalled"))
                        } else {
                            continuation.resume(returning: (true, "installComplete"))
                        }
                    } else {
                        continuation.resume(returning: (false, finalOutput))
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
    
    func downloadGlobalCaskMap() async -> [String: String] {
        guard let url = URL(string: "https://formulae.brew.sh/api/cask.json") else { return [:] }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = Constants.httpRequestTimeoutSeconds
            request.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return [:]
            }
            
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return [:]
            }
            
            var map: [String: String] = [:]
            let regex = try NSRegularExpression(pattern: "(?:github\\.com/)?([^/\\s\"]+/[^/\\s\"]+)")
            
            for item in jsonArray {
                guard let token = item["token"] as? String else { continue }
                
                // Extract repository identifier from URLs (homepage or download url)
                var repoName: String? = nil
                
                if let urlStr = item["url"] as? String {
                    let range = NSRange(location: 0, length: urlStr.utf16.count)
                    if let match = regex.firstMatch(in: urlStr, options: [], range: range) {
                        if let r = Range(match.range(at: 1), in: urlStr) {
                            repoName = String(urlStr[r]).replacingOccurrences(of: ".git", with: "")
                        }
                    }
                }
                
                if repoName == nil, let hpStr = item["homepage"] as? String {
                    let range = NSRange(location: 0, length: hpStr.utf16.count)
                    if let match = regex.firstMatch(in: hpStr, options: [], range: range) {
                         if let r = Range(match.range(at: 1), in: hpStr) {
                             repoName = String(hpStr[r]).replacingOccurrences(of: ".git", with: "")
                         }
                    }
                }
                
                if let r = repoName {
                    map[r.lowercased()] = token
                }
            }
            
            return map
            
        } catch {
            print("Failed to download global cask map: \(error)")
            return [:]
        }
    }
    
    func runBrewUpdate() async -> Bool {
        guard let path = brewPath else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["update"]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    print("Error running brew update: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
