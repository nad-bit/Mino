import Cocoa

@MainActor
class HeaderMenuItemView: NSView {
    
    let settingsBtn = MenuActionButton()
    private let addBtn = MenuActionButton()
    public var searchField: MenuSearchField!
    
    private let quickAddIcon = NSImageView()
    private let quickAddLabel = NSTextField(labelWithString: "")
    private let quickAddStack = NSStackView()
    internal var quickAddRepoStr: String? = nil
    
    private let leftStack = NSStackView()
    private let quickAddHitArea = NSButton()
    
    private let appDelegate: AppDelegate
    
    private var lastHighlightState = false
    private var isRefreshingState = false
    
    // Constraints for dynamic swapping
    private var quickAddTrailingToSearch: NSLayoutConstraint?
    private var quickAddTrailingToAddBtn: NSLayoutConstraint?
    private var quickAddHitAreaTrailingToSearch: NSLayoutConstraint?
    private var quickAddHitAreaTrailingToAddBtn: NSLayoutConstraint?
    
    /// Target width set by AppDelegate after calculating menu size
    private var widthConstraint: NSLayoutConstraint?
    var targetWidth: CGFloat = Constants.menuMinWidth {
        didSet {
            widthConstraint?.constant = targetWidth
            widthConstraint?.isActive = true
        }
    }
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.menuMinWidth, height: Constants.menuHeaderFooterHeight))
        self.autoresizingMask = [.width]
        self.wantsLayer = true
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // Settings Button
        let settingsConfig = NSImage.SymbolConfiguration(pointSize: Constants.menuBaseFontSize - 2, weight: .semibold)
        settingsBtn.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: Translations.get("preferences"))?.withSymbolConfiguration(settingsConfig)
        settingsBtn.isBordered = false
        settingsBtn.target = self
        settingsBtn.action = #selector(settingsClicked)
        settingsBtn.toolTip = Translations.get("preferences")
        settingsBtn.baseColor = .secondaryLabelColor
        settingsBtn.hoverColor = .labelColor
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // Add Button
        let addConfig = NSImage.SymbolConfiguration(pointSize: Constants.menuBaseFontSize, weight: .bold)
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
        searchField.font = .systemFont(ofSize: Constants.menuBaseFontSize - 2)
        searchField.alignment = .center
        searchField.focusRingType = .none
        searchField.translatesAutoresizingMaskIntoConstraints = false
        
        searchField.wantsLayer = true
        searchField.alphaValue = 0.5
        searchField.isHidden = false
        
        // Quick Add Icon
        let quickAddIconCfg = NSImage.SymbolConfiguration(pointSize: Constants.menuBaseFontSize - 1, weight: .semibold)
        quickAddIcon.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?.withSymbolConfiguration(quickAddIconCfg)
        quickAddIcon.contentTintColor = .secondaryLabelColor
        quickAddIcon.imageAlignment = .alignCenter
        quickAddIcon.imageScaling = .scaleNone
        quickAddIcon.translatesAutoresizingMaskIntoConstraints = false
        
        // Quick Add Label (Clipboard)
        quickAddLabel.font = .systemFont(ofSize: Constants.menuBaseFontSize - 2, weight: .medium)
        quickAddLabel.textColor = .secondaryLabelColor
        quickAddLabel.alignment = .center
        quickAddLabel.lineBreakMode = .byTruncatingMiddle
        // CRITICAL for truncation inside NSStackView: 
        // 1. Allow it to be compressed easily
        quickAddLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // 2. Allow it to stretch/shrink horizontally without resistance
        quickAddLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        quickAddLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Quick Add Stack - Truly centered and minimalist
        quickAddStack.addArrangedSubview(quickAddLabel)
        quickAddStack.orientation = .horizontal
        quickAddStack.spacing = 0
        quickAddStack.alignment = .centerY
        quickAddStack.distribution = .fill
        quickAddStack.translatesAutoresizingMaskIntoConstraints = false
        quickAddStack.isHidden = true
        
        // Quick Add Hit Area (makes the text clickable)
        quickAddHitArea.isTransparent = true
        quickAddHitArea.target = self
        quickAddHitArea.action = #selector(addClicked)
        quickAddHitArea.translatesAutoresizingMaskIntoConstraints = false
        quickAddHitArea.isHidden = true
        
        leftStack.addArrangedSubview(settingsBtn)
        leftStack.orientation = .horizontal
        leftStack.spacing = 6
        leftStack.alignment = .centerY
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(leftStack)
        addSubview(quickAddStack)
        addSubview(quickAddHitArea)
        addSubview(searchField)
        addSubview(addBtn)
        
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            searchField.centerXAnchor.constraint(equalTo: centerXAnchor),
            searchField.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.40),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            quickAddStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            quickAddStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            quickAddStack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
            
            quickAddHitArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            quickAddHitArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            quickAddHitArea.topAnchor.constraint(equalTo: topAnchor),
            quickAddHitArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            addBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            addBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 24),
            addBtn.heightAnchor.constraint(equalToConstant: 24),
            
            settingsBtn.widthAnchor.constraint(equalToConstant: 24),
            settingsBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        // swappable constraints no longer needed for centered layout
        
        // Initial state: Search is dominant
        updateClipboardState(repo: nil)
        
        // Define width constraint (initially inactive until targetWidth is set)
        widthConstraint = widthAnchor.constraint(equalToConstant: Constants.menuMinWidth)
    }
    
    func updateClipboardState(repo: String?, isProcessing: Bool = false) {
        self.quickAddRepoStr = repo
        
        let showQuickAdd = (repo != nil) || isProcessing
        
        if showQuickAdd {
            // Hide everything else for maximum focus
            leftStack.isHidden = true
            searchField.isHidden = true
            addBtn.isHidden = true
            
            if isProcessing, let adding = appDelegate.quickAddingRepo {
                quickAddLabel.stringValue = Translations.get("addingRepo").format(with: ["repo": adding])
            } else if let r = repo {
                quickAddLabel.stringValue = Translations.get("quickAddHead").format(with: ["repo": r])
            }
            
            quickAddStack.isHidden = false
            quickAddHitArea.isHidden = isProcessing // Disable clicks while adding
            
            let tip = (repo != nil) ? Translations.get("quickAdd").format(with: ["repo": repo!]) : ""
            quickAddHitArea.toolTip = tip
            
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        } else {
            // Restore normal header
            leftStack.isHidden = false
            searchField.isHidden = false
            addBtn.isHidden = false
            updateSearchOpacity()
            
            quickAddStack.isHidden = true
            quickAddHitArea.isHidden = true
            
            addBtn.toolTip = Translations.get("addRepoUnified")
            
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
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
                context.duration = Constants.defaultAnimationDuration
                searchField.animator().alphaValue = targetAlpha
            }
        }
    }
    

    
    func menuDidChangeHighlight(highlightedItem: Any?) {
        let highlighted = (highlightedItem as? HeaderMenuItemView) === self
        if highlighted != lastHighlightState {
            lastHighlightState = highlighted
            

            
            let shouldHighlightStyle = highlighted && quickAddRepoStr != nil
            applyHighlightState(shouldHighlightStyle)
            needsDisplay = true
        }
    }
    
    private func applyHighlightState(_ highlighted: Bool) {
        let baseSecondary: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let hoverSecondary: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        
        settingsBtn.baseColor = baseSecondary
        settingsBtn.hoverColor = hoverSecondary
        
        addBtn.baseColor = baseSecondary
        addBtn.hoverColor = hoverSecondary
        
        quickAddLabel.textColor = baseSecondary
        quickAddIcon.contentTintColor = baseSecondary
        
        // Reset hover visuals if row is no longer highlighted,
        // in case mouseExited was never delivered after a click.
        if !highlighted {
            settingsBtn.resetHoverState()
            addBtn.resetHoverState()
        }
    }
    
    @objc private func settingsClicked() {
        DispatchQueue.main.async {
            self.appDelegate.openSettingsWindow(self.settingsBtn)
        }
    }
    
    @objc func addClicked() {
        appDelegate.animateStatusIcon(with: .scale)
        if let repo = self.quickAddRepoStr {
            self.appDelegate.quickAddingRepo = repo
            self.appDelegate.refreshQuickAddState()
            Task {
                let _ = await self.appDelegate.addRepoSmart(repoName: repo)
                await MainActor.run {
                    self.appDelegate.quickAddingRepo = nil
                    self.appDelegate.refreshQuickAddState()
                }
            }
        } else {
            self.appDelegate.unifiedAddRepoDialog(self)
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
    
    private var viewTrackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = viewTrackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        viewTrackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(viewTrackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        menuDidChangeHighlight(highlightedItem: self)
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        menuDidChangeHighlight(highlightedItem: nil)
    }
}
