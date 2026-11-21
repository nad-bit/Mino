# Security Policy & Architecture

At **Mino**, security is not an afterthought or a compliance checklist—it is an intrinsic architectural pillar woven into every data flow, background task, and user interaction.

Because Mino handles user credentials (GitHub Personal Access Tokens), parses rich untrusted content from the web (Release Notes, markdown, images), interacts with the local system via Homebrew, and downloads binaries, we adhere to strict **Defense in Depth** principles. Every boundary where untrusted remote data meets macOS is guarded by multi-layered validation, structural sanitization, and cryptographic guarantees.

---

## Supported Versions

Only active major and minor releases receive automated security patches and backports. We strongly recommend always running the latest version available.

| Version | Supported          | Status |
| ------- | ------------------ | ------ |
| 2.3.x   | :white_check_mark: | Current production release |
| 2.2.x   | :white_check_mark: | Critical security patches only |
| < 2.2   | :x:                | End of Life (Upgrade recommended) |

---

## Reporting a Vulnerability

We deeply appreciate the efforts of security researchers and community members who practice responsible disclosure.

If you believe you have identified a security vulnerability in Mino:

1. **Do not disclose the issue publicly** in GitHub Issues, Discussions, or social media.
2. Submit a private report via **[GitHub Private Vulnerability Reporting](https://github.com/nad-bit/Mino/security/advisories/new)**
3. Please include:
   - A detailed description of the potential vulnerability.
   - Exact steps or minimal proof-of-concept (PoC) to reproduce the behavior.
   - Impact assessment and any suggested remediations.

### Response Commitment

- **Acknowledgment**: Within **48 hours** of receiving your report.
- **Triage & Assessment**: Within **3 to 5 business days**.
- **Fix & Disclosure**: We coordinate a patched release alongside a public CVE / Security Advisory, giving full attribution and credit to the reporter.

---

## Security Architecture & Defenses

Below is a technical breakdown of the protective measures engineered into Mino to safeguard your macOS system and privacy:

### 1. Network Perimeter & Host Allowlisting
- **Strict Host Whitelist**: All network traffic initiated by `GitHubAPI` is strictly locked to an exact allowlist: `github.com`, `api.github.com`, and `raw.githubusercontent.com`.
- **Anti-Spoofing & Wildcard Rejection**: Mino strictly rejects wildcard subdomains, spoofed TLDs, and attacker suffix trickery (e.g. `github.com.attacker.example` or `evil-github.com`).
- **No Third-Party Telemetry**: Mino communicates exclusively with official GitHub endpoints. There are zero third-party analytics, tracking pixels, or remote telemetry frameworks.

### 2. Input Validation & Shell Injection Prevention
- **Canonical Target Sanitization**: Every repository name, tap, and Cask identifier is strictly validated through `Utils.isValidMinoTarget` before processing.
- **Shell Escaping & Parameter Trapping**:
  - Rejects chained commands (`;`, `&&`, `||`, `|`, `\n`).
  - Rejects path traversal tokens (`..`), leading slashes, and illegal shell delimiters.
  - Rejects leading flag injection (e.g., `--force`, `--no-quarantine`, `-cask`).
  - Restricts path depth to valid `owner/repo` formats.
- **Direct Process Invocation**: Homebrew commands and system tools are executed using `Process` with direct `arguments: [String]` arrays, completely bypassing `/bin/zsh -c`, `eval`, or subshell expansions.

### 3. Content Sanitization & XSS Defense (Release Notes Viewer)
Because release notes on GitHub are authored by third parties and rendered in rich HTML, Mino implements aggressive structural sanitization:
- **Multi-Pass Tag Neutralization**: All executable HTML structures (`<script>`, `<iframe>`, `<embed>`, `<object>`) are stripped along with their entire contents.
- **Inline Event Handler Stripping**: Every `on*` attribute (`onclick`, `onload`, `onerror`, etc.) is eradicated via regex sanitizers.
- **CSS Injection Defense**: `<style>` tags containing `@import` statements or external CSS URL rules are neutralized.
- **URI Scheme Quarantine**:
  - Web protocols are strictly limited to `https://`, `http://`, and `mailto:`.
  - Dangerous pseudo-protocols (`javascript:`, `vbscript:`, `data:`, `file:`) are neutralized to `about:blank`.
  - Local traversal schemes (`file://`, `shortcuts://`, `terminal://`) are blocked from invoking external applications.

### 4. Cryptographic Asset Integrity & SHA-256 Verification
- **Real-Time Streaming Checksums**: Binary assets (DMGs, PKGs, ZIPs) downloaded via Mino's asset manager are streamed through Apple `CryptoKit` to compute their SHA-256 digest on the fly with zero extra memory overhead.
- **Automated Verification**: Mino cross-references computed digests against official GitHub release asset digests and release notes checksum blocks.
- **Instant Quarantine & Safe Deletion**: If a checksum mismatch is detected, the compromised artifact is instantly purged from disk, an error HUD alert is triggered, and the download task is terminated before execution.

### 5. Local Storage & Credential Hardening
- **Keychain Storage**: GitHub Personal Access Tokens (PATs) and OAuth credentials are saved securely in the macOS Keychain (`kSecClassGenericPassword`). Tokens are never persisted in plaintext configurations or shell history.
- **Minimal OAuth Scopes**: Mino requests empty scope (`""`), restricting access strictly to public data unless the user explicitly configures a private repo token.
- **Atomic File Operations**: All configuration modifications (`repos.json`, `cache.json`) use temporary files followed by atomic filesystem renames (`atomicWrite`), preventing partial writes or file corruption upon power loss.
- **POSIX Permission Isolation**: Configuration directories and files are initialized with strict permissions (`0o700` for directories, `0o600` for files), isolating your repository lists from other local system users.
- **Automated Backup & Self-Healing**: Every config modification maintains an automatic atomic backup snapshot (`repos.json.bak`). If corruption is ever detected, Mino self-heals by cleanly rolling back to the snapshot.

### 6. DoS & Decompression Bomb Mitigations
- **Pixel Flood Protection (`safeDecodeImage`)**: Before rendering remote release badges or icons, Mino inspects image metadata to ensure dimensions do not exceed 4,096 px and total pixel area does not exceed 16 megapixels, thwarting decompression bombs that exhaust memory.
- **Billion Laughs XML Defense**: Vector SVG rendering enforces strict XML entity expansion limits, capping expansions at 2,048 bytes to block nested XML entity bomb attacks.
- **Global Rate Limiter**: A paced pacing controller (`GlobalRateLimiter`) regulates background tasks to prevent rapid-fire requests, avoiding GitHub API secondary rate limits and IP throttling.
- **ETag Isolation**: Commit and Release ETags are isolated in separate namespaces, preventing cache pollution and redundant network roundtrips.

### 7. Homebrew Ecosystem Integrity
- **Untrusted Tap Target Correlation**: Untrusted third-party taps are correlated against expected targets using `HomebrewManager.extractTrustTarget`, preventing spoofed taps from hijacking installation workflows.

---

## Automated Verification & Regression Testing

Every commit and build of Mino runs a comprehensive suite of **22 automated verification tests** (`AuditValidationTests.swift`) compiling against production sources. These tests validate:

1. Host whitelist enforcement and regex evasion resistance.
2. Canonical target sanitization across valid/invalid inputs.
3. Link scheme and protocol quarantine.
4. XSS and HTML structural sanitization.
5. Path traversal, `.git` safety, and control character neutralization.
6. Decompression bomb prevention and SVG entity expansion caps.
7. Atomic writes, permissions, and backup recovery.
8. Homebrew tap extraction and spoofing rejection.
9. Cryptographic SHA-256 integrity pipeline.
10. HUD lifecycle, concurrency, and rate-limit shield integrity.

Run the security test suite locally at any time:
```bash
cd SwiftApp
./build.sh --test
```

---

*Thank you for helping us keep Mino minimal, fast, and secure.*
