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
        
        delegate.mainPopoverVC.updateAllAgeLabels()
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
        delegate.refreshQuickAddState()
        delegate.animateStatusIcon(with: .rotate)
        
        let startTime = Date()
        
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
            
            // Ensure the "Refreshing..." status remains visible for at least 1 second 
            // to provide consistent visual feedback even for very fast updates.
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 1.0 {
                try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
            }
            
            self.isRefreshing = false
            self.lastRefreshTime = Date()
            
            // Release accumulated HTTP connection pools, TLS session tickets,
            // and internal Foundation caches that grow over days of continuous use.
            GitHubAPI.shared.resetSession()
            
            self.startTimers()
            delegate.updatePopularTagsCache()
            delegate.refreshQuickAddState()
            delegate.rebuildMenu(preserveScroll: true)
        }
    }
    
    // MARK: - Tag & Description Backfill
    
    /// Silently fetches topics and description for legacy repositories
    /// to enable zero-configuration hashtag searching and About display in Notes.
    func startTagBackfillSequence() {
        Task { [weak self] in
            guard let self = self, let delegate = self.delegate else { return }
            
            let reposToUpdate = ConfigManager.shared.config.repos.compactMap { repo -> String? in
                return (repo.tags == nil || repo.repoDescription == nil) ? repo.name : nil
            }
            
            guard !reposToUpdate.isEmpty else { return }
            
            var didUpdateAny = false
            for repoName in reposToUpdate {
                let result = await GitHubAPI.shared.fetchRepoTags(repo: repoName)
                
                await MainActor.run {
                    if let currentIndex = ConfigManager.shared.config.repos.firstIndex(where: { $0.name == repoName }) {
                        ConfigManager.shared.config.repos[currentIndex].tags = result.tags ?? []
                        if let desc = result.description {
                            ConfigManager.shared.config.repos[currentIndex].repoDescription = desc
                        }
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
                    delegate.rebuildMenu(preserveScroll: true) // Re-render tag cloud if it's currently relevant
                }
            }
        }
    }
}
