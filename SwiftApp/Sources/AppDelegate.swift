import Cocoa

enum SymbolAnimation {
    case bounce
    case replaceWithSlash
    case wiggle
    case rotate
    case scale
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    private var statusIconView: NSImageView!
    private var statusIndicatorDot: NSBox!
    var mainPopover: NSPopover?
    var mainPopoverVC: MainPopoverViewController!
    var releaseNotesPopover: NSPopover?
    var settingsPopover: NSPopover?
    var aboutPopover: NSPopover?
    
    var repoCache: [String: RepoInfo] = [:]
    
    var headerView: HeaderMenuItemView!
    var footerView: FooterMenuItemView?
    
    // Search properties
    var searchField: NSSearchField?
    var currentSearchQuery: String = ""
    var readReposThisSession: Set<String> = []
    
    var menuIsOpen = false
    
    // Defer actions until menu completes its closing animation
    var pendingMenuAction: (() -> Void)? = nil
    var quickAddingRepo: String? = nil
    private var lastPasteboardChangeCount = -1
    private var lastClipboardRepo: String? = nil
    var popularTagsCache: [String] = []
    private var currentMenuWidth: CGFloat = 320.0
    
    
    var addRepoPopover: NSPopover?
    
    // Coordinators
    var refreshCoordinator: RefreshCoordinator!
    var repoCoordinator: RepoCoordinator!
    

    
    func hideInformationalWindows() {
        // Ensure any attached sheets are dismissed to prevent UI lockups (e.g. ghost NSAlerts)
        [releaseNotesPopover, settingsPopover].forEach { popover in
            if let window = popover?.contentViewController?.view.window, let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
        }
        
        releaseNotesPopover?.performClose(nil)
        settingsPopover?.performClose(nil)
        aboutPopover?.performClose(nil)
        addRepoPopover?.performClose(nil)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let btn = statusItem.button {
            // Remove default image and title to allow custom view
            btn.image = nil
            btn.title = ""
            
            // Create a custom image view to support AppKit SF Symbol animations
            let eyeImage = NSImage(systemSymbolName: "eye", accessibilityDescription: "Mino")!
            eyeImage.isTemplate = true
            
            statusIconView = NSImageView(image: eyeImage)
            statusIconView.translatesAutoresizingMaskIntoConstraints = false
            statusIconView.wantsLayer = true // REQUIRED for layer-backed symbol effects
            
            btn.addSubview(statusIconView)
            
            NSLayoutConstraint.activate([
                statusIconView.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
                statusIconView.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                statusIconView.widthAnchor.constraint(equalToConstant: 18),
                statusIconView.heightAnchor.constraint(equalToConstant: 16) // typical SF symbol aspect ratio inside button
            ])
            
            // Add the red iris overlay
            statusIndicatorDot = NSBox()
            statusIndicatorDot.boxType = .custom
            statusIndicatorDot.isTransparent = false
            statusIndicatorDot.fillColor = .systemRed
            statusIndicatorDot.cornerRadius = 2.0
            statusIndicatorDot.translatesAutoresizingMaskIntoConstraints = false
            statusIndicatorDot.isHidden = true
            
            btn.addSubview(statusIndicatorDot)
            NSLayoutConstraint.activate([
                statusIndicatorDot.widthAnchor.constraint(equalToConstant: 4),
                statusIndicatorDot.heightAnchor.constraint(equalToConstant: 4),
                statusIndicatorDot.centerXAnchor.constraint(equalTo: statusIconView.centerXAnchor, constant: 0),
                statusIndicatorDot.centerYAnchor.constraint(equalTo: statusIconView.centerYAnchor, constant: 0) 
            ])
        }
        
        let hasPulse = UserDefaults.standard.bool(forKey: "HasUnreadPulse")
        updateStatusIcon(hasUpdates: hasPulse)
        
        // Initialize Popover
        mainPopoverVC = MainPopoverViewController(appDelegate: self)
        let popover = NSPopover()
        popover.contentViewController = mainPopoverVC
        popover.behavior = .transient
        popover.animates = true
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
        
        // Defer heavy UI building and initial refresh to ensure status icon shows instantly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updatePopularTagsCache()
            self.rebuildMenu()
            self.refreshCoordinator.startTimers()
            self.triggerFullRefresh(nil)
            self.refreshCoordinator.startTagBackfillSequence()
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        refreshCoordinator.countdownTimer?.invalidate()
    }
    
