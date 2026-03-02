# Changelog

All notable changes to Mino will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.1] - 2026-03-02
### Fixed
- **Unread Status Syncing**: Relocated the background "Last Seen" chronometer trigger from the menu-open event to the menu-close event, guaranteeing that any active asynchronous background fetches that complete while the menu is visually held open will be correctly stamped as "read", eliminating phantom red indicator dots.
- **Installing Notification Persistence**: Abolished the strict 3.0-second fade-out timer on the "Installing Cask" HUD Notification. The processing indicator now persists indefinitely directly on screen throughout lengthy Homebrew auto-updates, remaining visible until the explicit completion-callback overrides the display with the final success panel.
- **Singleton Window Loophole**: Stripped the `.miniaturizable` style flag from all native popup interfaces (Preferences, Release Notes). This surgically disables the macOS Dock minimize feature, eliminating a loophole where users could evade the strict "Only one floating window allowed" application constraint by hiding active UI elements in their Dock.

## [1.3.0] - Ojo - 2026-03-01
### Added
- **Dynamic SF Symbol Icon**: Removed the static `icon.png` asset from the repository. Mino now programmatically compiles its own `AppIcon.icns` bundle directly from the native `eye.fill` SF Symbol upon every local build.
- **Native WebKit Renderer:** Migrated the Release Notes window from a simple Markdown string parser to a complete HTML WebKit bridge. Mino now securely requests pre-compiled `application/vnd.github.html+json` markup from GitHub's servers to flawlessly render complex lists, nested formatting, explicit image dimensions, and text alignments verbatim.
- **Glass Vibrancy Interfaces:** Add Repo and Preferences windows now employ native, system-adaptive `NSVisualEffectView` popover materials, blending seamlessly with dynamic macOS desktop backgrounds and respecting system accessibility contrast settings.
### Fixed
- **HUD Animating Freeze:** Fixed a critical RunLoop collision where opening the top menu bar paused macOS main-thread timers, permanently freezing the HUD success panel on the screen. The custom timer now safely executes on `.common` modes across event blockages.
- **Weak Regex Parser:** Rewrote the Quick Add algorithm using a strict inclusion array (`[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+`) to prevent the capture of typographic curly-quotes and extraneous punctuation marks from sentence boundaries.

## [1.2.5] - Hunter - 2026-03-01
### Added
- **Hybrid Quick Add System**: Dramatically sped up the repository addition process. If you have a valid, untracked GitHub URL in your clipboard, Mino will now transform the top "Refresh" menu area into a fully clickable, edge-to-edge "Quick Add" button containing the repository name. Adding repos is now a stealthy 2-click operation with zero modal windows.
- **Dynamic Translation Space**: Reduced all localized "Refresh Repositories" strings simply to "Refresh" to maximize horizontal menu real estate for the new feature.
### Fixed
- **Duplicate Prevention**: The standard "Add Repository" window now securely ignores clipboard URLs that are already tracked by Mino, preventing accidental duplicate repo attempts.
- **Menu Alignment Stability**: Hardcoded precise constraint masks to the custom menu items (Header and Footer) to enforce strict right-justification, preventing macOS's standard flexible menu stretching from center-aligning the icon controls.

## [1.2.4] - 2026-02-28
### Added
- **Major Localization Update**: Mino is now natively translated into French (`fr`), German (`de`), Italian (`it`), and Portuguese (`pt`), intelligently adapting to your macOS system language alongside English and Spanish.
### Fixed
- **HUD Visibility**: Prevented macOS from forcefully hiding the floating notification HUD when the `Finder` automatically opens to reveal newly installed Homebrew Casks.

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


