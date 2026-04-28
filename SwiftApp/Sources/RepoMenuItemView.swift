import Cocoa

/// Holds the pre-parsed data for building any layout mode.
struct RepoDisplayData {
    let repoName: String
    let formattedName: String
    let version: String?          // e.g. "v2.12.5"
    let ageLabel: String?         // e.g. "3 days"
    let ageSeconds: Double
    let originalDate: String?     // Raw ISO8601 date from GitHub
    let errorMessage: String?
    let isLoading: Bool
    let caskName: String?
    let freshnessColor: NSColor   // 🟢/🟡/⚪ mapped to NSColor
    let isNew: Bool
    let tags: [String]
    let isFavorite: Bool
}

class MenuActionButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    
    var baseColor: NSColor = .secondaryLabelColor {
        didSet { if !isHovered { contentTintColor = baseColor } }
    }
    var hoverColor: NSColor = .labelColor {
        didSet { if isHovered { contentTintColor = hoverColor } }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.masksToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 28, height: NSView.noIntrinsicMetric)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = self.trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        contentTintColor = hoverColor
        self.layer?.backgroundColor = hoverColor.withAlphaComponent(0.15).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        contentTintColor = baseColor
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    func resetHoverState() {
        guard isHovered else { return }
        isHovered = false
        contentTintColor = baseColor
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

@MainActor
class RepoMenuItemView: NSView {
    
    // UI Elements (common)
    private let titleLabel = NSTextField(labelWithString: "")
    private let installBtn = MenuActionButton()
    private let openReleasesBtn = MenuActionButton()
    private let notesBtn = MenuActionButton()
    private let deleteBtn = MenuActionButton()
    private let buttonStack = NSStackView()
    
    // Extra labels for multi-element layouts
    private let versionLabel = NSTextField(labelWithString: "")
    private let ageLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")   // Cards mode line 2
    private let dotLabel = NSTextField(labelWithString: "")        // Freshness dot (columns/cards with indicator ON)
    private let starLabel = NSTextField(labelWithString: "★")      // Favorite indicator (always present)
    
    /// Returns a fixed-size NSImageView with the SF Symbol warning icon.
    /// Using SF Symbol instead of ⚠️ emoji ensures the icon respects the given pointSize
    /// and never clips within a fixed-width slot.
    private func makeWarningView(pointSize: CGFloat, tooltip: String?) -> NSView {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        let iv = NSImageView(image: img ?? NSImage())
        iv.contentTintColor = .systemRed
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.toolTip = tooltip
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: 12).isActive = true
        iv.setContentHuggingPriority(.required, for: .horizontal)
        return iv
    }
    
    // Data
    private let repoName: String
    private let caskName: String?
    private let appDelegate: AppDelegate
    private let layoutMode: String
    private let baseFontSize: CGFloat
    private let originalDate: String?
    
    // Public exposure for AppDelegate search filtering
    let displayData: RepoDisplayData
    
    // Track highlight and "seen" state
    private var lastHighlightState = false
    private var wasEverHovered = false
    
    // Inline delete confirmation state
    private var isConfirmingDelete = false
    private var deleteConfirmTimer: Timer?
    
    // Column widths (for columns mode, set from outside)
    var nameColumnWidth: CGFloat = 0
    var versionColumnWidth: CGFloat = 0
    
    init(repoName: String, displayData: RepoDisplayData, layout: String, appDelegate: AppDelegate) {
        self.repoName = repoName
        self.caskName = displayData.caskName
        self.appDelegate = appDelegate
        self.layoutMode = layout
        self.baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        self.displayData = displayData
        self.originalDate = displayData.originalDate
        
        let rowHeight: CGFloat = (layout == "cards") ? baseFontSize + 27 : baseFontSize + 9
        
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: rowHeight))
        self.autoresizingMask = [.width]
        
        setupButtons()
        
        switch layout {
        case "cards":
            setupCardsView(data: displayData)
        case "tags":
            setupTagsView(data: displayData)
        case "columns":
            fallthrough
        default:
            setupColumnsView(data: displayData)
        }
        
        applyHighlightState(false, animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Button Setup (shared by all modes)
    
    private func setupButtons() {
        if caskName != nil && HomebrewManager.shared.brewPath != nil {
            setupButton(installBtn, icon: "shippingbox", action: #selector(installClicked), tooltip: Translations.get("installUpdate"))
        }
        setupButton(notesBtn, icon: "doc.text", action: #selector(notesClicked), tooltip: Translations.get("releaseNotes"))
        setupButton(openReleasesBtn, icon: "arrow.up.right.square", action: #selector(openReleasesClicked), tooltip: Translations.get("openReleases"))
        setupButton(deleteBtn, icon: "trash", action: #selector(deleteClicked), tooltip: Translations.get("deleteRepo"))
        
        let buttons = [installBtn, notesBtn, openReleasesBtn, deleteBtn].filter { $0.action != nil }
        buttonStack.setViews(buttons, in: .leading)
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 0
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupButton(_ btn: MenuActionButton, icon: String, action: Selector, tooltip: String) {
        let size: CGFloat = baseFontSize
        let imageConfig = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)?.withSymbolConfiguration(imageConfig)
        btn.isBordered = false
        btn.target = self
        btn.action = action
        btn.toolTip = tooltip
        btn.baseColor = .secondaryLabelColor
        btn.hoverColor = .labelColor
        btn.wantsLayer = true
    }
    
    // MARK: - Star Label (shared by all modes)
    
    /// Configures the ★ starLabel always present in the layout.
    /// isFavorite=true → gold; false → clear (invisible but reserves space).
    private func configureStarLabel(isFavorite: Bool, fontSize: CGFloat? = nil) {
        let size: CGFloat = fontSize ?? (baseFontSize - 2)
        starLabel.stringValue = "★"
        starLabel.font = .systemFont(ofSize: size)
        starLabel.textColor = isFavorite ? .systemYellow : .clear
        starLabel.alignment = .center
        starLabel.translatesAutoresizingMaskIntoConstraints = false
        starLabel.setContentHuggingPriority(.required, for: .horizontal)
        starLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        starLabel.widthAnchor.constraint(equalToConstant: 16).isActive = true
    }
    
    // MARK: - Layout: Tags (Single line with colorful pill)
    
    private func setupTagsView(data: RepoDisplayData) {
        // Name
        titleLabel.stringValue = data.formattedName
        titleLabel.font = .boldSystemFont(ofSize: baseFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Version Pill / Text
        // Version Pill
        configureVersionPill(data: data, layout: "tags")
        
        // Star (matches pill font size)
        configureStarLabel(isFavorite: data.isFavorite, fontSize: baseFontSize - 3)
        
        // Build content row: [⚠?] name + version/star
        var contentViews: [NSView] = []
        if data.errorMessage != nil {
            let warningView = makeWarningView(pointSize: baseFontSize - 3, tooltip: data.errorMessage)
            contentViews.append(warningView)
        }
        contentViews.append(contentsOf: [titleLabel, versionLabel, starLabel])
        
        let contentStack = NSStackView(views: contentViews)
        contentStack.orientation = .horizontal
        contentStack.spacing = 8
        contentStack.alignment = .firstBaseline
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(contentStack)
        addSubview(buttonStack)
        
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            buttonStack.topAnchor.constraint(equalTo: topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentStack.trailingAnchor, constant: 8)
        ])
    }
    
    // MARK: - Layout: Cards (two-line)
    
    private func setupCardsView(data: RepoDisplayData) {
        let showDot = ConfigManager.shared.config.showNewIndicator ?? false
        
        // Line 1: [●?] bold name + version pill
        titleLabel.stringValue = data.formattedName
        titleLabel.font = .boldSystemFont(ofSize: baseFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Version Pill
        configureVersionPill(data: data, layout: "cards")
        
        // Leading slot: error warning OR freshness dot
        var topRowViews: [NSView] = []
        if data.errorMessage != nil {
            // SF Symbol warning replaces the freshness dot
            let warningView = makeWarningView(pointSize: baseFontSize - 3, tooltip: data.errorMessage)
            topRowViews.append(warningView)
        } else if showDot {
            dotLabel.stringValue = "●"
            dotLabel.font = .systemFont(ofSize: 8)
            dotLabel.textColor = data.freshnessColor
            dotLabel.alignment = .center
            dotLabel.translatesAutoresizingMaskIntoConstraints = false
            dotLabel.setContentHuggingPriority(.required, for: .horizontal)
            dotLabel.widthAnchor.constraint(equalToConstant: 12).isActive = true
            topRowViews.append(dotLabel)
        }
        topRowViews.append(contentsOf: [titleLabel, versionLabel])
        
        let topRow = NSStackView(views: topRowViews)
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .firstBaseline
        topRow.translatesAutoresizingMaskIntoConstraints = false
        
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // Line 2: age + ★ (no error tooltip here — it's already on the triangle icon)
        if let age = data.ageLabel {
            subtitleLabel.stringValue = age
        } else if data.errorMessage != nil {
            subtitleLabel.stringValue = Translations.get("error")
        } else {
            subtitleLabel.stringValue = ""
        }
        subtitleLabel.toolTip = nil
        subtitleLabel.font = .systemFont(ofSize: baseFontSize - 2)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Star matches subtitle font size
        configureStarLabel(isFavorite: data.isFavorite, fontSize: baseFontSize - 2)
        
        let bottomRow = NSStackView(views: [subtitleLabel, starLabel])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 4
        bottomRow.alignment = .centerY
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // Vertical stack: topRow + bottomRow
        let vStack = NSStackView(views: [topRow, bottomRow])
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 1
        vStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(vStack)
        addSubview(buttonStack)
        
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            vStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            buttonStack.topAnchor.constraint(equalTo: topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: vStack.trailingAnchor, constant: 8)
        ])
    }
    
    // MARK: - Version Label Helper
    
    private func configureVersionPill(data: RepoDisplayData, layout: String) {
        let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? false
        let isCards = layout == "cards"
        let padding = isCards ? "" : " "
        let cornerRadius: CGFloat = isCards ? 4 : 6
        let fontWeight: NSFont.Weight = isCards ? .medium : .bold
        let errorWeight: NSFont.Weight = isCards ? .medium : .regular
        let errorColor: NSColor = isCards ? .tertiaryLabelColor : .secondaryLabelColor
        let pillColor: NSColor = isCards ? NSColor.systemBlue.withAlphaComponent(0.7) : (showNewIndicator ? data.freshnessColor : NSColor.systemBlue).withAlphaComponent(0.85)

        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.toolTip = nil
        versionLabel.isBezeled = false
        versionLabel.drawsBackground = false
        versionLabel.backgroundColor = .clear

        if data.errorMessage != nil {
            if let ver = data.version {
                versionLabel.stringValue = ver
                versionLabel.font = .monospacedSystemFont(ofSize: baseFontSize - 3, weight: errorWeight)
                versionLabel.textColor = errorColor
                versionLabel.alignment = .left
                versionLabel.wantsLayer = true
                versionLabel.layer?.cornerRadius = 0
                versionLabel.layer?.masksToBounds = false
                versionLabel.layer?.backgroundColor = NSColor.clear.cgColor
                versionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
                versionLabel.setContentHuggingPriority(.required, for: .horizontal)
            } else {
                versionLabel.stringValue = ""
            }
        } else if let ver = data.version {
            versionLabel.stringValue = "\(padding)\(ver)\(padding)"
            versionLabel.font = .monospacedSystemFont(ofSize: baseFontSize - 3, weight: fontWeight)
            versionLabel.textColor = .white
            versionLabel.backgroundColor = pillColor
            versionLabel.drawsBackground = true
            versionLabel.alignment = .center
            versionLabel.wantsLayer = true
            versionLabel.layer?.cornerRadius = cornerRadius
            versionLabel.layer?.masksToBounds = true
            versionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            versionLabel.setContentHuggingPriority(.required, for: .horizontal)
        } else if data.isLoading {
            versionLabel.stringValue = Translations.get("loading")
            versionLabel.font = .systemFont(ofSize: baseFontSize - 3)
            versionLabel.textColor = .secondaryLabelColor
        }
    }
    
    // MARK: - Layout: Columns (tabular, with optional color dot)
    
    private func setupColumnsView(data: RepoDisplayData) {
        let showDot = ConfigManager.shared.config.showNewIndicator ?? false
        
        // Name column
        titleLabel.stringValue = data.formattedName
        titleLabel.font = .systemFont(ofSize: baseFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Version column: grayed out if showing cached data under an error, normal otherwise
        if data.errorMessage != nil {
            if let ver = data.version {
                versionLabel.stringValue = ver
                versionLabel.textColor = .tertiaryLabelColor
            } else {
                versionLabel.stringValue = ""
            }
            versionLabel.toolTip = nil
        } else if let ver = data.version {
            versionLabel.stringValue = ver
        } else if data.isLoading {
            versionLabel.stringValue = "…"
        }
        versionLabel.font = .monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .left
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Age column
        ageLabel.stringValue = data.ageLabel ?? ""
        ageLabel.font = .systemFont(ofSize: baseFontSize - 2)
        ageLabel.textColor = .tertiaryLabelColor
        ageLabel.alignment = .right
        ageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Star
        configureStarLabel(isFavorite: data.isFavorite)
        
        // Leading slot: error warning OR freshness dot
        var rowViews: [NSView] = []
        if data.errorMessage != nil {
            // SF Symbol warning replaces the freshness dot
            let warningView = makeWarningView(pointSize: baseFontSize - 3, tooltip: data.errorMessage)
            rowViews.append(warningView)
        } else if showDot {
            dotLabel.stringValue = "●"
            dotLabel.font = .systemFont(ofSize: 8)
            dotLabel.textColor = data.freshnessColor
            dotLabel.alignment = .center
            dotLabel.translatesAutoresizingMaskIntoConstraints = false
            dotLabel.setContentHuggingPriority(.required, for: .horizontal)
            dotLabel.widthAnchor.constraint(equalToConstant: 12).isActive = true
            rowViews.append(dotLabel)
        }
        
        rowViews.append(contentsOf: [titleLabel, versionLabel, ageLabel, starLabel])
        
        let contentStack = NSStackView(views: rowViews)
        contentStack.orientation = .horizontal
        contentStack.spacing = 8
        contentStack.alignment = .centerY
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(contentStack)
        addSubview(buttonStack)
        
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        versionLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        ageLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        starLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        // Fixed-width columns for alignment across rows
        if nameColumnWidth > 0 {
            titleLabel.widthAnchor.constraint(equalToConstant: nameColumnWidth).isActive = true
        }
        if versionColumnWidth > 0 {
            versionLabel.widthAnchor.constraint(equalToConstant: versionColumnWidth).isActive = true
        }
        
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            buttonStack.topAnchor.constraint(equalTo: topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentStack.trailingAnchor, constant: 8)
        ])
    }
    
    // MARK: - Actions
    @objc private func installClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            menuItem.representedObject = caskName
            appDelegate.performAfterMenuClose {
                self.appDelegate.handleInstallBrewCask(menuItem)
            }
        }
    }
    
    @objc private func notesClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            menuItem.representedObject = repoName
            appDelegate.performAfterMenuClose {
                self.appDelegate.handleShowNotes(menuItem)
            }
        }
    }
    
    @objc private func openReleasesClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            menuItem.representedObject = repoName
            appDelegate.performAfterMenuClose {
                self.appDelegate.handleOpenReleases(menuItem)
            }
        }
    }
    
    @objc private func deleteClicked() {
        if isConfirmingDelete {
            // Second click — confirmed, execute inline delete
            deleteConfirmTimer?.invalidate()
            deleteConfirmTimer = nil
            isConfirmingDelete = false
            appDelegate.animateStatusIcon(with: .scale)
            
            // Fire-and-forget fade animation for visual polish
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.animator().alphaValue = 0
            }
            
            // Use a Timer in .common mode (fires during NSMenu tracking)
            // instead of NSAnimationContext completion handler which may not fire
            let deleteTimer = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                MainActor.assumeIsolated {
                    self.appDelegate.deleteRepoInline(repoName: self.repoName)
                }
            }
            RunLoop.main.add(deleteTimer, forMode: .common)
        } else {
            // First click — arm confirmation
            isConfirmingDelete = true
            
            // Swap icon to filled trash (armed state)
            let imageConfig = NSImage.SymbolConfiguration(pointSize: baseFontSize, weight: .medium)
            deleteBtn.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: Translations.get("confirmDelete"))?.withSymbolConfiguration(imageConfig)
            deleteBtn.contentTintColor = .white
            deleteBtn.toolTip = Translations.get("confirmDelete")
            
            // Fade out other action buttons to focus attention on confirmation
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                self.installBtn.animator().alphaValue = 0
                self.notesBtn.animator().alphaValue = 0
                self.openReleasesBtn.animator().alphaValue = 0
            }
            
            needsDisplay = true
            
            // Auto-cancel after 2s (must use .common mode to fire during NSMenu tracking)
            let timer = Timer(timeInterval: 2.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.cancelDeleteConfirm()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            deleteConfirmTimer = timer
        }
    }
    
    private func cancelDeleteConfirm() {
        guard isConfirmingDelete else { return }
        isConfirmingDelete = false
        deleteConfirmTimer?.invalidate()
        deleteConfirmTimer = nil
        
        // Restore trash icon
        let imageConfig = NSImage.SymbolConfiguration(pointSize: baseFontSize, weight: .regular)
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: Translations.get("deleteRepo"))?.withSymbolConfiguration(imageConfig)
        deleteBtn.toolTip = Translations.get("deleteRepo")
        
        // Restore normal highlight appearance
        applyHighlightState(lastHighlightState, animated: true)
        needsDisplay = true
    }
    
    // MARK: - Highlight Drawing
    
    func menuDidChangeHighlight(highlightedItem: NSMenuItem?) {
        let highlighted = (highlightedItem === enclosingMenuItem)
        if highlighted != lastHighlightState {
            lastHighlightState = highlighted
            
            if highlighted {
                wasEverHovered = true
                appDelegate.markRepoAsRead(repoName)
            }
            
            applyHighlightState(highlighted)
            needsDisplay = true
        }
    }
    
    private func applyHighlightState(_ highlighted: Bool, animated: Bool = true) {
        // Ensure buttons are always part of the layout
        if installBtn.isHidden { installBtn.isHidden = false }
        if notesBtn.isHidden { notesBtn.isHidden = false }
        if openReleasesBtn.isHidden { openReleasesBtn.isHidden = false }
        if deleteBtn.isHidden { deleteBtn.isHidden = false }

        let installAlpha: CGFloat = (caskName != nil && highlighted) ? 1.0 : 0.0
        let alpha: CGFloat = highlighted ? 1.0 : 0.0
        // During inline delete confirmation, keep deleteBtn visible and skip its hover reset
        let deleteAlpha: CGFloat = isConfirmingDelete ? 1.0 : alpha

        if !highlighted {
            installBtn.resetHoverState()
            notesBtn.resetHoverState()
            openReleasesBtn.resetHoverState()
            if !isConfirmingDelete { deleteBtn.resetHoverState() }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                
                self.installBtn.animator().alphaValue = installAlpha
                self.notesBtn.animator().alphaValue = alpha
                self.openReleasesBtn.animator().alphaValue = alpha
                self.deleteBtn.animator().alphaValue = deleteAlpha
            }
        } else {
            self.installBtn.alphaValue = installAlpha
            self.notesBtn.alphaValue = alpha
            self.openReleasesBtn.alphaValue = alpha
            self.deleteBtn.alphaValue = deleteAlpha
        }
        
        // Text colors
        let mainColor: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        let secondaryColor: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let tertiaryColor: NSColor = highlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
        
        // Button colors
        let btnBase: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let btnHover: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        
        applyOwnerDimming(to: titleLabel, baseColor: mainColor, highlighted: highlighted)
        applyOwnerDimming(to: subtitleLabel, baseColor: secondaryColor, highlighted: highlighted)
        
        // Version pill: white text in cards (inverts on highlight), secondary elsewhere
        versionLabel.textColor = (layoutMode == "cards") ? (highlighted ? mainColor : .white) : secondaryColor
        
        // Age: adapts to highlight
        ageLabel.textColor = highlighted ? mainColor : tertiaryColor
        
        // Star: intentionally NOT changed — always gold (or clear if not a favorite)
        // dotLabel: keeps its freshness color even on highlight (small element, readable)
        
        installBtn.baseColor = btnBase
        installBtn.hoverColor = btnHover
        notesBtn.baseColor = btnBase
        notesBtn.hoverColor = btnHover
        openReleasesBtn.baseColor = btnBase
        openReleasesBtn.hoverColor = btnHover
        if !isConfirmingDelete {
            deleteBtn.baseColor = btnBase
            deleteBtn.hoverColor = btnHover
        }
        
        // In cards mode, collapse the version pill background on highlight
        if layoutMode == "cards" {
            versionLabel.backgroundColor = highlighted ? .clear : NSColor.systemBlue.withAlphaComponent(0.7)
        }
    }
    
    /// Applies a base color to the full string, dimming the "owner/" prefix in owner-visible mode.
    private func applyOwnerDimming(to label: NSTextField, baseColor: NSColor, highlighted: Bool) {
        let text = label.stringValue
        if text.isEmpty { return }
        
        let attrStr = NSMutableAttributedString(string: text)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let fullRange = NSRange(location: 0, length: attrStr.length)
        
        attrStr.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
        attrStr.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        
        // Dim "owner/" prefix in lighter weight when showing full owner/repo name
        if label === titleLabel, let slashIndex = text.firstIndex(of: "/") {
            let prefixNSRange = NSRange(text.startIndex...slashIndex, in: text)
            let ownerColor = highlighted ? baseColor.withAlphaComponent(0.6) : NSColor.secondaryLabelColor
            attrStr.addAttribute(.foregroundColor, value: ownerColor, range: prefixNSRange)
            
            if let currentFont = label.font {
                let regularFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .regular)
                attrStr.addAttribute(.font, value: regularFont, range: prefixNSRange)
            }
        }
        
        label.attributedStringValue = attrStr
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if isConfirmingDelete {
            // Red wash during inline delete confirmation
            NSColor.systemRed.withAlphaComponent(0.35).set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4)
            path.fill()
        } else if lastHighlightState {
            NSColor.selectedContentBackgroundColor.set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4)
            path.fill()
        } else if !wasEverHovered && displayData.isNew {
            // Subtle highlight for unread/new notification
            NSColor.controlAccentColor.withAlphaComponent(0.2).set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4)
            path.fill()
        }
        
        super.draw(dirtyRect)
    }
    
    override func layout() {
        super.layout()
        
        let unconstrainedWidth = titleLabel.cell?.cellSize(forBounds: NSMakeRect(0, 0, .greatestFiniteMagnitude, .greatestFiniteMagnitude)).width ?? titleLabel.intrinsicContentSize.width
        
        let hasError = versionLabel.stringValue == "⚠️" || subtitleLabel.stringValue == Translations.get("error")
        let errorTooltip = versionLabel.toolTip ?? subtitleLabel.toolTip
        
        let isTruncated = unconstrainedWidth > titleLabel.frame.width + 0.1
        
        if hasError, let err = errorTooltip {
            titleLabel.toolTip = err
            versionLabel.toolTip = err
            subtitleLabel.toolTip = err
        } else if isTruncated {
            let fullName = titleLabel.stringValue
            titleLabel.toolTip = fullName
            versionLabel.toolTip = fullName
            subtitleLabel.toolTip = fullName
        } else {
            titleLabel.toolTip = nil
            versionLabel.toolTip = nil
            subtitleLabel.toolTip = nil
        }
    }
    
    // MARK: - Mouse Events
    
    // Left click: open GitHub repo page
    override func mouseUp(with event: NSEvent) {
        if enclosingMenuItem != nil {
            appDelegate.animateStatusIcon(with: .scale)
            appDelegate.mainMenu.cancelTracking()
            if let url = URL(string: "https://github.com/\(repoName)") {
                NSWorkspace.shared.open(url)
                appDelegate.hideInformationalWindows()
            }
        }
    }
    
    // Right click: toggle favorite (in-place, no menu rebuild)
    override func rightMouseUp(with event: NSEvent) {
        guard let index = ConfigManager.shared.config.repos
            .firstIndex(where: { $0.name == repoName }) else { return }
        
        let newState = !(ConfigManager.shared.config.repos[index].isFavorite ?? false)
        ConfigManager.shared.config.repos[index].isFavorite = newState
        ConfigManager.shared.saveConfig()
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.starLabel.animator().textColor = newState ? .systemYellow : .clear
        }
    }
    
    // MARK: - Local Live Updates
    
    func updateAgeDisplay() {
        guard let date = originalDate else { return }
        
        let ageInfo = Utils.getReleaseAge(dateString: date)
        
        switch layoutMode {
        case "cards":
            subtitleLabel.stringValue = ageInfo.seconds.isInfinite ? "" : ageInfo.label
        case "columns":
            ageLabel.stringValue = ageInfo.seconds.isInfinite ? "" : ageInfo.label
        default: break
        }
        
        applyHighlightState(lastHighlightState, animated: false)
    }
}
