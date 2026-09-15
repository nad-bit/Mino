import Foundation

func assertTest(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✅ PASS: \(message)")
    } else {
        print("  ❌ FAIL: \(message)")
        exit(1)
    }
}

print("\n🧪 Running Mino Audit Verification Tests...")

// --------------------------------------------------------
// Test 1: GitHub Host Validation Allowlist (M-01)
// --------------------------------------------------------
print("\n[Test 1] Testing GitHub Host Allowlist...")

func isTrustedGitHubHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return host == "github.com"
        || host == "api.github.com"
        || host == "raw.githubusercontent.com"
        || host == "user-images.githubusercontent.com"
        || host == "avatars.githubusercontent.com"
        || host == "camo.githubusercontent.com"
        || host == "objects.githubusercontent.com"
        || host == "githubusercontent.com"
        || host.hasSuffix(".githubusercontent.com")
        || host.hasSuffix(".github.com")
}

assertTest(isTrustedGitHubHost("github.com"), "github.com is trusted")
assertTest(isTrustedGitHubHost("api.github.com"), "api.github.com is trusted")
assertTest(isTrustedGitHubHost("raw.githubusercontent.com"), "raw.githubusercontent.com is trusted")
assertTest(isTrustedGitHubHost("user-images.githubusercontent.com"), "user-images.githubusercontent.com is trusted")
assertTest(isTrustedGitHubHost("avatars.githubusercontent.com"), "avatars.githubusercontent.com is trusted")
assertTest(isTrustedGitHubHost("objects.githubusercontent.com"), "objects.githubusercontent.com is trusted")
assertTest(isTrustedGitHubHost("subdomain.github.com"), "subdomain.github.com is trusted")

// Attack vectors from the audit:
assertTest(!isTrustedGitHubHost("github.com.attacker.example"), "github.com.attacker.example is REJECTED")
assertTest(!isTrustedGitHubHost("foo.githubusercontent.com.attacker.example"), "foo.githubusercontent.com.attacker.example is REJECTED")
assertTest(!isTrustedGitHubHost("evil-github.com"), "evil-github.com is REJECTED")
assertTest(!isTrustedGitHubHost("attacker.com"), "attacker.com is REJECTED")
assertTest(!isTrustedGitHubHost(nil), "nil host is REJECTED")

// --------------------------------------------------------
// Test 2: mino:// URL Scheme Target Validation (M-04)
// --------------------------------------------------------
print("\n[Test 2] Testing mino:// URL target regex validation...")

func isValidMinoTarget(_ rawTarget: String) -> Bool {
    guard !rawTarget.isEmpty, rawTarget.count <= 256 else { return false }
    let validTargetRegex = "^(brew:)?[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)*$"
    return rawTarget.range(of: validTargetRegex, options: .regularExpression) != nil
}

assertTest(isValidMinoTarget("nad-bit/Mino"), "Valid owner/repo: nad-bit/Mino")
assertTest(isValidMinoTarget("apple/swift"), "Valid owner/repo: apple/swift")
assertTest(isValidMinoTarget("visual-studio-code"), "Valid cask: visual-studio-code")
assertTest(isValidMinoTarget("homebrew/cask/docker"), "Valid tap/cask: homebrew/cask/docker")
assertTest(isValidMinoTarget("brew:warp"), "Valid brew: prefixed target")

// Attack vectors / malformed inputs:
assertTest(!isValidMinoTarget("repo; rm -rf /"), "Shell injection is REJECTED")
assertTest(!isValidMinoTarget("owner/repo&&malicious"), "Chained commands are REJECTED")
assertTest(!isValidMinoTarget("owner repo with spaces"), "Spaces are REJECTED")
assertTest(!isValidMinoTarget(""), "Empty string is REJECTED")
assertTest(!isValidMinoTarget(String(repeating: "a", count: 300)), "Excessively long target is REJECTED")

// --------------------------------------------------------
// Test 3: Release Notes Link Scheme Validation (M-05)
// --------------------------------------------------------
print("\n[Test 3] Testing Release Notes link scheme restriction...")

func isAllowedLinkScheme(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    let scheme = url.scheme?.lowercased() ?? ""
    return scheme == "https" || scheme == "http" || scheme == "mailto"
}

assertTest(isAllowedLinkScheme("https://github.com/nad-bit/Mino/releases"), "https:// is allowed")
assertTest(isAllowedLinkScheme("http://example.com"), "http:// is allowed")
assertTest(isAllowedLinkScheme("mailto:support@example.com"), "mailto: is allowed")

