import Cocoa

enum SymbolAnimation {
    case bounce
    case replaceWithSlash
    case wiggle
    case rotate
    case scale
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    var statusItem: NSStatusItem!
    private var statusIconView: NSImageView!
    private var statusIndicatorDot: NSBox!
    var mainMenu: NSMenu!
    
    var repoCache: [String: RepoInfo] = [:]
    
    private var headerMenuItem: NSMenuItem!
    var headerView: HeaderMenuItemView!
    private var noSearchResultsMenuItem: NSMenuItem!
    var emptyMenuPlaceholderItem: NSMenuItem?
    
    // Search properties
    private var searchField: NSSearchField?
    private var searchMenuItem: NSMenuItem?
    var repoMenuItems: [(item: NSMenuItem, data: RepoDisplayData)] = []
    private var readReposThisSession: Set<String> = []
    
    var menuIsOpen = false
    
    // Defer actions until menu completes its closing animation
    var pendingMenuAction: (() -> Void)? = nil
    var quickAddingRepo: String? = nil
    private var lastPasteboardChangeCount = -1
    private var lastClipboardRepo: String? = nil
    private var popularTagsCache: [String] = []
    private var currentMenuWidth: CGFloat = 320.0
    
    var settingsWindowController: SettingsWindowController?
    var releaseNotesWindowController: ReleaseNotesWindowController?
    var addRepoWindowController: AddRepoWindowController?
    
    // Coordinators
    var refreshCoordinator: RefreshCoordinator!
    var repoCoordinator: RepoCoordinator!
    
    // Ensure only one of our custom windows is visible at a time
    func hideAllWindowsExcept(keep: NSWindowController?) {
        // Force-close any blocking NSAlert or Modal Window
        if let modal = NSApp.modalWindow {
            NSApp.stopModal()
            modal.orderOut(nil)
        }
        
        if settingsWindowController !== keep { settingsWindowController?.window?.orderOut(nil) }
        if releaseNotesWindowController !== keep { releaseNotesWindowController?.window?.orderOut(nil) }
        if addRepoWindowController !== keep { addRepoWindowController?.window?.orderOut(nil) }
    }
    
