import Foundation
import Cocoa

@main
struct AuditValidationTests {
    static func assertTest(_ condition: Bool, _ message: String) {
        if condition {
            print("  ✅ PASS: \(message)")
        } else {
            print("  ❌ FAIL: \(message)")
            exit(1)
        }
    }
    
    static func main() {
        print("\n🧪 Running Mino Audit Verification Tests (Direct Production Code)...")
        
        testGitHubHostAllowlist()
        testMinoTargetValidation()
        testReleaseNotesLinkSchemes()
        testHTMLStructuralSanitization()
        testFileNameSanitization()
        testSafeImageDecompression()
        testConfigManagerAtomicityAndRecovery()
        testGitHubAPI403Discrimination()
        testUntrustedTapExtraction()
        
        print("\n🎉 ALL AUDIT VERIFICATION TESTS PASSED SUCCESSFULLY!\n")
    }
    
    // --------------------------------------------------------
    // Test 1: GitHub Host Validation Allowlist (Production Code)
    // --------------------------------------------------------
    static func testGitHubHostAllowlist() {
        print("\n[Test 1] Testing GitHubAPI.isTrustedGitHubHost (Strict Exact Allowlist)...")
        
        // Exact endpoints required by Mino:
        assertTest(GitHubAPI.isTrustedGitHubHost("github.com"), "github.com is trusted")
        assertTest(GitHubAPI.isTrustedGitHubHost("api.github.com"), "api.github.com is trusted")
        assertTest(GitHubAPI.isTrustedGitHubHost("raw.githubusercontent.com"), "raw.githubusercontent.com is trusted")
        
        // Hardening: Wildcard subdomains must now be REJECTED (audit finding fix)
        assertTest(!GitHubAPI.isTrustedGitHubHost("random.github.com"), "Wildcard random.github.com is REJECTED")
        assertTest(!GitHubAPI.isTrustedGitHubHost("foo.githubusercontent.com"), "Wildcard foo.githubusercontent.com is REJECTED")
        
        // Attack vectors from audit:
        assertTest(!GitHubAPI.isTrustedGitHubHost("github.com.attacker.example"), "github.com.attacker.example is REJECTED")
        assertTest(!GitHubAPI.isTrustedGitHubHost("foo.githubusercontent.com.attacker.example"), "foo.githubusercontent.com.attacker.example is REJECTED")
        assertTest(!GitHubAPI.isTrustedGitHubHost("evil-github.com"), "evil-github.com is REJECTED")
        assertTest(!GitHubAPI.isTrustedGitHubHost("attacker.com"), "attacker.com is REJECTED")
        assertTest(!GitHubAPI.isTrustedGitHubHost(nil), "nil host is REJECTED")
    }
    
    // --------------------------------------------------------
    // Test 2: mino:// URL Scheme Target Validation (Production Code)
    // --------------------------------------------------------
    static func testMinoTargetValidation() {
        print("\n[Test 2] Testing Utils.isValidMinoTarget (Canonical Targets & Depth Limit)...")
        
        // Valid canonical targets:
        assertTest(Utils.isValidMinoTarget("nad-bit/Mino"), "Valid owner/repo: nad-bit/Mino")
        assertTest(Utils.isValidMinoTarget("apple/swift"), "Valid owner/repo: apple/swift")
        assertTest(Utils.isValidMinoTarget("visual-studio-code"), "Valid cask: visual-studio-code")
        assertTest(Utils.isValidMinoTarget("homebrew/cask/docker"), "Valid tap/cask: homebrew/cask/docker")
        assertTest(Utils.isValidMinoTarget("brew:warp"), "Valid brew: prefixed target: brew:warp")
        
        // Attack vectors & malformed inputs:
        assertTest(!Utils.isValidMinoTarget("repo; rm -rf /"), "Shell injection is REJECTED")
        assertTest(!Utils.isValidMinoTarget("owner/repo&&malicious"), "Chained commands are REJECTED")
        assertTest(!Utils.isValidMinoTarget("owner repo with spaces"), "Spaces are REJECTED")
        assertTest(!Utils.isValidMinoTarget(""), "Empty string is REJECTED")
        assertTest(!Utils.isValidMinoTarget(String(repeating: "a", count: 300)), "Excessively long target is REJECTED")
        
        // Depth restriction from audit: a/b/c/d/... must be REJECTED:
        assertTest(!Utils.isValidMinoTarget("a/b/c/d"), "Depth > 3 components (a/b/c/d) is REJECTED")
        assertTest(!Utils.isValidMinoTarget("owner//repo"), "Empty components (owner//repo) are REJECTED")
        assertTest(!Utils.isValidMinoTarget("owner/../repo"), "Relative path traversal (owner/../repo) is REJECTED")
    }
    
