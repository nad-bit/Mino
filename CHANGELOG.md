# Changelog

All notable changes to GitHub Watcher will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
