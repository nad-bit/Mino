import Cocoa

enum SymbolAnimation {
    case bounce
    case replaceWithSlash
    case wiggle
    case rotate
    case scale
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSSearchFieldDelegate, NSPopoverDelegate, NSTextViewDelegate {
    var statusItem: NSStatusItem!
    private var statusIconView: NSImageView!
    private var statusIndicatorDot: NSBox!
    var mainPopover: NSPopover?
    var mainPopoverVC: MainPopoverViewController!
    var releaseNotesPopover: NSPopover?
    var settingsPopover: NSPopover?
    var aboutPopover: NSPopover?
    var lastSettingsCloseTime: Date?
    
    var repoCache: [String: RepoInfo] = [:]
    
    var headerView: HeaderMenuItemView!
    var footerView: FooterMenuItemView?
    
    // Search properties
    var searchField: NSSearchField?
    var currentSearchQuery: String = ""
    private var lastMainPopoverOpenTime: Date?
    
    var popoverIsOpen = false
    
    // Defer actions until the popover finishes its closing animation
    var pendingAction: (() -> Void)? = nil
    var quickAddingRepo: String? = nil
    
    // Undo support for last deleted repo
    var lastDeletedRepo: (config: RepoConfig, index: Int, cache: RepoInfo?)? = nil
    private var lastPasteboardChangeCount = -1
    private var lastClipboardRepo: String? = nil
    var popularTagsCache: [String] = []
    private var currentMenuWidth: CGFloat = 320.0
    
    
    var addRepoPopover: NSPopover?
    
    // Coordinators
    var refreshCoordinator: RefreshCoordinator!
    var repoCoordinator: RepoCoordinator!
    
    // Beer Handle (ASA)
    var beerHandle: BeerHandlePanel?
    private var beerHandleShowWorkItem: DispatchWorkItem?
    

    
    func hideInformationalWindows(except popoverToKeep: NSPopover? = nil) {
        // Ensure any attached sheets are dismissed to prevent UI lockups
        [releaseNotesPopover, settingsPopover, aboutPopover, addRepoPopover].forEach { popover in
            if popover != popoverToKeep, let window = popover?.contentViewController?.view.window, let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
        }
        
        if popoverToKeep != releaseNotesPopover { releaseNotesPopover?.close() }
        if popoverToKeep != settingsPopover { settingsPopover?.close() }
        if popoverToKeep != aboutPopover { aboutPopover?.close() }
        if popoverToKeep != addRepoPopover { addRepoPopover?.close() }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let btn = statusItem.button {
            // Remove default image to allow custom view
            btn.image = nil
            // macOS 27 Golden Gate Compatibility:
            // Tooltips on status bar items are automatically suppressed if both title and attributedTitle
            // are empty. We assign a zero-width space with clear color so that neither title nor
            // attributedTitle is empty, ensuring tooltips appear seamlessly without affecting visual layout.
            let zeroWidthTitle = NSAttributedString(string: "\u{200B}", attributes: [
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 0.01)
            ])
            btn.attributedTitle = zeroWidthTitle
            btn.toolTip = Translations.get("meow")
            btn.setAccessibilityTitle(Translations.get("meow"))
            btn.setAccessibilityLabel(Translations.get("meow"))
            btn.setAccessibilityHelp(Translations.get("meow"))
            
            // Create custom image view using signature Feline Eye vector icon
            let hasPulse = UserDefaults.standard.bool(forKey: "HasUnreadPulse")
            let eyeImage = FelineEyeIcon.createIcon(hasUpdates: hasPulse)
            
            statusIconView = NSImageView(image: eyeImage)
            statusIconView.translatesAutoresizingMaskIntoConstraints = false
            statusIconView.wantsLayer = true // REQUIRED for layer-backed symbol effects
            statusIconView.toolTip = Translations.get("meow")
            statusIconView.setAccessibilityLabel(Translations.get("meow"))
            
            btn.addSubview(statusIconView)
            
            NSLayoutConstraint.activate([
                statusIconView.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                statusIconView.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                statusIconView.widthAnchor.constraint(equalToConstant: 18),
                statusIconView.heightAnchor.constraint(equalToConstant: 16) // typical SF symbol aspect ratio inside button
            ])
            
            // Legacy indicator overlay maintained for backward compatibility (kept hidden)
            statusIndicatorDot = NSBox()
            statusIndicatorDot.boxType = .custom
            statusIndicatorDot.isTransparent = true
            statusIndicatorDot.isHidden = true
            statusIndicatorDot.translatesAutoresizingMaskIntoConstraints = false
            btn.addSubview(statusIndicatorDot)
        }
        
        let hasPulse = UserDefaults.standard.bool(forKey: "HasUnreadPulse")
        updateStatusIcon(hasUpdates: hasPulse)
        
        // Initialize Popover
        mainPopoverVC = MainPopoverViewController(appDelegate: self)
        let popover = NSPopover()
        popover.contentViewController = mainPopoverVC
        popover.behavior = .transient
        popover.animates = Constants.popoverAnimates
        popover.delegate = self
        self.mainPopover = popover
        
        if let btn = statusItem.button {
            btn.target = self
            btn.action = #selector(togglePopover(_:))
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Initialize coordinators
        refreshCoordinator = RefreshCoordinator(delegate: self)
        repoCoordinator = RepoCoordinator(delegate: self)
        
        // Restore persistent disk cache (metadata + ETags) so 900+ repositories
        // populate instantly on launch and subsequent conditional checks use 304 (0 rate limit cost)
        let diskCache = ConfigManager.shared.loadCache()
        self.repoCache = diskCache.repoCache
        GitHubAPI.shared.loadETags(diskCache.etags)
        
        // Defer heavy UI building and initial refresh to ensure status icon shows instantly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updatePopularTagsCache()
            self.rebuildMenu()
            self.refreshCoordinator.startTimers()
            
            // Allow the initial runloop pass to settle so icon animation doesn't freeze
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                
                // Smart launch refresh: Only trigger full network refresh if cache is empty
                // or if the configured interval has elapsed since the last recorded refresh.
                let refreshMinutes = ConfigManager.shared.config.refreshMinutes
                let nextRefreshDate = self.refreshCoordinator.lastRefreshTime.addingTimeInterval(TimeInterval(refreshMinutes * 60))
                let isDue = (self.refreshCoordinator.lastRefreshTime == Date.distantPast) || (nextRefreshDate.timeIntervalSinceNow <= 0)
                
                if self.repoCache.isEmpty || isDue {
                    self.triggerFullRefresh(nil)
                } else {
                    self.footerView?.updateTimeText(self.getRefreshTitle(), isRefreshing: false)
                }
                
                self.refreshCoordinator.startTagBackfillSequence()
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(configDidUpdate), name: Notification.Name("ConfigChanged"), object: nil)
        
        // Setup Global Hotkey
        GlobalHotkeyManager.shared.onHotkeyTriggered = { [weak self] in
            self?.togglePopover(nil)
        }
        
        var savedKeyCode = UserDefaults.standard.integer(forKey: "MinoShortcutKeyCode")
        var savedModifiers = UserDefaults.standard.integer(forKey: "MinoShortcutModifiers")
        
        // Migrate old default (CTRL + ALT + CMD + M) to new default (CTRL + ALT + M)
        let oldModifiers = Int(NSEvent.ModifierFlags([.control, .option, .command]).rawValue)
        if savedKeyCode == 46 && savedModifiers == oldModifiers {
            savedKeyCode = 46
            savedModifiers = Int(NSEvent.ModifierFlags([.control, .option]).rawValue)
            UserDefaults.standard.set(savedKeyCode, forKey: "MinoShortcutKeyCode")
            UserDefaults.standard.set(savedModifiers, forKey: "MinoShortcutModifiers")
        }
        
        // Default shortcut: CTRL + ALT + M (46)
        if savedKeyCode == 0 && UserDefaults.standard.object(forKey: "MinoShortcutKeyCode") == nil {
            savedKeyCode = 46
            savedModifiers = Int(NSEvent.ModifierFlags([.control, .option]).rawValue)
            UserDefaults.standard.set(savedKeyCode, forKey: "MinoShortcutKeyCode")
            UserDefaults.standard.set(savedModifiers, forKey: "MinoShortcutModifiers")
        }
        
        if savedKeyCode > 0 {
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(savedModifiers))
            GlobalHotkeyManager.shared.register(keyCode: savedKeyCode, modifiers: modifiers)
        }
        