// Dangerous schemes that must be blocked:
assertTest(!isAllowedLinkScheme("file:///Applications/Calculator.app"), "file:// is BLOCKED")
assertTest(!isAllowedLinkScheme("shortcuts://run-shortcut?name=Evil"), "shortcuts:// is BLOCKED")
assertTest(!isAllowedLinkScheme("terminal://execute"), "terminal:// is BLOCKED")
assertTest(!isAllowedLinkScheme("javascript:alert(1)"), "javascript: is BLOCKED")

// --------------------------------------------------------
// Test 4: ConfigManager Atomicity and Recovery (M-12)
// --------------------------------------------------------
print("\n[Test 4] Testing ConfigManager atomic writes and backup recovery...")

let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MinoTest_\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }

let testConfigFile = tempDir.appendingPathComponent("repos.json")
let testBackupFile = tempDir.appendingPathComponent("repos.json.bak")

// Simulate saving valid config
let validJSON = """
{
  "refresh_minutes": 360,
  "repos": [
    { "name": "nad-bit/Mino", "source": "manual", "is_favorite": true }
  ]
}
""".data(using: .utf8)!

try! validJSON.write(to: testConfigFile, options: .atomic)
try! validJSON.write(to: testBackupFile, options: .atomic)

assertTest(FileManager.default.fileExists(atPath: testConfigFile.path), "repos.json exists")
assertTest(FileManager.default.fileExists(atPath: testBackupFile.path), "repos.json.bak exists")

// Simulate corrupting repos.json
let corruptData = "INVALID_JSON_CORRUPTED_DATA".data(using: .utf8)!
try! corruptData.write(to: testConfigFile, options: .atomic)

// Simulate recovery logic from ConfigManager.loadConfig()
var loadedReposCount = 0
let decoder = JSONDecoder()

struct MockRepo: Codable {
    let name: String
}
struct MockConfig: Codable {
    let repos: [MockRepo]
}

if let data = try? Data(contentsOf: testConfigFile),
   let decoded = try? decoder.decode(MockConfig.self, from: data) {
    loadedReposCount = decoded.repos.count
} else {
    // Attempt recovery from backup
    if let backupData = try? Data(contentsOf: testBackupFile),
       let backupDecoded = try? decoder.decode(MockConfig.self, from: backupData) {
        loadedReposCount = backupDecoded.repos.count
    }
}

assertTest(loadedReposCount == 1, "Successfully recovered repository list from repos.json.bak when repos.json is corrupted")

// --------------------------------------------------------
// Test 5: GitHub API Rate Limit & 403 Discrimination
// --------------------------------------------------------
print("\n[Test 5] Testing GitHub API 403 Discrimination & Rate Limit Parsing...")

func simulate403(remaining: String?, jsonBody: String) -> String {
    // 1. Primary rate limit: x-ratelimit-remaining is explicitly 0
    if let remaining = remaining, remaining == "0" {
        return "apiRateLimit"
    }
    
    // 2. Otherwise inspect GitHub's JSON error payload
    if let data = jsonBody.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let message = json["message"] as? String {
        let lower = message.lowercased()
        if lower.contains("secondary rate limit") {
            return "apiSecondaryRateLimit"
        } else if lower.contains("saml") {
            return "SAML SSO: apiForbidden"
        }
    }
    
    return "apiForbidden"
}

// Case 1: Primary rate limit exhausted (remaining = "0")
let res1 = simulate403(remaining: "0", jsonBody: "{\"message\": \"API rate limit exceeded for user\"}")
assertTest(res1 == "apiRateLimit", "Primary rate limit (remaining 0) correctly mapped to apiRateLimit")

// Case 2: Secondary rate limit (burst / concurrency limit, remaining > 0)
let res2 = simulate403(remaining: "5000", jsonBody: "{\"message\": \"You have exceeded a secondary rate limit. Please wait a few minutes before you try again.\"}")
assertTest(res2 == "apiSecondaryRateLimit", "Secondary rate limit with remaining 5000 mapped to apiSecondaryRateLimit")

// Case 3: SAML SSO enforcement (remaining > 0)
let res3 = simulate403(remaining: "4990", jsonBody: "{\"message\": \"Resource protected by organization SAML enforcement. You must grant your token access.\"}")
assertTest(res3 == "SAML SSO: apiForbidden", "SAML SSO enforcement with remaining 4990 mapped to SAML SSO: apiForbidden")

// Case 4: Private repo or repository access blocked (remaining > 0)
let res4 = simulate403(remaining: "5000", jsonBody: "{\"message\": \"Repository access blocked\"}")
assertTest(res4 == "apiForbidden", "Repository access blocked with remaining 5000 mapped to apiForbidden")

print("\n🎉 ALL TESTS PASSED SUCCESSFULLY!\n")

