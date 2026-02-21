# GitHub Watcher 🟢

A native macOS menu bar application to track GitHub releases and updates for your favorite repositories.

## Features

- **👀 Menu Bar Integration**: Always visible, unobtrusive status of your tracked repos
- **🍺 Homebrew Integration**: Automatically detects if a repo has a Homebrew Cask and allows you to install/update it directly from the menu
- **🧠 Smart Add**: Paste a GitHub URL or `owner/repo` string, and the app intelligently detects if it's a Cask or a standard repo
- **📂 Quick Access**: After installing a Cask, the app reveals the application in Finder
- **🔐 Secure Token Storage**: GitHub Personal Access Tokens are stored in macOS Keychain (encrypted, never in plain text)
- **🌍 Native & Localized**: Built with native macOS UI elements. Available in English and Spanish
- **⚡️ Efficient**: Uses local caching, thread pooling, and batch menu updates to minimize resource usage
- **🔄 Auto-Start**: Launch automatically at login using native macOS LaunchAgent

## Installation

### Prerequisites

- macOS 11.0+
- Python 3.9+
- [Homebrew](https://brew.sh/) (Optional, for Cask integration)

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/GitHub_Watcher.git
   cd GitHub_Watcher
   ```

2. Create and activate a virtual environment:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Run the application:
   ```bash
   python3 main.py
   ```

## Usage

### Adding Repositories

Click **"Add Repository"** in the menu bar. You can:
- **Manual Input**: Enter `owner/repo` format (e.g., `microsoft/vscode`)
- **From Homebrew**: Select from your installed Homebrew Casks

> **Tip**: Copy a GitHub URL to your clipboard before opening the dialog - it will be auto-detected!

### Menu Interface

The menu displays each repository with:
- Repository name and latest version
- Time since last release
- 🟢 Green indicator for releases within the last 7 days

Click any repository to:
- **Open Releases Page**: View on GitHub
- **Release Notes**: View changelog in a native dialog
- **Install via Homebrew**: Install or update the Cask (if applicable)

### Preferences

Access via **Preferences** submenu:

| Option | Description |
|--------|-------------|
| **Start at Login** | Launch automatically when you log in |
| **Sort by Name/Date** | Change repository ordering |
| **Show/Hide Owner** | Toggle `owner/` prefix in repo names |
| **Configure Token** | Add GitHub PAT for 5000 req/hr (vs 60/hr) |
| **Change Interval** | Set update frequency (1-24 hours) |

### Security

Your GitHub Personal Access Token is stored securely in **macOS Keychain**:
- Never saved in plain text configuration files
- Visible in Keychain Access app under "GitHub Watcher"
- Automatically migrated from older versions

## Building for Distribution

Create a standalone `.app` bundle:

```bash
# Install PyInstaller if needed
pip install pyinstaller

# Build the application
pyinstaller GitHubWatcher.spec

# Find your app in dist/
open dist/
```

## Configuration

Configuration is stored in:
```
~/.config/GitHubWatcher/repos.json
```

> **Note**: Tokens are NOT stored in this file - they're in Keychain.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Credits

Built with:
- [rumps](https://github.com/jaredks/rumps) - macOS menu bar framework
- [keyring](https://github.com/jaraco/keyring) - Secure credential storage
- [requests](https://github.com/psf/requests) - HTTP library
