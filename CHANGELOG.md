# Changelog

All notable changes to Mino will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.1] - 2025-02-22

### Added
- **Configurable New Release Indicator**: Toggle on/off and set threshold (1-30 days) in Preferences
- Monochromatically neutral ✦ symbol replaces the old 🟢 emoji for a cleaner look

### Changed
- Sort option replaced from dropdown (`NSPopUpButton`) to `NSSegmentedControl` for one-click switching
- Indicator days slider dynamically updates label text

### Fixed
- HUD notification panel now forces dark appearance, fixing invisible text in Light Mode

## [0.9.0] - 2025-02-22

### Added
- **Inline Menu Actions**: Hover over any repository to reveal action buttons (install, release notes, open releases, delete) — replaces submenus entirely
- Direct synchronous `NSMenuDelegate` broadcasting for reliable hover highlighting
- Click on a repository row opens its main GitHub page
- Menu guard: `setupMenu()` no longer rebuilds items while the menu is open, preventing hover freeze

### Changed
- All repo menu items now use uniform width for consistent button alignment
- `autoenablesItems` disabled on `NSMenu` to allow custom-view items to participate in highlighting

### Fixed
- Off-by-one hover highlight (now uses `willHighlight` item parameter instead of stale `isHighlighted`)
- Homebrew install button only shown when Homebrew is actually installed on the system

## [0.8.0] - 2025-02-21

### Changed
- **Full rewrite from Python/rumps to native Swift/AppKit** — zero external dependencies
- Compiled via `build.sh` using `swiftc` directly (no Xcode project required)
- Concurrent API fetching with Swift `async/await` and `TaskGroup`
- Native `NSWindow`-based Preferences (token, interval slider, toggles, sort)
- HUD notification panel (`NSPanel`) with fade animations
- Secure token storage via native macOS Keychain Services (replaces `keyring` library)

### Added
- Show/Hide menu icons toggle (`SF Symbols`)
- Multi-line token field with smart clipboard paste detection
- Token masking (shows only last 4 characters)
- Delete token button
- About section integrated into Preferences window

### Removed
- Python runtime dependency
- All pip packages (`rumps`, `keyring`, `requests`)
- PyInstaller build process

## [0.7.0] - 2024-12-12

### Added
- **Secure Token Storage**: GitHub tokens are now stored in macOS Keychain instead of plain text JSON
- **Automatic Token Migration**: Existing tokens are automatically migrated to Keychain on first run
- **App Reveal in Finder**: After installing/updating a Cask, the application is revealed in Finder
- **Cask Info in Release Notes**: Release notes dialog now shows associated Cask name

### Changed
- Timer display now uses `ceil()` to prevent showing "0 minutes" before refresh
- LaunchAgent now uses direct executable for proper app identification in macOS notifications
- Removed duplicate "Quit" menu item that appeared during menu updates

### Fixed
- Fixed duplicate app instance launching when toggling "Start at Login"
- Fixed LaunchAgent error code 5 handling (benign I/O errors now silently ignored)
- Removed deprecated `add_repo_manual_dialog` and `add_repo_brew_dialog` methods

### Security
- Tokens are now encrypted in macOS Keychain
- Configuration file (`repos.json`) no longer contains sensitive data

## [0.6.0] - 2024-11-23

### Added
- Unified "Add Repository" dialog with Manual/Homebrew tabs
- Smart clipboard detection for GitHub URLs
- Owner name toggle (show/hide) in menu
- Sort by name or date options

### Changed
- Modularized codebase into `src/` directory structure
- Replaced `print()` with proper `logging` module
- Centralized constants in `constants.py`

## [0.5.0] - 2024-11-22

### Added
- Automatic Cask detection when adding repositories manually
- Batch menu updates to reduce UI rebuilds
- Countdown timer showing next refresh

### Fixed
- Menu not re-sorting after updates when sorted by date
- Memory leaks from circular callback references

## [0.4.0] - 2024-11-21

### Added
- Homebrew Cask integration (install/update from menu)
- Release notes viewer with scrollable text
- New release indicator (🟢) for releases within 7 days

### Changed
- Improved repository display format with version and age

## [0.3.0] - 2024-11-20

### Added
- GitHub Personal Access Token support
- Token validation with user feedback
- Configurable refresh interval (1-24 hours)

## [0.2.0] - 2024-11-19

### Added
- Start at Login functionality via LaunchAgent
- Spanish localization
- Preferences submenu

## [0.1.0] - 2024-11-18

### Added
- Initial release
- Menu bar app with repository tracking
- Manual repository addition
- Automatic refresh every 6 hours
- Release page shortcuts
