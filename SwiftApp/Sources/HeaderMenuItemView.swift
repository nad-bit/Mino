import Cocoa

@MainActor
class HeaderMenuItemView: NSView {
    
    private let refreshBtn = MenuActionButton()
    private let addBtn = MenuActionButton()
    public var searchField: MenuSearchField!
    
    private let quickAddLabel = NSTextField(labelWithString: "")
    private var quickAddRepoStr: String? = nil
    
    private let leftStack = NSStackView()
    private let quickAddHitArea = NSButton()
    
    private let appDelegate: AppDelegate
    
    // Track states
    private var lastHighlightState = false
    private var isRefreshingState = false
    
    // Constraints for dynamic swapping
    private var quickAddTrailingToSearch: NSLayoutConstraint?
    private var quickAddTrailingToAddBtn: NSLayoutConstraint?
    private var quickAddHitAreaTrailingToSearch: NSLayoutConstraint?
    private var quickAddHitAreaTrailingToAddBtn: NSLayoutConstraint?
    
    /// Target width set by AppDelegate after calculating menu size
    private var widthConstraint: NSLayoutConstraint?
    var targetWidth: CGFloat = 320 {
        didSet {
            widthConstraint?.constant = targetWidth
            widthConstraint?.isActive = true
        }
    }
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 30))
        self.autoresizingMask = [.width]
        self.wantsLayer = true
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // Refresh Button
        let refreshConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        refreshBtn.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")?.withSymbolConfiguration(refreshConfig)
        refreshBtn.isBordered = false
        refreshBtn.target = self
        refreshBtn.action = #selector(refreshClicked)
        refreshBtn.baseColor = .secondaryLabelColor
        refreshBtn.hoverColor = .labelColor
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // Add Button
        let addConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        addBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Repository")?.withSymbolConfiguration(addConfig)
        addBtn.isBordered = false
        addBtn.target = self
        addBtn.action = #selector(addClicked)
        addBtn.toolTip = Translations.get("addRepoUnified")
        addBtn.baseColor = .secondaryLabelColor
        addBtn.hoverColor = .labelColor
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // Search Field (Setup moved here since it was removed from refresh config block)
        self.searchField = MenuSearchField(appDelegate: appDelegate)
        searchField.placeholderString = Translations.get("search")
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 11)
        searchField.alignment = .center
        searchField.focusRingType = .none
        searchField.translatesAutoresizingMaskIntoConstraints = false
        
        searchField.wantsLayer = true
        searchField.alphaValue = 0.5
        searchField.isHidden = false
        
        // Quick Add Label (Clipboard)
        quickAddLabel.font = .systemFont(ofSize: 11, weight: .medium)
        quickAddLabel.textColor = .secondaryLabelColor
        quickAddLabel.lineBreakMode = .byTruncatingMiddle
        quickAddLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        quickAddLabel.translatesAutoresizingMaskIntoConstraints = false
        quickAddLabel.isHidden = true
        
        // Quick Add Hit Area (makes the text clickable)
        quickAddHitArea.isTransparent = true
        quickAddHitArea.target = self
        quickAddHitArea.action = #selector(addClicked)
        quickAddHitArea.translatesAutoresizingMaskIntoConstraints = false
        quickAddHitArea.isHidden = true
        
        leftStack.addArrangedSubview(refreshBtn)
        leftStack.orientation = .horizontal
        leftStack.spacing = 6
        leftStack.alignment = .centerY
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(leftStack)
        addSubview(quickAddLabel)
        addSubview(quickAddHitArea)
        addSubview(searchField)
        addSubview(addBtn)
        
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            searchField.centerXAnchor.constraint(equalTo: centerXAnchor),
            searchField.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.3),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            quickAddLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            quickAddLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            quickAddHitArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            quickAddHitArea.topAnchor.constraint(equalTo: topAnchor),
            quickAddHitArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            addBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            addBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 24),
            addBtn.heightAnchor.constraint(equalToConstant: 24),
            
            refreshBtn.widthAnchor.constraint(equalToConstant: 24),
            refreshBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        // Define swappable constraints
        quickAddTrailingToSearch = quickAddLabel.trailingAnchor.constraint(equalTo: searchField.leadingAnchor, constant: -10)
        quickAddTrailingToAddBtn = quickAddLabel.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -10)
        
        quickAddHitAreaTrailingToSearch = quickAddHitArea.trailingAnchor.constraint(equalTo: searchField.leadingAnchor)
        quickAddHitAreaTrailingToAddBtn = quickAddHitArea.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -10)
        
        // Initial state: Search is dominant
        quickAddTrailingToSearch?.isActive = true
        quickAddHitAreaTrailingToSearch?.isActive = true
        
        // Define width constraint (initially inactive until targetWidth is set)
        widthConstraint = widthAnchor.constraint(equalToConstant: 320)
    }
    
    func updateClipboardState(repo: String?) {
        self.quickAddRepoStr = repo
        if let r = repo {
            // Hide Refresh
            leftStack.isHidden = true
            
            // Show Quick Add
            quickAddLabel.stringValue = Translations.get("quickAddHead").format(with: ["repo": r])
            quickAddLabel.isHidden = false
            quickAddHitArea.isHidden = false
            
            let tip = Translations.get("quickAdd").format(with: ["repo": r])
            addBtn.toolTip = tip
            quickAddHitArea.toolTip = tip
            
            // Layout Swap: Use full width
            quickAddTrailingToSearch?.isActive = false
            quickAddHitAreaTrailingToSearch?.isActive = false
            
            quickAddTrailingToAddBtn?.isActive = true
            quickAddHitAreaTrailingToAddBtn?.isActive = true
            
            searchField.isHidden = true
        } else {
            // Show Refresh
            leftStack.isHidden = false
            
            searchField.isHidden = false
            updateSearchOpacity()
            
            // Layout Swap: Revert to restricted width
            quickAddTrailingToAddBtn?.isActive = false
            quickAddHitAreaTrailingToAddBtn?.isActive = false
            
            quickAddTrailingToSearch?.isActive = true
            quickAddHitAreaTrailingToSearch?.isActive = true
            
            // Hide Quick Add
            quickAddLabel.isHidden = true
            quickAddHitArea.isHidden = true
            
            addBtn.toolTip = Translations.get("addRepoUnified")
        }
        
        let shouldHighlightStyle = lastHighlightState && quickAddRepoStr != nil
        applyHighlightState(shouldHighlightStyle)
        needsDisplay = true
    }
    
    func setSearchVisible(_ visible: Bool) {
        // Not used anymore for Stealth Search, but kept for safe compilation if referenced
        if visible {
            updateSearchOpacity()
        }
    }
    
    func updateSearchOpacity() {
        let hasText = !searchField.stringValue.isEmpty
        let targetAlpha: CGFloat = hasText ? 1.0 : 0.5
        
        if searchField.alphaValue != targetAlpha {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                searchField.animator().alphaValue = targetAlpha
            }
        }
    }
    
    func updateTimeText(_ text: String, isRefreshing: Bool) {
        if refreshBtn.toolTip != text {
            refreshBtn.toolTip = text
        }
        self.isRefreshingState = isRefreshing
        let shouldHighlightStyle = lastHighlightState && quickAddRepoStr != nil
        applyHighlightState(shouldHighlightStyle)
    }
    
    func menuDidChangeHighlight(highlightedItem: NSMenuItem?) {
        let highlighted = (highlightedItem === enclosingMenuItem)
        if highlighted != lastHighlightState {
            lastHighlightState = highlighted
            
            // Proactively refresh tooltip when hovering to ensure absolute freshness
            if highlighted && quickAddRepoStr == nil {
                updateTimeText(appDelegate.getRefreshTitle(), isRefreshing: appDelegate.isRefreshing)
            }
            
            let shouldHighlightStyle = highlighted && quickAddRepoStr != nil
            applyHighlightState(shouldHighlightStyle)
            needsDisplay = true
        }
    }
    
    private func applyHighlightState(_ highlighted: Bool) {
        let baseSecondary: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let hoverSecondary: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        
        let baseTertiary: NSColor = highlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
        let hoverTertiary: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        
        refreshBtn.baseColor = isRefreshingState ? baseTertiary : baseSecondary
        refreshBtn.hoverColor = isRefreshingState ? hoverTertiary : hoverSecondary
        
        addBtn.baseColor = baseSecondary
        addBtn.hoverColor = hoverSecondary
        
        quickAddLabel.textColor = baseSecondary
    }
    
    @objc private func refreshClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            // Note: We intentionally don't close the menu for refresh
            DispatchQueue.main.async {
                self.appDelegate.triggerFullRefresh(menuItem)
            }
        }
    }
    
    @objc private func addClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            appDelegate.performAfterMenuClose {
                if let repo = self.quickAddRepoStr {
                    self.appDelegate.quickAddingRepo = repo
                    Task {
                        let _ = await self.appDelegate.addRepoSmart(repoName: repo)
                        await MainActor.run {
                            self.appDelegate.quickAddingRepo = nil
                        }
                    }
                } else {
                    self.appDelegate.unifiedAddRepoDialog(menuItem)
                }
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let shouldHighlightStyle = lastHighlightState && quickAddRepoStr != nil
        if shouldHighlightStyle {
            NSColor.selectedContentBackgroundColor.set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4)
            path.fill()
        }
        super.draw(dirtyRect)
    }
}
