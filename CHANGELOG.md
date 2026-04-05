# Changelog

All notable changes to Mino will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.1] - 2026-04-05

### Fixed
- **Sticky Button Hover State:** Resolved a visual glitch where inline action buttons (Install, Notes, Open Releases, Delete) and header/footer controls (Refresh, Add, Preferences, Quit) would remain stuck in their highlighted appearance the next time the menu was opened. The root cause was that macOS never delivers the `mouseExited` event when a click dismisses the menu mid-hover. A defensive `resetHoverState()` method now forcefully clears hover visuals whenever a button fades out of view, guaranteeing a perfectly clean state on every menu open.

## [1.5.0] - 2026-04-02

### Added
- **Omni-Search Interface:** A unified search bar that filters both repository names and tags seamlessly, providing a single source of truth for discovery.
- **Intelligent Tag Cloud:** Automatic discovery of the 25 most popular tags across the library, displayed as interactive suggestions when no search results are found.
- **Resilient Tag Cloud Layout:** Fixed a coordinate system inversion bug (`FlippedView`) that caused tags to be rendered from bottom-to-top.
- **Real-Time Tag Synchronization:** The suggestion cloud now updates instantly when repositories are added or removed, ensuring search suggestions remain perfectly in sync with the library state.
- **Zero-Configuration Discovery:** Automatic backfilling of repository topics via GitHub API for legacy or unconfigured repositories, enabling instant tag searching without manual effort.
- **400pt Layout Unification:** Established a robust 400pt minimum width baseline across all menu modes (Cards, Hybrid, Columns) to ensure a spacious and consistent visual experience for the search interface.
- **Deterministic Tag Sorting:** Implemented a dual-key sort (Frequency descending, Alphabetical ascending) to prevent random reordering of suggestion labels when frequencies match.
- **Tag Cache Optimization:** Throttled tag indexing for large collections (200+ repos) to prevent UI flickering and redundant CPU usage during background updates.
- **Smart Menu Persistence:** Eliminated redundant menu reconstructions when closing the menu. The application now perfectly preserves the "seen" status of repositories using in-memory view persistence, ensuring zero CPU cost for simple browsing sessions.
- **Continuous Age Updates:** Repository "age" labels (e.g., "59m" → "1h") now dynamically update in real-time every minute synchronously in the background. The timestamps are always perfectly up-to-date the exact millisecond the menu is opened.
- **Memory Overhaul:** Destroyed a significant source of memory churn by migrating to a static shared `ISO8601DateFormatter`. This single architectural patch instantly eradicates 160+ heavy object allocations per minute related to continuous time calculation updates.
- **Settings Optimization:** Prevented an expensive, full-scale menu reconstruction from firing unnecessarily every time the user adjusted the "Refresh Interval" slider in Preferences. The UI now relies entirely on the optimized background tick to reflect these temporal changes natively.
- **Double-Hashtag Normalization:** Fixed a redundant rendering issue where repositories with existing hashtags in their topics would display as `##tag` in the suggestion cloud.
- **Layout Stabilization:** Resolved the "1-line wrap" bug by prioritizing calculated target widths (400pt+) over AppKit's intermediate rendering reports during the first render frame.

## [1.4.9] - 2026-03-29

### Added
- **Performance Overhaul:** Optimized the application's underlying architecture to eliminate unnecessary background CPU and disk usage, particularly for large repository lists (160+ repos).
- **Smart Menu Reconstruction:** Refined the pre-rendering system to skip the entire menu rebuild process when closing the menu if no repos were hovered or read, ensuring zero-cost closures.
- **Preferences UI Modernization:** Replaced inconsistent switches with a clean, macOS-standard checklist for menu settings.
- **Aesthetic Refinement:** Justified numerical steppers and restored the 'Start at Login' master switch for better visual balance and hierarchy.
- **Smarter Tooltips:** Error messages in the menu now show descriptive failure reasons without redundant repository names.
- **UI Polish:** Refined the "Add Repository" success animation to be more subtle and consistent with the app's dynamic theme.

## [1.4.8] - 2026-03-28

### Added
- **Performance Overhaul:** Major optimization of the application's underlying architecture to eliminate unnecessary background CPU and disk usage.
- **Smart Menu Reconstruction:** Implemented a pre-rendering system that only rebuilds the menu UI when data actually changes, ensuring the menu opens instantly while staying idle when closed.
- **Optimized Background Timers:** The countdown timer now skips expensive UI reconstruction while the menu is closed, drastically reducing battery impact.
- **High-Performance Quick Add:** Optimized clipboard monitoring using `changeCount` tracking and regular expression caching. This prevents CPU spikes even when large amounts of text are copied to the system pasteboard.
- **Fluid Preferences Interaction:** Added a debouncing mechanism to the Settings window controls. Interactions with steppers, sliders, and switches are now perfectly smooth, deferring heavy rebuild operations until the user pauses.

