# Changelog

All notable changes to Mino will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.3] - 2026-02-28
### Added
- **Clipboard Auto-Detect**: The application now seamlessly detects GitHub URLs copied to your clipboard while the "Add Repo" window is active.
### Fixed
- **Settings Sliders Stutter**: Refactored the interval and indicator sliders to offload filesystem saves onto an asynchronous rendering thread, removing trailing stutters on track jumps.
- **Relased Notes Aesthetics**: Replaced the colorful Emoji fallback block character with a fully native, monochrome SF Symbol (\`shippingbox\`) matching the app styling.

## [1.2.2] - 2026-02-28
### Fixed
- **Missing HUD Animations**: Restored the `.wiggle` (error) and `.bounce` (success) visual menu icon animations that were inadvertently removed when transitioning from native `NSAlert`s to HUD Notification panels.

## [1.2.1] - 2026-02-28
### Fixed
- **Interval Slider Bug**: Fixed a UX bug where dragging the "Refresh Interval" slider would not save the configuration unless the window was closed. Interactions now save instantly in the background.
- **Alert Fatigue**: Removed overlapping modal pop-ups for minor informational errors (e.g., duplicated repos, network failures). These are now handled smoothly by the floating HUD Notification panel.
- **Homebrew Quarantine**: Removed the obsolete `--no-quarantine` flag from the internal installation scripts, squashing the deprecated yellow warnings.
- **Build Tools**: Guarded the internal `build.sh` Homebrew auto-deployment script behind a `--release` flag to prevent local compilation hashes from overriding the public `mino.rb` repository cache.

## [1.2.0] - 2026-02-28

### Added
- **Automated Homebrew Cask Discovery**: Mino now checks in the background (every 24h) if manually added repositories have been published to the official Homebrew Cask catalog, and silently links them for one-click installation.
- **Root Privilege Assistant**: Installing Homebrew Casks that require Administrator permissions (`sudo`) no longer causes the app to hang. Mino safely intercepts the security prompt and displays a native macOS warning with the exact Terminal command (`brew reinstall`) needed to proceed.

### Changed
- **Singleton UI Architecture**: Completely redesigned the window management system. 'Add Repository' and 'Release Notes' dialogs are now proper native floating windows (`NSWindowController`) instead of blocking modals.
- Windows are now mutually exclusive; opening a new window automatically dismisses the previous one, and clicking the menu no longer duplicates windows if they were already open.
- Fixed a z-index bug where the "Installing..." HUD panel would freeze behind macOS security alerts.

## [1.1.1] - 2026-02-27

### Added
- Homebrew installations (both via the README command and the in-app Install button) now automatically apply the `--no-quarantine` flag to prevent macOS Gatekeeper from blocking the app on first launch.

## [1.1.0] - 2026-02-27
### Added
- **GitHub Device Flow OAuth**: Users can now authenticate with a simple "Connect GitHub" button that opens their browser, eliminating the need to manually create and paste Personal Access Tokens.
- Automated app icon generation from `icon.png` during the build process to reduce repository footprint.

## [1.0.8] - 2026-02-27

### Added
- Optionally disable AppKit symbol animations and HUD panel fade animations based on the macOS accessibility setting for reduced motion (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`).

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


