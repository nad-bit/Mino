import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    
    var repoCache: [String: RepoInfo] = [:]
    var lastRefreshTime: Date = Date.distantPast
    
    var countdownTimer: Timer?
    var isRefreshing = false
    
    var refreshMenuItem: NSMenuItem!
    var addRepoMenuItem: NSMenuItem!
    var sortToggleMenuItem: NSMenuItem!
    var ownerToggleMenuItem: NSMenuItem!
    
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
        
        DispatchQueue.main.async {
            // Re-render menu to update times and countdown
            self.setupMenu()
        }
        
        if nextRefreshSeconds <= 0 {
            triggerFullRefresh(nil)
        }
    }
    
    @objc func triggerFullRefresh(_ sender: Any?) {
        if isRefreshing { return }
        isRefreshing = true
        
        DispatchQueue.main.async {
            self.refreshMenuItem.title = Translations.get("refreshing")
            self.refreshMenuItem.action = nil
        }
        
        let reposToFetch = ConfigManager.shared.config.repos.map { $0.name }
        
        Task {
            // Concurrent fetching for all repos
            await withTaskGroup(of: (String, RepoInfo).self) { group in
                for repo in reposToFetch {
                    group.addTask {
                        let info = await GitHubAPI.shared.fetchRepoInfo(repo: repo)
                        return (repo, info)
                    }
                }
                
                for await (repo, info) in group {
                    DispatchQueue.main.async {
                        self.repoCache[repo] = info
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.isRefreshing = false
                self.lastRefreshTime = Date()
                self.setupMenu()
                self.updateCountdown()
            }
        }
    }
    
    func setupMenu() {
        menu.removeAllItems()
        
        refreshMenuItem = NSMenuItem(title: getRefreshTitle(), action: #selector(triggerFullRefresh(_:)), keyEquivalent: "")
        refreshMenuItem.target = self
        menu.addItem(refreshMenuItem)
        if isRefreshing {
             refreshMenuItem.action = nil
        }
        
        addRepoMenuItem = NSMenuItem(title: Translations.get("addRepoUnified"), action: #selector(unifiedAddRepoDialog(_:)), keyEquivalent: "")
        addRepoMenuItem.target = self
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
            
            let repoMenuItem = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            let subMenu = NSMenu()
            
            let openItem = NSMenuItem(title: Translations.get("openReleases"), action: #selector(handleOpenReleases(_:)), keyEquivalent: "")
            openItem.representedObject = repoName
            openItem.target = self
            subMenu.addItem(openItem)
            
            let notesItem = NSMenuItem(title: Translations.get("releaseNotes"), action: #selector(handleShowNotes(_:)), keyEquivalent: "")
            notesItem.representedObject = repoName
            notesItem.target = self
            subMenu.addItem(notesItem)
            
            if HomebrewManager.shared.brewPath != nil && repoObj.source == "brew" {
                subMenu.addItem(NSMenuItem.separator())
                let installItem = NSMenuItem(title: Translations.get("installUpdate"), action: #selector(handleInstallBrewCask(_:)), keyEquivalent: "")
                installItem.representedObject = repoObj.cask
                installItem.target = self
                subMenu.addItem(installItem)
            }
            
            subMenu.addItem(NSMenuItem.separator())
            let deleteItem = NSMenuItem(title: Translations.get("deleteRepo"), action: #selector(handleDeleteRepo(_:)), keyEquivalent: "")
            deleteItem.representedObject = repoName
            deleteItem.target = self
            subMenu.addItem(deleteItem)
            
            repoMenuItem.submenu = subMenu
            menu.addItem(repoMenuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let prefMenuItem = NSMenuItem(title: Translations.get("preferences"), action: nil, keyEquivalent: "")
        let prefMenu = NSMenu()
        
        let loginItem = NSMenuItem(title: Translations.get("startAtLogin"), action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.state = isLoginItem() ? .on : .off
        loginItem.target = self
        prefMenu.addItem(loginItem)
        
        let sortTitle = isSortedByName ? Translations.get("sortByDate") : Translations.get("sortByName")
        sortToggleMenuItem = NSMenuItem(title: sortTitle, action: #selector(toggleSortOrder(_:)), keyEquivalent: "")
        sortToggleMenuItem.target = self
        prefMenu.addItem(sortToggleMenuItem)
        
        let ownerTitle = config.showOwner ? Translations.get("hideOwner") : Translations.get("showOwner")
        ownerToggleMenuItem = NSMenuItem(title: ownerTitle, action: #selector(toggleOwnerDisplay(_:)), keyEquivalent: "")
        ownerToggleMenuItem.target = self
        prefMenu.addItem(ownerToggleMenuItem)
        
        prefMenu.addItem(NSMenuItem(title: Translations.get("configureToken"), action: #selector(configureTokenDialog(_:)), keyEquivalent: ""))
        prefMenu.addItem(NSMenuItem(title: Translations.get("changeInterval"), action: #selector(changeIntervalDialog(_:)), keyEquivalent: ""))
        prefMenu.addItem(NSMenuItem(title: Translations.get("about"), action: #selector(showAbout(_:)), keyEquivalent: ""))
        
        // Ensure targets for pref menu
        for item in prefMenu.items {
            item.target = self
        }
        
        prefMenuItem.submenu = prefMenu
        menu.addItem(prefMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: Translations.get("quit"), action: #selector(quitApp(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    // MARK: - Handlers
    
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
            DispatchQueue.main.async {
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
                        DispatchQueue.main.async {
                            NSWorkspace.shared.selectFile(appPath, inFileViewerRootedAtPath: "/Applications")
                        }
                        return
                    } else if let appName = artifact["app"] as? String {
                        let appPath = "/Applications/\(appName)"
                        DispatchQueue.main.async {
                            NSWorkspace.shared.selectFile(appPath, inFileViewerRootedAtPath: "/Applications")
                        }
                        return
                    }
                }
            }
        }
    }
    
    @objc func showAbout(_ sender: Any) {
        UIHandlers.shared.showAbout()
    }
    
    @objc func configureTokenDialog(_ sender: Any) {
        UIHandlers.shared.showTokenDialog(currentToken: ConfigManager.shared.token) { newToken in
            guard let t = newToken else { return }
            if t.isEmpty {
                 self.triggerFullRefresh(nil)
                 return
            }
            Task {
                let valid = await GitHubAPI.shared.validateToken(t)
                DispatchQueue.main.async {
                    if valid {
                        _ = ConfigManager.shared.saveTokenToKeychain(t)
                        ConfigManager.shared.token = t
                        UIHandlers.shared.showAlert(title: Translations.get("configureToken"), message: Translations.get("tokenValidationSuccess"))
                        self.triggerFullRefresh(nil)
                    } else {
                        UIHandlers.shared.showAlert(title: Translations.get("error"), message: Translations.get("tokenValidationError"))
                    }
                }
            }
        }
    }
    
    @objc func changeIntervalDialog(_ sender: Any) {
        let currentMins = ConfigManager.shared.config.refreshMinutes
        if let newMinutes = UIHandlers.shared.showIntervalDialog(currentMinutes: currentMins) {
            ConfigManager.shared.config.refreshMinutes = newMinutes
            ConfigManager.shared.saveConfig()
            lastRefreshTime = Date()
            setupMenu()
        }
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
                DispatchQueue.main.async {
                    self.addRepo(repoName: repoName, source: "brew", cask: cask)
                }
            } else {
                DispatchQueue.main.async {
                    self.addRepo(repoName: repoName, source: "manual")
                }
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
            DispatchQueue.main.async {
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
                    
                    DispatchQueue.main.async {
                        if let r = repoName {
                            self.addRepo(repoName: r, source: "brew", cask: caskName)
                        } else {
                            UIHandlers.shared.showAlert(title: Translations.get("brewErrorTitle"), message: Translations.get("brewRepoNotFound").format(with: ["app_name": caskName]))
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    UIHandlers.shared.showAlert(title: Translations.get("error"), message: "Could not get info for \(caskName): \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Preferences Logics
    
    @objc func toggleSortOrder(_ sender: Any) {
        ConfigManager.shared.config.sortBy = ConfigManager.shared.config.sortBy == "date" ? "name" : "date"
        ConfigManager.shared.saveConfig()
        setupMenu()
    }
    
    @objc func toggleOwnerDisplay(_ sender: Any) {
        ConfigManager.shared.config.showOwner = !ConfigManager.shared.config.showOwner
        ConfigManager.shared.saveConfig()
        setupMenu()
    }
    
    func isLoginItem() -> Bool {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(Constants.launchAgentLabel).plist")
        return FileManager.default.fileExists(atPath: launchAgentPath.path)
    }
    
    @objc func toggleLoginItem(_ sender: Any) {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(Constants.launchAgentLabel).plist")
        
        if isLoginItem() {
            try? FileManager.default.removeItem(at: launchAgentPath)
        } else {
            let bundlePath = Bundle.main.bundlePath
            let executablePath: String
            
            // Check if it's actually an app bundle
            if bundlePath.hasSuffix(".app") {
                executablePath = Bundle.main.executablePath ?? bundlePath
            } else {
                executablePath = bundlePath // Could be command line script fallback
            }
            
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(Constants.launchAgentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(executablePath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            
            try? FileManager.default.createDirectory(at: launchAgentPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plistContent.write(to: launchAgentPath, atomically: true, encoding: .utf8)
        }
        setupMenu()
    }
    
    func sendNotification(title: String, subtitle: String, message: String = "") {
        let notification = NSUserNotification()
        notification.title = title
        notification.subtitle = subtitle
        notification.informativeText = message
        NSUserNotificationCenter.default.deliver(notification)
    }
}