    func hideInformationalWindows() {
        if settingsWindowController?.window?.isVisible == true {
            settingsWindowController?.window?.orderOut(nil)
        }
        if releaseNotesWindowController?.window?.isVisible == true {
            releaseNotesWindowController?.window?.orderOut(nil)
        }
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
        
        updateStatusIcon(hasUpdates: false)
        
        mainMenu = NSMenu()
        mainMenu.delegate = self
        mainMenu.autoenablesItems = false
        statusItem.menu = mainMenu
        
        // Initialize coordinators
        refreshCoordinator = RefreshCoordinator(delegate: self)
        repoCoordinator = RepoCoordinator(delegate: self)
        
        updatePopularTagsCache()
        setupMenu()
        refreshCoordinator.startTimers()
        
        triggerFullRefresh(nil)
        refreshCoordinator.startTagBackfillSequence()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        refreshCoordinator.countdownTimer?.invalidate()
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
    
    // MARK: - Forwarding to RepoCoordinator
    

    
    func deleteRepoInline(repoName: String) {
        repoCoordinator.deleteRepoInline(repoName: repoName)
    }
    
    @objc func handleOpenReleases(_ sender: NSMenuItem) {
        repoCoordinator.handleOpenReleases(sender)
    }
    
    @objc func handleShowNotes(_ sender: NSMenuItem) {
        repoCoordinator.handleShowNotes(sender)
    }
    
    @objc func handleInstallBrewCask(_ sender: NSMenuItem) {
        repoCoordinator.handleInstallBrewCask(sender)
    }
    
    @objc func unifiedAddRepoDialog(_ sender: Any) {
        repoCoordinator.openAddRepoDialog(sender)
    }
    
    func addRepoSmart(repoName: String) async -> Bool {
        return await repoCoordinator.addRepoSmart(repoName: repoName)
    }
    
    // MARK: - Menu Construction
    
    func setupMenu() {
        mainMenu.removeAllItems()
        repoMenuItems.removeAll()
        
        // Hidden NSMenuItems for keyboard shortcuts MUST be at the very top.
        // Key equivalents are disabled for items WITH custom views, but these items
        // have NO view — so their key equivalents fire normally during menu tracking.
        // allowsKeyEquivalentWhenHidden ensures they work even though isHidden = true.
        // Placing them at index 0 guarantees the Carbon Menu tracking loop resolves them 
        // before evaluating dynamically inserted/hidden search items.
        let shortcuts: [(action: Selector, key: String)] = [
            (#selector(openSettingsWindow(_:)), ","),   // CMD+, → Preferences
            (#selector(quitApp(_:)), "q"),               // CMD+Q → Quit
            (#selector(unifiedAddRepoDialog(_:)), "n"),  // CMD+N → Add Repositories
        ]
        for shortcut in shortcuts {
            let item = NSMenuItem(title: "", action: shortcut.action, keyEquivalent: shortcut.key)
            item.keyEquivalentModifierMask = .command
            item.target = self
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            mainMenu.addItem(item)
        }
        
        headerMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headerView = HeaderMenuItemView(appDelegate: self)
        headerView.updateTimeText(getRefreshTitle(), isRefreshing: isRefreshing)
        headerMenuItem.view = headerView
        mainMenu.addItem(headerMenuItem)
        
        // Link the app delegate's search field reference to the one in the header
        self.searchField = headerView.searchField
        self.searchField?.delegate = self
        

        
        mainMenu.addItem(NSMenuItem.separator())
        
        let config = ConfigManager.shared.config
        let isSortedByName = config.sortBy == "name"
        var currentLayout = config.menuLayout ?? "columns"
        
        // Migrate legacy "hybrid" layout to "columns"
        if currentLayout == "hybrid" {
            currentLayout = "columns"
            ConfigManager.shared.config.menuLayout = "columns"
            ConfigManager.shared.saveConfig()
        }
        
        var sortedRepos = config.repos
        if isSortedByName {
            sortedRepos.sort { $0.name.split(separator: "/").last?.lowercased() ?? "" < $1.name.split(separator: "/").last?.lowercased() ?? "" }
        } else {
            sortedRepos.sort { r1, r2 in
                let (_, s1) = Utils.getReleaseAge(dateString: self.repoCache[r1.name]?.date)
                let (_, s2) = Utils.getReleaseAge(dateString: self.repoCache[r2.name]?.date)
                return s1 < s2
            }
        }
        // Repos in error state always go to the bottom, regardless of sort order
        sortedRepos.sort { r1, r2 in
            let e1 = self.repoCache[r1.name]?.error != nil
            let e2 = self.repoCache[r2.name]?.error != nil
            if e1 != e2 { return !e1 } // non-error before error
            return false // preserve relative order within each group
        }
        
        if sortedRepos.isEmpty {
            let noRepos = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            noRepos.view = EmptyMenuPlaceholderView()
            mainMenu.addItem(noRepos)
            self.emptyMenuPlaceholderItem = noRepos
        } else {
            self.emptyMenuPlaceholderItem = nil
        }
        
        // Build display data for each repo
        let thresholdDays = config.newIndicatorDays ?? Constants.newReleaseThresholdDays
        
        var displayDataList: [(RepoConfig, RepoDisplayData)] = []
        
        let lastSeenVersions = UserDefaults.standard.dictionary(forKey: "LastSeenVersions") as? [String: String] ?? [:]
        
        for repoObj in sortedRepos {
            let repoName = repoObj.name
            let info = repoCache[repoName] ?? RepoInfo(name: repoName, error: nil)
            
            var formattedName = repoName
            if !config.showOwner {
                formattedName = String(repoName.split(separator: "/").last ?? Substring(repoName))
            }
            
            // error might be explicitly set to "" by default in some generic decoders, so check isEmpty
            let isError = info.error != nil && !info.error!.isEmpty
            let isLoading = info.version == nil && !isError
            
            let ageInfo = Utils.getReleaseAge(dateString: info.date)
            let daysDiff = ageInfo.seconds.isInfinite ? Int.max : Int(ageInfo.seconds / 86400)
            
            var isNewUpdate = false
            if !isLoading && !isError {
                if let currentVersion = info.version, lastSeenVersions[repoName] != currentVersion {
                    isNewUpdate = true
                }
            }
            
            // Freshness color (used by dot in columns/cards and pill in tags)
            let freshnessColor: NSColor
            if isLoading || isError {
                freshnessColor = .systemGray
            } else if daysDiff <= thresholdDays {
                freshnessColor = .systemGreen
            } else if daysDiff <= 90 {
                freshnessColor = .systemOrange
            } else {
                freshnessColor = .systemGray
            }
            
            let data = RepoDisplayData(
                repoName: repoName,
                formattedName: formattedName,
                version: info.version,        // pass cached version even on error
                ageLabel: isLoading ? nil : ageInfo.label,   // show cached date too unless loading
                ageSeconds: ageInfo.seconds,
                originalDate: info.date,
                errorMessage: isError ? info.error : nil,
                isLoading: isLoading,
                caskName: repoObj.cask,
                freshnessColor: freshnessColor,
                isNew: isNewUpdate,
                tags: repoObj.tags ?? [],
                isFavorite: repoObj.isFavorite ?? false
            )
            displayDataList.append((repoObj, data))
        }
        
        // Pre-compute column widths for columns/hybrid modes
        var maxNameWidth: CGFloat = 0
        var maxVersionWidth: CGFloat = 0
        
        if currentLayout == "columns" {
            let nameFont = NSFont.menuBarFont(ofSize: 0)
            let versionFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let attrs: (NSFont) -> [NSAttributedString.Key: Any] = { [.font: $0] }
            
            for (_, data) in displayDataList {
                let nameSize = (data.formattedName as NSString).size(withAttributes: attrs(nameFont))
                maxNameWidth = max(maxNameWidth, nameSize.width)
                let verText = data.version ?? "…"
                let verSize = (verText as NSString).size(withAttributes: attrs(versionFont))
                maxVersionWidth = max(maxVersionWidth, verSize.width)
            }
            maxNameWidth += 4  // small padding
            maxVersionWidth += 4
        }
        
        // Create views
        let baseFontSize = config.menuFontSize ?? Constants.menuBaseFontSize
        let rowHeight: CGFloat = (currentLayout == "cards") ? baseFontSize + 27 : baseFontSize + 9
        
        var repoEntries: [(NSMenuItem, RepoMenuItemView)] = []
        
        for (repoObj, data) in displayDataList {
            let repoMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let customView = RepoMenuItemView(repoName: repoObj.name, displayData: data, layout: currentLayout, appDelegate: self)
            
            if currentLayout == "columns" {
                customView.nameColumnWidth = maxNameWidth
                customView.versionColumnWidth = maxVersionWidth
            }
            
            repoMenuItem.view = customView
            repoEntries.append((repoMenuItem, customView))
        }
        
        // Calculate uniform width, ignoring the action button stack width (approx 100px)
        // because we don't want the menu to permanently widen just to hold them 
        // since they overlap the right margin when they appear.
        let maxWidth = repoEntries.reduce(Constants.menuDefaultWidth) { maxSoFar, entry in
            let fittingWidth = entry.1.fittingSize.width
            // Assume the button stack takes about 104pt (4 buttons * 26pt). We subtract it
            // from the fitting size so the menu stays compact.
            return max(maxSoFar, fittingWidth - 104 + 30)
        }
        
        // Apply uniform width and add to menu
        self.currentMenuWidth = maxWidth
        for (menuItem, customView) in repoEntries {
            customView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: rowHeight)
            mainMenu.addItem(menuItem)
            repoMenuItems.append((item: menuItem, data: customView.displayData))
        }
        
        noSearchResultsMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let noResultsView = NoSearchResultsView()
        noResultsView.targetWidth = maxWidth
        noResultsView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: 44)
        noSearchResultsMenuItem.view = noResultsView
        noSearchResultsMenuItem.isHidden = true
        mainMenu.addItem(noSearchResultsMenuItem)
        
        mainMenu.addItem(NSMenuItem.separator())
        

        // Apply uniform width to header
        headerView.targetWidth = maxWidth
        headerView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: Constants.menuHeaderFooterHeight)
        
        // Add footer
        let footerMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let footerView = FooterMenuItemView(appDelegate: self)
        footerView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: Constants.menuHeaderFooterHeight)
        footerMenuItem.view = footerView
        mainMenu.addItem(footerMenuItem)
        
        let hasPulse = UserDefaults.standard.bool(forKey: "HasUnreadPulse")
        updateStatusIcon(hasUpdates: hasPulse)
    }
    
