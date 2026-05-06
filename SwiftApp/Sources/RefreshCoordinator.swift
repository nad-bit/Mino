import Cocoa

/// Manages the periodic refresh cycle: timers, countdown display,
/// burst-fetching from GitHub, tag backfill, and cask discovery.
@MainActor
class RefreshCoordinator {
    
    weak var delegate: AppDelegate?
    
    var lastRefreshTime: Date = Date.distantPast
    var countdownTimer: Timer?
    var isRefreshing = false
    
    init(delegate: AppDelegate) {
        self.delegate = delegate
    }
    
    // MARK: - Timers
    
    func startTimers() {
        countdownTimer?.invalidate()
        let timer = Timer(timeInterval: Constants.countdownTimerIntervalSeconds, target: self, selector: #selector(updateCountdown), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }
    
    func getRefreshTitle() -> String {
        if isRefreshing { return Translations.get("refreshing") }
        
        let refreshMinutes = ConfigManager.shared.config.refreshMinutes
        let nextRefreshDate = lastRefreshTime.addingTimeInterval(TimeInterval(refreshMinutes * 60))
        let nextRefreshSeconds = nextRefreshDate.timeIntervalSince(Date())
        
        let refreshNow = Translations.get("refreshNow")
        if lastRefreshTime != Date.distantPast && nextRefreshSeconds > 0 {
            let totalMinutes = Int(ceil(nextRefreshSeconds / 60))
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            
            if h > 0 {
                if m > 0 {
                    return "\(refreshNow) (\(h)h \(m)min)"
                } else {
                    return "\(refreshNow) (\(h)h)"
                }
            } else {
                return "\(refreshNow) (\(m) min)"
            }
        }
        return refreshNow
    }
    
    @objc func updateCountdown() {
        guard let delegate = delegate else { return }
        if isRefreshing { return }
        
        let refreshMinutes = ConfigManager.shared.config.refreshMinutes
        let nextRefreshDate = lastRefreshTime.addingTimeInterval(TimeInterval(refreshMinutes * 60))
        let nextRefreshSeconds = nextRefreshDate.timeIntervalSince(Date())
        
        // Lightweight update of repository age labels and header title
        delegate.footerView?.updateTimeText(getRefreshTitle(), isRefreshing: isRefreshing)
        
        for repoView in delegate.mainPopoverVC.repoViews {
            repoView.updateAgeDisplay()
        }
        
        if nextRefreshSeconds <= 0 {
            triggerFullRefresh(nil)
        }
    }
    
    // MARK: - Full Refresh
    
    @objc func triggerFullRefresh(_ sender: Any?) {
        guard let delegate = delegate else { return }
        if isRefreshing { return }
        isRefreshing = true
        
        delegate.footerView?.updateTimeText(Translations.get("refreshing"), isRefreshing: true)
        delegate.animateStatusIcon(with: .rotate)
        
        // 1. Optimized prioritized sorting (O(N) lookup preparation)
        let repoConfigs = ConfigManager.shared.config.repos
        let configMap = Dictionary(repoConfigs.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        
        let sortedRepos = repoConfigs.map { $0.name }.sorted { a, b in
            // Favorites first
            let isFavA = configMap[a]?.isFavorite ?? false
            let isFavB = configMap[b]?.isFavorite ?? false
            if isFavA != isFavB { return isFavA }
            
            // New repositories (no cached data) next
            let dateA = delegate.repoCache[a]?.date
            let dateB = delegate.repoCache[b]?.date
            if (dateA == nil) != (dateB == nil) { return dateA == nil }
            
            // Most recent releases first
            return (dateA ?? "") > (dateB ?? "")
        }
        
        Task { [weak self, weak delegate] in
            guard let self = self, let delegate = delegate else { return }
            
            // 2. Optimized burst fetching: prioritized order, OS-managed concurrency
            var results: [(String, RepoInfo)] = []
            await withTaskGroup(of: (String, RepoInfo).self) { group in
                for repo in sortedRepos {
                    let cachedVersion = delegate.repoCache[repo]?.version
                    let looksLikeSHA = cachedVersion?.range(of: "^[0-9a-f]{7}$", options: .regularExpression) != nil
                    let hasExistingRelease = cachedVersion != nil && !looksLikeSHA
                    
                    group.addTask {
                        let info = await GitHubAPI.shared.fetchRepoInfo(repo: repo, hasExistingRelease: hasExistingRelease)
                        return (repo, info)
                    }
                }
                
                for await result in group {
                    results.append(result)
                }
            }
            
            // All fetches done, safely update the UI properties from within the MainActor Context
            var newCaskVersionsDetected = false
            var manualReposToDiscoverCask: [String] = []
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
                    } else if delegate.repoCache[repo] != nil || ConfigManager.shared.config.repos.contains(where: { $0.name == repo }) {
                        // It's a repo we know about but haven't notified for this specific version yet
                        hasFreshUpdates = true
                        updatedNotifiedVersions[repo] = currentVersion
                    }
                }

                if let oldInfo = delegate.repoCache[repo], let newVersion = info.version, let oldVersion = oldInfo.version {
                    if newVersion != oldVersion {
                        if let repoConf = ConfigManager.shared.config.repos.first(where: { $0.name == repo }) {
                            if repoConf.cask != nil {
                                newCaskVersionsDetected = true
                            } else if repoConf.source == "manual" && HomebrewManager.shared.brewPath != nil {
                                manualReposToDiscoverCask.append(repo)
                            }
                        }
                    }
                } else if delegate.repoCache[repo] == nil && info.version != nil {
                    // Newly added repo fetched its first version
                    if ConfigManager.shared.config.repos.first(where: { $0.name == repo })?.cask != nil {
                        newCaskVersionsDetected = true
                    }
                }
                if info.error != nil {
                    // Update only checking error, but preserve version/date/body
                    if var existingInfo = delegate.repoCache[repo] {
                        existingInfo.error = info.error
                        // We intentionally don't update version to keep the cache alive
                        delegate.repoCache[repo] = existingInfo
                    } else {
                        // If it's a completely new repo and we hit an error on first fetch
                        delegate.repoCache[repo] = info
                    }
                } else {
                    // Successful fetch: replace entirely
                    delegate.repoCache[repo] = info
                }
            }
            
            if hasFreshUpdates {
                UserDefaults.standard.set(updatedNotifiedVersions, forKey: "LastNotifiedVersions")
                UserDefaults.standard.set(true, forKey: "HasUnreadPulse")
                delegate.updateStatusIcon(hasUpdates: true)
            }

            if newCaskVersionsDetected {
                Task { let _ = await HomebrewManager.shared.runBrewUpdate() }
            }
            
            // --- Event-driven Cask Discovery ---
            // For manual repos that just received a version update, attempt to find
            // their Homebrew cask using local brew calls (no bulk JSON download needed).
            if !manualReposToDiscoverCask.isEmpty {
                Task {
                    var didDiscover = false
                    for repoName in manualReposToDiscoverCask {
                        if let cask = await HomebrewManager.shared.findCaskForRepo(repoName: repoName) {
                            await MainActor.run {
                                if let index = ConfigManager.shared.config.repos.firstIndex(where: { $0.name == repoName }) {
                                    ConfigManager.shared.config.repos[index].source = "brew"
                                    ConfigManager.shared.config.repos[index].cask = cask
                                    didDiscover = true
                                    print("Auto-discovered cask '\(cask)' for updated repo '\(repoName)'")
                                }
                            }
                        }
                    }
                    if didDiscover {
                        await MainActor.run {
                            ConfigManager.shared.saveConfig()
                            delegate.rebuildMenu()
                        }
                    }
                }
            }
            // ------------------------------------
            
            self.isRefreshing = false
            self.lastRefreshTime = Date()
            self.startTimers()
            delegate.updatePopularTagsCache()
            delegate.rebuildMenu()
        }
    }
    
