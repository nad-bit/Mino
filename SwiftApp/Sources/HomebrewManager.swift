import Foundation

final class HomebrewManager: Sendable {
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
        process.environment = ProcessInfo.processInfo.environment
        return process
    }
    
    func trustTarget(_ target: String) async -> Bool {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        let slashCount = trimmed.filter { $0 == "/" }.count
        let args: [String]
        if slashCount >= 2 {
            args = ["trust", "--cask", trimmed]
        } else if slashCount == 1 {
            args = ["trust", "--tap", trimmed]
        } else {
            args = ["trust", "--cask", trimmed]
        }
        
        guard let process = createProcess(arguments: args) else { return false }
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
    
    func trustCask(cask: String) async -> Bool {
        return await trustTarget(cask)
    }
    
    /// Resolves the canonical full cask identifier (e.g. "66hex/frame/frame") and its tap (e.g. "66hex/frame")
    /// for a short cask name (e.g. "frame") by inspecting locally tapped repositories.
    /// Returns nil if ambiguous (multiple taps define the cask) or not found.
    func resolveCanonicalCask(for shortName: String) -> (fullToken: String, tap: String)? {
        let cleanShort = shortName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanShort.isEmpty, !cleanShort.contains("/") else { return nil }
        
        var found: [(fullToken: String, tap: String)] = []
        let fileManager = FileManager.default
        
        let possibleBases = [
            "/opt/homebrew/Library/Taps",
            "/usr/local/Homebrew/Library/Taps"
        ]
        
        for base in possibleBases {
            guard fileManager.fileExists(atPath: base) else { continue }
            guard let users = try? fileManager.contentsOfDirectory(atPath: base) else { continue }
            for user in users {
                let userPath = "\(base)/\(user)"
                guard let repos = try? fileManager.contentsOfDirectory(atPath: userPath) else { continue }
                for repo in repos {
                    let tapCleanRepo = repo.replacingOccurrences(of: "homebrew-", with: "")
                    let tapName = "\(user)/\(tapCleanRepo)".lowercased()
                    
                    let caskFile = "\(userPath)/\(repo)/Casks/\(cleanShort).rb"
                    let formulaFile = "\(userPath)/\(repo)/Formula/\(cleanShort).rb"
                    if fileManager.fileExists(atPath: caskFile) || fileManager.fileExists(atPath: formulaFile) {
                        let fullToken = "\(tapName)/\(cleanShort)"
                        if !found.contains(where: { $0.fullToken == fullToken }) {
                            found.append((fullToken: fullToken, tap: tapName))
                        }
                    }
                }
            }
        }
        
        // Canonical resolution requires uniqueness: exactly one tap defines this cask name.
        if found.count == 1 {
            return found.first
        }
        return nil
    }

    func extractTrustTarget(from output: String, forCask expectedCask: String? = nil) -> String? {
        var candidate: String?
        
        // Pattern 1: Run `brew trust --cask <target>`
        if let regex = try? NSRegularExpression(pattern: "brew trust --cask\\s+([^`\\r\\n]+)", options: .caseInsensitive) {
            let range = NSRange(location: 0, length: output.utf16.count)
            if let match = regex.firstMatch(in: output, options: [], range: range),
               let matchRange = Range(match.range(at: 1), in: output) {
                let target = String(output[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !target.isEmpty { candidate = target }
            }
        }
        
        // Pattern 2: Error: Refusing to load cask <target> from untrusted tap
        if candidate == nil, let regex = try? NSRegularExpression(pattern: "refusing to load cask\\s+([^\\s]+)\\s+from untrusted tap", options: .caseInsensitive) {
            let range = NSRange(location: 0, length: output.utf16.count)
            if let match = regex.firstMatch(in: output, options: [], range: range),
               let matchRange = Range(match.range(at: 1), in: output) {
                let target = String(output[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !target.isEmpty { candidate = target }
            }
        }
        
        // Pattern 3: Run `brew trust <tap>`
        if candidate == nil, let regex = try? NSRegularExpression(pattern: "brew trust\\s+([^`\\r\\n]+)", options: .caseInsensitive) {
            let range = NSRange(location: 0, length: output.utf16.count)
            if let match = regex.firstMatch(in: output, options: [], range: range),
               let matchRange = Range(match.range(at: 1), in: output) {
                let target = String(output[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !target.isEmpty { candidate = target }
            }
        }
        
        guard let target = candidate else { return nil }
        
        // 1. Canonical Target Validation (reject shell characters, limit to 3 path components)
        guard Utils.isValidMinoTarget(target) else { return nil }
        
        // 2. Strict Cask Correlation
        if let expected = expectedCask {
            let normTarget = target.lowercased()
            let normExpected = expected.lowercased()
            
            if normExpected.contains("/") {
                // Fully-qualified or tap-qualified cask requested (e.g. "66hex/frame/frame" or "user/tap/cask"):
                // Target must either match exactly, or match the tap prefix of the expected cask.
                let isExactMatch = normTarget == normExpected
                let isTapOfCask = normExpected.hasPrefix(normTarget + "/")
                guard isExactMatch || isTapOfCask else { return nil }
            } else {
                // Short cask name requested (e.g. "frame"):
                // Require canonical resolution to prevent arbitrary namespace hijacking.
                if let canonical = resolveCanonicalCask(for: normExpected) {
                    guard normTarget == canonical.fullToken || normTarget == canonical.tap else {
                        return nil
                    }
                } else {
                    // Fallback for headless environments/mock tests where local tap directories don't exist:
                    // Verify strict structural correlation between the error message refusal and the target:
                    let components = normTarget.split(separator: "/")
                    let tokenMatches = (components.count == 3 && components.last == Substring(normExpected)) ||
                                       (components.count == 2 && output.lowercased().contains("refusing to load cask \(normTarget)/\(normExpected)"))
                    guard tokenMatches else { return nil }
                    
                    let matchesRefusal = output.lowercased().contains("refusing to load cask \(normTarget)") ||
                                        output.lowercased().contains("from untrusted tap \(normTarget)") ||
                                        output.lowercased().contains("refusing to load cask \(normTarget)/\(normExpected)")
                    guard matchesRefusal else { return nil }
                }
            }
        }
        
        return target
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
        if let info = await executeInfoForCask(cask: cask) {
            return info
        }
        return nil
    }
    
    private func executeInfoForCask(cask: String, canRetry: Bool = true) async -> String? {
        guard let process = createProcess(arguments: ["info", "--cask", "--json=v2", cask]) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let pipeOut = Pipe()
                let pipeErr = Pipe()
                process.standardOutput = pipeOut
                process.standardError = pipeErr
                
                do {
                    try process.run()
                    let data = pipeOut.fileHandleForReading.readDataToEndOfFile()
                    let errData = pipeErr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        if let output = String(data: data, encoding: .utf8) {
                            continuation.resume(returning: output)
                            return
                        }
                    } else if canRetry, let errStr = String(data: errData, encoding: .utf8),
                              let target = self.extractTrustTarget(from: errStr, forCask: cask) {
                        Task {
                            let trusted = await self.trustTarget(target)
                            if trusted {
                                let retryResult = await self.executeInfoForCask(cask: cask, canRetry: false)
                                continuation.resume(returning: retryResult)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                        return
                    }
                } catch {
                     print("Error running brew info: \(error)")
                }
                continuation.resume(returning: nil)
            }
        }
    }
    
    func installCask(cask: String) async -> (success: Bool, message: String) {
        _ = await runBrewUpdate()
        
        // If it's a tap cask or qualified name, trust it automatically upfront
        if cask.contains("/") {
            _ = await trustTarget(cask)
        }
        
        var result = await executeInstallProcess(cask: cask)
        
        // If it failed due to an untrusted tap/cask, extract target from Homebrew output, trust it, and retry once
        if !result.success, let target = extractTrustTarget(from: result.message, forCask: cask) {
            let trusted = await trustTarget(target)
            if trusted {
                result = await executeInstallProcess(cask: cask)
            }
        }
        
        return result
    }
    
    private func executeInstallProcess(cask: String) async -> (success: Bool, message: String) {
        guard let process = createProcess(arguments: ["reinstall", "--cask", cask]) else {
            return (false, "Homebrew not found")
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let pipeOut = Pipe()
                process.standardOutput = pipeOut
                let pipeErr = Pipe()
                process.standardError = pipeErr
                // Force stdin to /dev/null so sudo can never prompt via /dev/tty.
                // Without this, if the app has a controlling terminal, sudo writes
                // "Password:" directly to /dev/tty (bypassing our pipes) and blocks
                // indefinitely. With /dev/null, sudo immediately fails with a
                // detectable error message on stderr.
                process.standardInput = FileHandle.nullDevice
                
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
                        allOutput += str
                        let currentOutput = allOutput.lowercased()
                        outputLock.unlock()
                        
                        // Covers: classic "password:", "sudo:", "no tty present",
                        // "a password is required", "sorry, try again" (bad pwd)
                        let sudoPatterns = ["password:", "sudo:", "no tty", "a password is required", "sorry, try again"]
                        if sudoPatterns.contains(where: { currentOutput.contains($0) }) {
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
                        let isAlreadyInstalled = finalOutput.lowercased().contains("already installed")
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
        return await executeFindCaskForRepo(repoName: repoName, canRetry: true)
    }
    
    private func executeFindCaskForRepo(repoName: String, canRetry: Bool) async -> String? {
        let shortName = repoName.split(separator: "/").last.map { String($0) } ?? repoName
        let repoUrlPattern = "github.com/\(repoName)".lowercased()
        
        // 1. Search candidates
        let candidates = await brewSearch(term: shortName)
        guard !candidates.isEmpty else { return nil }
        
        guard let process = createProcess(arguments: ["info", "--cask", "--json=v2"] + candidates) else { return nil }
        
        // 2. Info mapping
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let pipeOut = Pipe()
                let pipeErr = Pipe()
                process.standardOutput = pipeOut
                process.standardError = pipeErr
                
                do {
                    try process.run()
                    let data = pipeOut.fileHandleForReading.readDataToEndOfFile()
                    let errData = pipeErr.fileHandleForReading.readDataToEndOfFile()
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
                    } else if canRetry, let errStr = String(data: errData, encoding: .utf8),
                              let target = self.extractTrustTarget(from: errStr) {
                        Task {
                            let trusted = await self.trustTarget(target)
                            if trusted {
                                let retry = await self.executeFindCaskForRepo(repoName: repoName, canRetry: false)
                                continuation.resume(returning: retry)
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                        return
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