    private func updateStatusIcon(hasUpdates: Bool) {
        // Show or hide the red pupil overlay
        statusIndicatorDot.isHidden = !hasUpdates
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
    
    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        
        readReposThisSession.removeAll()
        
        clearUnreadPulse()
        
        // Clean out search criteria and auto-select typing field
        searchField?.stringValue = ""
        filterMenuBySearchQuery("")
        
        DispatchQueue.main.async { [weak self] in
            if let window = self?.searchField?.window, let field = self?.searchField {
                window.makeFirstResponder(field)
            }
        }
        
        
        // Hybrid Quick Add interceptor
        if let header = headerView {
            if let adding = quickAddingRepo {
                // A repo is currently being fetched — show "Adding..." status
                header.updateClipboardState(repo: nil)
                header.updateTimeText(Translations.get("addingRepo").format(with: ["repo": adding]), isRefreshing: true)
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
    
    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        
        clearUnreadPulse()
        
        // Mark currently cached versions as definitively seen upon closing the menu block
        // BUT ONLY for repos that were actually hovered/read during this session
        var seenVersions = UserDefaults.standard.dictionary(forKey: "LastSeenVersions") as? [String: String] ?? [:]
        for (repoName, info) in repoCache {
            if let v = info.version, readReposThisSession.contains(repoName) {
                seenVersions[repoName] = v
            }
        }
        UserDefaults.standard.set(seenVersions, forKey: "LastSeenVersions")
        
        // Execute any actions deferred by custom views (like opening Settings/Quit)
        // This guarantees the menu's tracking loop is completely torn down
        // by macOS *before* we attempt to steal WindowServer focus with .regular policy.
        if let action = pendingMenuAction {
            pendingMenuAction = nil
            // A slight runloop jump ensures we are entirely outside the tracking session
            DispatchQueue.main.async {
                action()
            }
        }
    }
    
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        // Pass the item that WILL be highlighted directly to each custom view
        for menuItem in menu.items {
            if let repoView = menuItem.view as? RepoMenuItemView {
                repoView.menuDidChangeHighlight(highlightedItem: item)
            } else if let headerView = menuItem.view as? HeaderMenuItemView {
                headerView.menuDidChangeHighlight(highlightedItem: item)
            } else if let footerView = menuItem.view as? FooterMenuItemView {
                footerView.menuDidChangeHighlight(highlightedItem: item)
            }
        }
    }

    // MARK: - Handlers
    
    @objc func quitApp(_ sender: Any) {
        refreshCoordinator.countdownTimer?.invalidate()
        NSApplication.shared.terminate(self)
    }
    
    // MARK: - Activation Policy Management
    
    func performAfterMenuClose(_ action: @escaping () -> Void) {
        self.pendingMenuAction = action
        self.mainMenu.cancelTracking()
    }
    
    /// Call this INSTEAD of NSApp.activate() whenever the app needs to show a window/alert.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Stubbed out. The performAfterMenuClose correctly hands off WindowServer state.
    /// Setting activation policy repeatedly causes Dock bouncing bugs.
    func returnToAccessory() {
        // No-op
    }
    
    @objc func openSettingsWindow(_ sender: Any) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        
        hideAllWindowsExcept(keep: settingsWindowController)
        bringToFront()
        settingsWindowController?.showWindow(self)
    }
    
