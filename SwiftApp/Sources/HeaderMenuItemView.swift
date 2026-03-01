import Cocoa

@MainActor
class HeaderMenuItemView: NSView {
    
    private let refreshLabel = NSTextField(labelWithString: "")
    private let refreshIcon = NSImageView()
    private let addBtn = MenuActionButton()
    
    private let quickAddLabel = NSTextField(labelWithString: "")
    private var quickAddRepoStr: String? = nil
    
    // Transparent button overlay for the refresh section (so it's clickable)
    private let refreshHitArea = NSButton()
    
    private let appDelegate: AppDelegate
    
    // Track states
    private var lastHighlightState = false
    private var isRefreshingState = false
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // Refresh Icon
        let refreshConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        refreshIcon.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")?.withSymbolConfiguration(refreshConfig)
        refreshIcon.contentTintColor = .secondaryLabelColor
        refreshIcon.translatesAutoresizingMaskIntoConstraints = false
        
        // Refresh Label (Countdown)
        refreshLabel.font = .systemFont(ofSize: 11, weight: .medium)
        refreshLabel.textColor = .secondaryLabelColor
        refreshLabel.translatesAutoresizingMaskIntoConstraints = false
        refreshLabel.lineBreakMode = .byTruncatingTail
        
        // Hit area for refreshing
        refreshHitArea.isTransparent = true
        refreshHitArea.target = self
        refreshHitArea.action = #selector(refreshClicked)
        refreshHitArea.translatesAutoresizingMaskIntoConstraints = false
        
        // Add Button
        let addConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        addBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Repository")?.withSymbolConfiguration(addConfig)
        addBtn.isBordered = false
        addBtn.target = self
        addBtn.action = #selector(addClicked)
        addBtn.toolTip = Translations.get("addRepoUnified")
        addBtn.baseColor = .labelColor
        addBtn.hoverColor = .labelColor
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // Quick Add Label (Clipboard)
        quickAddLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        quickAddLabel.textColor = .controlAccentColor
        quickAddLabel.translatesAutoresizingMaskIntoConstraints = false
        quickAddLabel.lineBreakMode = .byTruncatingMiddle
        quickAddLabel.isHidden = true
        
        let leftStack = NSStackView(views: [refreshIcon, refreshLabel])
        leftStack.orientation = .horizontal
        leftStack.spacing = 6
        leftStack.alignment = .centerY
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(leftStack)
        addSubview(refreshHitArea)
        addSubview(quickAddLabel)
        addSubview(addBtn)
        
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // Hit area covers the left stack entirely
            refreshHitArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            refreshHitArea.trailingAnchor.constraint(equalTo: leftStack.trailingAnchor, constant: 10),
            refreshHitArea.topAnchor.constraint(equalTo: topAnchor),
            refreshHitArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            quickAddLabel.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -10),
            quickAddLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            quickAddLabel.leadingAnchor.constraint(greaterThanOrEqualTo: refreshHitArea.trailingAnchor, constant: 10),
            
            addBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    func updateClipboardState(repo: String?) {
        self.quickAddRepoStr = repo
        if let r = repo {
            quickAddLabel.stringValue = r
            quickAddLabel.isHidden = false
            addBtn.toolTip = "Quick Add \(r)"
            addBtn.baseColor = .controlAccentColor
            addBtn.hoverColor = .controlAccentColor
        } else {
            quickAddLabel.isHidden = true
            addBtn.toolTip = Translations.get("addRepoUnified")
            // Reset to default colors
            applyHighlightState(lastHighlightState)
        }
    }
    
    func updateTimeText(_ text: String, isRefreshing: Bool) {
        refreshLabel.stringValue = text
        self.isRefreshingState = isRefreshing
        applyHighlightState(lastHighlightState)
    }
    
    func menuDidChangeHighlight(highlightedItem: NSMenuItem?) {
        let highlighted = (highlightedItem === enclosingMenuItem)
        if highlighted != lastHighlightState {
            lastHighlightState = highlighted
            applyHighlightState(highlighted)
            needsDisplay = true
        }
    }
    
    private func applyHighlightState(_ highlighted: Bool) {
        let mainColor: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        let secondaryColor: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let tertiaryColor: NSColor = highlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
        
        refreshLabel.textColor = isRefreshingState ? tertiaryColor : secondaryColor
        refreshIcon.contentTintColor = isRefreshingState ? tertiaryColor : secondaryColor
        
        refreshIcon.contentTintColor = isRefreshingState ? tertiaryColor : secondaryColor
        
        if quickAddRepoStr == nil {
            addBtn.baseColor = mainColor
            addBtn.hoverColor = mainColor
        }
    }
    
    @objc private func refreshClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            appDelegate.menu.cancelTracking()
            appDelegate.triggerFullRefresh(menuItem)
        }
    }
    
    @objc private func addClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            appDelegate.menu.cancelTracking()
            
            if let repo = quickAddRepoStr {
                appDelegate.addRepoSmart(repoName: repo)
            } else {
                appDelegate.unifiedAddRepoDialog(menuItem)
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if lastHighlightState {
            NSColor.selectedContentBackgroundColor.set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4)
            path.fill()
        }
        super.draw(dirtyRect)
    }
}