    // MARK: - Tag Backfill
    
    /// Silently fetches topics for legacy repositories to enable zero-configuration hashtag searching
    func startTagBackfillSequence() {
        Task { [weak self] in
            guard let self = self, let delegate = self.delegate else { return }
            
            let reposToUpdate = ConfigManager.shared.config.repos.compactMap { repo -> String? in
                return repo.tags == nil ? repo.name : nil
            }
            
            guard !reposToUpdate.isEmpty else { return }
            
            var didUpdateAny = false
            for repoName in reposToUpdate {
                let fetchedTags = await GitHubAPI.shared.fetchRepoTags(repo: repoName)
                
                await MainActor.run {
                    if let currentIndex = ConfigManager.shared.config.repos.firstIndex(where: { $0.name == repoName }) {
                        ConfigManager.shared.config.repos[currentIndex].tags = fetchedTags ?? []
                        didUpdateAny = true
                    }
                }
                
                // Throttle to 1 request/second to avoid triggering GitHub API secondary rate limits
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            // Once all 200+ repos are processed, we save and update the cache exactly once for stability.
            if didUpdateAny {
                await MainActor.run {
                    ConfigManager.shared.saveConfig()
                    delegate.updatePopularTagsCache()
                    delegate.rebuildMenu() // Re-render tag cloud if it's currently relevant
                }
            }
        }
    }
}