### Fixed
- **Empty Release Notes Fallback:** Mino now mirrors GitHub's own web behavior when a release is published without a description body. If the release `body` is `null` or empty, the app automatically resolves the tag reference, dereferencing both lightweight and annotated tags, and displays the underlying commit message as the release notes content. Repositories like `nataliarsand/readdown` v1.8 now correctly render their full changelog instead of showing a blank window.

## [1.4.7] - 2026-03-27

### Changed
- **Grouped Preferences Design:** Rebuilt the Settings window layout from the ground up. All options are now neatly framed inside four logically grouped, borderless `NSBox` cards featuring native iOS-style translucent backgrounds and rounded paddings, retiring the legacy horizontal line separators.
- **Iconographic UI:** Upgraded all text-heavy segmented controls in the Preferences panel to use crisp, localized SF Symbols (e.g. `clock` for Date Sort, `square.grid.2x2` for Card Layout), making the interface instantly readable regardless of the active language.
- **Text Safety Anchors:** Implemented dynamic text truncation (`.byTruncatingTail`) on all variable-length localized settings labels. Expanded the base window width to 480pt to comfortably display verbose translations without crushing the trailing switches and buttons.

### Fixed
- **Flaky Save Interactions:** Re-engineered continuous background saves for all numeric interactions (`NSSlider`, `NSStepper`) using a 0.5s `DispatchWorkItem` debounce. Configurations now safely and flawlessly commit to disk the exact moment the user lifts their hand off the mouse, completely bypassing historical AppKit tracking loop drops.

## [1.4.6] - 2026-03-22

### Changed
- **Menu Aesthetics:** Centered the search field text for a more balanced look.
- **Repository Count UI:** Moved the repository count label from the bottom of the Preferences window to the footer of the main menu, neatly centered between the "Preferences" and "Quit" buttons.
- **Translations:** Shortened the repository count label across all supported languages (e.g. from "Vigilando 119 repositorios" to "119 repositorios") to prevent text truncation in the newly constrained menu footer space.
- **Preferences Polish:** Reduced the height of the Preferences window by 40 points to eliminate the white space left by the relocated repository count label.
- **Repo Typographic Hierarchy:** When viewing tracked repositories, the repository's owner handle is now rendered in a cleanly dimmed, regular-weight font to naturally recede from the bold repository name, dramatically improving scannability.
- **Empty Search State:** Searching for a repository that produces zero matches now presents a sleek, centered "eye.slash" icon in striking red to instantly confirm the filtered state.

### Fixed
- **Release Notes HTML Spacing:** Re-engineered the Markdown-to-HTML interpreter to systematically inject blank lines before block elements. Repositories using custom markdown paragraphs, nested lists, or bold-headers will now render with perfect vertical symmetry natively in macOS.

## [1.4.5] - 2026-03-18

### Changed
- **Header Aesthetics:** Increased the menu header height from 26pt to 32pt. This flawlessly aligns the hover background geometry of the Header Action Buttons (Refresh/Add) with the Footer Buttons (Preferences/Quit), resolving an optical squash illusion and yielding a perfectly symmetrical interface.
- **Button Brightness:** Gently increased the hover opacity of all inline `MenuActionButton` elements from 15% to 20% to drastically improve visual contrast and tactile feedback.

### Fixed
- **Phantom Red Dot:** Fixed a persistent state bug where the unread notification pulse remained active if background updates successfully resolved *while* the user was actively holding the menu open. The system now executes a strict `clearUnreadPulse()` synchronization upon closing the menu, guaranteeing the red dot remains tightly coupled to what the user implicitly consumed on screen.

## [1.4.4] - 2026-03-14

### Fixed
- **Quick Add UI:** Solved a regression where long repository names would abnormally widen the menu.
- **Improved Truncation:** The Quick Add header now correctly truncates long names in the middle, matching the repository list behavior.
- **Visual Consistency:** Standardized the header font size (11pt) and aligned control buttons (-18pt trailing) to match the main interface perfectly.
- **Luminance Balance:** Adjusted the "+" icon's normal state color to match the subtle tone of other control icons (Refresh, Quit, Preferences).

## [1.4.3] - 2026-03-14

### Added
- **Stealth Search (Final):** The search field is now always present in the header and automatically receives focus when opening the menu for instant typing.
- **Content-Driven Opacity:** The search field remains subtly semitransparent (25% opacity) even with focus to maintain a clean look. It transitions to 100% opacity instantly as soon as the first character is entered.
- **UI Simplification:** Permanently removed the "Show Search" preference as the new always-available design makes it redundant.