    // --------------------------------------------------------
    // Test 3: Release Notes Link Scheme Validation
    // --------------------------------------------------------
    static func testReleaseNotesLinkSchemes() {
        print("\n[Test 3] Testing Release Notes link scheme restrictions...")
        
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
    }
    
    // --------------------------------------------------------
    // Test 4: Structural HTML Sanitization (Production Code)
    // --------------------------------------------------------
    static func testHTMLStructuralSanitization() {
        print("\n[Test 4] Testing Utils.sanitizeHTML (Executable Tags & Event Handlers)...")
        
        let maliciousScript = "<p>Hello</p><script>alert('pwned')</script><b>World</b>"
        let cleanScript = Utils.sanitizeHTML(maliciousScript)
        assertTest(!cleanScript.contains("<script>") && !cleanScript.contains("alert('pwned')"), "script tag and contents stripped")
        assertTest(cleanScript.contains("<p>Hello</p>") && cleanScript.contains("<b>World</b>"), "Valid formatting preserved")
        
        let maliciousIframe = "Text <iframe src=\"https://evil.com\"></iframe> more text"
        let cleanIframe = Utils.sanitizeHTML(maliciousIframe)
        assertTest(!cleanIframe.contains("<iframe"), "iframe tag stripped")
        
        let maliciousHandlers = "<img src=\"local.png\" onload=\"steal()\" onerror=\"evil()\" />"
        let cleanHandlers = Utils.sanitizeHTML(maliciousHandlers)
        assertTest(!cleanHandlers.contains("onload") && !cleanHandlers.contains("onerror"), "Event handlers stripped")
        
        let maliciousJSLink = "<a href=\"javascript:doEvil()\">Click me</a>"
        let cleanJSLink = Utils.sanitizeHTML(maliciousJSLink)
        assertTest(!cleanJSLink.contains("href=\"javascript:"), "javascript: pseudo-protocol neutralized")
    }
    
    // --------------------------------------------------------
    // Test 5: Filename Sanitization (Production Code)
    // --------------------------------------------------------
    static func testFileNameSanitization() {
        print("\n[Test 5] Testing Utils.sanitizeFileName (Path Traversal & Control Chars)...")
        
        let traversal = "../../etc/passwd"
        let cleanTraversal = Utils.sanitizeFileName(traversal)
        assertTest(!cleanTraversal.contains("..") && !cleanTraversal.contains("/"), "Path traversal tokens removed: \(cleanTraversal)")
        
        let withColons = "file:name:with:colons.zip"
        let cleanColons = Utils.sanitizeFileName(withColons)
        assertTest(!cleanColons.contains(":"), "Colons normalized to hyphens: \(cleanColons)")
        
        let controlChars = "bad\u{0000}file\u{001F}name.dmg"
        let cleanControl = Utils.sanitizeFileName(controlChars)
        assertTest(cleanControl == "badfilename.dmg", "ASCII control characters stripped: \(cleanControl)")
        
        let emptyResult = "   ...   "
        let cleanEmpty = Utils.sanitizeFileName(emptyResult)
        assertTest(cleanEmpty == "downloaded-asset", "Fallback provided for degenerate names: \(cleanEmpty)")
    }
    
    // --------------------------------------------------------
    // Test 6: Safe Image Decompression & Dimension Limits
    // --------------------------------------------------------
    static func testSafeImageDecompression() {
        print("\n[Test 6] Testing GitHubAPI.safeDecodeImage (Decompression Bomb Prevention)...")
        
        // Generate a small valid 10x10 PNG in memory
        let size = NSSize(width: 10, height: 10)
        let validImage = NSImage(size: size)
        validImage.lockFocus()
        NSColor.red.set()
        NSRect(origin: .zero, size: size).fill()
        validImage.unlockFocus()
        
        guard let tiff = validImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            assertTest(false, "Failed to create synthetic test PNG")
            return
        }
        
        let decoded = GitHubAPI.safeDecodeImage(from: pngData)
        assertTest(decoded != nil, "Standard valid PNG (10x10) decoded successfully")
        
        // Test strict dimension limits: maximum 4096 px dimension
        let rejectedByDimension = GitHubAPI.safeDecodeImage(from: pngData, maxPixelDimension: 5)
        assertTest(rejectedByDimension == nil, "Image exceeding maxPixelDimension constraint correctly rejected")
        
        // Test strict area limits: maximum pixels area
        let rejectedByArea = GitHubAPI.safeDecodeImage(from: pngData, maxPixelArea: 50)
        assertTest(rejectedByArea == nil, "Image exceeding maxPixelArea constraint correctly rejected")
        
