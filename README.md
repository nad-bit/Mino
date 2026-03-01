<div align="center">
  <img src="icon.png" width="128" alt="Mino Logo"/>
  <h1>Mino ✦</h1>
  <p>A lightweight, native macOS menu bar app to track GitHub releases. Built entirely with Swift and AppKit — no frameworks, no dependencies, no Xcode project required.</p>
  
  [![macOS](https://img.shields.io/badge/macOS-12.0+-000000?style=flat&logo=apple&logoColor=white)](https://apple.com/macos)
  [![Swift](https://img.shields.io/badge/Swift-5.0+-FA7343?style=flat&logo=swift&logoColor=white)](https://swift.org)
  [![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
</div>


https://github.com/user-attachments/assets/9b7cbe6b-5d9e-49c8-817e-5ff761ee4fbe


## Features

- **👀 Menu Bar Integration**: Unobtrusive status bar icon with inline repository information
- **⚡️ Inline Actions**: Hover over any repository to reveal contextual action buttons — view release notes, open releases, install via Homebrew, or delete — all without submenus
- **🍺 Homebrew Integration**: Detects installed Casks automatically and enables one-click install/update directly from the menu (only shown if Homebrew is installed)
- **🧠 Hybrid Quick Add**: Copy a GitHub repository URL, open the menu, and a 1-click "Quick Add" button intelligently appears at the top. Bypass the modal window completely!
- **📂 Quick Reveal**: After installing a Cask, the app reveals the application in Finder
- **🔐 Secure Token Storage**: GitHub Personal Access Tokens stored in macOS Keychain — never in plain text
- **✦ Configurable New Release Indicator**: Customizable threshold (1-30 days) with toggle, replacing the old fixed emoji
- **🌍 Localized**: English, Spanish, French, German, Italian, and Portuguese with automatic system detection
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

> **Note**: No Xcode project needed. The `build.sh` script compiles all Swift sources directly with `swiftc`.

> **Important**: If macOS blocks the compiled application from running (saying it's damaged or cannot be verified), remove the quarantine attribute by running:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Mino.app
> ```

## Usage

### Adding Repositories

**Fastest Way (Hybrid Quick Add):**
1. Copy any GitHub repository URL to your clipboard.
2. Click the Mino menu bar icon. A **Quick Add** button will instantly appear at the top.
3. Click it. You're done.

**Standard Way:**
Click the `(+)` button in the menu. You can:
- **Manual**: Enter `owner/repo` format (e.g., `microsoft/vscode`). If you have a URL in your clipboard, it will automatically populate the field.
- **From Homebrew**: Select from your installed Homebrew Casks.

### Menu Interface

Each repository displays its name, latest version, and time since release. Hover over a row to reveal action buttons aligned to the right:

| Button | Action |
|--------|--------|
| 📦 | Install/update via Homebrew (if available) |
| 📄 | View release notes |
| ↗ | Open releases page on GitHub |
| 🗑 | Remove from watch list |

Click the row itself to open the repository's main GitHub page.

Repos with recent releases show a **✦** indicator (configurable in Preferences).

### Preferences

Accessible via the **Preferences** menu item:

| Option | Description |
|--------|-------------|
| **GitHub Account** | Connect via OAuth for 5,000 req/hr limit (vs 60/hr unauthenticated) |
| **Refresh Interval** | Slider: 1-24 hours between auto-checks |
| **Start at Login** | Toggle macOS LaunchAgent |
| **Show Owner Name** | Toggle `owner/` prefix in repo names |
| **New Release Indicator** | Toggle the ✦ symbol and configure threshold (1-30 days) |
| **Sort by** | Segmented control: Date or Name |

### Security

Your GitHub authentication token is stored securely in **macOS Keychain**:
- Encrypted, never saved in raw config files
- Visible in Keychain Access under "Mino"
- Uses GitHub's official Device Authorization Flow (OAuth)

## Configuration

Configuration is stored in:
```
~/.config/Mino/repos.json
```

> **Note**: Tokens are NOT stored in this file — they're in Keychain.

## Architecture

```
SwiftApp/
├── build.sh                    # One-step build script (no Xcode required)
└── Sources/
    ├── main.swift              # App entry point
    ├── AppDelegate.swift       # Menu bar, lifecycle, NSMenuDelegate
    ├── RepoMenuItemView.swift  # Custom inline menu item with hover actions
    ├── SettingsWindowController.swift  # Preferences window
    ├── ConfigManager.swift     # JSON config + Keychain management
    ├── GitHubAPI.swift         # GitHub REST API client
    ├── GitHubAuth.swift        # GitHub Device Flow OAuth handling
    ├── HomebrewManager.swift   # Homebrew Cask detection and installation
    ├── HUDPanel.swift          # Floating notification panel
    ├── UIHandlers.swift        # Dialogs and alert helpers
    ├── Models.swift            # Data structures (RepoInfo, AppConfig)
    ├── Constants.swift         # App-wide constants
    ├── Translations.swift      # i18n (English, Spanish, French, German, Italian, Portuguese)
    └── Utils.swift             # Date formatting utilities
```

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Credits

Built with pure Swift and AppKit. No external dependencies.