### Fixed
- **Interaction Robustness:** Eliminated an issue where the search field would gain focus but remain opaque, and fixed hover interference from the repository list.
- **Translation Cleanup:** Removed obsolete search-related labels in all 11 supported languages.
## [1.4.1] - 2026-03-13

### Changed
- **Search UI Simplification:** Removed the `CMD + F` shortcut to prevent accidental menu closures. The search toggle has been renamed to "Show Search" and moved under the "Start at Login" option in Preferences for better accessibility.
- **Status Indicator Decoupling:** The red dot notification is now independent of repository highlighting. Opening the menu clears the red dot immediately, while repository highlights persist until explicitly hovered, ensuring a less intrusive notification experience.
- **Refresh Tooltip Stability:** Optimized the refresh button tooltip to only update when the time actually changes, improving stability on macOS. Restored the classic ellipses to the "Refreshing..." status.

### Fixed
- **New Repo Notification:** Guaranteed that adding a new repository correctly triggers the red notification pulse immediately.
- **Notification State Cleanup:** Synchronized the notification state to wipe memory of deleted repositories, preventing phantom notifications if a repo is re-added.

## [1.4.0] - 2026-03-13

### Added
- **Integrated Header Search:** The dedicated search row has been retired in favor of a sleek, centered search field (30% width) integrated directly into the menu header between action icons.
- **Dynamic Tooltip Tracker:** The refresh countdown text is now hidden by default to maximize aesthetics, accessible instantly via a native hover tooltip on the refresh icon.
- **Horizontal Symmetry (18pt):** Unified the entire interface to a strict 18pt horizontal margin. All primary controls (Refresh, Add, Search, Preferences, and Quit) now align perfectly with repository list items for a professional, native feel.
- **Header Highlight Polish:** Converted the refresh icon into a native `MenuActionButton`, enabling the same subtle, high-quality hover background highlighting found on other menu actions.
- **Improved Tooltip Support:** Added intelligent hover tooltips for repository names that are too long for the menu width, ensuring full visibility without breaking the layout.

### Changed
- **Unified Confirmation Animations:** Synchronized the "Add Repository" success feedback; the menu icon and the floating window now both perform the same signature green `.bounce` SF Symbol effect.
- **Keyboard Robustness:** Rewrote the shortcut handler to be significantly more resilient. `CMD + ,` is now bulletproof, and common accidental keystrokes (like `CMD+Q` or `CMD+N`) no longer cause the menu to close unexpectedly.

### Fixed
- **Quick Add Race Condition:** Guaranteed that newly added repositories correctly display their red notification dot even if a background refresh occurs while the menu is actively held open.
- **Translation Consistency:** Refined Portuguese, German, and French strings to ensure "Quick Add" headers and live progress states match the new compact UI.

## [1.3.9] - 2026-03-10

### Added
- **Dynamic Action Status:** When a repository is being added via the Quick Add mechanism or the Hub, the menu header instantly transforms to display an "Añadiendo {dueño}/{repo}..." progress state to provide real-time feedback over slow network connections before seamlessly updating the UI.

### Fixed
- **Phantom Indicator Bug:** Overhauled the `NSMenu` lifecycle handling to guarantee the Red Notification "Iris" remains organically synchronized with the user's focus. The 'visto' state is now strictly enforced only upon *closing* the menubar, meaning newly-added repositories are accurately decorated with the red notification dot until explicitly dismissed.
- **State Purge on Deletion:** Eliminating a repository now synchronously wipes its lingering "last-seen" memory state, preventing bugs where re-adding a previously deleted repository would bypass the notification dot entirely.
- **Dangling Release Notes:** Solved a visual glitch where the floating Release Notes window remained open after its associated repository was forcefully deleted from the main menu list.
- **Foreign Cask Resilience:** Greatly enhanced the exception handling for Homebrew Casks sourced from third-party TAPs (custom external repositories). Mino now cleanly intercepts the `404` errors returned by the public `formulae.brew.sh` API instead of crashing the URLSession parser natively.

## [1.3.8] - 2026-03-08

### Added
- **Global Localization Expansion:** Mino is now natively accessible to hundreds of millions of new users with full UI translation support for **Mandarin Chinese**, **Hindi**, **Arabic**, **Russian**, and **Japanese**. The application automatically detects and adopts your Mac's primary system language natively.

## [1.3.7] - Density & Hue Expansion - 2026-03-06