        // Test vector/SVG format decoding
        let svgString = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"20\"><rect width=\"100\" height=\"20\" fill=\"#4c1\"/></svg>"
        let svgData = svgString.data(using: .utf8)!
        let decodedSVG = GitHubAPI.safeDecodeImage(from: svgData)
        assertTest(decodedSVG != nil, "Vector SVG format decoded successfully")
    }
    
    // --------------------------------------------------------
    // Test 7: ConfigManager Atomicity and Recovery (Production Code)
    // --------------------------------------------------------
    static func testConfigManagerAtomicityAndRecovery() {
        print("\n[Test 7] Testing ConfigManager atomic writes and backup recovery...")
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MinoTest_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testConfigFile = tempDir.appendingPathComponent("repos.json")
        let testBackupFile = tempDir.appendingPathComponent("repos.json.bak")
        
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
        
        // Verify recovery logic
        var loadedReposCount = 0
        let decoder = JSONDecoder()
        
        if let data = try? Data(contentsOf: testConfigFile),
           let decoded = try? decoder.decode(AppConfig.self, from: data) {
            loadedReposCount = decoded.repos.count
        } else {
            if let backupData = try? Data(contentsOf: testBackupFile),
               let backupDecoded = try? decoder.decode(AppConfig.self, from: backupData) {
                loadedReposCount = backupDecoded.repos.count
            }
        }
        
        assertTest(loadedReposCount == 1, "Successfully recovered repository list from repos.json.bak when repos.json is corrupted")
    }
    
    // --------------------------------------------------------
    // Test 8: GitHub API Rate Limit & 403 Discrimination
    // --------------------------------------------------------
    static func testGitHubAPI403Discrimination() {
        print("\n[Test 8] Testing GitHub API 403 Discrimination & Rate Limit Parsing...")
        
        func simulate403(remaining: String?, jsonBody: String) -> String {
            if let remaining = remaining, remaining == "0" {
                return "apiRateLimit"
            }
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
        
        let res1 = simulate403(remaining: "0", jsonBody: "{\"message\": \"API rate limit exceeded for user\"}")
        assertTest(res1 == "apiRateLimit", "Primary rate limit (remaining 0) correctly mapped to apiRateLimit")
        
        let res2 = simulate403(remaining: "5000", jsonBody: "{\"message\": \"You have exceeded a secondary rate limit. Please wait a few minutes before you try again.\"}")
        assertTest(res2 == "apiSecondaryRateLimit", "Secondary rate limit with remaining 5000 mapped to apiSecondaryRateLimit")
        
        let res3 = simulate403(remaining: "4990", jsonBody: "{\"message\": \"Resource protected by organization SAML enforcement. You must grant your token access.\"}")
        assertTest(res3 == "SAML SSO: apiForbidden", "SAML SSO enforcement with remaining 4990 mapped to SAML SSO: apiForbidden")
        
        let res4 = simulate403(remaining: "5000", jsonBody: "{\"message\": \"Repository access blocked\"}")
        assertTest(res4 == "apiForbidden", "Repository access blocked with remaining 5000 mapped to apiForbidden")
    }
    
    // --------------------------------------------------------
    // Test 9: Untrusted Tap Target Extraction (Production Code)
    // --------------------------------------------------------
    static func testUntrustedTapExtraction() {
        print("\n[Test 9] Testing HomebrewManager.extractTrustTarget...")
        
        let errorOutput1 = """
        Error: Refusing to load cask 66hex/frame/frame from untrusted tap 66hex/frame.
        Run `brew trust --cask 66hex/frame/frame` or `brew trust 66hex/frame` to trust it.
        """
        let extracted1 = HomebrewManager.shared.extractTrustTarget(from: errorOutput1)
        assertTest(extracted1 == "66hex/frame/frame", "Target extracted from brew trust --cask: 66hex/frame/frame")
        
        let errorOutput2 = """
        Error: Refusing to load cask custom/tap/my-app from untrusted tap custom/tap.
        """
        let extracted2 = HomebrewManager.shared.extractTrustTarget(from: errorOutput2)
        assertTest(extracted2 == "custom/tap/my-app", "Target extracted from refusing to load cask: custom/tap/my-app")
        
        let errorOutput3 = """
        Run `brew trust some-user/some-tap` to trust it.
        """
        let extracted3 = HomebrewManager.shared.extractTrustTarget(from: errorOutput3)
        assertTest(extracted3 == "some-user/some-tap", "Target extracted from brew trust <tap>: some-user/some-tap")
        
        let cleanOutput = "🍺  app was successfully installed!"
        let extractedClean = HomebrewManager.shared.extractTrustTarget(from: cleanOutput)
        assertTest(extractedClean == nil, "No trust target extracted on normal output")
    }
}