        // Register URL Scheme Handler (mino://)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    static func createMugImage(slashed: Bool) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "mug.fill", accessibilityDescription: nil) else { return nil }
        guard slashed else { return base }
        
        let size = NSSize(width: 48, height: 48)
        let img = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect.insetBy(dx: 4, dy: 4))
            
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            
            let p1 = CGPoint(x: rect.minX + 6, y: rect.maxY - 6)
            let p2 = CGPoint(x: rect.maxX - 6, y: rect.minY + 6)
            
            // Knockout gap around slash
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.setLineCap(.round)
            ctx.setLineWidth(5.5)
            ctx.strokeLineSegments(between: [p1, p2])
            ctx.restoreGState()
            
            // Slash stroke
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setLineWidth(2.5)
            NSColor.white.setStroke()
            ctx.strokeLineSegments(between: [p1, p2])
            ctx.restoreGState()
            
            return true
        }
        img.isTemplate = false
        return img
    }
    
    func applyBeerHandleState(_ newState: Bool) {
        DispatchQueue.main.async {
            ConfigManager.shared.config.beerHandleEnabled = newState
            ConfigManager.shared.saveConfig()
            
            if newState {
                self.updateBeerHandleVisibility()
            } else {
                self.beerHandle?.hideAnimated()
            }
            
            let statusText = newState ? Translations.get("beerHandleEnabled") : Translations.get("beerHandleDisabled")
            let mugImage = AppDelegate.createMugImage(slashed: !newState)
            HUDPanel.shared.show(title: Translations.get("beerHandleTitle"), subtitle: statusText, image: mugImage)
        }
    }
    
    static func findMatchingRepo(for target: String, in repos: [RepoConfig]) -> RepoConfig? {
        let trimmed = target.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return nil }
        
        // 1. Exact match on repo.name (e.g. "rclone-ui/rclone-ui" or "nad-bit/Mino")
        if let match = repos.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }
        
        // 2. Exact match on repo.cask (e.g. "nad-bit/tap/mino" or "lulu")
        if let match = repos.first(where: { $0.cask?.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }
        
        // 3. Short repo name match (e.g. "rclone-ui" matching "rclone-ui/rclone-ui")
        if let match = repos.first(where: {
            $0.name.split(separator: "/").last?.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return match
        }
        
        // 4. Short cask name match (e.g. "mino" matching "nad-bit/tap/mino")
        if let match = repos.first(where: {
            $0.cask?.split(separator: "/").last?.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return match
        }
        
        return nil
    }
    
    func findMatchingRepo(for target: String) -> RepoConfig? {
        return AppDelegate.findMatchingRepo(for: target, in: ConfigManager.shared.config.repos)
    }
    
    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }
        
        guard url.scheme?.lowercased() == "mino" else { return }
        
        let host = url.host?.lowercased() ?? ""
        
        // 1. Handle ASA (Beer Mug Handle): mino://handle or mino://handle/[on|off|toggle]
        if host == "handle" {
            let action = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            let validHandleActions: Set<String> = ["", "toggle", "on", "off", "enable", "disable", "true", "false", "1", "0"]
            guard validHandleActions.contains(action) else {
                print("⚠️ [AppDelegate] Unrecognized handle action: \(action)")
                return
            }
            
            let current = ConfigManager.shared.config.beerHandleEnabled ?? true
            let newState: Bool
            if action == "on" || action == "true" || action == "1" || action == "enable" {
                newState = true
            } else if action == "off" || action == "false" || action == "0" || action == "disable" {
                newState = false
            } else {
                newState = !current
            }
            applyBeerHandleState(newState)
            return
        }
        
        // 2. Set parameter: mino://set?beer_handle=true|false|toggle
        if host == "set" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let items = components.queryItems {
                if let item = items.first(where: { $0.name == "beer_handle" || $0.name == "beer_handle_enabled" }),
                   let val = item.value?.lowercased() {
                    let current = ConfigManager.shared.config.beerHandleEnabled ?? true
                    let newState: Bool
                    if val == "on" || val == "true" || val == "1" || val == "enable" {
                        newState = true
                    } else if val == "off" || val == "false" || val == "0" || val == "disable" {
                        newState = false
                    } else if val == "toggle" {
                        newState = !current
                    } else {
                        return
                    }
                    applyBeerHandleState(newState)
                    return
                }
            }
        }
        
        // 3. Open Notes Popover: mino://notes/<target> or mino://notes?target=<target>
        if host == "notes" {
            var target = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if target.isEmpty,
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let items = components.queryItems {
                target = items.first(where: { $0.name == "target" || $0.name == "repo" || $0.name == "cask" })?.value ?? ""
            }
            
            // Clean up target (strip https://github.com/ etc.)
            target = target.replacingOccurrences(of: "https://github.com/", with: "", options: .caseInsensitive)
            target = target.replacingOccurrences(of: "http://github.com/", with: "", options: .caseInsensitive)
            target = target.replacingOccurrences(of: "github.com/", with: "", options: .caseInsensitive)
            target = target.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
            
            guard !target.isEmpty else { return }
            
            if let matchedRepo = findMatchingRepo(for: target) {
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    if self.mainPopover?.isShown == true {
                        self.mainPopover?.close()
                    }
                    self.hideInformationalWindows(except: self.releaseNotesPopover)
                    if let button = self.statusItem?.button {
                        self.repoCoordinator.handleShowNotes(for: matchedRepo.name, relativeTo: button)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    HUDPanel.shared.showCompletion(
                        title: Translations.get("notesNotFound"),
                        subtitle: target,
                        isSuccess: false
                    )
                }
            }
            return
        }
        
        // 4. Add repository: mino://add/<target>
        if host == "add" {
            var rawTarget = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if rawTarget.isEmpty,
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let items = components.queryItems {
                rawTarget = items.first(where: { $0.name == "target" || $0.name == "repo" || $0.name == "cask" })?.value ?? ""
            }
            
            // Clean up URL prefix if someone passes https://github.com/... or github.com/...
            rawTarget = rawTarget.replacingOccurrences(of: "https://github.com/", with: "", options: .caseInsensitive)
            rawTarget = rawTarget.replacingOccurrences(of: "http://github.com/", with: "", options: .caseInsensitive)
            rawTarget = rawTarget.replacingOccurrences(of: "github.com/", with: "", options: .caseInsensitive)
            rawTarget = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !rawTarget.isEmpty, rawTarget.count <= 256 else { return }
            
            // Strict canonical validation via Utils.isValidMinoTarget
            guard Utils.isValidMinoTarget(rawTarget) else {
                print("⚠️ [AppDelegate] Ignored malformed target from mino://add/ URL: \(rawTarget)")
                return
            }
            
            Task {
                _ = await self.repoCoordinator.addRepoSmart(repoName: rawTarget)
            }
            return
        }
        
        print("⚠️ [AppDelegate] Ignored unrecognized or unsupported mino:// command: \(host)")
    }
    
    @objc private func configDidUpdate() {
        DispatchQueue.main.async {
            // When the user changes the refresh interval, recalculate boundaries
            // and immediately reschedule exactRefreshTimer so obsolete pending timers
            // don't fire prematurely.
            let newMinutes = ConfigManager.shared.config.refreshMinutes
            let nextRefresh = self.refreshCoordinator.lastRefreshTime.addingTimeInterval(TimeInterval(newMinutes * 60))
            if nextRefresh.timeIntervalSinceNow <= 0 && !self.refreshCoordinator.isRefreshing {
                self.refreshCoordinator.lastRefreshTime = Date()
            }
            
            self.refreshCoordinator.scheduleExactTimer()
            self.footerView?.updateTimeText(self.getRefreshTitle(), isRefreshing: self.isRefreshing)
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        refreshCoordinator.countdownTimer?.invalidate()
        refreshCoordinator.exactRefreshTimer?.invalidate()
        GlobalHotkeyManager.shared.unregister()
        ConfigManager.shared.saveCacheSync(repoCache: self.repoCache, etags: GitHubAPI.shared.allETags())
    }
    
    @objc func togglePopover(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showAboutPanel()
            return
        }
        
        let anyPopoverShown = (mainPopover?.isShown == true) ||
                              (settingsPopover?.isShown == true) ||
                              (releaseNotesPopover?.isShown == true) ||
                              (aboutPopover?.isShown == true) ||
                              (addRepoPopover?.isShown == true)
        
        if anyPopoverShown {
            mainPopover?.close()
            settingsPopover?.close()
            releaseNotesPopover?.close()
            aboutPopover?.close()
            addRepoPopover?.close()
        } else {
            if let button = statusItem.button {
                refreshQuickAddState()
                rebuildMenu() // Ensure latest data
                mainPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                
                // Activate app to bring popover to front and ensure focus
                NSApp.activate(ignoringOtherApps: true)
                
                // Force the popover's window to become key so it handles 'transient' clicks correctly
                if let popoverWindow = mainPopover?.contentViewController?.view.window {
                    popoverWindow.makeKeyAndOrderFront(nil)
                }
                
                // Focus search field automatically
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.searchField?.window?.makeFirstResponder(self.searchField)
                }
            }
        }
    }
    
    @objc func showAboutPanel() {
        hideInformationalWindows(except: aboutPopover)
        if aboutPopover == nil {
            let popover = NSPopover()
            popover.contentViewController = AboutViewController()
            popover.behavior = .transient
            popover.animates = Constants.popoverAnimates
            self.aboutPopover = popover
        }
        
        guard let popover = aboutPopover else { return }
        
        if popover.isShown {
            popover.close()
        } else {
            if let btn = statusItem.button {
                popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
                
                // CRITICAL: Delaying activation and key state slightly to allow the click event to finish.
                // This ensures the popover can become key and thus handle 'transient' dismissal correctly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = popover.contentViewController?.view.window {
                        window.makeKeyAndOrderFront(nil)
                        window.makeFirstResponder(popover.contentViewController?.view)
                    }
                }
            }
        }
    }
    
    func rebuildMenu(preserveScroll: Bool = false) {
        mainPopoverVC.rebuildMenu(preserveScroll: preserveScroll)
        refreshQuickAddState()
    }
    
    // MARK: - Forwarding to RefreshCoordinator
    
    var isRefreshing: Bool {
        get { refreshCoordinator?.isRefreshing ?? false }
        set { refreshCoordinator?.isRefreshing = newValue }
    }
    
    func getRefreshTitle() -> String {
        return refreshCoordinator.getRefreshTitle()
    }
    
    @objc func triggerFullRefresh(_ sender: Any?) {
        refreshCoordinator.triggerFullRefresh(sender)
    }
    
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Forwarding to RepoCoordinator
    
    func handleOpenRepo(for repoName: String) {
        repoCoordinator.handleOpenRepo(for: repoName)
    }
    
    func handleOpenReleases(for repoName: String) {
        repoCoordinator.handleOpenReleases(for: repoName)
    }
    
    func handleShowNotes(for repoName: String, relativeTo view: NSView) {
        repoCoordinator.handleShowNotes(for: repoName, relativeTo: view)
    }
    
    func handleInstallBrewCask(for caskName: String) {
        repoCoordinator.handleInstallBrewCask(for: caskName)
    }
    
    func handleToggleFavorite(for repoName: String) {
        guard let index = ConfigManager.shared.config.repos.firstIndex(where: { $0.name == repoName }) else { return }
        
        let newState = !(ConfigManager.shared.config.repos[index].isFavorite ?? false)
        ConfigManager.shared.config.repos[index].isFavorite = newState
        ConfigManager.shared.saveConfig()
        
        // Sync the change with the UI's data source so scrolling doesn't revert the visual state
        mainPopoverVC.updateFavoriteState(for: repoName, isFavorite: newState)
    }
    
    func performAfterPopoverClose(_ action: @escaping () -> Void) {
        mainPopover?.close()
        action()
    }
    

    
    func deleteRepoInline(repoName: String) {
        repoCoordinator.deleteRepoInline(repoName: repoName)
    }
    
    @objc func unifiedAddRepoDialog(_ sender: Any) {
        repoCoordinator.openAddRepoDialog(sender)
    }
    
    func addRepoSmart(repoName: String) async -> Bool {
        return await repoCoordinator.addRepoSmart(repoName: repoName)
    }
    
    // MARK: - App Actions
    
    func focusSearchField() {
        if let sf = searchField {
            sf.window?.makeFirstResponder(sf)
        }
    }
    
    @objc func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }
    
    @objc func openSettingsWindow(_ sender: Any?) {
        hideInformationalWindows(except: settingsPopover)
        
        if settingsPopover == nil {
            let popover = NSPopover()
            popover.contentViewController = SettingsViewController()
            popover.behavior = .transient
            popover.animates = Constants.popoverAnimates
            popover.delegate = self
            self.settingsPopover = popover
        }
        
        guard let popover = settingsPopover else { return }
        
        if popover.isShown {
            popover.close()
        } else {
            // Prevent immediate reopening if closed by transient behavior (clicking the button itself)
            if let lastClose = lastSettingsCloseTime, Date().timeIntervalSince(lastClose) < 0.2 {
                return
            }
            if let headerView = self.headerView, headerView.window != nil {
                // Anchor to the top edge of the header with zero height.
                // This forces the arrow to the top and helps align the popover body 
                // with the menu's top edge even when constrained by the screen.
                let anchor = NSRect(x: 0, y: 0, width: headerView.bounds.width, height: 0)
                popover.show(relativeTo: anchor, of: headerView, preferredEdge: .minX)
            } else if let view = sender as? NSView, view.window != nil {
                popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minX)
            } else if let btn = statusItem.button {
                popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            }
            
            // CRITICAL: Delaying activation and key state slightly to allow the click event to finish.
            // This ensures the popover can become key and thus handle 'transient' dismissal correctly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
                if let window = popover.contentViewController?.view.window {
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(popover.contentViewController?.view)
                }
            }
        }
    }
    
    func updateStatusIcon(hasUpdates: Bool) {
        statusIconView?.image = FelineEyeIcon.createIcon(hasUpdates: hasUpdates)
        statusIndicatorDot?.isHidden = true
        let meow = Translations.get("meow")
        statusIconView?.toolTip = meow
        statusIconView?.setAccessibilityLabel(meow)
        
        let zeroWidthTitle = NSAttributedString(string: "\u{200B}", attributes: [
            .foregroundColor: NSColor.clear,
            .font: NSFont.systemFont(ofSize: 0.01)
        ])
        statusItem?.button?.attributedTitle = zeroWidthTitle
        statusItem?.button?.toolTip = meow
        statusItem?.button?.setAccessibilityTitle(meow)
        statusItem?.button?.setAccessibilityLabel(meow)
        statusItem?.button?.setAccessibilityHelp(meow)
        
        // Sync beer handle visibility with the Red Eye state
        updateBeerHandleVisibility()
    }
    
    // MARK: - Search Filtering Logic
    
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        currentSearchQuery = field.stringValue
        filterMenuBySearchQuery(currentSearchQuery)
        headerView?.updateSearchOpacity()
    }
    
    func controlTextDidBeginEditing(_ obj: Notification) {
        if let field = obj.object as? NSSearchField,
           let editor = field.currentEditor() as? NSTextView {
            editor.menu = nil
        }
    }
    
    func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        return nil
    }
    
    func updatePopularTagsCache() {
        let repos = ConfigManager.shared.config.repos
        if repos.isEmpty {
            popularTagsCache = []
            return
        }
        var counts: [String: Int] = [:]
        for repo in repos {
            repo.tags?.forEach { counts[$0, default: 0] += 1 }
        }
        popularTagsCache = counts.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            return a.key.lowercased() < b.key.lowercased()
        }.map { 
            let clean = $0.key.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            return "#\(clean)"
        }
    }
    
    func filterMenuBySearchQuery(_ query: String) {
        currentSearchQuery = query
        
        // With NSTableView, we don't hide views manually. 
        // We just rebuild the data source and reload the table.
        mainPopoverVC.rebuildMenu()
    }
    
    // MARK: - Animations
    
    func animateStatusIcon(with animation: SymbolAnimation) {
        guard let imageView = statusIconView else { return }
        
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return
        }
        
        // Ensure anchorPoint is centered at (0.5, 0.5) so scale/rotation pivots around center
        if let layer = imageView.layer, layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let frame = imageView.frame
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: frame.midX, y: frame.midY)
        }
        
        switch animation {
        case .bounce:
            let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bounce.values = [0, 4.0, -2.0, 1.5, 0]
            bounce.keyTimes = [0.0, 0.25, 0.5, 0.75, 1.0]
            bounce.duration = 0.4
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageView.layer?.add(bounce, forKey: "mino.bounce")
            
        case .replaceWithSlash:
            let slashImg = FelineEyeIcon.createSlashIcon()
            imageView.image = slashImg
            
            // Revert after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                let currentPulse = UserDefaults.standard.bool(forKey: "HasUnreadPulse")
                self.statusIconView?.image = FelineEyeIcon.createIcon(hasUpdates: currentPulse)
            }
            
        case .wiggle:
            let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            let angle: CGFloat = 0.24 // ~14 degrees
            wiggle.values = [0, -angle, angle, -angle * 0.6, angle * 0.6, -angle * 0.2, 0]
            wiggle.keyTimes = [0.0, 0.18, 0.36, 0.54, 0.72, 0.88, 1.0]
            wiggle.duration = 0.5
            wiggle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageView.layer?.add(wiggle, forKey: "mino.wiggle")
            
        case .rotate:
            let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
            rotate.fromValue = 0
            rotate.toValue = -2.0 * CGFloat.pi
            rotate.duration = 0.55
            rotate.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageView.layer?.add(rotate, forKey: "mino.rotate")
            
        case .scale:
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1.0, 0.78, 1.15, 0.95, 1.0]
            scale.keyTimes = [0.0, 0.25, 0.55, 0.8, 1.0]
            scale.duration = 0.35
            scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageView.layer?.add(scale, forKey: "mino.scale")
        }
    }
    
    func setStatusIconRefreshing(_ isRefreshing: Bool) {
        guard let imageView = statusIconView else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
        
        // Ensure anchorPoint is centered at (0.5, 0.5)
        if let layer = imageView.layer, layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let frame = imageView.frame
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: frame.midX, y: frame.midY)
        }
        
        if isRefreshing {
            if imageView.layer?.animation(forKey: "mino.refreshRotation") == nil {
                let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotation.fromValue = 0
                rotation.toValue = -2.0 * CGFloat.pi
                rotation.duration = 1.0
                rotation.repeatCount = .infinity
                rotation.isRemovedOnCompletion = false
                imageView.layer?.add(rotation, forKey: "mino.refreshRotation")
            }
        } else {
            imageView.layer?.removeAnimation(forKey: "mino.refreshRotation")
        }
    }
    
    // MARK: - Popover State
    
    
    
    func clearUnreadPulse() {
        // Acknowledge current versions for the red pulse
        var notifiedVersions = UserDefaults.standard.dictionary(forKey: "LastNotifiedVersions") as? [String: String] ?? [:]
        for (repoName, info) in repoCache {
            if let v = info.version {
                notifiedVersions[repoName] = v
            }
        }
        UserDefaults.standard.set(notifiedVersions, forKey: "LastNotifiedVersions")
        UserDefaults.standard.set(false, forKey: "HasUnreadPulse")
        
        updateStatusIcon(hasUpdates: false) // Turn off red dot immediately for responsiveness
    }
    
    func refreshQuickAddState() {
        // Hybrid Quick Add & Global Refresh interceptor
        if let header = headerView {
            if quickAddingRepo != nil || refreshCoordinator.isRefreshing {
                // Currently fetching — show "Adding..." or "Refreshing..." status
                header.updateClipboardState(repo: nil, isProcessing: true)
            } else {
                let currentChangeCount = NSPasteboard.general.changeCount
                let clipboardRepo: String?
                
                if currentChangeCount != lastPasteboardChangeCount {
                    // Contents changed — re-run the clipboard regex (pre-compiled, fast)
                    lastPasteboardChangeCount = currentChangeCount
                    lastClipboardRepo = Utils.getGitHubRepoFromClipboard()
                    clipboardRepo = lastClipboardRepo
                } else {
                    // Use cached result
                    clipboardRepo = lastClipboardRepo
                }
                
                // Only show quick-add if the repo is NOT already in our list
                if let repo = clipboardRepo,
                   !ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == repo.lowercased() }) {
                    header.updateClipboardState(repo: repo)
                } else {
                    header.updateClipboardState(repo: nil)
                }
            }
        }
    }
    
    // MARK: - Beer Handle (ASA)
    
    /// Central method to show/hide the beer handle based on current state.
    /// The handle is visible only when ALL of these are true:
    /// 1. beerHandleEnabled is true in Constants
    /// 2. HasUnreadPulse is true (Red Eye is active)
    /// 3. The main popover is open
    /// 4. There are visible repos (scroll area has content)
    func updateBeerHandleVisibility() {
        // Cancel any pending debounced show
        beerHandleShowWorkItem?.cancel()
        beerHandleShowWorkItem = nil
        
        guard Constants.beerHandleEnabled else {
            beerHandle?.hide()
            return
        }
        
        // Hide handle if any secondary popover (Settings, Release Notes, About, Add Repo) is currently visible
        let secondaryPopoverShown = (settingsPopover?.isShown == true) ||
                                    (releaseNotesPopover?.isShown == true) ||
                                    (aboutPopover?.isShown == true) ||
                                    (addRepoPopover?.isShown == true)
        
        let hasUnread = UserDefaults.standard.bool(forKey: "HasUnreadPulse")
        let basicConditionsMet = hasUnread && popoverIsOpen && !secondaryPopoverShown
        
        guard basicConditionsMet else {
            beerHandle?.hideAnimated()
            return
        }
        
        // Check scroll area height IMMEDIATELY — no delay
        let scrollHeight = mainPopoverVC.currentScrollAreaHeight
        let effectiveHeight = scrollHeight - (Constants.beerHandleVerticalInset * 2)
        
        guard effectiveHeight >= Constants.beerHandleMinHeight else {
            // Immediately hide without any debounce delay if menu height reduced below minimum
            beerHandle?.hide()
            return
        }
        
        // If the handle is ALREADY visible, reposition it immediately without debounce
        // so it resizes/repositions smoothly as search query or menu content changes
        if beerHandle?.isCurrentlyVisible == true,
           let popoverWindow = mainPopover?.contentViewController?.view.window {
            let scrollAreaFrame = mainPopoverVC.scrollAreaFrameInScreenCoordinates
            let positioned = beerHandle?.positionRelativeTo(
                popoverWindow: popoverWindow,
                scrollAreaFrame: scrollAreaFrame,
                scrollAreaHeight: scrollHeight
            ) ?? false
            
            if !positioned {
                beerHandle?.hide()
            }
            return
        }
        
        // Debounce only the initial show (when handle is not yet visible)
        let workItem = DispatchWorkItem { [weak self] in
            self?.showBeerHandleNow()
        }
        beerHandleShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.beerHandleShowDebounce,
            execute: workItem
        )
    }
    
    /// Actually show and position the beer handle. Called after debounce.
    private func showBeerHandleNow() {
        guard Constants.beerHandleEnabled else {
            beerHandle?.hide()
            return
        }
        
        // Re-verify that no secondary popovers are open and main popover is still open with pulse
        let secondaryPopoverShown = (settingsPopover?.isShown == true) ||
                                    (releaseNotesPopover?.isShown == true) ||
                                    (aboutPopover?.isShown == true) ||
                                    (addRepoPopover?.isShown == true)
        
        let hasUnread = UserDefaults.standard.bool(forKey: "HasUnreadPulse")
        guard hasUnread && popoverIsOpen && !secondaryPopoverShown else {
            beerHandle?.hideAnimated()
            return
        }
        
        // Get scroll area height from the popover VC
        let scrollHeight = mainPopoverVC.currentScrollAreaHeight
        let effectiveHeight = scrollHeight - (Constants.beerHandleVerticalInset * 2)
        
        guard effectiveHeight >= Constants.beerHandleMinHeight else {
            beerHandle?.hideAnimated()
            return
        }
        
        // Create handle lazily
        if beerHandle == nil {
            beerHandle = BeerHandlePanel()
        }
        
        // Position relative to the popover window
        // IMPORTANT: Do NOT use addChildWindow — it breaks NSPopover's
        // transient behavior (click-outside-to-close). Instead, we manage
        // the handle's lifecycle and z-order independently.
        if let popoverWindow = mainPopover?.contentViewController?.view.window {
            let scrollAreaFrame = mainPopoverVC.scrollAreaFrameInScreenCoordinates
            let positioned = beerHandle?.positionRelativeTo(
                popoverWindow: popoverWindow,
                scrollAreaFrame: scrollAreaFrame,
                scrollAreaHeight: scrollHeight
            ) ?? false
            
            // Only show if positioning succeeded (height was sufficient)
            if positioned {
                beerHandle?.showAnimated(relativeTo: popoverWindow)
            }
        }
    }
    
    // MARK: - NSPopoverDelegate
    
    func popoverWillShow(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        
        if popover == mainPopover {
            popoverIsOpen = true
            lastMainPopoverOpenTime = Date()
            
            // Show beer handle after a brief delay to let the popover window settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.updateBeerHandleVisibility()
            }
        } else {
            // Secondary popover (Settings, Release Notes, About, Add Repo) opening -> cancel pending show and hide handle immediately
            beerHandleShowWorkItem?.cancel()
            beerHandleShowWorkItem = nil
            beerHandle?.hide()
        }
    }
    
    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        
        if popover == settingsPopover {
            lastSettingsCloseTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.updateBeerHandleVisibility()
            }
            return
        }
        
        if popover == releaseNotesPopover || popover == aboutPopover || popover == addRepoPopover {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.updateBeerHandleVisibility()
            }
            return
        }
        
        if popover == mainPopover {
            popoverIsOpen = false
            mainPopoverVC.clearHighlight()
            
            // Hide beer handle immediately when popover closes
            beerHandle?.hide()
            
            // Mark visible versions as seen ONLY if the popover was open for a reasonable time (0.8s)
            // to avoid accidental 'marking as seen' on double-clicks or very fast interactions.
            if let openTime = lastMainPopoverOpenTime, Date().timeIntervalSince(openTime) > 0.8 {
                var seenVersions = UserDefaults.standard.dictionary(forKey: "LastSeenVersions") as? [String: String] ?? [:]
                
                // Purely visual tracking: only what's on screen at the moment of closing is "seen"
                for rowView in mainPopoverVC.repoViews {
                    let name = rowView.displayData.repoName
                    if let currentVersion = repoCache[name]?.version {
                        seenVersions[name] = currentVersion
                    }
                }
                UserDefaults.standard.set(seenVersions, forKey: "LastSeenVersions")
            }
            
            // Clear the global red dot indicator ONLY when closing the main menu
            clearUnreadPulse()
            
            // Execute any actions deferred by custom views (like opening Settings/Quit)
            if let action = pendingAction {
                pendingAction = nil
                DispatchQueue.main.async {
                    action()
                }
            }
            
            updateStatusIcon(hasUpdates: false)
        }
    }
    
    func sendNotification(title: String, subtitle: String, message: String = "") {
        let fullSubtitle = message.isEmpty ? subtitle : "\(subtitle)\n\(message)"
        HUDPanel.shared.show(title: title, subtitle: fullSubtitle)
        
        if title == Translations.get("error") || title == Translations.get("brewErrorTitle") {
            animateStatusIcon(with: .wiggle)
        }
    }
    
    // MARK: - Keyboard Shortcuts
    
    func handleGlobalShortcuts(with event: NSEvent) -> Bool {
        // 1. Navigation (Arrows) - Intercepted even without modifiers
        if event.keyCode == 125 { // Down Arrow
            mainPopoverVC.clearButtonFocus()
            mainPopoverVC.moveHighlight(direction: 1)
            return true
        } else if event.keyCode == 126 { // Up Arrow
            mainPopoverVC.clearButtonFocus()
            mainPopoverVC.moveHighlight(direction: -1)
            return true
        } else if event.keyCode == 123 { // Left Arrow
            mainPopoverVC.moveButtonFocus(direction: -1)
            return true
        } else if event.keyCode == 124 { // Right Arrow
            mainPopoverVC.moveButtonFocus(direction: 1)
            return true
        }
        
        // 2. Global App Shortcuts (CMD + ...)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad])
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "s": // CMD+S -> Toggle favorite
                mainPopoverVC.triggerActionOnHighlighted(.favorite)
                return true
            case ",":
                openSettingsWindow(footerView)
                return true
            case "m": // CMD+M → About (M de Mino)
                showAboutPanel()
                return true
            case "f": // CMD+F → Focus search
                focusSearchField()
                return true
            case "n":
                unifiedAddRepoDialog(self)
                return true
            case "q":
                quitApp(nil)
                return true
            case "o": // CMD+O → Open repo
                mainPopoverVC.triggerActionOnHighlighted(.open)
                return true
            case "b": // CMD+B → Install via Homebrew
                mainPopoverVC.triggerActionOnHighlighted(.install)
                return true
            case "i": // CMD+I → Info / Release Notes
                mainPopoverVC.triggerActionOnHighlighted(.notes)
                return true
            case "c": // CMD+C → Copy GitHub URL
                mainPopoverVC.triggerActionOnHighlighted(.copy)
                return true
            case "r": // CMD+R → Refresh highlighted repo (or full refresh if none highlighted)
                if mainPopoverVC.currentlyHighlightedRowIndex != nil {
                    mainPopoverVC.triggerActionOnHighlighted(.refresh)
                } else {
                    triggerFullRefresh(nil)
                }
                return true
            case "z": // CMD+Z → Undo last delete
                repoCoordinator.undoLastDelete()
                return true
            case "v": // CMD+V → Quick Add repo if available
                refreshQuickAddState()
                if headerView?.quickAddRepoStr != nil {
                    headerView?.addClicked()
                    return true
                }
                break
            case "\u{7F}": // CMD+Backspace → Delete
                mainPopoverVC.triggerActionOnHighlighted(.delete)
                return true
            default:
                break
            }
        }
        
        // 3. Contextual Row Actions (Return / Enter)
        if event.keyCode == 36 { // Return
            // If a specific button is focused via ←→, trigger it
            if mainPopoverVC.triggerFocusedButton() {
                return true
            }
            if mainPopoverVC.currentlyHighlightedRow != nil {
                mainPopoverVC.triggerActionOnHighlighted(.open)
                return true
            } else if headerView?.quickAddRepoStr != nil {
                // If Quick Add is active and no row is specifically highlighted, 
                // Return triggers the Quick Add action.
                headerView?.addClicked()
                return true
            }
        }
        
        return false
    }
}

// MARK: - MenuSearchField (subclass for AppDelegate reference)

class MenuSearchField: NSSearchField {
    private weak var appDelegate: AppDelegate?
    
    convenience init(appDelegate: AppDelegate) {
        self.init(frame: .zero)
        self.appDelegate = appDelegate
    }
    
    override class var defaultMenu: NSMenu? {
        return nil
    }
    
    override func menu(for event: NSEvent) -> NSMenu? {
        return nil
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // Suppress right-click context menu
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent, (event.type == .rightMouseDown || event.type == .rightMouseUp) {
            let localPoint = convert(point, from: superview)
            if bounds.contains(localPoint) {
                return self
            }
        }
        return super.hitTest(point)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let appDelegate = appDelegate, appDelegate.handleGlobalShortcuts(with: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