### Added
- **Compact Mode:** Transitioned the Easter Egg Density logic into a designated `NSSwitch` UI component in the `SettingsWindowController.swift`. Users can now explicitly toggle extreme repository density (shrinking rows from 22pt to 16pt), translating the label natively across all 6 supported languages.
- **Color Palette Expansion:** Expanded the curated list of colors in `GenerateIcon.swift` from 12 static colors to over 20 neon-themed, distinct colors (e.g. Cyberpunk Yellow, Crimson Red) to dramatically lower the odds of visually identical sequential builds.

### Fixed
- **Universal App Icon Color Sync:** Fixed a compilation desync in `build.sh` where `swift GenerateIcon.swift` generated three separate random colors for `Intel`, `Silicon`, and `Universal` builds. Decoupled the generation logic upstream so exactly *one* `AppIcon.icns` and exactly *one* `GeneratedColor.swift` property are shared universally before generating the macOS file structures.

## [1.3.6] - Panther Hotfix - 2026-03-05

### Fixed
- **Architectural Memory Leak:** Completely eliminated the severe RAM and CPU spikes introduced in v1.3.5 when interacting with the "Add Repository" window. The dynamic UI color synchronization has been re-engineered from a heavy runtime image processor into a zero-cost build-time code injection. Rendering the tint colors now consumes 0.0% CPU and RAM.

## [1.3.5] - Lynx - 2026-03-05

### Added
- **Intelligent Homebrew Cask Updates:** The top-level menu refresh interval now silently runs `brew update` in a background thread if it detects that any of your tracked repositories with an installed Homebrew Cask have released a new version on GitHub. This effectively eliminates the "Cask Not Found" errors when users immediately try to update right after a new release drops.
- **Dynamic Personality Colors:** Abandoned the static blue system color. The app now compiles its icon natively during `build.sh` by randomly selecting from a curated palette of vibrant colors (Electric Pink, Toxic Green, Neon Turquoise, etc.). Each compilation generates a visually unique Mino. 
- **UI Color Synchronization:** The animated SF Symbol "Eye" floating inside the "Add Repository" window now dynamically scans the generated application bundle at runtime and synchronizes its own tint color to seamlessly match the randomly generated App Icon.

### Changed
- **Animation Polish:** Removed duplicate scale animation triggers from the menu bar icon when interacting with certain action buttons. The visual confirmation is now a singular, precise pulse.
- **Code Optimization:** Conducted a comprehensive cleanup of dead code, specifically targeting legacy `showAbout` methods and pruning 11 orphaned localization keys from the translation mapping file.

### Fixed
- **Menu Row UI Flashing:** Completely removed the visual stammer and flash of inline tracking icons that occurred at the very instant a user clicked to open the menu while the width was dynamically calculated. State transitions for hovering are now suspended securely until the view is fully rendered on screen.

## [1.3.4] - Argos Hotfix - 2026-03-03
### Fixed
- **Pure Stealth Mode:** Removed experimental `NSApp` activation policies that were causing Mino's icon to temporarily pop into the macOS Dock when opening windows like Settings or Add Repository. Mino is now perfectly invisible in the Dock again while retaining the WindowServer fix from 1.3.3.

## [1.3.3] - Argos - 2026-03-03

### Fixed
- **The "Stuck Dock" WindowServer Anomaly:** Successfully identified and patched a complex, framework-level bug introduced in version 1.0.0 where Mino's custom interface abruptly hijacked the macOS menu tracking loop. By meticulously yielding the main thread and deferring UI actions until after the native `menuDidClose` event organically completes, macOS WindowServer can finally reclaim proper edge-detection, guaranteeing the Dock's auto-hide mechanism remains flawless.

## [1.3.2] - 2026-03-02
### Added
- **Multi-Hunt Repository Hub:** The "Add Repository" window now functions as a persistent, `.floating` background-aware targeting hub. It actively monitors your clipboard while you browse Safari, seamlessly queuing sequential GitHub URLs for one-click ingestion without dismissing the window. 
- **Zarpazo Interaction:** Successfully added repositories trigger a native, animated "cat swipe" (`pawprint`) visual confirmation to provide satisfying tactile feedback.
- **Pluralized Tooltips:** Semantic updates across English and Spanish localized files to reflect sequential addition capabilities ("Add Repositories...").

### Changed
- **Modern Segmented UI:** Stripped the legacy radio buttons and instructional text from the Add Repository window in favor of a clean, highly compact `NSSegmentedControl` layout.
- **Expanded Interaction Targets:** Dramatically increased the clickable surface area (`intrinsicContentSize` override to 26x26) for inline hover actions (Install, Delete, Notes) in the repository menu, removing frustrating dead zones and making them immensely easier to trigger.

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