    @objc func togglePopover(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showAboutPanel()
            return
        }
        
        if addRepoPopover?.isShown == true {
            addRepoPopover?.performClose(sender)
            return
        }
        
        if mainPopover?.isShown == true {
            mainPopover?.performClose(sender)
        } else {
            if let button = statusItem.button {
                refreshQuickAddState()
                clearUnreadPulse()
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
        hideInformationalWindows()
        
        if aboutPopover == nil {
            let popover = NSPopover()
            popover.contentViewController = AboutViewController()
            popover.behavior = .transient
            popover.animates = true
            self.aboutPopover = popover
        }
        
        guard let popover = aboutPopover else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let btn = statusItem.button {
                popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
                
                // CRITICAL: Delaying activation and key state slightly to allow the click event to finish.
                // This ensures the popover can become key and thus handle 'transient' dismissal correctly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.activate(ignoringOtherApps: true)
                    popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    
    func rebuildMenu() {
        mainPopoverVC.rebuildMenu()
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
    
    func performAfterMenuClose(_ action: @escaping () -> Void) {
        mainPopover?.performClose(nil)
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
    
    @objc func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }
    
    @objc func openSettingsWindow(_ sender: Any?) {
        hideInformationalWindows()
        
        if settingsPopover == nil {
            let popover = NSPopover()
            popover.contentViewController = SettingsViewController()
            popover.behavior = .transient
            popover.animates = true
            self.settingsPopover = popover
        }
        
        guard let popover = settingsPopover else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Find the sender view or default to status item button
            // If the view is already detached (e.g. menu closed), fallback to status bar button
            if let view = sender as? NSView, view.window != nil {
                popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minX)
            } else if let btn = statusItem.button {
                popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            }
        }
    }
    
    func updateStatusIcon(hasUpdates: Bool) {
        // Show or hide the red pupil overlay
        statusIndicatorDot.isHidden = !hasUpdates
    }
    
    // MARK: - Search Filtering Logic
    
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        currentSearchQuery = field.stringValue
        filterMenuBySearchQuery(currentSearchQuery)
        headerView?.updateSearchOpacity()
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
        }.prefix(Constants.tagCloudMaxTags).map { 
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
        
        if #available(macOS 14.0, *) {
            switch animation {
            case .bounce:
                imageView.addSymbolEffect(.bounce, options: .nonRepeating)
            case .replaceWithSlash:
                let slashImg = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)!
                let normalImg = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)!
                slashImg.isTemplate = true
                normalImg.isTemplate = true
                
                imageView.setSymbolImage(slashImg, contentTransition: .replace.downUp.byLayer)
                
                // Revert after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    imageView.setSymbolImage(normalImg, contentTransition: .replace.upUp.byLayer)
                }
            case .wiggle:
                if #available(macOS 15.0, *) {
                    imageView.addSymbolEffect(.wiggle, options: .nonRepeating)
                } else {
                    imageView.addSymbolEffect(.bounce, options: .nonRepeating) // Fallback
                }
            case .rotate:
                if #available(macOS 15.0, *) {
                    imageView.addSymbolEffect(.rotate, options: .nonRepeating)
                } else {
                    imageView.addSymbolEffect(.pulse, options: .nonRepeating) // Fallback
                }
            case .scale:
                // Use a bounce.down effect to emulate a "click/scale" interaction
                imageView.addSymbolEffect(.bounce.down, options: .nonRepeating)
            }
        }
    }
    
    // MARK: - NSMenuDelegate
    
    func markRepoAsRead(_ repoName: String) {
        readReposThisSession.insert(repoName)
    }
    
    func isRepoRead(_ repoName: String) -> Bool {
        return readReposThisSession.contains(repoName)
    }
    
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
        // Hybrid Quick Add interceptor
        if let header = headerView {
            if quickAddingRepo != nil {
                // A repo is currently being fetched — show "Adding..." status centered
                header.updateClipboardState(repo: nil, isProcessing: true)
            } else {
                let currentChangeCount = NSPasteboard.general.changeCount
                let clipboardRepo: String?
                
                if currentChangeCount != lastPasteboardChangeCount {
                    // Contents have changed, perform the expensive regex check
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
    
    // MARK: - NSPopoverDelegate
    
    func popoverWillShow(_ notification: Notification) {
        menuIsOpen = true
        readReposThisSession.removeAll()
    }
    
    func popoverDidClose(_ notification: Notification) {
        menuIsOpen = false
        
        // Mark currently cached versions as definitively seen upon closing the popover
        // BUT ONLY for repos that were actually hovered/read during this session
        var seenVersions = UserDefaults.standard.dictionary(forKey: "LastSeenVersions") as? [String: String] ?? [:]
        for (repoName, info) in repoCache {
            if let v = info.version, readReposThisSession.contains(repoName) {
                seenVersions[repoName] = v
            }
        }
        UserDefaults.standard.set(seenVersions, forKey: "LastSeenVersions")
        
        // Execute any actions deferred by custom views (like opening Settings/Quit)
        if let action = pendingMenuAction {
            pendingMenuAction = nil
            DispatchQueue.main.async {
                action()
            }
        }
    }
    
    func sendNotification(title: String, subtitle: String, message: String = "") {
        let fullSubtitle = message.isEmpty ? subtitle : "\(subtitle)\n\(message)"
        HUDPanel.shared.show(title: title, subtitle: fullSubtitle)
        
        if title == Translations.get("error") || title == Translations.get("brewErrorTitle") {
            animateStatusIcon(with: .wiggle)
        }
    }
}

// MARK: - MenuSearchField (subclass for AppDelegate reference)

class MenuSearchField: NSSearchField {
    private weak var appDelegate: AppDelegate?
    
    convenience init(appDelegate: AppDelegate) {
        self.init(frame: .zero)
        self.appDelegate = appDelegate
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 1. Navigation (Arrows) - Intercepted even without modifiers
        // Using keyCode for reliability across layouts
        if event.keyCode == 125 { // Down Arrow
            appDelegate?.mainPopoverVC.moveHighlight(direction: 1)
            return true
        } else if event.keyCode == 126 { // Up Arrow
            appDelegate?.mainPopoverVC.moveHighlight(direction: -1)
            return true
        }
        
        // 2. Global App Shortcuts (CMD + ...)
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case ",":
                appDelegate?.openSettingsWindow(appDelegate?.footerView)
                return true
            case "i":
                appDelegate?.showAboutPanel()
                return true
            case "n":
                appDelegate?.unifiedAddRepoDialog(self)
                return true
            case "q":
                appDelegate?.quitApp(nil)
                return true
            case "o": // CMD+O (Open)
                appDelegate?.mainPopoverVC.triggerActionOnHighlighted(.open)
                return true
            case "b": // CMD+B (Install/Brew)
                appDelegate?.mainPopoverVC.triggerActionOnHighlighted(.install)
                return true
            case "l": // CMD+L (Notes)
                appDelegate?.mainPopoverVC.triggerActionOnHighlighted(.notes)
                return true
            case "\u{7F}": // CMD+Backspace (Delete)
                appDelegate?.mainPopoverVC.triggerActionOnHighlighted(.delete)
                return true
            default:
                break
            }
        }
        
        // 3. Contextual Row Actions (Return / Enter)
        if event.keyCode == 36 { // Return
            appDelegate?.mainPopoverVC.triggerActionOnHighlighted(.open)
            return true
        }
        
        return super.performKeyEquivalent(with: event)
    }
}
