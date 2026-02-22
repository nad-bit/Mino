# GitHub Watcher ✦

A lightweight, native macOS menu bar app to track GitHub releases. Built entirely with Swift and AppKit — no frameworks, no dependencies, no Xcode project required.

## Features

- **👀 Menu Bar Integration**: Unobtrusive status bar icon with inline repository information
- **⚡️ Inline Actions**: Hover over any repository to reveal contextual action buttons — view release notes, open releases, install via Homebrew, or delete — all without submenus
- **🍺 Homebrew Integration**: Detects installed Casks automatically and enables one-click install/update directly from the menu (only shown if Homebrew is installed)
- **🧠 Smart Add**: Paste a GitHub URL or `owner/repo` string; the app auto-detects if a matching Homebrew Cask exists
- **📂 Quick Reveal**: After installing a Cask, the app reveals the application in Finder
- **🔐 Secure Token Storage**: GitHub Personal Access Tokens stored in macOS Keychain — never in plain text
- **✦ Configurable New Release Indicator**: Customizable threshold (1-30 days) with toggle, replacing the old fixed emoji
- **🌍 Localized**: English and Spanish, with automatic detection
- **🔄 Auto-Start**: Launch at login via native macOS LaunchAgent
- **🎨 Light & Dark Mode**: Full support, including a forced-dark HUD panel for notifications

## Installation

### Prerequisites

- macOS 12.0+
- Xcode Command Line Tools (`xcode-select --install`)
- [Homebrew](https://brew.sh/) (optional, for Cask integration)

### Build from Source

```bash
git clone https://github.com/yourusername/GitHub_Watcher.git
cd GitHub_Watcher/SwiftApp
chmod +x build.sh
./build.sh
```

The compiled app bundle will be at `build/GitHubWatcher.app`. Move it to `/Applications` or run it directly:

```bash
open build/GitHubWatcher.app
```

> **Note**: No Xcode project needed. The `build.sh` script compiles all Swift sources directly with `swiftc`.

## Usage

### Adding Repositories

Click **"Add Repository"** in the menu. You can:
- **Manual**: Enter `owner/repo` format (e.g., `microsoft/vscode`)
- **From Homebrew**: Select from your installed Homebrew Casks

> **Tip**: Copy a GitHub URL to your clipboard before opening the dialog — it will be auto-detected!

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

Accessible via the **Preferences** menu item (`⌘,`):

| Option | Description |
|--------|-------------|
| **GitHub Token** | Add a PAT for 5,000 req/hr (vs 60/hr unauthenticated) |
| **Refresh Interval** | Slider: 1-24 hours between auto-checks |
| **Start at Login** | Toggle macOS LaunchAgent |
| **Show Owner Name** | Toggle `owner/` prefix in repo names |
| **Show Icons** | Toggle SF Symbol icons in standard menu items |
| **New Release Indicator** | Toggle the ✦ symbol and configure threshold (1-30 days) |
| **Sort by** | Segmented control: Date or Name |

### Security

Your GitHub Personal Access Token is stored in **macOS Keychain**:
- Encrypted, never saved in config files
- Visible in Keychain Access under "GitHub Watcher"
- Smart paste: copies token from clipboard automatically

## Configuration

Configuration is stored in:
```
~/.config/GitHubWatcher/repos.json
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
    ├── HomebrewManager.swift   # Homebrew Cask detection and installation
    ├── HUDPanel.swift          # Floating notification panel
    ├── UIHandlers.swift        # Dialogs and alert helpers
    ├── Models.swift            # Data structures (RepoInfo, AppConfig)
    ├── Constants.swift         # App-wide constants
    ├── Translations.swift      # i18n (English, Spanish)
    └── Utils.swift             # Date formatting utilities
```

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Credits

Built with pure Swift and AppKit. No external dependencies.