    // MARK: - Preferences Logics
    
    // Removed redundant inline toggles since they are now in SettingsWindowController.
    
    func sendNotification(title: String, subtitle: String, message: String = "") {
        let fullSubtitle = message.isEmpty ? subtitle : "\(subtitle)\n\(message)"
        HUDPanel.shared.show(title: title, subtitle: fullSubtitle)
        
        if title == Translations.get("error") || title == Translations.get("brewErrorTitle") {
            animateStatusIcon(with: .wiggle)
        }
    }
}

// MARK: - Search Filtering Logic
extension AppDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        let query = field.stringValue
        filterMenuBySearchQuery(query)
        headerView?.updateSearchOpacity()
    }
    // MARK: - Search Filtering
    
    func updatePopularTagsCache() {
        var counts: [String: Int] = [:]
        for repo in ConfigManager.shared.config.repos {
            repo.tags?.forEach { counts[$0, default: 0] += 1 }
        }
        // Normalize tags: ensure they have exactly one leading '#' and are sorted by frequency (descending)
        // with an alphabetical fallback (ascending) to ensure a stable, deterministic order.
        popularTagsCache = counts.sorted { a, b in
            if a.value != b.value {
                return a.value > b.value
            }
            return a.key.lowercased() < b.key.lowercased()
        }.prefix(Constants.tagCloudMaxTags).map { 
            let clean = $0.key.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            return "#\(clean)"
        }
    }
    
    func filterMenuBySearchQuery(_ query: String) {
        let q = query.lowercased()
        var visibleCount = 0
        
        // Hide the "No repos" placeholder if we are filtering
        emptyMenuPlaceholderItem?.isHidden = !q.isEmpty
        
        for map in repoMenuItems {
            if q.isEmpty {
                map.item.isHidden = false
                visibleCount += 1
            } else {
                // Omni-Search: Match implicitly by Name OR Tag
                let nameMatch = map.data.formattedName.lowercased().contains(q) || map.data.repoName.lowercased().contains(q)
                let tagMatch = map.data.tags.contains(where: { $0.lowercased().contains(q) })
                let matches = nameMatch || tagMatch
                
                map.item.isHidden = !matches
                if matches { visibleCount += 1 }
            }
        }
        
        if q.isEmpty {
            noSearchResultsMenuItem?.isHidden = true
        } else {
            if visibleCount == 0, let noResultsView = noSearchResultsMenuItem?.view as? NoSearchResultsView {
                // Route clicks from the Tag Cloud directly into our text field
                noResultsView.onTagSelected = { [weak self] tag in
                    self?.searchField?.stringValue = tag
                    self?.filterMenuBySearchQuery(tag)
                }
                // Sync the true menu width to the tag cloud so its first-pass layout is perfect
                noResultsView.targetWidth = self.currentMenuWidth
                // The view handles its own FlowLayout and dynamically kicks NSMenu frame size internally.
                noResultsView.configure(suggestedTags: popularTagsCache)
            }
            noSearchResultsMenuItem?.isHidden = visibleCount > 0
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
}
