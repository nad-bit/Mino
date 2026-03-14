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
    var statusIconView: NSImageView!
    var statusIndicatorDot: NSBox!
    var menu: NSMenu!
    
    var repoCache: [String: RepoInfo] = [:]
    
    var headerMenuItem: NSMenuItem!
    var headerView: HeaderMenuItemView!
    
    // Search properties
    var searchField: NSSearchField?
    var searchMenuItem: NSMenuItem?
    var repoMenuItems: [(item: NSMenuItem, data: RepoDisplayData)] = []
    private var readReposThisSession: Set<String> = []
    
    // Refresh Logic and States
    var lastRefreshTime: Date = Date.distantPast
    var lastCaskDiscoveryTime: Date = Date.distantPast
    var countdownTimer: Timer?
    var isRefreshing = false
    var menuIsOpen = false
    
    // Defer actions until menu completes its closing animation
    var pendingMenuAction: (() -> Void)? = nil
    var quickAddingRepo: String? = nil
    
    var settingsWindowController: SettingsWindowController?
    var releaseNotesWindowController: ReleaseNotesWindowController?
    var addRepoWindowController: AddRepoWindowController?
    
    // Ensure only one of our custom windows is visible at a time
    private func hideAllWindowsExcept(keep: NSWindowController?) {
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
        
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false  // Critical: prevents AppKit from disabling custom-view items that have no action
        statusItem.menu = menu
        
        setupMenu()
        startTimers()
        
        triggerFullRefresh(nil)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        countdownTimer?.invalidate()
    }
    
    func startTimers() {
        let timer = Timer(timeInterval: Constants.countdownTimerIntervalSeconds, target: self, selector: #selector(updateCountdown), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }
    
    func getRefreshTitle() -> String {
        if isRefreshing { return Translations.get("refreshing") }
        
        let refreshMinutes = ConfigManager.shared.config.refreshMinutes
        let nextRefreshDate = lastRefreshTime.addingTimeInterval(TimeInterval(refreshMinutes * 60))
        let nextRefreshSeconds = nextRefreshDate.timeIntervalSince(Date())
        
        var refreshTitle = Translations.get("refreshNow")
        if lastRefreshTime != Date.distantPast && nextRefreshSeconds > 0 {
            if nextRefreshSeconds < 3600 {
                let nextRefreshMinutes = Int(ceil(nextRefreshSeconds / 60))
                refreshTitle = "\(Translations.get("refreshNow")) (\(nextRefreshMinutes) \(Translations.get("minutes")))"
            } else {
                let nextRefreshHours = Int(ceil(nextRefreshSeconds / 3600))
                refreshTitle = "\(Translations.get("refreshNow")) (\(nextRefreshHours) \(Translations.get("hours")))"
            }
        }
        return refreshTitle
    }
    
    @objc func updateCountdown() {
        if isRefreshing { return }
        
        let refreshMinutes = ConfigManager.shared.config.refreshMinutes
        let nextRefreshDate = lastRefreshTime.addingTimeInterval(TimeInterval(refreshMinutes * 60))
        let nextRefreshSeconds = nextRefreshDate.timeIntervalSince(Date())
        
        // Only rebuild the menu if it's NOT currently being shown to the user
        // Rebuilding while open destroys custom views and kills hover tracking
        if !menuIsOpen {
            self.setupMenu()
        } else {
            // At minimum update the countdown text in the refresh item
            headerView?.updateTimeText(getRefreshTitle(), isRefreshing: isRefreshing)
        }
        
        if nextRefreshSeconds <= 0 {
            triggerFullRefresh(nil)
        }
    }
    
    @objc func triggerFullRefresh(_ sender: Any?) {
        if isRefreshing { return }
        isRefreshing = true
        
        self.headerView?.updateTimeText(Translations.get("refreshing"), isRefreshing: true)
        self.animateStatusIcon(with: .rotate)
        
        let reposToFetch = ConfigManager.shared.config.repos.map { $0.name }
        
        Task { [weak self] in
            guard let self = self else { return }
            // Concurrent fetching for all repos
            var results: [(String, RepoInfo)] = []
            await withTaskGroup(of: (String, RepoInfo).self) { group in
                for repo in reposToFetch {
                    group.addTask {
                        let info = await GitHubAPI.shared.fetchRepoInfo(repo: repo)
                        return (repo, info)
                    }
                }
                
                for await result in group {
                    results.append(result)
                }
            }
            
            // All fetches done, safely update the UI properties from within the MainActor Context
            var newCaskVersionsDetected = false
            var hasFreshUpdates = false
            let lastNotifiedVersions = UserDefaults.standard.dictionary(forKey: "LastNotifiedVersions") as? [String: String] ?? [:]
            var updatedNotifiedVersions = lastNotifiedVersions

            for (repo, info) in results {
                if let currentVersion = info.version {
                    if let oldVersion = lastNotifiedVersions[repo] {
                        if currentVersion != oldVersion {
                            hasFreshUpdates = true
                            updatedNotifiedVersions[repo] = currentVersion
                        }
                    } else if self.repoCache[repo] != nil || ConfigManager.shared.config.repos.contains(where: { $0.name == repo }) {
                        // It's a repo we know about but haven't notified for this specific version yet
                        hasFreshUpdates = true
                        updatedNotifiedVersions[repo] = currentVersion
                    }
                }

                if let oldInfo = self.repoCache[repo], let newVersion = info.version, let oldVersion = oldInfo.version {
                    if newVersion != oldVersion {
                        if ConfigManager.shared.config.repos.first(where: { $0.name == repo })?.cask != nil {
                            newCaskVersionsDetected = true
                        }
                    }
                } else if self.repoCache[repo] == nil && info.version != nil {
                    // Newly added repo fetched its first version
                    if ConfigManager.shared.config.repos.first(where: { $0.name == repo })?.cask != nil {
                        newCaskVersionsDetected = true
                    }
                }
                self.repoCache[repo] = info
            }
            
            if hasFreshUpdates {
                UserDefaults.standard.set(updatedNotifiedVersions, forKey: "LastNotifiedVersions")
                UserDefaults.standard.set(true, forKey: "HasUnreadPulse")
            }

            if newCaskVersionsDetected {
                Task { let _ = await HomebrewManager.shared.runBrewUpdate() }
            }
            
            // --- Auto-Discovery of Homebrew Casks ---
            let now = Date()
            // Run on first launch (distantPast) or if 24 hours (86400 seconds) have passed
            if now.timeIntervalSince(self.lastCaskDiscoveryTime) > 86400 {
                let manualRepos = ConfigManager.shared.config.repos.filter { $0.source == "manual" }
                if !manualRepos.isEmpty {
                    let caskMap = await HomebrewManager.shared.downloadGlobalCaskMap()
                    if !caskMap.isEmpty {
                        var didUpdate = false
                        for (index, repoConf) in ConfigManager.shared.config.repos.enumerated() {
                            if repoConf.source == "manual", let discoveredCask = caskMap[repoConf.name.lowercased()] {
                                ConfigManager.shared.config.repos[index].source = "brew"
                                ConfigManager.shared.config.repos[index].cask = discoveredCask
                                didUpdate = true
                                print("Auto-discovered cask '\(discoveredCask)' for repo '\(repoConf.name)'")
                            }
                        }
                        if didUpdate {
                            ConfigManager.shared.saveConfig()
                        }
                    }
                }
                self.lastCaskDiscoveryTime = now
            }
            // ----------------------------------------
            
            self.isRefreshing = false
            self.lastRefreshTime = Date()
            self.setupMenu()
            self.updateCountdown()
        }
    }
    
    func setupMenu() {
        menu.removeAllItems()
        repoMenuItems.removeAll()
        
        headerMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headerView = HeaderMenuItemView(appDelegate: self)
        headerView.updateTimeText(getRefreshTitle(), isRefreshing: isRefreshing)
        headerMenuItem.view = headerView
        menu.addItem(headerMenuItem)
        
        // Link the app delegate's search field reference to the one in the header
        self.searchField = headerView.searchField
        self.searchField?.delegate = self
        

        
        menu.addItem(NSMenuItem.separator())
        
        let config = ConfigManager.shared.config
        let isSortedByName = config.sortBy == "name"
        let currentLayout = config.menuLayout ?? "columns"
        
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
        
        if sortedRepos.isEmpty {
            let noRepos = NSMenuItem(title: Translations.get("noRepos"), action: nil, keyEquivalent: "")
            noRepos.isEnabled = false
            noRepos.image = NSImage(systemSymbolName: "slash.circle", accessibilityDescription: nil)
            menu.addItem(noRepos)
        }
        
        // Build display data for each repo
        let indicatorEnabled = config.showNewIndicator ?? true
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
            let newIndicator = (indicatorEnabled && !isLoading && !isError && daysDiff <= thresholdDays) ? " \(Constants.newReleaseIndicator)" : ""
            
            var isNewUpdate = false
            if !isLoading && !isError {
                if let currentVersion = info.version, lastSeenVersions[repoName] != currentVersion {
                    isNewUpdate = true
                }
            }
            
            // Freshness color for hybrid mode
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
                version: info.version,
                ageLabel: (isLoading || isError) ? nil : ageInfo.label,
                ageSeconds: ageInfo.seconds,
                newIndicator: newIndicator,
                errorMessage: isError ? info.error : nil,
                isLoading: isLoading,
                caskName: repoObj.cask,
                freshnessColor: freshnessColor,
                isNew: isNewUpdate
            )
            displayDataList.append((repoObj, data))
        }
        
        // Pre-compute column widths for columns/hybrid modes
        var maxNameWidth: CGFloat = 0
        var maxVersionWidth: CGFloat = 0
        
        if currentLayout == "columns" || currentLayout == "hybrid" {
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
        let isCompact = config.isCompactMode ?? false
        var rowHeight: CGFloat = (currentLayout == "cards") ? 40 : 22
        if isCompact { rowHeight -= 6 }
        
        var repoEntries: [(NSMenuItem, RepoMenuItemView)] = []
        
        for (repoObj, data) in displayDataList {
            let repoMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let customView = RepoMenuItemView(repoName: repoObj.name, displayData: data, layout: currentLayout, appDelegate: self)
            
            if currentLayout == "columns" || currentLayout == "hybrid" {
                customView.nameColumnWidth = maxNameWidth
                customView.versionColumnWidth = maxVersionWidth
            }
            
            repoMenuItem.view = customView
            repoEntries.append((repoMenuItem, customView))
        }
        
        // Calculate uniform width, ignoring the action button stack width (approx 100px)
        // because we don't want the menu to permanently widen just to hold them 
        // since they overlap the right margin when they appear.
        let maxWidth = repoEntries.reduce(CGFloat(320)) { maxSoFar, entry in
            let fittingWidth = entry.1.fittingSize.width
            // Assume the button stack takes about 104pt (4 buttons * 26pt). We subtract it
            // from the fitting size so the menu stays compact.
            return max(maxSoFar, fittingWidth - 104 + 30)
        }
        
        // Apply uniform width and add to menu
        for (menuItem, customView) in repoEntries {
            customView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: rowHeight)
            menu.addItem(menuItem)
            repoMenuItems.append((item: menuItem, data: customView.displayData))
        }
        
        menu.addItem(NSMenuItem.separator())
        

        // Apply uniform width to header
        headerView.targetWidth = maxWidth
        headerView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: 26)
        
        // Add footer
        let footerMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let footerView = FooterMenuItemView(appDelegate: self)
        footerView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: 32)
        footerMenuItem.view = footerView
        menu.addItem(footerMenuItem)
        
        // Hidden NSMenuItems for keyboard shortcuts.
        // Key equivalents are disabled for items WITH custom views, but these items
        // have NO view — so their key equivalents fire normally during menu tracking.
        // allowsKeyEquivalentWhenHidden ensures they work even though isHidden = true.
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
            menu.addItem(item)
        }

        
        
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
    
    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        readReposThisSession.removeAll()
        
        // Acknowledge current versions for the red pulse
        var notifiedVersions = UserDefaults.standard.dictionary(forKey: "LastNotifiedVersions") as? [String: String] ?? [:]
        for (repoName, info) in repoCache {
            if let v = info.version {
                notifiedVersions[repoName] = v
            }
        }
        UserDefaults.standard.set(notifiedVersions, forKey: "LastNotifiedVersions")
        UserDefaults.standard.set(false, forKey: "HasUnreadPulse")
        
        updateStatusIcon(hasUpdates: false) // Turn off red dot immediately upon physical click for responsiveness
        
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
            } else if let clipboardRepo = Utils.getGitHubRepoFromClipboard(),
               !ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == clipboardRepo.lowercased() }) {
                header.updateClipboardState(repo: clipboardRepo)
            } else {
                header.updateClipboardState(repo: nil)
            }
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        
        // Mark currently cached versions as definitively seen upon closing the menu block
        // BUT ONLY for repos that were actually hovered/read during this session
        var seenVersions = UserDefaults.standard.dictionary(forKey: "LastSeenVersions") as? [String: String] ?? [:]
        for (repoName, info) in repoCache {
            if let v = info.version, readReposThisSession.contains(repoName) {
                seenVersions[repoName] = v
            }
        }
        UserDefaults.standard.set(seenVersions, forKey: "LastSeenVersions")
        updateStatusIcon(hasUpdates: false)
        
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
        
        // Rebuild the menu now that it's closed, to pick up any missed countdown updates
        setupMenu()
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
        countdownTimer?.invalidate()
        NSApplication.shared.terminate(self)
    }
    
    // MARK: - Activation Policy Management
    
    func performAfterMenuClose(_ action: @escaping () -> Void) {
        self.pendingMenuAction = action
        self.menu.cancelTracking()
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
    
    @objc func handleOpenReleases(_ sender: NSMenuItem) {
        guard let repoName = sender.representedObject as? String else { return }
        
        hideInformationalWindows()
        
        if let url = URL(string: "https://github.com/\(repoName)/releases") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func handleShowNotes(_ sender: NSMenuItem) {
        guard let repoName = sender.representedObject as? String else { return }
        let info = repoCache[repoName] ?? RepoInfo(name: repoName, error: nil)
        
        if releaseNotesWindowController == nil {
            releaseNotesWindowController = ReleaseNotesWindowController()
        }
        
        hideAllWindowsExcept(keep: releaseNotesWindowController)
        bringToFront()
        releaseNotesWindowController?.loadNotes(for: info)
        releaseNotesWindowController?.showWindow(self)
    }
    
    @objc func handleDeleteRepo(_ sender: NSMenuItem) {
        guard let repoName = sender.representedObject as? String else { return }
        if UIHandlers.shared.confirmDeleteRepo(name: repoName) {
            ConfigManager.shared.config.repos.removeAll { $0.name == repoName }
            repoCache.removeValue(forKey: repoName)
            // Clean up seen state so re-adding this repo later triggers the red dot
            var seenVersions = UserDefaults.standard.dictionary(forKey: "LastSeenVersions") as? [String: String] ?? [:]
            seenVersions.removeValue(forKey: repoName)
            UserDefaults.standard.set(seenVersions, forKey: "LastSeenVersions")
            
            var notifiedVersions = UserDefaults.standard.dictionary(forKey: "LastNotifiedVersions") as? [String: String] ?? [:]
            notifiedVersions.removeValue(forKey: repoName)
            UserDefaults.standard.set(notifiedVersions, forKey: "LastNotifiedVersions")
            // Close release notes window if it's showing the deleted repo
            if releaseNotesWindowController?.currentRepoName == repoName {
                releaseNotesWindowController?.window?.orderOut(nil)
            }
            ConfigManager.shared.saveConfig()
            setupMenu()
            animateStatusIcon(with: .replaceWithSlash)
        }
    }
    
    @objc func handleInstallBrewCask(_ sender: NSMenuItem) {
        guard let caskName = sender.representedObject as? String else { return }
        
        // Show indefinite persistent installing notification while Brew works
        HUDPanel.shared.show(title: Translations.get("installingTitle"), subtitle: Translations.get("installingMsg").format(with: ["cask_name": caskName]), duration: nil)
        
        Task { [weak self] in
            guard let self = self else { return }
            let result = await HomebrewManager.shared.installCask(cask: caskName)
            
            if result.success {
                let msgId = result.message == "alreadyInstalled" ? "alreadyInstalled" : "installComplete"
                self.sendNotification(title: "Mino", subtitle: Translations.get(msgId).format(with: ["cask_name": caskName]))
                
                // Reveal in Finder
                self.revealCaskInFinder(caskName: caskName)
            } else if result.message == "requires_sudo" {
                // Aborted because Homebrew asked for a password
                DispatchQueue.main.async {
                    self.animateStatusIcon(with: .wiggle)
                    HUDPanel.shared.hide()
                    let alert = NSAlert()
                    alert.messageText = Translations.get("sudoRequiredTitle")
                    alert.informativeText = Translations.get("sudoRequiredDesc").format(with: ["cask_name": caskName])
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            } else {
                self.sendNotification(title: Translations.get("error"), subtitle: Translations.get("installFailed").format(with: ["cask_name": caskName]), message: String(result.message.prefix(100)))
            }
        }
    }
    
    func revealCaskInFinder(caskName: String) {
        Task {
            if let jsonOutput = await HomebrewManager.shared.infoForCask(cask: caskName),
               let data = jsonOutput.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let casks = json["casks"] as? [[String: Any]],
               let firstCask = casks.first,
               let artifacts = firstCask["artifacts"] as? [[String: Any]] {
                
                for artifact in artifacts {
                    if let appArray = artifact["app"] as? [String], let appName = appArray.first {
                        let appPath = "/Applications/\(appName)"
                        NSWorkspace.shared.selectFile(appPath, inFileViewerRootedAtPath: "/Applications")
                        return
                    } else if let appName = artifact["app"] as? String {
                        let appPath = "/Applications/\(appName)"
                        NSWorkspace.shared.selectFile(appPath, inFileViewerRootedAtPath: "/Applications")
                        return
                    }
                }
            }
        }
    }
    
    @objc func openSettingsWindow(_ sender: Any) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        
        hideAllWindowsExcept(keep: settingsWindowController)
        bringToFront()
        settingsWindowController?.showWindow(self)
    }
    
    @objc func unifiedAddRepoDialog(_ sender: Any) {
        if addRepoWindowController == nil {
            addRepoWindowController = AddRepoWindowController()
            addRepoWindowController?.completionHandler = { [weak self] repoName, source, cask, completion in
                guard let self = self else { return }
                if let repo = repoName {
                    self.quickAddingRepo = repo
                }
                Task {
                    var success = false
                    if let repo = repoName, source == "manual" {
                        success = await self.addRepoSmart(repoName: repo)
                    } else if source == "brew", let caskName = cask {
                        success = await self.processBrewSelection(caskName: caskName)
                    }
                    await MainActor.run {
                        self.quickAddingRepo = nil
                        completion(success)
                    }
                }
            }
        }
        
        hideAllWindowsExcept(keep: addRepoWindowController)
        bringToFront()
        addRepoWindowController?.resetAndShow()
    }
    
    func addRepoSmart(repoName: String) async -> Bool {
        if HomebrewManager.shared.brewPath == nil {
            return await addRepo(repoName: repoName, source: "manual")
        }
        
        if ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == repoName.lowercased() }) {
            return await addRepo(repoName: repoName, source: "manual")
        }
        
        let parts = repoName.split(separator: "/")
        if parts.count != 2 {
            return await addRepo(repoName: repoName, source: "manual")
        }
        
        if let cask = await HomebrewManager.shared.findCaskForRepo(repoName: repoName) {
            return await addRepo(repoName: repoName, source: "brew", cask: cask)
        } else {
            return await addRepo(repoName: repoName, source: "manual")
        }
    }
    
    func addRepo(repoName: String, source: String, cask: String? = nil) async -> Bool {
        if ConfigManager.shared.config.repos.contains(where: { $0.name == repoName }) {
            if let index = ConfigManager.shared.config.repos.firstIndex(where: { $0.name == repoName }) {
                if ConfigManager.shared.config.repos[index].source == "manual" && source == "brew" {
                    ConfigManager.shared.config.repos[index].source = "brew"
                    ConfigManager.shared.config.repos[index].cask = cask
                    ConfigManager.shared.saveConfig()
                    await MainActor.run {
                        self.setupMenu()
                        self.animateStatusIcon(with: .bounce)
                    }
                    return true
                } else {
                    await MainActor.run {
                        self.sendNotification(title: Translations.get("error"), subtitle: Translations.get("repoExists"))
                    }
                    return false
                }
            }
            return false
        }
        
        let info = await GitHubAPI.shared.fetchRepoInfo(repo: repoName)
        if info.error != nil {
            await MainActor.run {
                self.sendNotification(title: Translations.get("error"), subtitle: Translations.get("repoNotFound"))
            }
            return false
        } else {
            let newRepo = RepoConfig(name: repoName, source: source, cask: cask)
            ConfigManager.shared.config.repos.append(newRepo)
            ConfigManager.shared.saveConfig()
            
            await MainActor.run {
                self.repoCache[repoName] = info
                UserDefaults.standard.set(true, forKey: "HasUnreadPulse")
                self.setupMenu()
                self.animateStatusIcon(with: .bounce)
            }
            return true
        }
    }
    
    func processBrewSelection(caskName: String) async -> Bool {
        // Early check: if any repo already has this cask, show duplicate message
        if ConfigManager.shared.config.repos.contains(where: { $0.cask?.lowercased() == caskName.lowercased() }) {
            await MainActor.run {
                self.sendNotification(title: Translations.get("error"), subtitle: Translations.get("repoExists"))
            }
            return false
        }
        
        guard let url = URL(string: "https://formulae.brew.sh/api/cask/\(caskName).json") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // TAP casks (e.g. from custom taps) are not in the public API and return 404
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                await MainActor.run {
                    self.sendNotification(title: Translations.get("brewErrorTitle"), subtitle: Translations.get("brewRepoNotFound").format(with: ["app_name": caskName]))
                }
                return false
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var repoName: String? = nil
                let regex = try NSRegularExpression(pattern: "github\\.com/([^/]+/[^/\\s\"]+)")
                
                let searchKeys = ["verified", "homepage", "url"]
                for key in searchKeys {
                    if repoName != nil { break }
                    var urlString = ""
                    if key == "verified" {
                        urlString = (json["url_specs"] as? [String: Any])?["verified"] as? String ?? ""
                    } else {
                        urlString = json[key] as? String ?? ""
                    }
                    
                    if !urlString.isEmpty {
                        let range = NSRange(location: 0, length: urlString.utf16.count)
                        if let match = regex.firstMatch(in: urlString, options: [], range: range) {
                            if let r = Range(match.range(at: 1), in: urlString) {
                                repoName = String(urlString[r]).replacingOccurrences(of: ".git", with: "")
                            }
                        }
                    }
                }
                
                if let r = repoName {
                    return await addRepo(repoName: r, source: "brew", cask: caskName)
                } else {
                    await MainActor.run {
                        self.sendNotification(title: Translations.get("brewErrorTitle"), subtitle: Translations.get("brewRepoNotFound").format(with: ["app_name": caskName]))
                    }
                    return false
                }
            }
        } catch {
            await MainActor.run {
                self.sendNotification(title: Translations.get("brewErrorTitle"), subtitle: Translations.get("brewRepoNotFound").format(with: ["app_name": caskName]))
            }
        }
        return false
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
    
    private func filterMenuBySearchQuery(_ query: String) {
        let q = query.lowercased()
        
        for map in repoMenuItems {
            if q.isEmpty {
                map.item.isHidden = false
            } else {
                // If the user's input matches the exact username or repo name locally
                let matches = map.data.formattedName.lowercased().contains(q) || map.data.repoName.lowercased().contains(q)
                map.item.isHidden = !matches
            }
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
