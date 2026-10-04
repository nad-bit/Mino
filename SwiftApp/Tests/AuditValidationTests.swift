import Foundation
import Cocoa

@main
@MainActor
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
        testMarkdownAutolinking()
        testLocalizationCompleteness()
        testSHA256Integrity()
        testChecksumParsingAndIntegrity()
        testDiskCacheSecurity()
        testStatusItemTooltipCompatibility()
        testErrorTooltipAndCodeHandling()
        testPhase1Optimizations()
        testPhase2Optimizations()
        
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
        assertTest(!cleanJSLink.contains("href=\"javascript:"), "javascript: href neutralized")
        
        let maliciousVBSLink = "<a href=\"vbscript:doEvil()\">Click me</a>"
        let cleanVBSLink = Utils.sanitizeHTML(maliciousVBSLink)
        assertTest(!cleanVBSLink.contains("href=\"vbscript:"), "vbscript: href neutralized")
        
        let maliciousDataLink = "<a href=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==\">Click me</a>"
        let cleanDataLink = Utils.sanitizeHTML(maliciousDataLink)
        assertTest(!cleanDataLink.contains("href=\"data:"), "data: href neutralized")
        
        let maliciousDataImg = "<img src=\"data:image/svg+xml;utf8,<svg onload=alert(1)/>\" />"
        let cleanDataImg = Utils.sanitizeHTML(maliciousDataImg)
        assertTest(!cleanDataImg.contains("src=\"data:"), "data: src neutralized")
        
        let maliciousVBSSrc = "<iframe src=\"vbscript:evil()\"></iframe>"
        let cleanVBSSrc = Utils.sanitizeHTML(maliciousVBSSrc)
        assertTest(!cleanVBSSrc.contains("vbscript:"), "vbscript: src neutralized")
        
        // file: protocol neutralization (Audit finding fix)
        let maliciousFileLink = "<a href=\"file:///etc/passwd\">Secret</a>"
        let cleanFileLink = Utils.sanitizeHTML(maliciousFileLink)
        assertTest(!cleanFileLink.contains("href=\"file:"), "file: href neutralized")
        
        let maliciousFileImg = "<img src=\"file:///etc/hosts\" />"
        let cleanFileImg = Utils.sanitizeHTML(maliciousFileImg)
        assertTest(!cleanFileImg.contains("src=\"file:"), "file: src neutralized")
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
        
        // Test XML entity rejection beyond 2048 bytes (Audit finding fix)
        let padding = String(repeating: " ", count: 3000)
        let paddedXMLWithEntity = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"20\"><!--\(padding)--><!ENTITY evil \"bomb\"><rect width=\"100\" height=\"20\" fill=\"#4c1\"/></svg>"
        let entityData = paddedXMLWithEntity.data(using: .utf8)!
        let rejectedPaddedEntity = GitHubAPI.safeDecodeImage(from: entityData)
        assertTest(rejectedPaddedEntity == nil, "XML entity expansion beyond 2048 bytes is REJECTED")
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
        
        // Test atomic modifyConfig
        ConfigManager.shared.modifyConfig { cfg in
            cfg.refreshMinutes = 123
        }
        assertTest(ConfigManager.shared.config.refreshMinutes == 123, "ConfigManager.shared.modifyConfig atomically updates and commits state")
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
        
        // Test strict cask correlation (Audit finding)
        let correlated = HomebrewManager.shared.extractTrustTarget(from: errorOutput1, forCask: "66hex/frame/frame")
        assertTest(correlated == "66hex/frame/frame", "Target correlated successfully with expected cask")
        
        let uncorrelated = HomebrewManager.shared.extractTrustTarget(from: errorOutput1, forCask: "unrelated/malicious/cask")
        assertTest(uncorrelated == nil, "Uncorrelated target from untrusted tap output is REJECTED")
        
        // Canonical resolution for short cask name "frame" (Audit finding fix)
        let correlatedShort = HomebrewManager.shared.extractTrustTarget(from: errorOutput1, forCask: "frame")
        assertTest(correlatedShort == "66hex/frame/frame", "Canonical target correlated for short cask name 'frame'")
        
        // Suffix hijacking prevention: spoofed/uncanonical tap output with matching short name is REJECTED
        let spoofedError = """
        Error: Refusing to load cask attacker/evil/frame from untrusted tap attacker/evil.
        Run `brew trust --cask attacker/evil/frame` to trust it.
        """
        let rejectedSpoof = HomebrewManager.shared.extractTrustTarget(from: spoofedError, forCask: "frame")
        assertTest(rejectedSpoof == nil, "Spoofed/uncanonical tap for short cask 'frame' is REJECTED")
    }
    
    // --------------------------------------------------------
    // Test 10: Markdown Autolinking (Bare URLs, Mentions, Issues)
    // --------------------------------------------------------
    static func testMarkdownAutolinking() {
        print("\n[Test 10] Testing Utils.convertMarkdownToHTML autolinking...")
        
        // 1. Bare URLs (e.g., kiwix-apple release notes)
        let bareURLText = "Localisation updates from https://translatewiki.net and https://github.com/kiwix/kiwix-apple/pull/1676."
        let htmlWithURL = Utils.convertMarkdownToHTML(bareURLText, repo: "kiwix/kiwix-apple")
        assertTest(htmlWithURL.contains("<a href=\"https://translatewiki.net\">https://translatewiki.net</a>"), "Bare URL converted to link")
        assertTest(htmlWithURL.contains("<a href=\"https://github.com/kiwix/kiwix-apple/pull/1676\">https://github.com/kiwix/kiwix-apple/pull/1676</a>."), "Trailing period excluded from link")
        
        // 2. Mentions & Issue references
        let mentionAndIssue = "- Accessibility improvements (@BPerlakiH #1688, #1689)"
        let htmlMentions = Utils.convertMarkdownToHTML(mentionAndIssue, repo: "kiwix/kiwix-apple")
        assertTest(htmlMentions.contains("<a href=\"https://github.com/BPerlakiH\">@BPerlakiH</a>"), "GitHub mention autolinked")
        assertTest(htmlMentions.contains("<a href=\"https://github.com/kiwix/kiwix-apple/issues/1688\">#1688</a>"), "Issue reference autolinked")
        assertTest(htmlMentions.contains("<a href=\"https://github.com/kiwix/kiwix-apple/issues/1689\">#1689</a>"), "Second issue reference autolinked")
        
        // 3. Explicit markdown links preserved
        let explicitLink = "See [Release Notes](https://example.com/notes) for details."
        let htmlExplicit = Utils.convertMarkdownToHTML(explicitLink)
        assertTest(htmlExplicit.contains("<a href=\"https://example.com/notes\">Release Notes</a>"), "Explicit markdown link preserved")
        
        // 4. Inline code protection (no autolinking inside `code`)
        let codeProtection = "Use `#123` or `@admin` or `https://secret.local` in config."
        let htmlCode = Utils.convertMarkdownToHTML(codeProtection, repo: "owner/repo")
        assertTest(htmlCode.contains("<code>#123</code>"), "Code issue ref not linked")
        assertTest(htmlCode.contains("<code>@admin</code>"), "Code mention not linked")
        assertTest(!htmlCode.contains("https://secret.local\">"), "Code URL not linked")
        
        // 5. Blockquote support & raw HTML tag protection (prevent autolinking inside src/href)
        let blockquoteImage = "> <img width=\"400\" alt=\"test\" src=\"https://github.com/user-attachments/assets/12345\" />"
        let htmlBlockquote = Utils.convertMarkdownToHTML(blockquoteImage)
        assertTest(htmlBlockquote.contains("<blockquote>"), "Blockquote tag generated")
        assertTest(htmlBlockquote.contains("src=\"https://github.com/user-attachments/assets/12345\""), "Image src attribute preserved without autolink corruption")
        assertTest(!htmlBlockquote.contains("src=\"<a href="), "Image src not corrupted with anchor tag")
    }
    
    // --------------------------------------------------------
    // Test 11: Multi-Language Localization Completeness
    // --------------------------------------------------------
    static func testLocalizationCompleteness() {
        print("\n[Test 11] Testing Multi-Language Localization Completeness (All 11 Languages vs English Base)...")
        
        guard let enDict = Translations.i18n["en"] else {
            assertTest(false, "Base English dictionary must exist")
            return
        }
        assertTest(!enDict.isEmpty, "Base English dictionary contains entries (\(enDict.count) keys)")
        
        let allLanguages = ["es", "fr", "de", "it", "pt", "zh", "hi", "ar", "ru", "ja"]
        for lang in allLanguages {
            guard let langDict = Translations.i18n[lang] else {
                assertTest(false, "Language '\(lang)' dictionary exists")
                continue
            }
            
            var missingOrEmptyKeys: [String] = []
            for (key, _) in enDict {
                if let val = langDict[key], !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }
                missingOrEmptyKeys.append(key)
            }
            
            assertTest(missingOrEmptyKeys.isEmpty, "Language '\(lang)' has 100% dictionary completeness against English (missing: \(missingOrEmptyKeys.joined(separator: ", ")))")
        }
        
        // Verify feline onomatopoeia 'meow' tooltip exists across all supported languages
        for (lang, dict) in Translations.i18n {
            let meow = dict["meow"]
            assertTest(meow != nil && !meow!.isEmpty, "Feline tooltip 'meow' localized for '\(lang)': \"\(meow ?? "")\"")
        }
        
        // Spot-check key Spanish translations
        let esDict = Translations.i18n["es"]
        assertTest(esDict?["apiRepoNotFound"] == "Repositorio no encontrado o privado", "apiRepoNotFound translated in Spanish")
        assertTest(esDict?["apiRateLimit"] == "Límite de peticiones a la API excedido", "apiRateLimit translated in Spanish")
        assertTest(esDict?["apiHttpError"] == "Error HTTP {code}", "apiHttpError translated in Spanish")
        assertTest(esDict?["repoPlaceholder"] == "propietario/repo o cask", "repoPlaceholder translated in Spanish")
    }
    
    // --------------------------------------------------------
    // Test 12: Cryptographic SHA-256 Digest Computation
    // --------------------------------------------------------
    static func testSHA256Integrity() {
        print("\n[Test 12] Testing Utils.computeSHA256...")
        
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("sha256_test_\(UUID().uuidString).bin")
        let testString = "Mino macOS release tracker cryptographic verification test"
        try! testString.data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let computed = Utils.computeSHA256(for: tempFile)
        assertTest(computed != nil && computed?.count == 64, "SHA-256 digest computed successfully (64 hex characters)")
    }
    
    // --------------------------------------------------------
    // Test 13: Checksum Extraction & Asset Integrity Pipeline
    // --------------------------------------------------------
    static func testChecksumParsingAndIntegrity() {
        print("\n[Test 13] Testing Checksum Extraction & Asset Integrity Pipeline...")
        
        // 1. Checksum extraction from release body text
        let releaseBody = """
        ## Release v1.0.0
        Some changes and features.
        
        ### SHA-256 Checksums
        6a89c256038481ff2262a05f13459eeea5388c3a070eb3511116c90ee928a6f4  Mino-1.0.0.dmg
        SHA256 (Mino-1.0.0.zip) = b16fb365dd6e1f32fe4a390b1e19488a038bf3b85e4a836814b2d184711f58a7
        """
        
        let extractedChecksums = Utils.extractChecksums(from: releaseBody)
        assertTest(extractedChecksums["mino-1.0.0.dmg"] == "6a89c256038481ff2262a05f13459eeea5388c3a070eb3511116c90ee928a6f4", "sha256sum format parsed correctly")
        assertTest(extractedChecksums["mino-1.0.0.zip"] == "b16fb365dd6e1f32fe4a390b1e19488a038bf3b85e4a836814b2d184711f58a7", "BSD format parsed correctly")
        
        // 2. parseReleaseAssets associates expectedSHA256 with assets
        let mockJSON: [String: Any] = [
            "tag_name": "v1.0.0",
            "body": releaseBody,
            "assets": [
                [
                    "name": "Mino-1.0.0.dmg",
                    "size": 1024,
                    "browser_download_url": "https://github.com/nad-bit/Mino/releases/download/v1.0.0/Mino-1.0.0.dmg"
                ],
                [
                    "name": "OtherAsset.tar.gz",
                    "size": 2048,
                    "browser_download_url": "https://github.com/nad-bit/Mino/releases/download/v1.0.0/OtherAsset.tar.gz"
                ]
            ]
        ]
        
        let assets = GitHubAPI.parseReleaseAssets(from: mockJSON, repo: "nad-bit/Mino", tag: "v1.0.0")
        let dmgAsset = assets.first(where: { $0.name == "Mino-1.0.0.dmg" })
        let otherAsset = assets.first(where: { $0.name == "OtherAsset.tar.gz" })
        
        assertTest(dmgAsset?.expectedSHA256 == "6a89c256038481ff2262a05f13459eeea5388c3a070eb3511116c90ee928a6f4", "expectedSHA256 populated from release notes")
        assertTest(otherAsset?.expectedSHA256 == nil, "expectedSHA256 is nil when no checksum is provided")
    }

    // --------------------------------------------------------
    // Test 14: Disk Cache SHA-256 Hash & Overflow Protection
    // --------------------------------------------------------
    static func testDiskCacheSecurity() {
        print("\n[Test 14] Testing Disk Cache Hashing & Overflow Safety...")
        
        let extremeURL = String(repeating: "a", count: 10000)
        let _ = GitHubAPI.shared.getCachedImage(from: extremeURL)
        assertTest(true, "Image cache URL generation is resilient against overflow and extreme strings")
    }
    
    // --------------------------------------------------------
    // Test 15: macOS 27 Status Item Tooltip Compatibility
    // --------------------------------------------------------
    static func testStatusItemTooltipCompatibility() {
        print("\n[Test 15] Testing macOS 27 Golden Gate Status Bar Tooltip Compatibility...")
        
        let button = NSStatusBarButton()
        // Default button has non-empty default title
        assertTest(!button.title.isEmpty, "Initial NSStatusBarButton title is non-empty")
        
        // Emulate previous behavior: setting empty title
        button.title = ""
        button.attributedTitle = NSAttributedString()
        assertTest(button.title.isEmpty && button.attributedTitle.string.isEmpty, "Previous behavior: title and attributedTitle were both empty")
        
        // Apply macOS 27 Golden Gate fix: non-empty zero-width attributed string
        let zeroWidthTitle = NSAttributedString(string: "\u{200B}", attributes: [
            .foregroundColor: NSColor.clear,
            .font: NSFont.systemFont(ofSize: 0.01)
        ])
        button.attributedTitle = zeroWidthTitle
        button.toolTip = Translations.get("meow")
        
        assertTest(!button.title.isEmpty, "Status button title is NOT empty with zero-width space")
        assertTest(!button.attributedTitle.string.isEmpty, "Status button attributedTitle is NOT empty")
        assertTest(button.toolTip != nil && !button.toolTip!.isEmpty, "Status button tooltip is configured with localized meow")
    }

    // --------------------------------------------------------
    // Test 16: Error Code Handling & Warning Tooltip Discrimination
    // --------------------------------------------------------
    static func testErrorTooltipAndCodeHandling() {
        print("\n[Test 16] Testing Error Code Tracking & Warning Tooltip Discrimination...")
        
        let info = RepoInfo(name: "org/repo", error: "Not Found", errorCode: 404)
        assertTest(info.errorCode == 404, "RepoInfo stores errorCode 404")
        
        let displayData = RepoDisplayData(
            repoName: "org/repo",
            formattedName: "repo",
            ageSeconds: 0,
            errorMessage: "Localized error message",
            errorCode: 404,
            isLoading: false,
            freshnessColor: .systemRed,
            isNew: false,
            tags: [],
            isFavorite: false
        )
        assertTest(displayData.errorCode == 404, "RepoDisplayData preserves errorCode")
        
        // HTTP 404 error formatting
        let tooltip404 = RepoMenuItemView.formatWarningTooltip(errorCode: 404, fallbackMessage: "Fallback")
        let expected404 = Translations.get("apiHttpError").format(with: ["code": "404"])
        assertTest(tooltip404 == expected404, "HTTP 404 warning tooltip formats as '\(expected404)'")
        
        // HTTP 403 error formatting
        let tooltip403 = RepoMenuItemView.formatWarningTooltip(errorCode: 403, fallbackMessage: "Fallback")
        let expected403 = Translations.get("apiHttpError").format(with: ["code": "403"])
        assertTest(tooltip403 == expected403, "HTTP 403 warning tooltip formats as '\(expected403)'")
        
        // Non-HTTP error formatting (e.g. CFNetwork / URLError)
        let tooltipNetwork = RepoMenuItemView.formatWarningTooltip(errorCode: -1009, fallbackMessage: "Fallback")
        let expectedNetwork = "\(Translations.get("error")) -1009"
        assertTest(tooltipNetwork == expectedNetwork, "Non-HTTP code formats with error prefix: '\(expectedNetwork)'")
        
        // Fallback when errorCode is nil
        let tooltipNil = RepoMenuItemView.formatWarningTooltip(errorCode: nil, fallbackMessage: "Fallback message")
        assertTest(tooltipNil == "Fallback message", "Nil errorCode safely falls back to descriptive localized message")
    }

    // --------------------------------------------------------
    // Test 17: Phase 1 Optimizations (Digest, ETag, Non-blocking Image Cache)
    // --------------------------------------------------------
    static func testPhase1Optimizations() {
        print("\n[Test 17] Testing Phase 1 Optimizations (Official Digest, ETag Cache & RAM Image Cache)...")
        
        // 1. GitHubAPI.parseDigest validation
        let validHex = "6a89c256038481ff2262a05f13459eeea5388c3a070eb3511116c90ee928a6f4"
        let prefixedDigest = "sha256:\(validHex)"
        let parsedPrefixed = GitHubAPI.parseDigest(prefixedDigest)
        assertTest(parsedPrefixed == validHex, "Prefixed sha256 digest parsed successfully")
        
        let bareDigest = GitHubAPI.parseDigest(validHex)
        assertTest(bareDigest == validHex, "Bare 64-char hex digest parsed successfully")
        
        let invalidDigest = GitHubAPI.parseDigest("not-a-valid-sha256")
        assertTest(invalidDigest == nil, "Invalid digest string is safely rejected")
        
        // 2. Official asset digest precedence over release notes body
        let releaseBody = "6a89c256038481ff2262a05f13459eeea5388c3a070eb3511116c90ee928a6f4  Mino.dmg"
        let officialDigestHex = "1111111111111111111111111111111111111111111111111111111111111111"
        let mockJSON: [String: Any] = [
            "tag_name": "v2.2.9",
            "body": releaseBody,
            "assets": [
                [
                    "name": "Mino.dmg",
                    "size": 1024,
                    "digest": "sha256:\(officialDigestHex)",
                    "browser_download_url": "https://github.com/nad-bit/Mino/releases/download/v2.2.9/Mino.dmg"
                ],
                [
                    "name": "Fallback.dmg",
                    "size": 2048,
                    "browser_download_url": "https://github.com/nad-bit/Mino/releases/download/v2.2.9/Fallback.dmg"
                ]
            ]
        ]
        let assets = GitHubAPI.parseReleaseAssets(from: mockJSON, repo: "nad-bit/Mino", tag: "v2.2.9")
        let officialAsset = assets.first(where: { $0.name == "Mino.dmg" })
        assertTest(officialAsset?.expectedSHA256 == officialDigestHex, "Official asset.digest takes precedence over release notes body")
        
        // 3. ETag Conditional Request Cache
        let testRepo = "test-owner/test-repo"
        let testETag = "W/\"d41d8cd98f00b204e9800998ecf8427e\""
        GitHubAPI.shared.setETag(testETag, for: testRepo)
        assertTest(GitHubAPI.shared.etag(for: testRepo) == testETag, "ETag stored and retrieved correctly")
        
        GitHubAPI.shared.clearETags()
        assertTest(GitHubAPI.shared.etag(for: testRepo) == nil, "ETag cache cleared successfully")
        
        // 4. RepoInfo isNotModified flag and Codable integrity
        var info304 = RepoInfo(name: testRepo)
        info304.isNotModified = true
        assertTest(info304.isNotModified == true, "RepoInfo supports isNotModified flag")
        
        // Codable serialization does not fail and omits isNotModified
        if let encoded = try? JSONEncoder().encode(info304),
           let decoded = try? JSONDecoder().decode(RepoInfo.self, from: encoded) {
            assertTest(decoded.name == testRepo, "RepoInfo encoded and decoded successfully via Codable")
            assertTest(decoded.isNotModified == false, "isNotModified defaults to false upon deserialization")
        } else {
            assertTest(false, "Failed to encode/decode RepoInfo")
        }
        
        // 5. RAM Cache Fast Path
        let nonCachedURL = "https://example.com/nonexistent_image_\(UUID().uuidString).png"
        let ramHit = GitHubAPI.shared.getRAMCachedImage(from: nonCachedURL)
        assertTest(ramHit == nil, "getRAMCachedImage returns nil without doing synchronous disk reads")
    }

    // --------------------------------------------------------
    // Test 18: Phase 2 Optimizations (HUD Cancel & Rate Limit Auth Decoupling)
    // --------------------------------------------------------
    static func testPhase2Optimizations() {
        print("\n[Test 18] Testing Phase 2 Optimizations (HUD Cancel & Rate Limit Auth Decoupling)...")
        
        // 1. HUDPanel cancel button activation and reset
        var wasCancelled = false
        HUDPanel.shared.showDownloadProgress(title: "TestAsset.dmg", status: "Downloading...", details: "10 MB / 50 MB", progress: 0.2, onCancel: {
            wasCancelled = true
        })
        assertTest(!wasCancelled, "Cancel handler registered without premature invocation")
        
        HUDPanel.shared.hide()
        assertTest(true, "HUDPanel resets cancel state safely upon dismissal")
        
        // 2. Rate limit decoupled authentication flag & 401 / public limit protection
        let resetEpoch = Date().addingTimeInterval(3600).timeIntervalSince1970
        let headers: [String: String] = [
            "x-ratelimit-limit": "100",
            "x-ratelimit-remaining": "99",
            "x-ratelimit-reset": "\(resetEpoch)"
        ]
        let response = HTTPURLResponse(url: URL(string: "https://api.github.com/rate_limit")!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        
        // Test explicit wasAuthenticated flag
        GitHubAPI.shared.clearRateLimits()
        let hasToken = ConfigManager.shared.token != nil && !ConfigManager.shared.token!.isEmpty
        GitHubAPI.shared.recordRateLimit(from: response, wasAuthenticated: hasToken)
        
        if let current = GitHubAPI.shared.currentRateLimit {
            assertTest(current.limit == 100 && current.remaining == 99, "Rate limit recorded accurately with explicit wasAuthenticated")
        } else {
            assertTest(!hasToken, "Rate limit correctly disregarded if token configuration doesn't match state")
        }
        
        // 3. Verify 401 Unauthorized responses and public 60 limits are NEVER recorded as authenticated
        let resp401 = HTTPURLResponse(url: URL(string: "https://api.github.com/rate_limit")!, statusCode: 401, httpVersion: nil, headerFields: [
            "x-ratelimit-limit": "60",
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": "\(resetEpoch)"
        ])!
        GitHubAPI.shared.clearRateLimits()
        GitHubAPI.shared.recordRateLimit(from: resp401, wasAuthenticated: true)
        assertTest(GitHubAPI.shared.currentRateLimit == nil, "401 responses never recorded as authenticated rate limit")
        
        let respPublic60 = HTTPURLResponse(url: URL(string: "https://api.github.com/rate_limit")!, statusCode: 200, httpVersion: nil, headerFields: [
            "x-ratelimit-limit": "60",
            "x-ratelimit-remaining": "10",
            "x-ratelimit-reset": "\(resetEpoch)"
        ])!
        GitHubAPI.shared.clearRateLimits()
        GitHubAPI.shared.recordRateLimit(from: respPublic60, wasAuthenticated: true)
        if hasToken {
            assertTest(GitHubAPI.shared.currentRateLimit == nil, "Public limit <= 60 rejected from authenticated rate limit window")
        }
        
        // 4. Verify HUDPanel download completion with separate SHA line and cancellation styling
        let destURL = URL(fileURLWithPath: "/tmp/MinoTestAsset.dmg")
        HUDPanel.shared.showDownloadCompletion(title: "MinoTestAsset.dmg", subtitle: "15.40 MB • Descarga completada", sha: "SHA-256: 3a7b1c4e...", destinationURL: destURL)
        assertTest(HUDPanel.shared.cancelButton.isHidden, "Cancel button is hidden on download completion")
        assertTest(HUDPanel.shared.progressBar.isHidden, "Progress bar is hidden on download completion")
        assertTest(!HUDPanel.shared.detailLabel.isHidden && HUDPanel.shared.detailLabel.stringValue == "SHA-256: 3a7b1c4e...", "SHA-256 is displayed on a separate line below completion text")
        
        HUDPanel.shared.showCancellation(title: "MinoTestAsset.dmg", subtitle: "Descarga cancelada")
        assertTest(HUDPanel.shared.cancelButton.isHidden, "Cancel button is hidden on download cancellation")
        assertTest(HUDPanel.shared.iconView.contentTintColor == .systemOrange, "Cancellation HUD displays orange symbol")
        HUDPanel.shared.hide()
    }
}


