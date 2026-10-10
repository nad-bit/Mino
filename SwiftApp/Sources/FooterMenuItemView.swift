import Cocoa

@MainActor
class FooterMenuItemView: NSView {
    
    let refreshBtn = MenuActionButton()
    private let quitBtn = MenuActionButton()
    private let repoCountLabel = NSTextField(labelWithString: "")
    private let appDelegate: AppDelegate
    
    // Track states
    private var lastHighlightState = false
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.menuWidth, height: Constants.menuHeaderFooterHeight)) // slightly taller for safe framing at bottom
        self.autoresizingMask = [.width]
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // Refresh Button
        let config = NSImage.SymbolConfiguration(pointSize: Constants.menuBaseFontSize - 2, weight: .semibold)
        refreshBtn.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")?.withSymbolConfiguration(config)
        refreshBtn.isBordered = false
        refreshBtn.target = self
        refreshBtn.action = #selector(refreshClicked)
        refreshBtn.baseColor = .secondaryLabelColor
        refreshBtn.hoverColor = .labelColor
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // Quit Button
        quitBtn.image = NSImage(systemSymbolName: "power", accessibilityDescription: Translations.get("quit"))?.withSymbolConfiguration(config)
        quitBtn.isBordered = false
        quitBtn.target = self
        quitBtn.action = #selector(quitClicked)
        quitBtn.toolTip = Translations.get("quit")
        quitBtn.baseColor = .secondaryLabelColor
        quitBtn.hoverColor = .labelColor
        quitBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // Repo Count Label
        repoCountLabel.font = .systemFont(ofSize: Constants.menuBaseFontSize - 2)
        repoCountLabel.textColor = .tertiaryLabelColor
        repoCountLabel.alignment = .center
        repoCountLabel.isBezeled = false
        repoCountLabel.isEditable = false
        repoCountLabel.drawsBackground = false
        repoCountLabel.lineBreakMode = .byTruncatingTail
        repoCountLabel.translatesAutoresizingMaskIntoConstraints = false
        
        updateRepoCount()
        
        addSubview(refreshBtn)
        addSubview(quitBtn)
        addSubview(repoCountLabel)
        
        let btnSize = (ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize) + 10
        
        NSLayoutConstraint.activate([
            refreshBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            refreshBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            refreshBtn.widthAnchor.constraint(equalToConstant: btnSize),
            refreshBtn.heightAnchor.constraint(equalToConstant: btnSize),
            
            quitBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            quitBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            quitBtn.widthAnchor.constraint(equalToConstant: btnSize),
            quitBtn.heightAnchor.constraint(equalToConstant: btnSize),
            
            repoCountLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            repoCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            repoCountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: refreshBtn.trailingAnchor, constant: 8),
            repoCountLabel.trailingAnchor.constraint(lessThanOrEqualTo: quitBtn.leadingAnchor, constant: -8)
        ])
        
        updateFontSize()
    }
    
    func updateFontSize() {
        let baseFontSize = (ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize) * Constants.menuScale
        let btnSize = baseFontSize + (10 * Constants.menuScale)
        
        let config = NSImage.SymbolConfiguration(pointSize: baseFontSize - 2, weight: .semibold)
        refreshBtn.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")?.withSymbolConfiguration(config)
        refreshBtn.constraints.first(where: { $0.firstAttribute == .width })?.constant = btnSize
        refreshBtn.constraints.first(where: { $0.firstAttribute == .height })?.constant = btnSize
        
        quitBtn.image = NSImage(systemSymbolName: "power", accessibilityDescription: Translations.get("quit"))?.withSymbolConfiguration(config)
        quitBtn.constraints.first(where: { $0.firstAttribute == .width })?.constant = btnSize
        quitBtn.constraints.first(where: { $0.firstAttribute == .height })?.constant = btnSize
        
        repoCountLabel.font = .systemFont(ofSize: baseFontSize - 2)
    }
    
    private var lastRefreshTitle: String = ""
    
    /// Refreshes the repo count label from the current config and updates the Cask count tooltip.
    func updateRepoCount(filteredCount: Int? = nil, totalCount: Int? = nil, filteredCaskCount: Int? = nil) {
        let allRepos = ConfigManager.shared.config.repos
        let totalCasks = allRepos.filter { $0.source == "brew" }.count
        
        if let filtered = filteredCount, let total = totalCount {
            let template = Translations.get("repoCount")
            repoCountLabel.stringValue = template.format(with: ["count": "\(filtered)/\(total)"])
            
            let filteredCasks = filteredCaskCount ?? filtered
            let caskTemplate = Translations.get("caskCount")
            repoCountLabel.toolTip = caskTemplate.format(with: ["count": "\(filteredCasks)/\(totalCasks)"])
        } else {
            let count = allRepos.count
            if count == 1 {
                repoCountLabel.stringValue = Translations.get("repoCountSingular")
            } else {
                repoCountLabel.stringValue = Translations.get("repoCount").format(with: ["count": "\(count)"])
            }
            
            if totalCasks == 1 {
                repoCountLabel.toolTip = Translations.get("caskCountSingular")
            } else {
                repoCountLabel.toolTip = Translations.get("caskCount").format(with: ["count": "\(totalCasks)"])
            }
        }
        self.toolTip = nil
        updateRefreshTooltip()
    }
    
    /// Updates the tooltip of the refresh button combining refresh countdown/title and last update timestamp.
    func updateRefreshTooltip(lastRefreshDate: Date? = nil) {
        let date = lastRefreshDate ?? appDelegate.refreshCoordinator.lastRefreshTime
        let lastUpdateText: String
        if date == Date.distantPast {
            lastUpdateText = Translations.get("lastUpdateNever")
        } else {
            let timeStr: String
            if Calendar.current.isDateInToday(date) {
                timeStr = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
            } else {
                timeStr = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
            }
            lastUpdateText = Translations.get("lastUpdate").format(with: ["time": timeStr])
        }
        
        let title = lastRefreshTitle.isEmpty ? Translations.get("refreshNow") : lastRefreshTitle
        refreshBtn.toolTip = "\(title)\n\(lastUpdateText)"
    }
    
    func updateLastRefreshTooltip(lastRefreshDate: Date? = nil) {
        updateRefreshTooltip(lastRefreshDate: lastRefreshDate)
    }
    
    @objc private func refreshClicked() {
        DispatchQueue.main.async {
            self.appDelegate.triggerFullRefresh(self)
        }
    }
    
    func updateTimeText(_ text: String, isRefreshing: Bool) {
        lastRefreshTitle = text
        refreshBtn.baseColor = isRefreshing ? .tertiaryLabelColor : .secondaryLabelColor
        refreshBtn.needsDisplay = true
        updateRefreshTooltip()
    }
    
    @objc private func quitClicked() {
        appDelegate.animateStatusIcon(with: .scale)
        appDelegate.mainPopover?.close()
        self.appDelegate.quitApp(self)
    }
    
    func menuDidChangeHighlight(highlightedItem: Any?) {
        // No full-row highlight for footer, buttons handle their own hover.
        // But reset hover state on all buttons to avoid stale highlights
        // when the menu is closed mid-hover via a click.
        refreshBtn.resetHoverState()
        quitBtn.resetHoverState()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
}
