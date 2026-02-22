import Cocoa

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    
    var repoCache: [String: RepoInfo] = [:]
    var lastRefreshTime: Date = Date.distantPast
    
    var countdownTimer: Timer?
    var isRefreshing = false
    var menuIsOpen = false
    
    var refreshMenuItem: NSMenuItem!
    var addRepoMenuItem: NSMenuItem!
    
    var settingsWindowController: SettingsWindowController?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Use SF Symbol "eye"
        if let eyeImage = NSImage(systemSymbolName: "eye", accessibilityDescription: "GitHub Watcher") {
            eyeImage.isTemplate = true
            statusItem.button?.image = eyeImage
        } else {
            statusItem.button?.title = "GW"
        }
        
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
        countdownTimer = Timer.scheduledTimer(timeInterval: Constants.countdownTimerIntervalSeconds, target: self, selector: #selector(updateCountdown), userInfo: nil, repeats: true)
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
            refreshMenuItem?.title = getRefreshTitle()
        }
        
        if nextRefreshSeconds <= 0 {
            triggerFullRefresh(nil)
        }
    }
    
    @objc func triggerFullRefresh(_ sender: Any?) {
        if isRefreshing { return }
        isRefreshing = true
        
        self.refreshMenuItem.title = Translations.get("refreshing")
        self.refreshMenuItem.action = nil
        
        let reposToFetch = ConfigManager.shared.config.repos.map { $0.name }
        
        Task {
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
            for (repo, info) in results {
                self.repoCache[repo] = info
            }
            
            self.isRefreshing = false
            self.lastRefreshTime = Date()
            self.setupMenu()
            self.updateCountdown()
        }
    }
    
    func setupMenu() {
        menu.removeAllItems()
        
        refreshMenuItem = NSMenuItem(title: getRefreshTitle(), action: #selector(triggerFullRefresh(_:)), keyEquivalent: "")
        refreshMenuItem.target = self
        refreshMenuItem.image = getIcon("arrow.clockwise")
        menu.addItem(refreshMenuItem)
        if isRefreshing {
             refreshMenuItem.action = nil
        }
        
        addRepoMenuItem = NSMenuItem(title: Translations.get("addRepoUnified"), action: #selector(unifiedAddRepoDialog(_:)), keyEquivalent: "")
        addRepoMenuItem.target = self
        addRepoMenuItem.image = getIcon("plus")
        menu.addItem(addRepoMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let config = ConfigManager.shared.config
        let isSortedByName = config.sortBy == "name"
        
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
            noRepos.image = getIcon("slash.circle")
            menu.addItem(noRepos)
        }
        
        for repoObj in sortedRepos {
            let repoName = repoObj.name
            let info = repoCache[repoName] ?? RepoInfo(name: repoName, error: nil)
            
            var label = "\(repoName) - \(Translations.get("loading"))"
            
            if info.error != nil {
                label = "⚠️ \(repoName) - \(Translations.get("error"))"
            } else if let version = info.version {
                let ageInfo = Utils.getReleaseAge(dateString: info.date)
                let daysDiff = Int(ageInfo.seconds / 86400)
                let newIndicator = daysDiff <= Constants.newReleaseThresholdDays ? " \(Constants.newReleaseIndicator)" : ""
                
                var formattedName = repoName
                if !config.showOwner {
                    formattedName = String(repoName.split(separator: "/").last ?? Substring(repoName))
                }
                
                label = "\(formattedName) (\(version)) · \(ageInfo.label)\(newIndicator)"
            }
            
            let repoMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let customView = RepoMenuItemView(repoName: repoName, labelText: label, caskName: repoObj.cask, appDelegate: self)
            
            // Calculate dynamic width to prevent NSMenu collapse while avoiding truncation
            let fittingSize = customView.fittingSize
            let requiredWidth = max(320, fittingSize.width + 10)
            customView.frame = NSRect(x: 0, y: 0, width: requiredWidth, height: 26)
            
            repoMenuItem.view = customView
            menu.addItem(repoMenuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        

        let prefTitle = Translations.get("preferences")
        // Append zero-width space if no icons, to bypass macOS auto-injecting a gear icon
        let finalPrefTitle = (ConfigManager.shared.config.showIcons ?? false) ? prefTitle : prefTitle + "\u{200B}"
        
        let preferencesItem = NSMenuItem(title: finalPrefTitle, action: #selector(openSettingsWindow(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        preferencesItem.image = getIcon("gearshape")
        menu.addItem(preferencesItem)
        
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: Translations.get("quit"), action: #selector(quitApp(_:)), keyEquivalent: "")
        quitItem.target = self
        quitItem.image = getIcon("xmark.circle")
        menu.addItem(quitItem)
    }
    
    // MARK: - NSMenuDelegate
    
    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
    }
    
    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        // Rebuild the menu now that it's closed, to pick up any missed countdown updates
        setupMenu()
    }
    
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        // Pass the item that WILL be highlighted directly to each custom view
        for menuItem in menu.items {
            if let repoView = menuItem.view as? RepoMenuItemView {
                repoView.menuDidChangeHighlight(highlightedItem: item)
            }
        }
    }

    // MARK: - Handlers
    
    private func getIcon(_ name: String) -> NSImage? {
        if ConfigManager.shared.config.showIcons ?? false {
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        return nil
    }
    
    @objc func quitApp(_ sender: Any) {
        countdownTimer?.invalidate()
        NSApplication.shared.terminate(self)
    }
    
    @objc func handleOpenReleases(_ sender: NSMenuItem) {
        guard let repoName = sender.representedObject as? String else { return }
        if let url = URL(string: "https://github.com/\(repoName)/releases") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func handleShowNotes(_ sender: NSMenuItem) {
        guard let repoName = sender.representedObject as? String else { return }
        let info = repoCache[repoName] ?? RepoInfo(name: repoName, error: nil)
        UIHandlers.shared.showReleaseNotes(info: info)
    }
    
    @objc func handleDeleteRepo(_ sender: NSMenuItem) {
        guard let repoName = sender.representedObject as? String else { return }
        if UIHandlers.shared.confirmDeleteRepo(name: repoName) {
            ConfigManager.shared.config.repos.removeAll { $0.name == repoName }
            repoCache.removeValue(forKey: repoName)
            ConfigManager.shared.saveConfig()
            setupMenu()
        }
    }
    
    @objc func handleInstallBrewCask(_ sender: NSMenuItem) {
        guard let caskName = sender.representedObject as? String else { return }
        sendNotification(title: Translations.get("installingTitle"), subtitle: Translations.get("installingMsg").format(with: ["cask_name": caskName]))
        
        Task {
            let result = await HomebrewManager.shared.installCask(cask: caskName)
            
            if result.success {
                let msgId = result.message == "alreadyInstalled" ? "alreadyInstalled" : "installComplete"
                self.sendNotification(title: "GitHub Watcher", subtitle: Translations.get(msgId).format(with: ["cask_name": caskName]))
                
                // Reveal in Finder
                self.revealCaskInFinder(caskName: caskName)
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
    
    @objc func showAbout(_ sender: Any) {
        UIHandlers.shared.showAbout()
    }
    
    @objc func openSettingsWindow(_ sender: Any) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(self)
    }
    
    @objc func unifiedAddRepoDialog(_ sender: Any) {
        let hasBrew = HomebrewManager.shared.brewPath != nil
        UIHandlers.shared.showUnifiedAddRepoDialog(hasBrew: hasBrew) { repoName, source, cask in
            if let repo = repoName, source == "manual" {
                self.addRepoSmart(repoName: repo)
            } else if source == "brew", let caskName = cask {
                self.processBrewSelection(caskName: caskName)
            }
        }
    }
    
    func addRepoSmart(repoName: String) {
        if HomebrewManager.shared.brewPath == nil {
            addRepo(repoName: repoName, source: "manual")
            return
        }
        
        if ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == repoName.lowercased() }) {
            addRepo(repoName: repoName, source: "manual")
            return
        }
        
        let parts = repoName.split(separator: "/")
        if parts.count != 2 {
            addRepo(repoName: repoName, source: "manual")
            return
        }
        
        Task {
            // Very simplistic check, without fetching headers explicitly as in Python.
            if let cask = await HomebrewManager.shared.findCaskForRepo(repoName: repoName) {
                self.addRepo(repoName: repoName, source: "brew", cask: cask)
            } else {
                self.addRepo(repoName: repoName, source: "manual")
            }
        }
    }
    
    func addRepo(repoName: String, source: String, cask: String? = nil) {
        if ConfigManager.shared.config.repos.contains(where: { $0.name == repoName }) {
            if let index = ConfigManager.shared.config.repos.firstIndex(where: { $0.name == repoName }) {
                if ConfigManager.shared.config.repos[index].source == "manual" && source == "brew" {
                    ConfigManager.shared.config.repos[index].source = "brew"
                    ConfigManager.shared.config.repos[index].cask = cask
                    ConfigManager.shared.saveConfig()
                    setupMenu()
                } else {
                    UIHandlers.shared.showAlert(title: Translations.get("error"), message: Translations.get("repoExists"))
                }
            }
            return
        }
        
        // Fix: Do not add to config/cache immediately. Fetch first to validate.
        Task {
            let info = await GitHubAPI.shared.fetchRepoInfo(repo: repoName)
            if info.error != nil {
                // Invalid repo, show error and do NOT add to array
                UIHandlers.shared.showAlert(title: Translations.get("error"), message: Translations.get("repoNotFound"))
            } else {
                // Valid repo, add to array and cache
                let newRepo = RepoConfig(name: repoName, source: source, cask: cask)
                ConfigManager.shared.config.repos.append(newRepo)
                ConfigManager.shared.saveConfig()
                
                self.repoCache[repoName] = info
                self.setupMenu()
            }
        }
    }
    
    func processBrewSelection(caskName: String) {
        Task {
            guard let url = URL(string: "https://formulae.brew.sh/api/cask/\(caskName).json") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
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
                        self.addRepo(repoName: r, source: "brew", cask: caskName)
                    } else {
                        UIHandlers.shared.showAlert(title: Translations.get("brewErrorTitle"), message: Translations.get("brewRepoNotFound").format(with: ["app_name": caskName]))
                    }
                }
            } catch {
                UIHandlers.shared.showAlert(title: Translations.get("error"), message: "Could not get info for \(caskName): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Preferences Logics
    
    // Removed redundant inline toggles since they are now in SettingsWindowController.
    
    func sendNotification(title: String, subtitle: String, message: String = "") {
        let fullSubtitle = message.isEmpty ? subtitle : "\(subtitle)\n\(message)"
        HUDPanel.shared.show(title: title, subtitle: fullSubtitle)
    }
}
