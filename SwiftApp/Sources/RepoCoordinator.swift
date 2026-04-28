import Cocoa

/// Manages repository lifecycle: add, delete, install, and navigation actions.
@MainActor
class RepoCoordinator {
    
    weak var delegate: AppDelegate?
    
    init(delegate: AppDelegate) {
        self.delegate = delegate
    }
    
    // MARK: - Delete
    
    /// Cleans up all cached data and config for a given repository upon deletion.
    private func cleanupRepoData(repoName: String) {
        guard let delegate = delegate else { return }
        ConfigManager.shared.config.repos.removeAll { $0.name == repoName }
        delegate.repoCache.removeValue(forKey: repoName)
        
        var seenVersions = UserDefaults.standard.dictionary(forKey: "LastSeenVersions") as? [String: String] ?? [:]
        seenVersions.removeValue(forKey: repoName)
        UserDefaults.standard.set(seenVersions, forKey: "LastSeenVersions")
        
        var notifiedVersions = UserDefaults.standard.dictionary(forKey: "LastNotifiedVersions") as? [String: String] ?? [:]
        notifiedVersions.removeValue(forKey: repoName)
        UserDefaults.standard.set(notifiedVersions, forKey: "LastNotifiedVersions")
        
        if delegate.releaseNotesWindowController?.currentRepoName == repoName {
            delegate.releaseNotesWindowController?.window?.orderOut(nil)
        }
        
        ConfigManager.shared.saveConfig()
        delegate.updatePopularTagsCache()
    }
    
    /// Inline delete: called after the user confirmed via the in-menu two-click flow.
    /// Skips the modal NSAlert and removes only the affected menu item (no full rebuild).
    func deleteRepoInline(repoName: String) {
        guard let delegate = delegate else { return }
        
        cleanupRepoData(repoName: repoName)
        
        // Remove the specific menu item without rebuilding the entire menu.
        // Hide first to collapse the space, then remove to clean up.
        if let idx = delegate.repoMenuItems.firstIndex(where: { $0.data.repoName == repoName }) {
            let menuItem = delegate.repoMenuItems[idx].item
            menuItem.isHidden = true
            delegate.mainMenu.removeItem(menuItem)
            delegate.repoMenuItems.remove(at: idx)
        }
        
        // Update the footer's repo count label
        for item in delegate.mainMenu.items {
            if let footerView = item.view as? FooterMenuItemView {
                footerView.updateRepoCount()
                break
            }
        }
        
        // Show empty-state placeholder when all repos have been deleted
        if delegate.repoMenuItems.isEmpty {
            if delegate.emptyMenuPlaceholderItem == nil {
                let noRepos = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                noRepos.view = EmptyMenuPlaceholderView()
                // Insert before the separator that precedes the footer
                let insertIndex = max(delegate.mainMenu.items.count - 3, 0)
                delegate.mainMenu.insertItem(noRepos, at: insertIndex)
                delegate.emptyMenuPlaceholderItem = noRepos
            }
            delegate.emptyMenuPlaceholderItem?.isHidden = false
        }
        
        // Force NSMenu to recalculate its window size during active tracking
        delegate.mainMenu.update()
        
        delegate.animateStatusIcon(with: .replaceWithSlash)
    }
    
    // MARK: - Navigation
    
