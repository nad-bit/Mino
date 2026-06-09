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
    
    private func createProcess(arguments: [String]) -> Process? {
        guard let path = brewPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_REQUIRE_TAP_TRUST"] = "1"
        process.environment = env
        return process
    }
    
    func trustCask(cask: String) async -> Bool {
        guard let process = createProcess(arguments: ["trust", "--cask", cask]) else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    func listCasks() async -> [String] {
        guard let process = createProcess(arguments: ["list", "--casks"]) else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
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
        guard let process = createProcess(arguments: ["info", "--cask", "--json=v2", cask]) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
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
        // If it's a tap cask, trust it first so it's also trusted permanently in the user's terminal
        if cask.contains("/") {
            _ = await trustCask(cask: cask)
        }
        
        guard let process = createProcess(arguments: ["reinstall", "--cask", cask]) else {
            return (false, "Homebrew not found")
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
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
        let shortName = repoName.split(separator: "/").last.map { String($0) } ?? repoName
        let repoUrlPattern = "github.com/\(repoName)".lowercased()
        
        // 1. Search candidates
        let candidates = await brewSearch(term: shortName)
        guard !candidates.isEmpty else { return nil }
        
        guard let process = createProcess(arguments: ["info", "--cask", "--json=v2"] + candidates) else { return nil }
        
        // 2. Info mapping
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
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
        guard let process = createProcess(arguments: ["search", "--cask", term]) else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let pipe = Pipe()
                process.standardOutput = pipe
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
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
    
    func runBrewUpdate() async -> Bool {
        guard let process = createProcess(arguments: ["update"]) else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
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
