import Cocoa

@MainActor
class HeaderMenuItemView: NSView {
    
    private let refreshLabel = NSTextField(labelWithString: "")
    private let refreshIcon = NSImageView()
    private let addBtn = MenuActionButton()
    
    private let quickAddLabel = NSTextField(labelWithString: "")
    private var quickAddRepoStr: String? = nil
    
    private let leftStack = NSStackView()
    private let refreshHitArea = NSButton()
    private let quickAddHitArea = NSButton()
    
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
        
        // Refresh Hit area
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
        
        // Quick Add Label (Clipboard)
        quickAddLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        quickAddLabel.textColor = .controlAccentColor
        quickAddLabel.translatesAutoresizingMaskIntoConstraints = false
        quickAddLabel.lineBreakMode = .byTruncatingMiddle
        quickAddLabel.isHidden = true
        
        // Quick Add Hit Area (makes the text clickable)
        quickAddHitArea.isTransparent = true
        quickAddHitArea.target = self
        quickAddHitArea.action = #selector(addClicked)
        quickAddHitArea.translatesAutoresizingMaskIntoConstraints = false
        quickAddHitArea.isHidden = true
        
        leftStack.addArrangedSubview(refreshIcon)
        leftStack.addArrangedSubview(refreshLabel)
        leftStack.orientation = .horizontal
        leftStack.spacing = 6
        leftStack.alignment = .centerY
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(leftStack)
        addSubview(refreshHitArea)
        addSubview(quickAddLabel)
        addSubview(quickAddHitArea)
        addSubview(addBtn)
        
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: addBtn.leadingAnchor, constant: -10),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            refreshHitArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            refreshHitArea.trailingAnchor.constraint(equalTo: leftStack.trailingAnchor, constant: 5),
            refreshHitArea.topAnchor.constraint(equalTo: topAnchor),
            refreshHitArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            quickAddLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            quickAddLabel.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -10),
            quickAddLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            quickAddHitArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            quickAddHitArea.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor),
            quickAddHitArea.topAnchor.constraint(equalTo: topAnchor),
            quickAddHitArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            addBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            addBtn.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    func updateClipboardState(repo: String?) {
        self.quickAddRepoStr = repo
        if let r = repo {
            // Hide Refresh
            leftStack.isHidden = true
            refreshHitArea.isHidden = true
            
            // Show Quick Add
            quickAddLabel.stringValue = r
            quickAddLabel.isHidden = false
            quickAddHitArea.isHidden = false
            
            let tip = Translations.get("quickAdd").replacingOccurrences(of: "{repo}", with: r)
            addBtn.toolTip = tip
            quickAddHitArea.toolTip = tip
            addBtn.baseColor = .controlAccentColor
            addBtn.hoverColor = .controlAccentColor
        } else {
            // Show Refresh
            leftStack.isHidden = false
            refreshHitArea.isHidden = false
            
            // Hide Quick Add
            quickAddLabel.isHidden = true
            quickAddHitArea.isHidden = true
            
            addBtn.toolTip = Translations.get("addRepoUnified")
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
