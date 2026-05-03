import Cocoa

class MainPopoverViewController: NSViewController {
    
    weak var appDelegate: AppDelegate?
    
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let clipView = FlippedClipView()
    
    // Data Source
    private var tableRepos: [RepoDisplayData] = []
    private var lastRowHeight: CGFloat = 40
    
    // Contenedores fijos para Header y Footer
    private let headerContainer = NSView()
    private let footerContainer = NSView()
    
    private var headerView: HeaderMenuItemView?
    private var footerView: FooterMenuItemView?
    
    // Centralized Mouse Tracking
    private var mouseMonitor: Any?
    private var currentlyHighlightedRow: RepoMenuItemView?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let container = NSView()
        self.view = container
        
        // 1. Setup Table & ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        clipView.postsBoundsChangedNotifications = true
        scrollView.contentView = clipView
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize.zero
        if #available(macOS 11.0, *) {
            tableView.style = .plain
        }
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("RepoColumn"))
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        
        scrollView.documentView = tableView
        
        // 3. Setup NoSearchResultsView (init early to include in stack)
        let nrv = NoSearchResultsView()
        nrv.translatesAutoresizingMaskIntoConstraints = false
        nrv.isHidden = true
        self.noSearchResultsView = nrv
        nrv.onTagSelected = { [weak appDelegate] tag in
            guard let appDelegate = appDelegate else { return }
            appDelegate.currentSearchQuery = tag
            appDelegate.searchField?.stringValue = tag
            appDelegate.filterMenuBySearchQuery(tag)
            appDelegate.headerView?.updateSearchOpacity()
        }
        
        // 4. Use a Master StackView to guarantee zero gaps
        let masterStack = NSStackView(views: [headerContainer, nrv, scrollView, footerContainer])
        masterStack.translatesAutoresizingMaskIntoConstraints = false
        masterStack.orientation = .vertical
        masterStack.spacing = 0
        masterStack.alignment = .centerX
        masterStack.distribution = .fill
        
        container.addSubview(masterStack)
        
        NSLayoutConstraint.activate([
            masterStack.topAnchor.constraint(equalTo: container.topAnchor),
            masterStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            masterStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            masterStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            headerContainer.widthAnchor.constraint(equalTo: masterStack.widthAnchor),
            footerContainer.widthAnchor.constraint(equalTo: masterStack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: masterStack.widthAnchor),
            
            tableView.topAnchor.constraint(equalTo: clipView.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor)
        ])
        
        setupScrollObservation()
    }
    
    private func setupScrollObservation() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleScroll), name: NSView.boundsDidChangeNotification, object: clipView)
    }
    
    @objc private func handleScroll() {
        updateHighlightUnderMouse()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        // Universal mouse tracking: catches movement even when over subviews (buttons)
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateHighlightUnderMouse()
            return event
        }
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func updateHighlightUnderMouse() {
        guard let window = view.window else { return }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let locationInTable = tableView.convert(mouseLocation, from: nil)
        let row = tableView.row(at: locationInTable)
        
        var hitView: RepoMenuItemView? = nil
        if row >= 0, let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? RepoMenuItemView {
            hitView = view
        }
        
        if hitView !== currentlyHighlightedRow {
            currentlyHighlightedRow?.setHighlighted(false)
            currentlyHighlightedRow = hitView
            currentlyHighlightedRow?.setHighlighted(true)
        }
    }
    
    func clearHighlight() {
        currentlyHighlightedRow?.setHighlighted(false)
        currentlyHighlightedRow = nil
    }
    
    func rebuildMenu() {
        guard let appDelegate = appDelegate else { return }
        
        // 1. Setup/Update Header
        if headerView == nil {
            let hv = HeaderMenuItemView(appDelegate: appDelegate)
            headerContainer.addSubview(hv)
            hv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hv.topAnchor.constraint(equalTo: headerContainer.topAnchor),
                hv.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
                hv.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
                headerContainer.heightAnchor.constraint(equalToConstant: Constants.menuHeaderFooterHeight)
            ])
            self.headerView = hv
            appDelegate.headerView = hv
            appDelegate.searchField = hv.searchField
            appDelegate.searchField?.delegate = appDelegate
        }
        
        guard let headerView = headerView else { return }
        headerView.updateTimeText(appDelegate.getRefreshTitle(), isRefreshing: appDelegate.isRefreshing)
        
        // Restore previous search query if any
        if !appDelegate.currentSearchQuery.isEmpty {
            appDelegate.searchField?.stringValue = appDelegate.currentSearchQuery
            headerView.updateSearchOpacity()
        }
        
        // 3. Setup/Update Footer
        if footerView == nil {
            let fv = FooterMenuItemView(appDelegate: appDelegate)
            footerContainer.addSubview(fv)
            fv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                fv.topAnchor.constraint(equalTo: footerContainer.topAnchor),
                fv.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
                fv.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
                fv.bottomAnchor.constraint(equalTo: footerContainer.bottomAnchor),
                footerContainer.heightAnchor.constraint(equalToConstant: Constants.menuHeaderFooterHeight)
            ])
            self.footerView = fv
        }
        footerView?.updateRepoCount()
        
        // 4. Get and Sort Data
        let config = ConfigManager.shared.config
        let isSortedByName = config.sortBy == "name"
        var currentLayout = config.menuLayout ?? "columns"
        
        if currentLayout == "hybrid" {
            currentLayout = "columns"
            ConfigManager.shared.config.menuLayout = "columns"
            ConfigManager.shared.saveConfig()
        }
        
        let lowerQuery = appDelegate.currentSearchQuery.lowercased()
        let filteredRepos = config.repos.filter { repo in
            if lowerQuery.isEmpty { return true }
            let name = repo.name.lowercased()
            let tags = repo.tags?.map { $0.lowercased() } ?? []
            return name.contains(lowerQuery) || tags.contains(where: { $0.contains(lowerQuery) })
        }
        
        var sortedRepos = filteredRepos
        if isSortedByName {
            sortedRepos.sort { $0.name.split(separator: "/").last?.lowercased() ?? "" < $1.name.split(separator: "/").last?.lowercased() ?? "" }
        } else {
            sortedRepos.sort { r1, r2 in
                let (_, s1) = Utils.getReleaseAge(dateString: appDelegate.repoCache[r1.name]?.date)
                let (_, s2) = Utils.getReleaseAge(dateString: appDelegate.repoCache[r2.name]?.date)
                return s1 < s2
            }
        }
        sortedRepos.sort { r1, r2 in
            let e1 = appDelegate.repoCache[r1.name]?.error != nil
            let e2 = appDelegate.repoCache[r2.name]?.error != nil
            if e1 != e2 { return !e1 }
            return false
        }
        
        // 5. Build Row Views & Calculate Target Width
        let baseFontSize = config.menuFontSize ?? Constants.menuBaseFontSize
        let rowHeight: CGFloat = (currentLayout == "cards") ? baseFontSize + 27 : baseFontSize + 9
        
        var maxNameWidth: CGFloat = 0
        var maxVersionWidth: CGFloat = 0
        let nameFont = NSFont.systemFont(ofSize: baseFontSize, weight: .bold)
        let versionFont = NSFont.systemFont(ofSize: baseFontSize - 2, weight: .medium)
        let attrs: (NSFont) -> [NSAttributedString.Key: Any] = { [.font: $0] }

        for repoObj in sortedRepos {
            let info = appDelegate.repoCache[repoObj.name] ?? RepoInfo(name: repoObj.name, error: nil)
            var formattedName = repoObj.name
            if !config.showOwner {
                formattedName = String(repoObj.name.split(separator: "/").last ?? Substring(repoObj.name))
            }
            let nameSize = (formattedName as NSString).size(withAttributes: attrs(nameFont))
            maxNameWidth = max(maxNameWidth, nameSize.width)
            let verText = info.version ?? "…"
            let verSize = (verText as NSString).size(withAttributes: attrs(versionFont))
            maxVersionWidth = max(maxVersionWidth, verSize.width)
        }
        
        let rowContentWidth = maxNameWidth + maxVersionWidth + 120 // padding/icons
        let targetWidth = min(Constants.menuMaxWidth, max(Constants.menuDefaultWidth, rowContentWidth))
        self.lastTargetWidth = targetWidth
        
        if sortedRepos.isEmpty {
            let isSearching = !(appDelegate.searchField?.stringValue.isEmpty ?? true)
            noSearchResultsView?.targetWidth = targetWidth
            noSearchResultsView?.configure(suggestedTags: appDelegate.popularTagsCache, isSearching: isSearching)
            noSearchResultsView?.isHidden = false
            tableView.isHidden = true
            scrollView.isHidden = true
            self.tableRepos = []
        } else {
            noSearchResultsView?.isHidden = true
            tableView.isHidden = false
            scrollView.isHidden = false
            
            var newTableData: [RepoDisplayData] = []
            for repoObj in sortedRepos {
                let repoName = repoObj.name
                let info = appDelegate.repoCache[repoName] ?? RepoInfo(name: repoName, error: nil)
                
                var formattedName = repoName
                if !config.showOwner {
                    formattedName = String(repoName.split(separator: "/").last ?? Substring(repoName))
                }
                
                let isError = info.error != nil && !info.error!.isEmpty
                let isLoading = info.version == nil && !isError
                let ageInfo = Utils.getReleaseAge(dateString: info.date)
                
                let lastSeenVersions = UserDefaults.standard.dictionary(forKey: "LastSeenVersions") as? [String: String] ?? [:]
                var isNewUpdate = false
                if !isLoading && !isError {
                    if let currentVersion = info.version, lastSeenVersions[repoName] != currentVersion {
                        isNewUpdate = true
                    }
                }
                
                let daysDiff = ageInfo.seconds.isInfinite ? Int.max : Int(ageInfo.seconds / 86400)
                let thresholdDays = config.newIndicatorDays ?? Constants.newReleaseThresholdDays
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
                    ageLabel: isLoading ? nil : ageInfo.label,
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
                newTableData.append(data)
            }
            
            self.tableRepos = newTableData
            self.lastRowHeight = rowHeight
            tableView.reloadData()
        }
        
        // 7. Finalize
        self.view.layoutSubtreeIfNeeded()
        updatePreferredContentSize()
        
        // Ensure highlights update correctly as items move under a stationary mouse
        updateHighlightUnderMouse()
    }
    
    func updatePreferredContentSize() {
        let visibleItemsHeight: CGFloat
        if tableRepos.isEmpty && noSearchResultsView?.isHidden == false {
            // Force layout of the tag cloud so its fittingSize is accurate
            noSearchResultsView?.layoutSubtreeIfNeeded()
            visibleItemsHeight = noSearchResultsView?.intrinsicContentSize.height ?? 0
        } else {
            // Use the table height
            visibleItemsHeight = CGFloat(tableRepos.count) * lastRowHeight
        }
        
        let targetScrollHeight = min(visibleItemsHeight, 600)
        
        scrollView.constraints.filter { $0.firstAttribute == .height }.forEach { scrollView.removeConstraint($0) }
        scrollView.heightAnchor.constraint(equalToConstant: targetScrollHeight).isActive = true
        
        let targetWidth = self.lastTargetWidth ?? Constants.menuDefaultWidth
        let headerFooterHeight = Constants.menuHeaderFooterHeight * 2
        self.preferredContentSize = NSSize(width: targetWidth, height: targetScrollHeight + headerFooterHeight)
        
        if let nrv = noSearchResultsView {
            nrv.targetWidth = targetWidth
        }
    }
    
    private var lastTargetWidth: CGFloat?
    
    var noSearchResultsView: NoSearchResultsView?
    var repoViews: [RepoMenuItemView] {
        // Return only currently visible rows
        var views: [RepoMenuItemView] = []
        tableView.enumerateAvailableRowViews { rowView, row in
            if let cell = rowView.view(atColumn: 0) as? RepoMenuItemView {
                views.append(cell)
            }
        }
        return views
    }
}

extension MainPopoverViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return tableRepos.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let appDelegate = appDelegate, row < tableRepos.count else { return nil }
        let data = tableRepos[row]
        let config = ConfigManager.shared.config
        let currentLayout = config.menuLayout ?? "columns"
        
        let identifier = NSUserInterfaceItemIdentifier("RepoRow")
        var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? RepoMenuItemView
        
        if cellView == nil {
            cellView = RepoMenuItemView(repoName: data.repoName, displayData: data, layout: currentLayout, appDelegate: appDelegate)
            cellView?.identifier = identifier
        } else {
            // Since RepoMenuItemView is complex and its layout is set in init,
            // for now we re-init if the layout changed, otherwise we could update data.
            // But to be 100% safe with virtualization and the current RepoMenuItemView implementation,
            // we'll just create a new one. In a future refactor, we'd add an 'update(with:)' method.
            cellView = RepoMenuItemView(repoName: data.repoName, displayData: data, layout: currentLayout, appDelegate: appDelegate)
            cellView?.identifier = identifier
        }
        
        return cellView
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return lastRowHeight
    }
}

class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// Specialized flipped view to ensure top-to-bottom layout for tag clouds
class MainPopoverFlippedView: NSView {
    override var isFlipped: Bool { true }
}