    @objc func handleOpenReleases(_ sender: NSMenuItem) {
        guard let delegate = delegate else { return }
        guard let repoName = sender.representedObject as? String else { return }
        
        delegate.hideInformationalWindows()
        
        if let url = URL(string: "https://github.com/\(repoName)/releases") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func handleShowNotes(_ sender: NSMenuItem) {
        guard let delegate = delegate else { return }
        guard let repoName = sender.representedObject as? String else { return }
        let info = delegate.repoCache[repoName] ?? RepoInfo(name: repoName, error: nil)
        
        if delegate.releaseNotesWindowController == nil {
            delegate.releaseNotesWindowController = ReleaseNotesWindowController()
        }
        
        delegate.hideAllWindowsExcept(keep: delegate.releaseNotesWindowController)
        delegate.bringToFront()
        delegate.releaseNotesWindowController?.loadNotes(for: info)
        delegate.releaseNotesWindowController?.showWindow(nil)
    }
    
    // MARK: - Install
    
    @objc func handleInstallBrewCask(_ sender: NSMenuItem) {
        guard let delegate = delegate else { return }
        guard let caskName = sender.representedObject as? String else { return }
        
        // Show indefinite persistent installing notification while Brew works
        HUDPanel.shared.show(title: Translations.get("installingTitle"), subtitle: Translations.get("installingMsg").format(with: ["cask_name": caskName]), duration: nil)
        
        Task { [weak delegate] in
            guard let delegate = delegate else { return }
            let result = await HomebrewManager.shared.installCask(cask: caskName)
            
            if result.success {
                let msgId = result.message == "alreadyInstalled" ? "alreadyInstalled" : "installComplete"
                delegate.sendNotification(title: "Mino", subtitle: Translations.get(msgId).format(with: ["cask_name": caskName]))
                
                // Reveal in Finder
                self.revealCaskInFinder(caskName: caskName)
            } else if result.message == "requires_sudo" {
                // Aborted because Homebrew asked for a password
                DispatchQueue.main.async {
                    delegate.animateStatusIcon(with: .wiggle)
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
                delegate.sendNotification(title: Translations.get("error"), subtitle: Translations.get("installFailed").format(with: ["cask_name": caskName]), message: String(result.message.prefix(100)))
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
    
    // MARK: - Add Repo
    
    @objc func openAddRepoDialog(_ sender: Any) {
        guard let delegate = delegate else { return }
        
        if delegate.addRepoWindowController == nil {
            delegate.addRepoWindowController = AddRepoWindowController()
            delegate.addRepoWindowController?.completionHandler = { [weak delegate] repoName, source, cask, completion in
                guard let delegate = delegate else { return }
                if let repo = repoName {
                    delegate.quickAddingRepo = repo
                }
                Task {
                    var success = false
                    if let repo = repoName, source == "manual" {
                        success = await delegate.repoCoordinator.addRepoSmart(repoName: repo)
                    } else if source == "brew", let caskName = cask {
                        success = await delegate.repoCoordinator.processBrewSelection(caskName: caskName)
                    }
                    await MainActor.run {
                        delegate.quickAddingRepo = nil
                        completion(success)
                    }
                }
            }
        }
        
        delegate.hideAllWindowsExcept(keep: delegate.addRepoWindowController)
        delegate.bringToFront()
        delegate.addRepoWindowController?.resetAndShow()
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
        guard let delegate = delegate else { return false }
        
        if ConfigManager.shared.config.repos.contains(where: { $0.name == repoName }) {
            if let index = ConfigManager.shared.config.repos.firstIndex(where: { $0.name == repoName }) {
                if ConfigManager.shared.config.repos[index].source == "manual" && source == "brew" {
                    ConfigManager.shared.config.repos[index].source = "brew"
                    ConfigManager.shared.config.repos[index].cask = cask
                    ConfigManager.shared.saveConfig()
                    await MainActor.run {
                        delegate.setupMenu()
                        delegate.animateStatusIcon(with: .bounce)
                    }
                    return true
                } else {
                    await MainActor.run {
                        delegate.sendNotification(title: Translations.get("error"), subtitle: Translations.get("repoExists"))
                    }
                    return false
                }
            }
            return false
        }
        
        let info = await GitHubAPI.shared.fetchRepoInfo(repo: repoName)
        if info.error != nil {
            await MainActor.run {
                delegate.sendNotification(title: Translations.get("error"), subtitle: Translations.get("repoNotFound"))
            }
            return false
        } else {
            let fetchedTags = await GitHubAPI.shared.fetchRepoTags(repo: repoName)
            let newRepo = RepoConfig(name: repoName, source: source, cask: cask, tags: fetchedTags ?? [])
            ConfigManager.shared.config.repos.append(newRepo)
            ConfigManager.shared.saveConfig()
            
            await MainActor.run {
                delegate.repoCache[repoName] = info
                UserDefaults.standard.set(true, forKey: "HasUnreadPulse")
                delegate.updatePopularTagsCache()
                delegate.setupMenu()
                delegate.animateStatusIcon(with: .bounce)
            }
            return true
        }
    }
    
    func processBrewSelection(caskName: String) async -> Bool {
        guard let delegate = delegate else { return false }
        
        // Early check: if any repo already has this cask, show duplicate message
        if ConfigManager.shared.config.repos.contains(where: { $0.cask?.lowercased() == caskName.lowercased() }) {
            await MainActor.run {
                delegate.sendNotification(title: Translations.get("error"), subtitle: Translations.get("repoExists"))
            }
            return false
        }
        
        guard let url = URL(string: "https://formulae.brew.sh/api/cask/\(caskName).json") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // TAP casks (e.g. from custom taps) are not in the public API and return 404
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                await MainActor.run {
                    delegate.sendNotification(title: Translations.get("brewErrorTitle"), subtitle: Translations.get("brewRepoNotFound").format(with: ["app_name": caskName]))
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
                        delegate.sendNotification(title: Translations.get("brewErrorTitle"), subtitle: Translations.get("brewRepoNotFound").format(with: ["app_name": caskName]))
                    }
                    return false
                }
            }
        } catch {
            await MainActor.run {
                delegate.sendNotification(title: Translations.get("brewErrorTitle"), subtitle: Translations.get("brewRepoNotFound").format(with: ["app_name": caskName]))
            }
        }
        return false
    }
}
