<div align="center">
  <p align="center">
    <img src="docs/icon.png" width="150" alt="Mino Logo">
  </p>
  <h1 align="center">Mino</h1>
  <p>A lightweight, native macOS menu bar app to track GitHub releases with Homebrew integration.</p>
  
  [![macOS](https://img.shields.io/badge/macOS-12.0+-000000?style=flat&logo=apple&logoColor=white)](https://apple.com/macos)
  [![Swift](https://img.shields.io/badge/Swift-5.0+-FA7343?style=flat&logo=swift&logoColor=white)](https://swift.org)
  [![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
</div>


<img width="1920" height="1080" alt="Mino" src="https://github.com/user-attachments/assets/4a2e592b-2fa5-4f56-9d26-47ecdb94c430" />


## Features

- **👀 Menu Bar Integration**: Unobtrusive status bar icon with inline repository information
- **⚡️ Inline Actions**: Hover over any repository to reveal contextual action buttons with expanded, easy-to-click target areas — view release notes and download binary assets, open the repo on GitHub, install via Homebrew, or delete
- **🍺 Homebrew Integration**: Detects installed Casks automatically and enables one-click install/update with native mug iconography directly from the menu (only shown if Homebrew is installed)
- **📦 In-App Asset Downloads**: Download release binaries (DMGs, PKGs, source archives) directly from the Release Notes viewer with live transfer speeds, ETA estimation, percentage bars, and instant "Show in Finder" reveal
- **🔄 Targeted Single-Repo Refresh**: Press `CMD + R` on any selected repository to immediately refresh all its metadata (releases, GitHub topics, description, and newly published Homebrew casks) as if freshly added
- **🧩 Integrated Search**: A sleek, centered search field with an intelligent Tag Cloud. Filter your repositories by language, topic, or status instantly using the auto-generated suggestion cloud.
- **🧠 Quick Add**: Copy a GitHub repository URL, open the menu, and the header intelligently transforms into a "Quick Add" action with dynamic iconography. Bypass modal windows completely!
- **📏 Dynamic Typography**: Choose your preferred text size (11pt to 21pt). The entire menu UI, from repository names to release notes and segmented controls, scales proportionally to ensure perfect legibility for every user.
- **⏱ Tooltip Tracker**: The refresh countdown is hidden for a cleaner look — simply hover over the refresh icon to see the time remaining, or hover over the footer count for the exact last-update timestamp.
- **🎯 Multi-Hunt Window**: The floating "Add Repositories..." window acts as a persistent tracking hub. Keep it open while you browse Safari, and simply hit `CMD+C` on sequential GitHub URLs. Mino automatically sniffs your clipboard and queues them up for rapid batch-ingestion without ever losing focus.
- **📂 Quick Reveal**: After installing a Cask, the app reveals the application in Finder
- **🔐 Hardened Security & Resilience**: GitHub OAuth tokens stored in macOS Keychain with minimal scopes (`""`), strict domain allowlist validation, atomic configuration persistence, and link protocol isolation
- **★ Favorites**: Right-click any repository (or hit `CMD + S`) to mark it as a favorite. A gold ★ appears inline — toggles instantly without closing the menu.
- **🌍 Localized**: English, Spanish, French, German, Italian, Portuguese, Mandarin Chinese, Hindi, Arabic, Russian, and Japanese with automatic system detection
- **🔄 Auto-Start**: Launch at login via native macOS LaunchAgent
- **🎨 Light & Dark Mode**: Full support, including a forced-dark HUD panel for notifications

## Installation

### Prerequisites

- macOS 12.0+
- Xcode Command Line Tools (`xcode-select --install`)
- [Homebrew](https://brew.sh/) (optional, for Cask integration)

### Homebrew (Recommended)

```bash
brew install nad-bit/tap/mino
```

### Build from Source

```bash
git clone https://github.com/nad-bit/Mino.git
cd Mino/SwiftApp
chmod +x build.sh
./build.sh
```

The compiled app bundle will be at `build/Mino.app`. Move it to `/Applications` or run it directly:

```bash
open build/Mino.app
```

> **Note**: No Xcode project needed. The `build.sh` script compiles all Swift sources directly with `swiftc` into a Universal binary (Apple Silicon & Intel). Run `./build.sh --test` to execute the automated verification test suite.

> **Important**: If macOS blocks the compiled application from running (saying it's damaged or cannot be verified), remove the quarantine attribute by running:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Mino.app
> ```

## Usage

### Adding Repositories

**Fastest Way (Quick Add):**
1. Copy any GitHub repository URL to your clipboard.
2. Click the Mino menu bar icon. A **Quick Add** button will instantly appear at the top.
3. Click it. You're done.

**Multi-Hunt Way (Batch Processing):**
Click the `(+)` button in the menu to open the floating Window.
- Don't close the window! Keep it hovering on your screen.
- Go to your browser, copy a URL (`CMD+C`). Watch Mino automatically catch the link. Click the Add button.
- The window remains open and the text field clears. Cycle through your browser tabs, copying and adding rapidly.

**Automation & URL Scheme (`mino://`):**
Integrate Mino with macOS Shortcuts, PopClip, Alfred, Raycast, or custom scripts:
- `mino://add/owner/repo` (e.g. `mino://add/nad-bit/mino`)
- `mino://add/cask_name` (e.g. `mino://add/firefox`)
- `mino://add/https://github.com/owner/repo`

**Standard Manual Input:**
- Enter `owner/repo` format (e.g., `microsoft/vscode`).
- Enter a Homebrew **Cask name** (e.g., `lulu` or `stats`) to automatically resolve and track its GitHub repository. No prefixes required.

### Menu Interface

Each repository displays its name, latest version, and time since release. Hover over a row to reveal action buttons aligned to the right:

| Button | Action |
|--------|--------|
| 🍺 | Install/update via Homebrew (if available) |
| 📄 | View release notes & download assets |
| ↗ | Open the repository on GitHub |
| 🗑 | Remove from watch list |

Repos with a recent release show a **●** freshness indicator (green / orange / grey) before the name when the *New Release Indicator* option is enabled in Preferences. The threshold (1–30 days) is configurable.

Right-click any row to toggle a **★** favorite mark.

### Filtering
Simply start typing in the **Integrated Search** field at the top of the menu to filter your repository list in real-time. It features an intelligent **Tag Cloud** that suggests languages and topics from your collection for instant filtering without typing.

### Preferences

Accessible via the **Preferences** menu item:

| Option | Description |
|--------|-------------|
| **GitHub Account** | Connect via OAuth for 5,000 req/hr limit (vs 60/hr unauthenticated) |
| **Menu layout** | Segmented control: Choose between 3 distinct UI arrangements (Columns, Cards, Tags) |
| **Text Size** | Segmented control: Choose your preferred reading comfort (11pt to 21pt) |
| **Sort by** | Segmented control: Date or Name |
| **New Release Indicator** | Toggle the ● freshness dot (Columns/Cards) or dynamic pill color (Tags) and configure threshold (1-30 days) |
| **Show Owner Name** | Toggle `owner/` prefix in repo names |
| **Refresh Interval** | Slider: 1-24 hours between auto-checks |
| **Global Hotkey** | Set global hotkey to open/close the menu |
| **Start at Login** | Toggle macOS LaunchAgent |

### System Permissions

Mino requires certain macOS permissions to function seamlessly:
- **Background Activity (Login Items)**: Required to allow the app to run persistently in the menu bar and start automatically when you log into your Mac.
- **App Management (Privacy & Security)**: Required because Mino executes background scripts (`brew reinstall`) that modify or install other applications inside your `/Applications` folder. macOS enforces this protection to prevent silent app tampering.

### Security & Resilience

Mino adheres to strict defense-in-depth principles across authentication, networking, and data storage:

- **Least Privilege OAuth Scope**: Uses GitHub's official Device Authorization Flow with an empty scope (`""`), granting public read access and the full 5,000 req/hr API quota with zero access to private code or write permissions.
- **Strict Host Allowlist**: Authorization headers are exclusively dispatched to verified GitHub hosts (`github.com`, `api.github.com`, `*.githubusercontent.com`, `*.github.com`), preventing token exfiltration to unauthorized endpoints.
- **Secure Keychain Storage**: Tokens are stored and updated via native macOS Keychain Services (`SecItemUpdate` / `SecItemAdd`)—never written in raw configuration files or system logs.
- **Link & Protocol Isolation**: Clickable links in release notes strictly enforce `https://`, `http://`, or `mailto:` protocols to prevent execution of dangerous system schemes (`file://`, `shortcuts://`, etc.). All inputs received via the `mino://` custom URL scheme are sanitized against strict regular expressions.
- **Atomic Persistence & Fail-Safe Recovery**: Configuration (`repos.json`) is saved via atomic writes (`.atomic`) and continuously mirrored to `repos.json.bak`. If corruption ever occurs, Mino automatically restores from the backup to safeguard your repository collection.
- **Resource Protection & Memory Guards**: Remote release images are capped at 10 MB in memory, and the local disk cache (`~/Library/Caches/com.nad.mino/ReleaseImages`) is managed with automated background LRU pruning (150 MB quota / 30-day TTL).
- **Automated Audit Suite**: All security controls, host allowlists, URL regexes, and recovery routines are verified via automated tests in `SwiftApp/Tests/AuditValidationTests.swift` (`./build.sh --test`).

## Configuration

Configuration is stored in:
```
~/.config/Mino/repos.json
```

> **Note**: Tokens are NOT stored in this file — they're in Keychain.

## Keyboard Shortcuts

Mino is designed for power users.

- **Global Hotkey**: Press **`Ctrl + Alt + M`** (customizable in Preferences) to open or close the main menu from anywhere on your Mac.

Use these shortcuts while the main menu is open:

| Shortcut | Action |
|----------|--------|
| `CMD + ,` | Open Preferences |
| `CMD + N` | Open new "Multi-Hunt" batch addition window |
| `CMD + F` | Focus Search field |
| `CMD + R` | Refresh metadata and version for selected repo (or full refresh if none selected) |
| `CMD + C` | Copy GitHub URL of selected repo to clipboard |
| `CMD + O` | Open selected repo on GitHub |
| `CMD + I` | Show Release Notes & Assets for selected repo |
| `CMD + S` | Mark or unmark selected repo as Starred (Favorite) |
| `CMD + B` | Install or update the focused repo via Homebrew |
| `CMD + Z` | Undo last repository deletion |
| `CMD + M` | Open About Mino panel |
| `CMD + Q` | Quit Mino |
| `TAB`     | Switch focus between Search field and Repo list |
| `↑↓`     | Navigate up and down the Repo list |
| `←→`     | Cycle through inline action buttons on the selected repo |
| `ENTER`   | Trigger the focused action button, or open repo on GitHub if no button is focused |
| `CMD + DELETE` | Delete the selected repo |
| `ESC`     | Close any active popover |

## Architecture

Mino uses a modern, coordinator-based architecture driving a fully native **NSPopover** interface with a virtualized **NSTableView** for high performance with hundreds of repositories.

```
SwiftApp/
├── build.sh                         # Universal build script (ARM64/x86_64, packaging & tests)
├── Tests/
│   └── AuditValidationTests.swift   # Automated security, parsing, and recovery test suite
└── Sources/
    ├── main.swift                   # Application entry point
    ├── AppDelegate.swift            # App lifecycle, popover orchestration, and global shortcuts
    ├── MainPopoverViewController.swift # Core UI controller (NSTableView, Search, Tag Cloud)
    ├── HeaderMenuItemView.swift     # Search bar, Quick Add, and popular tags bar
    ├── FooterMenuItemView.swift     # Repository counts, update trigger, and quit actions
    ├── RepoMenuItemView.swift       # Virtualized row views (Columns, Cards, Tags layouts)
    ├── NoSearchResultsView.swift    # Empty state view for filtered searches
    ├── RepoCoordinator.swift        # Lifecycle actions (add, delete, install, single refresh)
    ├── RefreshCoordinator.swift     # Background update cycles, 30-worker pool, exact timers
    ├── SettingsViewController.swift # Preferences, UI scaling, layout modes, and intervals
    ├── ReleaseNotesWindowController.swift # Release notes viewer and in-app asset download manager
    ├── AddRepoViewController.swift  # Multi-Hunt batch ingestion window
    ├── OAuthWindowController.swift  # GitHub Device Flow OAuth authorization window
    ├── BeerHandlePanel.swift        # Aesthetic popover handle attachment
    ├── ConfigManager.swift          # Atomic JSON persistence and fail-safe backup recovery
    ├── GitHubAPI.swift              # GitHub REST API client with domain allowlist & rate limits
    ├── GitHubAuth.swift             # Device Flow OAuth protocol & least-privilege token retrieval
    ├── HomebrewManager.swift        # Homebrew Cask discovery, verification, and CLI bridge
    ├── GlobalHotkeyManager.swift    # System-wide hotkey listener and recorder
    ├── HUDPanel.swift               # Floating feedback overlay with progress tracking & Finder reveal
    ├── Translations.swift           # Localization engine (11 languages)
    ├── Models.swift                 # Data structures (RepoInfo, AppConfig, RepoConfig)
    ├── Constants.swift              # Performance thresholds, timings, and layout metrics
    ├── GeneratedColor.swift         # Dynamic app accent colors derived from app icon
    └── Utils.swift                  # Relative date formatting, styling, and window utilities
```

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Credits

No credits.
