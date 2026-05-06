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
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.menuMinWidth, height: Constants.menuHeaderFooterHeight)) // slightly taller for safe framing at bottom
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
        
        NSLayoutConstraint.activate([
            refreshBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            refreshBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            refreshBtn.widthAnchor.constraint(equalToConstant: 24),
            refreshBtn.heightAnchor.constraint(equalToConstant: 24),
            
            quitBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            quitBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            quitBtn.widthAnchor.constraint(equalToConstant: 24),
            quitBtn.heightAnchor.constraint(equalToConstant: 24),
            
            repoCountLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            repoCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            repoCountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: refreshBtn.trailingAnchor, constant: 8),
            repoCountLabel.trailingAnchor.constraint(lessThanOrEqualTo: quitBtn.leadingAnchor, constant: -8)
        ])
    }
    
    /// Refreshes the repo count label from the current config.
    func updateRepoCount() {
        let count = ConfigManager.shared.config.repos.count
        if count == 1 {
            repoCountLabel.stringValue = Translations.get("repoCountSingular")
        } else {
            repoCountLabel.stringValue = Translations.get("repoCount").format(with: ["count": "\(count)"])
        }
    }
    
    @objc private func refreshClicked() {
        DispatchQueue.main.async {
            self.appDelegate.triggerFullRefresh(self)
        }
    }
    
    func updateTimeText(_ text: String, isRefreshing: Bool) {
        if refreshBtn.toolTip != text {
            refreshBtn.toolTip = text
        }
        refreshBtn.baseColor = isRefreshing ? .tertiaryLabelColor : .secondaryLabelColor
        refreshBtn.needsDisplay = true
    }
    
    @objc private func quitClicked() {
        appDelegate.animateStatusIcon(with: .scale)
        appDelegate.mainPopover?.performClose(nil)
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
