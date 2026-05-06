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
        delegate.readReposThisSession.remove(repoName)
        
        var seenVersions = UserDefaults.standard.dictionary(forKey: "LastSeenVersions") as? [String: String] ?? [:]
        seenVersions.removeValue(forKey: repoName)
        UserDefaults.standard.set(seenVersions, forKey: "LastSeenVersions")
        
        var notifiedVersions = UserDefaults.standard.dictionary(forKey: "LastNotifiedVersions") as? [String: String] ?? [:]
        notifiedVersions.removeValue(forKey: repoName)
        UserDefaults.standard.set(notifiedVersions, forKey: "LastNotifiedVersions")
        
        if let vc = delegate.releaseNotesPopover?.contentViewController as? ReleaseNotesViewController, vc.currentRepoName == repoName {
            delegate.releaseNotesPopover?.performClose(nil)
        }
        
        ConfigManager.shared.saveConfig()
        delegate.updatePopularTagsCache()
    }
    
    /// Inline delete: called after the user confirmed via the in-menu two-click flow.
    /// Skips the modal NSAlert and removes only the affected menu item (no full rebuild).
    func deleteRepoInline(repoName: String) {
        guard let delegate = delegate else { return }
        
        // Snapshot before deletion for CMD+Z undo
        if let index = ConfigManager.shared.config.repos.firstIndex(where: { $0.name == repoName }) {
            delegate.lastDeletedRepo = (
                config: ConfigManager.shared.config.repos[index],
                index: index,
                cache: delegate.repoCache[repoName]
            )
        }
        
        cleanupRepoData(repoName: repoName)
        
        // Full rebuild is safer to ensure all layout constraints and scroll heights are updated.
        delegate.rebuildMenu()
        
        delegate.animateStatusIcon(with: .replaceWithSlash)
    }
    
    func undoLastDelete() {
        guard let delegate = delegate,
              let last = delegate.lastDeletedRepo else { return }
        
        delegate.lastDeletedRepo = nil
        
        // Prevent duplicate if the user manually added the repo back before hitting CMD+Z (case-insensitive check)
        if ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == last.config.name.lowercased() }) {
            return
        }
        
        // Re-insert at original position (clamped to current count)
        let insertIndex = min(last.index, ConfigManager.shared.config.repos.count)
        ConfigManager.shared.config.repos.insert(last.config, at: insertIndex)
        ConfigManager.shared.saveConfig()
        
        // Restore cache if available
        if let cache = last.cache {
            delegate.repoCache[last.config.name] = cache
        }
        
        delegate.updatePopularTagsCache()
        delegate.rebuildMenu()
        delegate.animateStatusIcon(with: .bounce)
    }
    
    // MARK: - Navigation
    
    @objc func handleOpenRepo(for repoName: String) {
        guard let delegate = delegate else { return }
        
        delegate.hideInformationalWindows()
        
        if let url = URL(string: "https://github.com/\(repoName)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func handleOpenReleases(for repoName: String) {
        guard let delegate = delegate else { return }
        
        delegate.hideInformationalWindows()
        
        if let url = URL(string: "https://github.com/\(repoName)/releases") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func handleShowNotes(for repoName: String, relativeTo view: NSView) {
        guard let delegate = delegate else { return }
        
        // Toggle: If the notes popover is already open for this exact repo, close it.
        if let popover = delegate.releaseNotesPopover,
           popover.isShown,
           let vc = popover.contentViewController as? ReleaseNotesViewController,
           vc.currentRepoName == repoName {
            popover.performClose(nil)
            return
        }
        
        let info = delegate.repoCache[repoName] ?? RepoInfo(name: repoName, error: nil)
        
        if delegate.releaseNotesPopover == nil {
            let popover = NSPopover()
            popover.contentViewController = ReleaseNotesViewController()
            popover.behavior = .transient
            popover.animates = Constants.popoverAnimates
            delegate.releaseNotesPopover = popover
        }
        
        delegate.settingsPopover?.performClose(nil)
        delegate.addRepoPopover?.performClose(nil)
        
        guard let popover = delegate.releaseNotesPopover,
              let vc = popover.contentViewController as? ReleaseNotesViewController else { return }
        
        // Forzar la carga de la vista antes de acceder a los outlets
        _ = vc.view
        
        vc.loadNotes(for: info)
        popover.contentSize = vc.preferredContentSize
        
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minX)
    }
    
    // MARK: - Install
    
    @objc func handleInstallBrewCask(for caskName: String) {
        guard let delegate = delegate else { return }
        
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
                let lowerMsg = result.message.lowercased()
                let isDownloadError = lowerMsg.contains("download failed") || 
                                    lowerMsg.contains("returned error: 404") || 
                                    lowerMsg.contains("returned error: 503")
                
                if isDownloadError {
                    delegate.sendNotification(title: Translations.get("brewDownloadErrorTitle"), 
                                            subtitle: Translations.get("brewDownloadErrorMsg"))
                } else {
                    delegate.sendNotification(title: Translations.get("error"), 
                                            subtitle: Translations.get("installFailed").format(with: ["cask_name": caskName]), 
                                            message: String(result.message.prefix(100)))
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
        
        if delegate.addRepoPopover == nil {
            let popover = NSPopover()
            let vc = AddRepoViewController()
            popover.contentViewController = vc
            // Using applicationDefined to stay open until manually closed or eye-clicked
            popover.behavior = .applicationDefined 
            popover.animates = Constants.popoverAnimates
            delegate.addRepoPopover = popover
            
            vc.completionHandler = { [weak delegate] repoName, source, cask, completion in
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
                        delegate.refreshQuickAddState()
                        completion(success)
                    }
                }
            }
        }
        
        delegate.hideInformationalWindows()
        delegate.bringToFront()
        
        if let popover = delegate.addRepoPopover, let vc = popover.contentViewController as? AddRepoViewController {
            if popover.isShown {
                popover.performClose(nil)
            } else if let btn = delegate.statusItem.button {
                popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
                // Focus slightly delayed for NSPopover reliability
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    vc.resetAndPrepare()
                    popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    
    func addRepoSmart(repoName: String) async -> Bool {
        // 1. Handle explicit brew: prefix if user still uses it
        if repoName.lowercased().hasPrefix("brew:") {
            let caskName = repoName.replacingOccurrences(of: "brew:", with: "", options: [.caseInsensitive])
            return await processBrewSelection(caskName: caskName)
        }
        
        // 2. Distinguish between GitHub (owner/repo) and potential Cask (name)
        let parts = repoName.split(separator: "/")
        if parts.count == 2 {
            // Standard GitHub pattern
            if HomebrewManager.shared.brewPath == nil {
                return await addRepo(repoName: repoName, source: "manual")
            }
            
            if ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == repoName.lowercased() }) {
                return await addRepo(repoName: repoName, source: "manual")
            }
            
            if let cask = await HomebrewManager.shared.findCaskForRepo(repoName: repoName) {
                return await addRepo(repoName: repoName, source: "brew", cask: cask)
            } else {
                return await addRepo(repoName: repoName, source: "manual")
            }
        } else {
            // No slash? Treat as a potential Homebrew Cask name
            if HomebrewManager.shared.brewPath != nil {
                return await processBrewSelection(caskName: repoName)
            } else {
                // If no brew, we can't do anything with a single name
                await MainActor.run {
                    delegate?.sendNotification(title: Translations.get("error"), subtitle: Translations.get("repoNotFound"))
                }
                return false
            }
        }
    }
    
    func addRepo(repoName: String, source: String, cask: String? = nil) async -> Bool {
        guard let delegate = delegate else { return false }
        
        if ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == repoName.lowercased() }) {
            if let index = ConfigManager.shared.config.repos.firstIndex(where: { $0.name.lowercased() == repoName.lowercased() }) {
                if ConfigManager.shared.config.repos[index].source == "manual" && source == "brew" {
                    ConfigManager.shared.config.repos[index].source = "brew"
                    ConfigManager.shared.config.repos[index].cask = cask
                    ConfigManager.shared.saveConfig()
                    await MainActor.run {
                        delegate.rebuildMenu()
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
        if let errorMsg = info.error {
            await MainActor.run {
                delegate.sendNotification(title: Translations.get("error"), subtitle: errorMsg)
            }
            return false
        } else {
            let fetchedTags = await GitHubAPI.shared.fetchRepoTags(repo: repoName)
            
            // Re-check for duplicates after async fetch to prevent race conditions (e.g. CMD+Z during fetch)
            if ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == repoName.lowercased() }) {
                return true
            }
            
            let newRepo = RepoConfig(name: repoName, source: source, cask: cask, tags: fetchedTags ?? [])
            ConfigManager.shared.config.repos.append(newRepo)
            ConfigManager.shared.saveConfig()
            
            await MainActor.run {
                delegate.repoCache[repoName] = info
                delegate.updatePopularTagsCache()
                delegate.rebuildMenu()
                delegate.animateStatusIcon(with: .bounce)
                
                if delegate.popoverIsOpen {
                    delegate.clearUnreadPulse()
                } else {
                    UserDefaults.standard.set(true, forKey: "HasUnreadPulse")
                    delegate.updateStatusIcon(hasUpdates: true)
                }
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
                    let msg: String
                    if httpResponse.statusCode == 429 {
                        msg = Translations.get("apiTooManyRequests")
                    } else if httpResponse.statusCode == 403 {
                        msg = Translations.get("apiRateLimit")
                    } else {
                        msg = Translations.get("brewRepoNotFound").format(with: ["app_name": caskName])
                    }
                    delegate.sendNotification(title: Translations.get("brewErrorTitle"), subtitle: msg)
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
