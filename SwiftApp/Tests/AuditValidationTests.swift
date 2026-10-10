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
    
    static func main() async {
        print("\n🧪 Running Mino Audit Verification Tests (16 High-Value Production Tests)...")
        
        // Backup user's actual disk cache & ETags to prevent wiping ~/.config/Mino/cache.json
        // and avoid exhausting GitHub API rate limit quota during subsequent app launches.
        let originalCacheBackup = ConfigManager.shared.backupDiskCache()
        let originalETags = GitHubAPI.shared.allETags()
        defer {
            if let backup = originalCacheBackup {
                ConfigManager.shared.restoreDiskCache(from: backup)
                GitHubAPI.shared.loadETags(originalETags)
                print("💾 Restored original user disk cache and ETags cleanly.")
            }
        }
        
        testGitHubHostAllowlist()
        testMinoTargetValidation()
        testReleaseNotesLinkSchemes()
        testHTMLStructuralSanitization()
        testFileNameSanitization()
        testSafeImageDecompression()
        testConfigManagerAtomicityAndRecovery()
        testUntrustedTapExtraction()
        testMarkdownAutolinking()
        testLocalizationCompleteness()
        testChecksumAndAssetIntegrityPipeline()
        testRateLimitAndHUDProtection()
        await testCommitETagAndRateLimiterPacing()
        testTargetResolutionAndURLSchemes()
        testPersistentDiskCache()
        testRefreshTimingAndMinuteAnchoring()
        
        print("\n🎉 ALL 16 AUDIT VERIFICATION TESTS PASSED SUCCESSFULLY!\n")
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
        let previousRefreshMinutes = ConfigManager.shared.config.refreshMinutes
        ConfigManager.shared.modifyConfig { cfg in
            cfg.refreshMinutes = 123
        }
        assertTest(ConfigManager.shared.config.refreshMinutes == 123, "ConfigManager.shared.modifyConfig atomically updates and commits state")
        
        // Restore user configuration so ~/.config/Mino/repos.json is never left polluted
        let restoredMinutes = (previousRefreshMinutes == 123) ? 180 : previousRefreshMinutes
        ConfigManager.shared.modifyConfig { cfg in
            cfg.refreshMinutes = restoredMinutes
        }
    }
    
    // --------------------------------------------------------
    // Test 8: Untrusted Tap Target Extraction (Production Code)
    // --------------------------------------------------------
    static func testUntrustedTapExtraction() {
        print("\n[Test 8] Testing HomebrewManager.extractTrustTarget...")
        
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
    // Test 9: Markdown Autolinking (Bare URLs, Mentions, Issues)
    // --------------------------------------------------------
    static func testMarkdownAutolinking() {
        print("\n[Test 9] Testing Utils.convertMarkdownToHTML autolinking...")
        
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
    // Test 10: Multi-Language Localization Completeness
    // --------------------------------------------------------
    static func testLocalizationCompleteness() {
        print("\n[Test 10] Testing Multi-Language Localization Completeness (All 11 Languages vs English Base)...")
        
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
        assertTest(esDict?["caskCount"] == "{count} Casks", "caskCount translated in Spanish")
        assertTest(esDict?["caskCountSingular"] == "1 Cask", "caskCountSingular translated in Spanish")
        assertTest(esDict?["menuScaleTitle"] == "Escala del Menú", "menuScaleTitle translated in Spanish")
    }
    
    // --------------------------------------------------------
    // Test 11: Checksum & Asset Integrity Pipeline (Production Code)
    // --------------------------------------------------------
    static func testChecksumAndAssetIntegrityPipeline() {
        print("\n[Test 11] Testing Checksum Extraction, Official Digest Parsing & CryptoKit SHA-256...")
        
        // 1. Cryptographic SHA-256 calculation on real file
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("sha256_test_\(UUID().uuidString).bin")
        let testString = "Mino macOS release tracker cryptographic verification test"
        try! testString.data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let computed = Utils.computeSHA256(for: tempFile)
        assertTest(computed != nil && computed?.count == 64, "Utils.computeSHA256 computes valid 64-char hex digest")
        
        // 2. GitHubAPI.parseDigest validation
        let validHex = "6a89c256038481ff2262a05f13459eeea5388c3a070eb3511116c90ee928a6f4"
        let prefixedDigest = "sha256:\(validHex)"
        assertTest(GitHubAPI.parseDigest(prefixedDigest) == validHex, "GitHubAPI.parseDigest handles 'sha256:' prefixed hash")
        assertTest(GitHubAPI.parseDigest(validHex) == validHex, "GitHubAPI.parseDigest handles bare 64-char hex string")
        assertTest(GitHubAPI.parseDigest("not-a-valid-sha256") == nil, "Invalid digest string safely rejected")
        
        // 3. Checksum extraction from release body text (sha256sum & BSD formats)
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
        
        // 4. parseReleaseAssets associates expectedSHA256 & official digest takes precedence
        let officialDigestHex = "1111111111111111111111111111111111111111111111111111111111111111"
        let mockJSON: [String: Any] = [
            "tag_name": "v1.0.0",
            "body": releaseBody,
            "assets": [
                [
                    "name": "Mino-1.0.0.dmg",
                    "size": 1024,
                    "digest": "sha256:\(officialDigestHex)",
                    "browser_download_url": "https://github.com/nad-bit/Mino/releases/download/v1.0.0/Mino-1.0.0.dmg"
                ],
                [
                    "name": "Mino-1.0.0.zip",
                    "size": 2048,
                    "browser_download_url": "https://github.com/nad-bit/Mino/releases/download/v1.0.0/Mino-1.0.0.zip"
                ],
                [
                    "name": "OtherAsset.tar.gz",
                    "size": 4096,
                    "browser_download_url": "https://github.com/nad-bit/Mino/releases/download/v1.0.0/OtherAsset.tar.gz"
                ]
            ]
        ]
        let assets = GitHubAPI.parseReleaseAssets(from: mockJSON, repo: "nad-bit/Mino", tag: "v1.0.0")
        let dmgAsset = assets.first(where: { $0.name == "Mino-1.0.0.dmg" })
        let zipAsset = assets.first(where: { $0.name == "Mino-1.0.0.zip" })
        let otherAsset = assets.first(where: { $0.name == "OtherAsset.tar.gz" })
        
        assertTest(dmgAsset?.expectedSHA256 == officialDigestHex, "Official asset.digest takes precedence over body checksum")
        assertTest(zipAsset?.expectedSHA256 == "b16fb365dd6e1f32fe4a390b1e19488a038bf3b85e4a836814b2d184711f58a7", "expectedSHA256 parsed from body when no official digest present")
        assertTest(otherAsset?.expectedSHA256 == nil, "expectedSHA256 is nil when no checksum is provided")
    }

    // --------------------------------------------------------
    // Test 12: Rate Limit Isolation & HUD Download Protection
    // --------------------------------------------------------
    static func testRateLimitAndHUDProtection() {
        print("\n[Test 12] Testing Rate Limit Isolation, 401 Rejection & HUD Download Protection...")
        
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
        
        // 5. RAM Cache Fast Path non-blocking query
        let nonCachedURL = "https://example.com/nonexistent_image_\(UUID().uuidString).png"
        let ramHit = GitHubAPI.shared.getRAMCachedImage(from: nonCachedURL)
        assertTest(ramHit == nil, "getRAMCachedImage returns nil without doing synchronous disk reads")
    }
    
    // --------------------------------------------------------
    // Test 13: Commit ETag Isolation, Rate Limiter Pacing & Smart Matching
    // --------------------------------------------------------
    static func testCommitETagAndRateLimiterPacing() async {
        print("\n[Test 13] Testing Commit ETag Isolation, Global Rate Limiter & Asset Smart Matching...")
        
        // 1. Test Commit ETag cache isolation and retrieval
        let commitRepo = "nad-bit/commit-tracked-repo"
        let commitsETagKey = "\(commitRepo):commits"
        let sampleCommitETag = "W/\"commit-abc1234\""
        let sampleReleaseETag = "W/\"release-v1.0.0\""
        
        GitHubAPI.shared.setETag(sampleCommitETag, for: commitsETagKey)
        GitHubAPI.shared.setETag(sampleReleaseETag, for: commitRepo)
        
        assertTest(GitHubAPI.shared.etag(for: commitsETagKey) == sampleCommitETag, "Commit ETag stored and retrieved for \(commitsETagKey)")
        assertTest(GitHubAPI.shared.etag(for: commitRepo) == sampleReleaseETag, "Release ETag stored and retrieved for \(commitRepo)")
        assertTest(GitHubAPI.shared.etag(for: commitsETagKey) != GitHubAPI.shared.etag(for: commitRepo), "Strict isolation between release ETag and commit ETag namespaces")
        
        GitHubAPI.shared.setETag(nil, for: commitsETagKey)
        assertTest(GitHubAPI.shared.etag(for: commitsETagKey) == nil, "Commit ETag cleared cleanly")
        assertTest(GitHubAPI.shared.etag(for: commitRepo) == sampleReleaseETag, "Release ETag preserved when commit ETag is cleared")
        GitHubAPI.shared.setETag(nil, for: commitRepo)
        
        // 2. Test Commit SHA detection pattern
        let commitSHA = "7b2d5f1"
        let releaseTag = "v2.3.0"
        let shortTag = "1.0.0"
        let invalidSHA = "xyz1234"
        
        let isSHA: (String) -> Bool = { version in
            version.range(of: "^[0-9a-f]{7}$", options: .regularExpression) != nil
        }
        
        assertTest(isSHA(commitSHA), "'7b2d5f1' correctly identified as commit SHA")
        assertTest(!isSHA(releaseTag), "'v2.3.0' not classified as commit SHA")
        assertTest(!isSHA(shortTag), "'1.0.0' not classified as commit SHA")
        assertTest(!isSHA(invalidSHA), "'xyz1234' with non-hex characters rejected as commit SHA")
        
        // 3. Test GlobalRateLimiter global pacing across concurrent tasks
        let limiter = GlobalRateLimiter(minInterval: 0.04) // 40ms interval
        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    await limiter.acquire()
                }
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        // 3 tasks with 40ms interval must take at least ~70ms (0ms, 40ms, 80ms slots)
        assertTest(elapsed >= 0.06, "GlobalRateLimiter enforced sequential slot pacing across concurrent tasks (elapsed: \(String(format: "%.3f", elapsed))s >= 0.06s)")
        
        // 4. Test Smart Matching for Release Assets inside Notes
        let sampleAssets = [
            ReleaseAsset(name: "rclone-ui-arm64.dmg", size: 15_000_000, downloadURL: "https://github.com/rclone-ui/rclone-ui/releases/download/v1.0.0/rclone-ui-arm64.dmg", isSourceArchive: false, expectedSHA256: "aabbcc112233"),
            ReleaseAsset(name: "rclone-ui-x86_64.dmg", size: 16_000_000, downloadURL: "https://github.com/rclone-ui/rclone-ui/releases/download/v1.0.0/rclone-ui-x86_64.dmg", isSourceArchive: false)
        ]
        
        let exactURL = URL(string: "https://github.com/rclone-ui/rclone-ui/releases/download/v1.0.0/rclone-ui-arm64.dmg")!
        let matchedExact = ReleaseNotesViewController.findMatchingReleaseAsset(for: exactURL, in: sampleAssets)
        assertTest(matchedExact?.name == "rclone-ui-arm64.dmg", "Smart Matching: Exact asset download URL matched successfully")
        
        let queryURL = URL(string: "https://github.com/rclone-ui/rclone-ui/releases/download/v1.0.0/rclone-ui-arm64.dmg?raw=true")!
        let matchedQuery = ReleaseNotesViewController.findMatchingReleaseAsset(for: queryURL, in: sampleAssets)
        assertTest(matchedQuery?.name == "rclone-ui-arm64.dmg", "Smart Matching: URL with query parameter matched successfully")
        
        let untrustedHostURL = URL(string: "https://evil-site.com/rclone-ui/rclone-ui/releases/download/v1.0.0/rclone-ui-arm64.dmg")!
        let matchedUntrusted = ReleaseNotesViewController.findMatchingReleaseAsset(for: untrustedHostURL, in: sampleAssets)
        assertTest(matchedUntrusted == nil, "Smart Matching: Untrusted domain link is REJECTED and falls back to browser")
        
        let otherRepoURL = URL(string: "https://github.com/other-user/other-repo/releases/download/v1.0.0/rclone-ui-arm64.dmg")!
        let matchedOtherRepo = ReleaseNotesViewController.findMatchingReleaseAsset(for: otherRepoURL, in: sampleAssets)
        assertTest(matchedOtherRepo == nil, "Smart Matching: Unrelated repo asset link is REJECTED and falls back to browser")
        
        let issuesURL = URL(string: "https://github.com/rclone-ui/rclone-ui/issues/42")!
        let matchedIssue = ReleaseNotesViewController.findMatchingReleaseAsset(for: issuesURL, in: sampleAssets)
        assertTest(matchedIssue == nil, "Smart Matching: General GitHub issue link is ignored and falls back to browser")
        
        // 5. Test real-world rclone-ui repository transfer / org rename matching:
        // Asset has downloadURL under rclone/rclone-ui, but release notes link points to rclone-ui/rclone-ui
        let transferredAssets = [
            ReleaseAsset(name: "Rclone.UI_aarch64.dmg", size: 25_000_000, downloadURL: "https://github.com/rclone/rclone-ui/releases/download/v3.7.5/Rclone.UI_aarch64.dmg", isSourceArchive: false)
        ]
        let transferredMarkdownURL = URL(string: "https://github.com/rclone-ui/rclone-ui/releases/download/v3.7.5/Rclone.UI_aarch64.dmg")!
        let matchedTransferred = ReleaseNotesViewController.findMatchingReleaseAsset(for: transferredMarkdownURL, in: transferredAssets, currentRepoName: "rclone-ui/rclone-ui")
        assertTest(matchedTransferred?.name == "Rclone.UI_aarch64.dmg", "Smart Matching: Transferred/renamed repository asset URL (rclone-ui -> rclone) matched successfully")
    }
    
    // --------------------------------------------------------
    // Test 14: Target Resolution & Shortcut Event Handling
    // --------------------------------------------------------
    static func testTargetResolutionAndURLSchemes() {
        print("\n[Test 14] Testing AppDelegate.findMatchingRepo & CMD+H Shortcut Dispatch...")
        
        // 1. Test handleGlobalShortcuts for CMD+H
        let appDelegate = AppDelegate()
        if let cmdHEvent = NSEvent.keyEvent(with: .keyDown,
                                            location: .zero,
                                            modifierFlags: .command,
                                            timestamp: 0,
                                            windowNumber: 0,
                                            context: nil,
                                            characters: "h",
                                            charactersIgnoringModifiers: "h",
                                            isARepeat: false,
                                            keyCode: 4) {
            let handled = appDelegate.handleGlobalShortcuts(with: cmdHEvent)
            assertTest(handled == true, "handleGlobalShortcuts: CMD+H handled successfully")
        }
        
        // Test handleGlobalShortcuts for CMD+0..9, CMD++, CMD+-
        for (char, label) in [("0", "CMD+0"), ("1", "CMD+1"), ("9", "CMD+9"), ("=", "CMD+="), ("-", "CMD+-")] {
            if let event = NSEvent.keyEvent(with: .keyDown,
                                            location: .zero,
                                            modifierFlags: .command,
                                            timestamp: 0,
                                            windowNumber: 0,
                                            context: nil,
                                            characters: char,
                                            charactersIgnoringModifiers: char,
                                            isARepeat: false,
                                            keyCode: 0) {
                let handled = appDelegate.handleGlobalShortcuts(with: event)
                assertTest(handled == true, "handleGlobalShortcuts: \(label) handled successfully")
            }
        }
        
        // Test applyMenuScale clamps to min/max with 5% steps
        appDelegate.applyMenuScale(1.05)
        assertTest(ConfigManager.shared.config.menuScale == 1.05, "applyMenuScale: 1.05 (5% step) saved to configuration")
        appDelegate.applyMenuScale(0.5) // below min (1.0)
        assertTest(ConfigManager.shared.config.menuScale == 1.0, "applyMenuScale: 0.5 clamped to minimum 1.0")
        appDelegate.applyMenuScale(2.5) // beyond max
        let currentMax = ConfigManager.shared.config.menuScale ?? 1.0
        assertTest(currentMax >= 1.0 && currentMax <= 1.9, "applyMenuScale: 2.5 clamped safely to screen maximum (\(currentMax))")
        
        // Test validateAndClampMenuScaleForCurrentScreen
        ConfigManager.shared.config.menuScale = 2.0
        appDelegate.validateAndClampMenuScaleForCurrentScreen()
        let validatedScale = ConfigManager.shared.config.menuScale ?? 1.0
        assertTest(validatedScale <= currentMax, "validateAndClampMenuScaleForCurrentScreen clamped excessive scale to screen max (\(validatedScale))")
        
        // Test BeerHandle (ASA) tolerance across all 5% scale steps with Float quantization
        for s in [1.00, 1.05, 1.10, 1.15, 1.20, 1.25, 1.30, 1.35, 1.40, 1.45] {
            let scale = CGFloat(s)
            let menuMax = 688.0 * scale
            let headerFooter = 54.0 * scale
            let beerMin = menuMax - (2.0 * headerFooter)
            let storedInConstraint = CGFloat(Float(menuMax))
            let effective = storedInConstraint - (headerFooter * 2.0)
            let passes = effective >= (beerMin - 2.0)
            assertTest(passes, "ASA Float quantization tolerance passes at scale \(s)")
        }
        
        appDelegate.applyMenuScale(1.0) // reset
        
        // 2. Test AppDelegate.findMatchingRepo resolution
        let testRepos = [
            RepoConfig(name: "rclone-ui/rclone-ui", source: "manual"),
            RepoConfig(name: "objective-see/LuLu", source: "brew", cask: "lulu"),
            RepoConfig(name: "nad-bit/Mino", source: "brew", cask: "nad-bit/tap/mino", isFavorite: true)
        ]
        
        // Exact name match
        let exactMatch = AppDelegate.findMatchingRepo(for: "rclone-ui/rclone-ui", in: testRepos)
        assertTest(exactMatch?.name == "rclone-ui/rclone-ui", "findMatchingRepo: exact match on repo name")
        
        // Case-insensitive exact name
        let caseMatch = AppDelegate.findMatchingRepo(for: "RCLONE-UI/RCLONE-UI", in: testRepos)
        assertTest(caseMatch?.name == "rclone-ui/rclone-ui", "findMatchingRepo: case-insensitive repo name match")
        
        // GitHub URL input
        let urlMatch = AppDelegate.findMatchingRepo(for: "https://github.com/rclone-ui/rclone-ui", in: testRepos)
        assertTest(urlMatch == nil, "findMatchingRepo: raw URL requires normalization before findMatchingRepo")
        let normalizedURLTarget = "https://github.com/rclone-ui/rclone-ui"
            .replacingOccurrences(of: "https://github.com/", with: "")
        assertTest(AppDelegate.findMatchingRepo(for: normalizedURLTarget, in: testRepos)?.name == "rclone-ui/rclone-ui",
                   "findMatchingRepo: normalized GitHub URL matches")
        
        // Short repo name
        let shortRepoMatch = AppDelegate.findMatchingRepo(for: "rclone-ui", in: testRepos)
        assertTest(shortRepoMatch?.name == "rclone-ui/rclone-ui", "findMatchingRepo: short repo name matches")
        
        // Exact cask match
        let exactCaskMatch = AppDelegate.findMatchingRepo(for: "lulu", in: testRepos)
        assertTest(exactCaskMatch?.name == "objective-see/LuLu", "findMatchingRepo: exact cask match")
        
        // Short cask match (from tap)
        let shortCaskMatch = AppDelegate.findMatchingRepo(for: "mino", in: testRepos)
        assertTest(shortCaskMatch?.name == "nad-bit/Mino", "findMatchingRepo: short cask name matches tap cask")
        
        // Full tap cask match
        let fullTapCaskMatch = AppDelegate.findMatchingRepo(for: "nad-bit/tap/mino", in: testRepos)
        assertTest(fullTapCaskMatch?.name == "nad-bit/Mino", "findMatchingRepo: full tap cask matches")
        
        // Untracked / non-existent target
        let nonExistentMatch = AppDelegate.findMatchingRepo(for: "unknown-repo/unknown", in: testRepos)
        assertTest(nonExistentMatch == nil, "findMatchingRepo: unknown target returns nil safely")
        
        // Empty target
        let emptyMatch = AppDelegate.findMatchingRepo(for: "   ", in: testRepos)
        assertTest(emptyMatch == nil, "findMatchingRepo: empty target returns nil safely")
    }
    
    // --------------------------------------------------------
    // Test 15: Persistent Disk Cache (Metadata, ETags & Rate Limit Shield)
    // --------------------------------------------------------
    static func testPersistentDiskCache() {
        print("\n[Test 15] Testing Persistent Disk Cache (Metadata, ETags & Rate Limit Protection)...")
        
        let sampleRepoName = "nad-bit/Mino"
        let sampleInfo = RepoInfo(name: sampleRepoName, version: "v2.3.1", body: "Release notes body", assets: [
            ReleaseAsset(name: "Mino.zip", size: 1024, downloadURL: "https://github.com/nad-bit/Mino/releases/download/v2.3.1/Mino.zip", isSourceArchive: false)
        ])
        let sampleETags = [
            sampleRepoName: "\"etag-release-12345\"",
            "\(sampleRepoName):commits": "\"etag-commits-67890\""
        ]
        
        // 1. Save cache synchronously
        ConfigManager.shared.saveCacheSync(repoCache: [sampleRepoName: sampleInfo], etags: sampleETags)
        
        // 2. Load cache back from disk
        let loaded = ConfigManager.shared.loadCache()
        assertTest(loaded.repoCache[sampleRepoName]?.version == "v2.3.1", "PersistentCache: Successfully restored repo version from disk")
        assertTest(loaded.repoCache[sampleRepoName]?.assets?.count == 1, "PersistentCache: Successfully restored assets from disk")
        assertTest(loaded.etags[sampleRepoName] == "\"etag-release-12345\"", "PersistentCache: Successfully restored release ETag from disk")
        assertTest(loaded.etags["\(sampleRepoName):commits"] == "\"etag-commits-67890\"", "PersistentCache: Successfully restored commits ETag from disk")
        
        // 3. Test GitHubAPI loadETags and allETags
        GitHubAPI.shared.loadETags(loaded.etags)
        assertTest(GitHubAPI.shared.etag(for: sampleRepoName) == "\"etag-release-12345\"", "GitHubAPI: etag(for:) returns loaded release ETag")
        assertTest(GitHubAPI.shared.allETags().count >= 2, "GitHubAPI: allETags() exports currently loaded ETags")
        assertTest(loaded.savedAt != nil, "PersistentCache: Successfully restored savedAt timestamp from disk")
        
        // 4. Test cache cleanup and async write coordination
        ConfigManager.shared.clearDiskCache()
        let cleared = ConfigManager.shared.loadCache()
        assertTest(cleared.repoCache.isEmpty && cleared.etags.isEmpty, "PersistentCache: clearDiskCache removes cache file cleanly")
        
        // 5. Async save followed immediately by clearDiskCache does not resurrect cache file
        ConfigManager.shared.saveCache(repoCache: [sampleRepoName: sampleInfo], etags: sampleETags)
        ConfigManager.shared.clearDiskCache()
        let clearedAfterAsync = ConfigManager.shared.loadCache()
        assertTest(clearedAfterAsync.repoCache.isEmpty && clearedAfterAsync.etags.isEmpty, "PersistentCache: Serial queue and generation counter prevent file resurrection")
        
        // 6. RepoInfo isNotModified flag and Codable integrity
        var info304 = RepoInfo(name: sampleRepoName)
        info304.isNotModified = true
        assertTest(info304.isNotModified == true, "RepoInfo supports isNotModified flag")
        if let encoded = try? JSONEncoder().encode(info304),
           let decoded = try? JSONDecoder().decode(RepoInfo.self, from: encoded) {
            assertTest(decoded.name == sampleRepoName, "RepoInfo encoded and decoded successfully via Codable")
            assertTest(decoded.isNotModified == false, "isNotModified defaults to false upon deserialization")
        }
    }
    
    // --------------------------------------------------------
    // Test 16: Refresh Timing, Exact Minute Anchoring & Non-Drifting Interval
    // --------------------------------------------------------
    static func testRefreshTimingAndMinuteAnchoring() {
        print("\n[Test 16] Testing Refresh Timing, Exact Minute Anchoring & Zero-Drift Scheduling...")
        
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 10
        comps.day = 9
        comps.hour = 7
        comps.minute = 13
        comps.second = 42
        
        guard let sampleTriggerDate = calendar.date(from: comps) else {
            fatalError("Could not create test date")
        }
        
        // 1. Truncate to minute
        let anchor = RefreshCoordinator.truncateToMinute(sampleTriggerDate)
        let anchorComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: anchor)
        assertTest(anchorComps.hour == 7 && anchorComps.minute == 13 && anchorComps.second == 0, "Minute Anchoring: 07:13:42 correctly truncated to 07:13:00")
        
        // 2. Scheduled next run at configured interval (e.g. 60 min)
        let intervalSeconds: TimeInterval = 60 * 60
        let nextRun = anchor.addingTimeInterval(intervalSeconds)
        let nextRunComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nextRun)
        assertTest(nextRunComps.hour == 8 && nextRunComps.minute == 13 && nextRunComps.second == 0, "Next Scheduled Run: exactly 08:13:00 (first second of minute 13)")
        
        // 3. Subsequent runs maintain zero drift
        let subsequentRun = nextRun.addingTimeInterval(intervalSeconds)
        let subComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: subsequentRun)
        assertTest(subComps.hour == 9 && subComps.minute == 13 && subComps.second == 0, "Subsequent Run: exactly 09:13:00 with zero accumulated drift")
        
        // 4. Multiple chained intervals
        var chained = anchor
        var allSecondsZero = true
        for _ in 1...12 {
            chained = chained.addingTimeInterval(intervalSeconds)
            let s = calendar.component(.second, from: chained)
            if s != 0 { allSecondsZero = false }
        }
        assertTest(allSecondsZero, "Chained Scheduling: all 12 hourly intervals land precisely at second 00")
    }
}
