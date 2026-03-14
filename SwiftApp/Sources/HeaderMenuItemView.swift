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
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
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
        addBtn.baseColor = .labelColor
        addBtn.hoverColor = .labelColor
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // Search Field (Setup moved here since it was removed from refresh config block)
        self.searchField = MenuSearchField(appDelegate: appDelegate)
        searchField.placeholderString = Translations.get("search")
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 11)
        searchField.focusRingType = .none
        searchField.translatesAutoresizingMaskIntoConstraints = false
        
        searchField.wantsLayer = true
        searchField.alphaValue = 0.25
        searchField.isHidden = false
        
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
            quickAddLabel.trailingAnchor.constraint(equalTo: searchField.leadingAnchor, constant: -10),
            quickAddLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            quickAddHitArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            quickAddHitArea.trailingAnchor.constraint(equalTo: searchField.leadingAnchor),
            quickAddHitArea.topAnchor.constraint(equalTo: topAnchor),
            quickAddHitArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            addBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            addBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 24),
            addBtn.heightAnchor.constraint(equalToConstant: 24),
            
            // Explicit size for refreshBtn to ensure hover background is nicely squared
            refreshBtn.widthAnchor.constraint(equalToConstant: 24),
            refreshBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
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
            addBtn.baseColor = .controlAccentColor
            addBtn.hoverColor = .controlAccentColor
            
            // Hide search if it overlaps? For now 30% centered should be fine.
            // But let's be safe and hide search if quickAdd is active to prioritize it.
            searchField.isHidden = true
        } else {
            // Show Refresh
            leftStack.isHidden = false
            
            searchField.isHidden = false
            updateSearchOpacity()
            
            // Hide Quick Add
            quickAddLabel.isHidden = true
            quickAddHitArea.isHidden = true
            
            addBtn.toolTip = Translations.get("addRepoUnified")
            applyHighlightState(lastHighlightState)
        }
    }
    
    func setSearchVisible(_ visible: Bool) {
        // Not used anymore for Stealth Search, but kept for safe compilation if referenced
        if visible {
            updateSearchOpacity()
        }
    }
    
    func updateSearchOpacity() {
        let hasText = !searchField.stringValue.isEmpty
        let targetAlpha: CGFloat = hasText ? 1.0 : 0.25
        
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
        applyHighlightState(lastHighlightState)
    }
    
    func menuDidChangeHighlight(highlightedItem: NSMenuItem?) {
        let highlighted = (highlightedItem === enclosingMenuItem)
        if highlighted != lastHighlightState {
            lastHighlightState = highlighted
            
            // Proactively refresh tooltip when hovering to ensure absolute freshness
            if highlighted && quickAddRepoStr == nil {
                updateTimeText(appDelegate.getRefreshTitle(), isRefreshing: appDelegate.isRefreshing)
            }
            
            applyHighlightState(highlighted)
            needsDisplay = true
        }
    }
    
    private func applyHighlightState(_ highlighted: Bool) {
        let mainColor: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        let secondaryColor: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let tertiaryColor: NSColor = highlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
        
        refreshBtn.baseColor = isRefreshingState ? tertiaryColor : secondaryColor
        refreshBtn.hoverColor = isRefreshingState ? tertiaryColor : secondaryColor
        
        if quickAddRepoStr == nil {
            addBtn.baseColor = mainColor
            addBtn.hoverColor = mainColor
        }
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
        if lastHighlightState {
            NSColor.selectedContentBackgroundColor.set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4)
            path.fill()
        }
        super.draw(dirtyRect)
    }
}
