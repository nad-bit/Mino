# Changelog

All notable changes to Mino will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.7] - 2026-02-26

### Fixed
- Fixed an issue where the Update Interval slider in Preferences would visually reset if another setting was modified before closing the window.

## [0.9.1] - 2026-02-22

### Added
- **Configurable New Release Indicator**: Toggle on/off and set threshold (1-30 days) in Preferences
- Monochromatically neutral ✦ symbol replaces the old 🟢 emoji for a cleaner look

### Changed
- Sort option replaced from dropdown (`NSPopUpButton`) to `NSSegmentedControl` for one-click switching
- Indicator days slider dynamically updates label text

### Fixed
- HUD notification panel now forces dark appearance, fixing invisible text in Light Mode

## [0.9.0] - 2026-02-22

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

## [0.8.0] - 2026-02-21

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


