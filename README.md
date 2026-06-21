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


https://github.com/user-attachments/assets/3ca0d651-5059-4683-812f-c9f24b8aa8fc


## Features

- **👀 Menu Bar Integration**: Unobtrusive status bar icon with inline repository information
- **⚡️ Inline Actions**: Hover over any repository to reveal contextual action buttons with expanded, easy-to-click target areas — view release notes, open the repo on GitHub, install via Homebrew, or delete
- **🍺 Homebrew Integration**: Detects installed Casks automatically and enables one-click install/update directly from the menu (only shown if Homebrew is installed)
- **🧩 Integrated Search**: A sleek, centered search field with an intelligent Tag Cloud. Filter your repositories by language, topic, or status instantly using the auto-generated suggestion cloud.
- **🧠 Quick Add**: Copy a GitHub repository URL, open the menu, and the header intelligently transforms into a "Quick Add" action with dynamic iconography. Bypass modal windows completely!
- **📏 Dynamic Typography**: Choose your preferred text size (11pt to 21pt). The entire menu UI, from repository names to release notes, scales proportionally to ensure perfect legibility for every user.
- **⏱ Tooltip Tracker**: The refresh countdown is hidden for a cleaner look — simply hover over the refresh icon to see the time remaining.
- **🎯 Multi-Hunt Window**: The floating "Add Repositories..." window acts as a persistent tracking hub. Keep it open while you browse Safari, and simply hit `CMD+C` on sequential GitHub URLs. Mino automatically sniffs your clipboard and queues them up for rapid batch-ingestion without ever losing focus.
- **📂 Quick Reveal**: After installing a Cask, the app reveals the application in Finder
- **🔐 Secure Token Storage**: GitHub Personal Access Tokens stored in macOS Keychain — never in plain text
- **★ Favorites**: Right-click any repository to mark it as a favorite. A gold ★ appears inline — toggles instantly without closing the menu.
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

> **Note**: No Xcode project needed. The `build.sh` script compiles all Swift sources directly with `swiftc`.

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

**Standard Manual Input:**
- Enter `owner/repo` format (e.g., `microsoft/vscode`).
- Enter a Homebrew **Cask name** (e.g., `lulu` or `stats`) to automatically resolve and track its GitHub repository. No prefixes required.

### Menu Interface

Each repository displays its name, latest version, and time since release. Hover over a row to reveal action buttons aligned to the right:

| Button | Action |
|--------|--------|
| 📦 | Install/update via Homebrew (if available) |
| 📄 | View the release notes |
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
| **Start at Login** | Toggle macOS LaunchAgent |

### System Permissions

Mino requires certain macOS permissions to function seamlessly:
- **Background Activity (Login Items)**: Required to allow the app to run persistently in the menu bar and start automatically when you log into your Mac.
- **App Management (Privacy & Security)**: Required because Mino executes background scripts (`brew reinstall`) that modify or install other applications inside your `/Applications` folder. macOS enforces this protection to prevent silent app tampering.

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

## Keyboard Shortcuts

Mino is designed for power users.

- **Global Hotkey**: Press **`Ctrl + Alt + M`** (customizable in Preferences) to open or close the main menu from anywhere on your Mac.

Use these shortcuts while the main menu is open:

| Shortcut | Action |
|----------|--------|
| `CMD + ,` | Open Preferences |
| `CMD + N` | Open new "Multi-Hunt" window |
| `CMD + F` | Focus Search field |
| `CMD + I` | Show Release Notes for selected repo |
| `CMD + Z` | Undo last repository deletion |
| `CMD + B` | Install or update the focused repo |
| `CMD + Q` | Quit Mino |
| `TAB`     | Switch focus between Search field and Repo list |
| `↑↓`     | Navigate up and down the Repo list |
| `←→`     | Cycle through the inline action buttons on the selected repo |
| `ENTER`   | Trigger the focused action button, or open the repo on GitHub if no button is focused |
| `CMD + DELETE` | Delete the selected repo |
| `ESC`     | Close any active popover |

## Architecture

Mino uses a modern, coordinator-based architecture driving a fully native **NSPopover** interface with a virtualized **NSTableView** for maximum performance.

```
SwiftApp/
├── build.sh                    # Universal build script (ARM64/x86_64)
└── Sources/
    ├── AppDelegate.swift               # App lifecycle and Popover management
    ├── MainPopoverViewController.swift # Main UI controller (Table, Search, Tags)
    ├── RepoCoordinator.swift           # Logic for adding/deleting/managing repos
    ├── RefreshCoordinator.swift        # Background update cycle and timers
    ├── RepoMenuItemView.swift          # Virtualized row view with hover logic
    ├── SettingsViewController.swift    # App preferences and UI scaling logic
    ├── ReleaseNotesWindowController.swift # Native markdown-ready notes viewer
    ├── AddRepoViewController.swift     # Multi-Hunt batch ingestion logic
    ├── ConfigManager.swift             # JSON persistence and Keychain security
    ├── GitHubAPI.swift                 # GitHub REST API client
    ├── HomebrewManager.swift           # Homebrew Cask discovery and CLI bridge
    ├── Translations.swift              # Localization engine (11 languages)
    ├── HUDPanel.swift                  # Custom notification overlay
    ├── Models.swift                    # Data structures (RepoInfo, AppConfig)
    └── Utils.swift                     # Date logic and window animations
```

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Credits

No credits.
