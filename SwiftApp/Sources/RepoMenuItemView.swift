import Cocoa

/// Holds the pre-parsed data for building any layout mode.
struct RepoDisplayData {
    var repoName: String
    var formattedName: String
    var version: String?          // e.g. "v2.12.5"
    var ageLabel: String?         // e.g. "3 days"
    var ageSeconds: Double
    var originalDate: String?     // Raw ISO8601 date from GitHub
    var errorMessage: String?
    var isLoading: Bool
    var caskName: String?
    var freshnessColor: NSColor   // 🟢/🟡/⚪ mapped to NSColor
    var isNew: Bool
    var tags: [String]
    var isFavorite: Bool
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
        self.layer?.cornerRadius = 4
        self.layer?.masksToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: NSSize {
        // Buttons should be slightly smaller than the row height (approx 22pt) to avoid 'sticking out'
        return NSSize(width: 26, height: 18)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = self.trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
        
        // Fix for "ghost hover" when the view moves but the mouse stays still.
        // Only perform this coordinate check if the button is currently hovered.
        if isHovered, let window = self.window {
            let mouseLocation = window.mouseLocationOutsideOfEventStream
            let localPoint = convert(mouseLocation, from: nil)
            if !bounds.contains(localPoint) {
                resetHoverState()
            }
        }
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
    private let openRepoBtn = MenuActionButton()
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
    private func makeWarningView(pointSize: CGFloat, slotWidth: CGFloat? = nil, tooltip: String?) -> NSView {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        let iv = NSImageView(image: img ?? NSImage())
        iv.contentTintColor = .systemRed
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.toolTip = tooltip
        iv.translatesAutoresizingMaskIntoConstraints = false
        let width = slotWidth ?? max(12, pointSize)
        iv.widthAnchor.constraint(equalToConstant: width).isActive = true
        iv.setContentHuggingPriority(.required, for: .horizontal)
        return iv
    }
    
    // Data (var for cell reuse via reconfigure(with:))
    private var repoName: String
    private var caskName: String?
    private let appDelegate: AppDelegate
    private let layoutMode: String
    private let baseFontSize: CGFloat
    private var originalDate: String?
    
    // Public exposure for AppDelegate search filtering
    private(set) var displayData: RepoDisplayData
    
    // Track highlight state
    private var lastHighlightState = false
    
    // Keyboard button focus
    private(set) var focusedButtonIndex: Int? = nil
    
    // Inline delete confirmation state
    private var isConfirmingDelete = false
    private var deleteConfirmTimer: Timer?
    
    // Column widths (for columns mode, set from outside)
    var nameColumnWidth: CGFloat = 0
    var versionColumnWidth: CGFloat = 0
    // Managed width constraints (tracked explicitly so we don't deactivate AppKit internal intrinsic constraints)
    private var versionMaxWidthConstraint: NSLayoutConstraint?
    private var titleWidthConstraint: NSLayoutConstraint?
    private var dotWidthConstraint: NSLayoutConstraint?
    private var starWidthConstraint: NSLayoutConstraint?
    
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
        
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.layer?.cornerRadius = 5
        self.layer?.masksToBounds = true
    }
    
    /// Reconfigures this view with new data, reusing the NSView allocation,
    /// CALayer, and all instance-property components (buttons, labels, stacks).
    /// Only the lightweight NSStackView wrappers and constraints are recreated.
    func reconfigure(with data: RepoDisplayData) {
        // Close release notes popover if it is currently open for this repo before we recycle the view.
        if let popover = appDelegate.releaseNotesPopover,
           popover.isShown,
           let vc = popover.contentViewController as? ReleaseNotesViewController,
           vc.currentRepoName == self.repoName {
            popover.close()
            // Purge WebKit's internal URL cache that accumulates when parsing
            // HTML release notes via NSAttributedString(data:options:documentType:.html)
            URLCache.shared.removeAllCachedResponses()
        }

        // 1. Update stored data
        self.repoName = data.repoName
        self.caskName = data.caskName
        self.originalDate = data.originalDate
        self.displayData = data
        
        // 2. Reset interactive state
        if isConfirmingDelete {
            isConfirmingDelete = false
            deleteConfirmTimer?.invalidate()
            deleteConfirmTimer = nil
        }
        lastHighlightState = false
        focusedButtonIndex = nil
        
        // 3. Strip the old view hierarchy (auto-deactivates inter-view constraints)
        subviews.forEach { $0.removeFromSuperview() }
        
        // 4. Remove only the explicit size constraints WE add in setupButton /
        //    configureStarLabel / dotLabel setup.  Do NOT call removeConstraints
        //    on NSStackView or labels — that destroys their internal layout.
        for btn in [installBtn, notesBtn, openRepoBtn, deleteBtn] {
            for c in btn.constraints where c.firstAttribute == .width || c.firstAttribute == .height {
                c.isActive = false
            }
        }
        starWidthConstraint?.isActive = false
        starWidthConstraint = nil
        dotWidthConstraint?.isActive = false
        dotWidthConstraint = nil
        versionMaxWidthConstraint?.isActive = false
        versionMaxWidthConstraint = nil
        titleWidthConstraint?.isActive = false
        titleWidthConstraint = nil
        
        // 5. Clear install button action before setupButtons re-evaluates caskName
        installBtn.action = nil
        
        // 6. Rebuild the layout with updated data
        setupButtons()
        switch layoutMode {
        case "cards":  setupCardsView(data: data)
        case "tags":   setupTagsView(data: data)
        default:       setupColumnsView(data: data)
        }
        
        // 7. Reset visual state (alphaValue guards against stale delete animations)
        self.alphaValue = 1.0
        applyHighlightState(false, animated: false)
        needsDisplay = true
    }
    
    /// Calculates the ideal width this row needs to show its content without truncation.
    func calculateDesiredWidth() -> CGFloat {
        let nameWidth = titleLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 1000, height: 50)).width ?? 0
        let buttonCount = buttonStack.arrangedSubviews.count
        let btnHeight = (layoutMode == "cards") ? baseFontSize + 22 : baseFontSize + 8
        let buttonsWidth = CGFloat(buttonCount) * (btnHeight + 4)
        
        switch layoutMode {
        case "cards":
            // Cards have two lines, name is on top.
            // Width = margins (18+12) + icon/dot (12) + spacing (6) + max(name, subtitle) + spacing (8) + buttons
            let subWidth = subtitleLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 1000, height: 50)).width ?? 0
            let rawVersionWidth = versionLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 1000, height: 50)).width ?? 0
            let versionWidth = min(rawVersionWidth, 160)
            let contentWidth = max(nameWidth + 6 + versionWidth, subWidth + 20) // 20 for star
            return 18 + 12 + 6 + contentWidth + 8 + buttonsWidth + 12
            
        case "tags":
            // Single line: margin(12) + [warning?] + name + spacing(8) + version + spacing(8) + star(16) + spacing(6) + buttons + margin(12)
            let rawVersionWidth = versionLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 1000, height: 50)).width ?? 0
            let versionWidth = min(rawVersionWidth, 140)
            return 12 + (displayData.errorMessage != nil ? 18 : 0) + nameWidth + 8 + versionWidth + 8 + 16 + 6 + buttonsWidth + 12
            
        case "columns":
            // Fixed columns + margins + buttons
            // If nameColumnWidth or versionColumnWidth are set, use them as minimums
            let showDot = ConfigManager.shared.config.showNewIndicator ?? false
            let hasLeadingSlot = showDot || displayData.errorMessage != nil
            let leadingMargin: CGFloat = hasLeadingSlot ? 12 : 18
            let dotWidth: CGFloat = hasLeadingSlot ? (max(14, ceil(baseFontSize - 4) + 4) + 6) : 0
            let rawVersionWidth = versionLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 1000, height: 50)).width ?? 0
            let versionWidth = versionColumnWidth > 0 ? versionColumnWidth : min(rawVersionWidth, 120)
            let totalColumns = dotWidth + (nameColumnWidth > 0 ? nameColumnWidth : nameWidth) + versionWidth + 60 + 20 // 60 for age, 20 for star
            return leadingMargin + totalColumns + 8 + buttonsWidth + 12
            
        default:
            return 400
        }
    }
    
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
    }
    
    func setHighlighted(_ highlighted: Bool) {
        if highlighted != lastHighlightState {
            lastHighlightState = highlighted
            
            if !highlighted && isConfirmingDelete {
                cancelDeleteConfirm()
            }
            
            applyHighlightState(highlighted)
            needsDisplay = true
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Button Setup (shared by all modes)
    
    private func setupButtons() {
        if caskName != nil && HomebrewManager.shared.brewPath != nil {
            setupButton(installBtn, icon: "mug", action: #selector(installClicked), tooltip: Translations.get("installUpdate"))
        }
        setupButton(notesBtn, icon: "doc.text", action: #selector(notesClicked), tooltip: Translations.get("releaseNotes"))
        setupButton(openRepoBtn, icon: "safari", action: #selector(openRepoClicked), tooltip: Translations.get("openRepo"))
        setupButton(deleteBtn, icon: "trash", action: #selector(deleteClicked), tooltip: Translations.get("deleteRepo"))
        
        let buttons = [installBtn, notesBtn, openRepoBtn, deleteBtn].filter { $0.action != nil }
        buttonStack.setViews(buttons, in: .leading)
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 0
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
    }
    
    // MARK: - Keyboard Button Focus
    
    /// Returns only the action buttons that are visible and actionable.
    var actionButtons: [MenuActionButton] {
        return [installBtn, notesBtn, openRepoBtn, deleteBtn].filter { $0.action != nil }
    }
    
    /// Applies a visual keyboard focus ring to the button at the given index.
    func setKeyboardFocus(index: Int?) {
        // Clear focus on all potential buttons to ensure no stale borders persist
        for btn in [installBtn, notesBtn, openRepoBtn, deleteBtn] {
            btn.layer?.borderWidth = 0
        }
        
        focusedButtonIndex = index
        
        // Apply new focus
        if let idx = index, idx < actionButtons.count {
            let btn = actionButtons[idx]
            btn.layer?.borderWidth = 2
            btn.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }
    
    /// Clears any keyboard focus ring.
    func clearKeyboardFocus() {
        setKeyboardFocus(index: nil)
    }
    
    /// Triggers the action of the currently focused button.
    func triggerFocusedAction() {
        guard let idx = focusedButtonIndex, idx < actionButtons.count else { return }
        actionButtons[idx].performClick(nil)
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
        
        // Ensure buttons don't exceed row height
        btn.translatesAutoresizingMaskIntoConstraints = false
        let btnHeight = (layoutMode == "cards") ? baseFontSize + 18 : baseFontSize + 4
        btn.widthAnchor.constraint(equalToConstant: btnHeight + 4).isActive = true
        btn.heightAnchor.constraint(equalToConstant: btnHeight).isActive = true
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
        starWidthConstraint?.isActive = false
        let sConstraint = starLabel.widthAnchor.constraint(equalToConstant: max(16, size + 2))
        sConstraint.isActive = true
        starWidthConstraint = sConstraint
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
        contentStack.alignment = .centerY
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(contentStack)
        addSubview(buttonStack)
        
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        versionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        versionLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        versionMaxWidthConstraint?.isActive = false
        let tagVerConstraint = versionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 140)
        tagVerConstraint.isActive = true
        versionMaxWidthConstraint = tagVerConstraint
        
        starLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonStack.setContentHuggingPriority(.required, for: .horizontal)
        
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: 6),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.trailingAnchor.constraint(equalTo: buttonStack.trailingAnchor, constant: 12)
        ])
    }
    
    // MARK: - Layout: Cards (two-line)
    
    private func setupCardsView(data: RepoDisplayData) {
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
        }
        topRowViews.append(contentsOf: [titleLabel, versionLabel])
        
        let topRow = NSStackView(views: topRowViews)
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .firstBaseline
        topRow.translatesAutoresizingMaskIntoConstraints = false
        
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        versionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        versionLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        versionMaxWidthConstraint?.isActive = false
        let cardVerConstraint = versionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 160)
        cardVerConstraint.isActive = true
        versionMaxWidthConstraint = cardVerConstraint
        
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
        let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? false
        let isOlderThan90 = data.ageSeconds.isInfinite || (data.ageSeconds / 86400.0) > 90.0
        subtitleLabel.textColor = (showNewIndicator && !isOlderThan90 && data.errorMessage == nil) ? data.freshnessColor : .secondaryLabelColor
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
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: vStack.trailingAnchor, constant: 8),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.trailingAnchor.constraint(equalTo: buttonStack.trailingAnchor, constant: 12)
        ])
    }
    
    // MARK: - Version Label Helper
    
    private func configureVersionPill(data: RepoDisplayData, layout: String) {
        let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? false
        let isCards = layout == "cards"
        let padding = isCards ? "" : " "
        let cornerRadius: CGFloat = isCards ? 4 : 6
        let errorWeight: NSFont.Weight = isCards ? .medium : .regular
        let errorColor: NSColor = isCards ? .tertiaryLabelColor : .secondaryLabelColor
        let pillColor: NSColor = isCards ? NSColor.systemBlue.withAlphaComponent(0.8) : (showNewIndicator ? data.freshnessColor : NSColor.systemBlue)

        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.toolTip = nil
        versionLabel.isBezeled = false
        versionLabel.drawsBackground = false
        versionLabel.backgroundColor = .clear
        versionLabel.isHidden = false
        versionLabel.lineBreakMode = .byTruncatingTail
        versionLabel.cell?.truncatesLastVisibleLine = true

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
                versionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                versionLabel.setContentHuggingPriority(.required, for: .horizontal)
            } else {
                versionLabel.stringValue = ""
                versionLabel.isHidden = true
            }
        } else if let ver = data.version {
            versionLabel.stringValue = "\(padding)\(ver)\(padding)"
            versionLabel.font = .systemFont(ofSize: baseFontSize - 2, weight: .bold)
            versionLabel.textColor = NSColor.white
            versionLabel.drawsBackground = false
            versionLabel.alignment = .center
            versionLabel.wantsLayer = true
            versionLabel.appearance = NSAppearance(named: .aqua) // Forces solid white text, bypassing Dark Mode vibrancy dimming
            versionLabel.layer?.backgroundColor = pillColor.cgColor
            versionLabel.layer?.opacity = 1.0
            versionLabel.layer?.cornerRadius = cornerRadius
            versionLabel.layer?.masksToBounds = true
            versionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            versionLabel.setContentHuggingPriority(.required, for: .horizontal)
        } else if data.isLoading {
            versionLabel.stringValue = Translations.get("loading")
            versionLabel.font = .systemFont(ofSize: baseFontSize - 3)
            versionLabel.textColor = .secondaryLabelColor
        } else {
            versionLabel.stringValue = ""
            versionLabel.isHidden = true
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
        versionLabel.lineBreakMode = .byTruncatingTail
        versionLabel.cell?.truncatesLastVisibleLine = true
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Age column
        ageLabel.stringValue = data.ageLabel ?? ""
        ageLabel.font = .systemFont(ofSize: baseFontSize - 2)
        ageLabel.textColor = .tertiaryLabelColor
        ageLabel.alignment = .right
        ageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Star
        configureStarLabel(isFavorite: data.isFavorite, fontSize: baseFontSize - 2)
        
        // Leading slot: error warning OR freshness dot
        var rowViews: [NSView] = []
        let dotFontSize = max(8.0, baseFontSize - 6.0)
        dotLabel.stringValue = "●"
        dotLabel.font = .systemFont(ofSize: dotFontSize)
        let cellW = dotLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 100, height: 100)).width ?? 14
        let slotWidth = ceil(cellW) + 2
        
        var leadingSlotView: NSView? = nil
        if data.errorMessage != nil {
            // SF Symbol warning replaces the freshness dot
            let warningView = makeWarningView(pointSize: dotFontSize + 2, slotWidth: slotWidth, tooltip: data.errorMessage)
            rowViews.append(warningView)
            leadingSlotView = warningView
        } else if showDot {
            dotLabel.textColor = data.freshnessColor
            dotLabel.alignment = .center
            dotLabel.translatesAutoresizingMaskIntoConstraints = false
            dotLabel.setContentHuggingPriority(.required, for: .horizontal)
            
            dotWidthConstraint?.isActive = false
            let dConstraint = dotLabel.widthAnchor.constraint(equalToConstant: slotWidth)
            dConstraint.isActive = true
            dotWidthConstraint = dConstraint
            
            rowViews.append(dotLabel)
            leadingSlotView = dotLabel
        }
        
        rowViews.append(contentsOf: [titleLabel, versionLabel, ageLabel, starLabel])
        
        let contentStack = NSStackView(views: rowViews)
        contentStack.orientation = .horizontal
        contentStack.spacing = 8
        contentStack.alignment = .centerY
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        if let slot = leadingSlotView {
            contentStack.setCustomSpacing(6, after: slot)
        }
        
        addSubview(contentStack)
        addSubview(buttonStack)
        
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        versionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        versionLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        ageLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        starLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        // Fixed-width columns for alignment across rows
        titleWidthConstraint?.isActive = false
        if nameColumnWidth > 0 {
            let tConstraint = titleLabel.widthAnchor.constraint(equalToConstant: nameColumnWidth)
            tConstraint.isActive = true
            titleWidthConstraint = tConstraint
        }
        
        versionMaxWidthConstraint?.isActive = false
        if versionColumnWidth > 0 {
            let vConstraint = versionLabel.widthAnchor.constraint(equalToConstant: versionColumnWidth)
            vConstraint.isActive = true
            versionMaxWidthConstraint = vConstraint
        } else {
            let vConstraint = versionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 120)
            vConstraint.isActive = true
            versionMaxWidthConstraint = vConstraint
        }
        
        let hasLeadingSlot = leadingSlotView != nil
        let leadingMargin: CGFloat = hasLeadingSlot ? 12 : 18
        
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingMargin),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentStack.trailingAnchor, constant: 8),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.trailingAnchor.constraint(equalTo: buttonStack.trailingAnchor, constant: 12)
        ])
    }
    
    // MARK: - Actions
    @objc func installClicked() {
        if let caskName = caskName {
            appDelegate.animateStatusIcon(with: .scale)
            appDelegate.performAfterPopoverClose {
                self.appDelegate.handleInstallBrewCask(for: caskName)
            }
        }
    }
    
    @objc func notesClicked() {
        DispatchQueue.main.async {
            self.appDelegate.handleShowNotes(for: self.repoName, relativeTo: self)
        }
    }
    
    @objc func openRepoClicked() {
        appDelegate.animateStatusIcon(with: .scale)
        self.appDelegate.handleOpenRepo(for: self.repoName)
    }
    
    @objc func refreshClicked() {
        Task { @MainActor in
            await self.appDelegate.repoCoordinator.refreshSingleRepo(repoName: self.repoName)
        }
    }
    
    @objc func deleteClicked() {
        if isConfirmingDelete {
            // Second click — confirmed, execute inline delete
            deleteConfirmTimer?.invalidate()
            deleteConfirmTimer = nil
            isConfirmingDelete = false
            appDelegate.animateStatusIcon(with: .scale)
            
            // Fire-and-forget fade animation for visual polish
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Constants.defaultAnimationDuration
                self.animator().alphaValue = 0
            }
            
            // Use a Timer in .common mode to fire reliably during popover animations
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
                ctx.duration = Constants.defaultAnimationDuration
                self.installBtn.animator().alphaValue = 0
                self.notesBtn.animator().alphaValue = 0
                self.openRepoBtn.animator().alphaValue = 0
            }
            
            needsDisplay = true
            
            // Auto-cancel after 2s
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
    
    func menuDidChangeHighlight(highlightedItem: Any?) {
        let highlighted = (highlightedItem as? RepoMenuItemView) === self
        if highlighted != lastHighlightState {
            lastHighlightState = highlighted
            
            
            applyHighlightState(highlighted)
            needsDisplay = true // Triggers updateLayer()
        }
    }
    
    private func applyHighlightState(_ highlighted: Bool, animated: Bool = true) {
        // Ensure buttons are always part of the layout
        if installBtn.isHidden { installBtn.isHidden = false }
        if notesBtn.isHidden { notesBtn.isHidden = false }
        if openRepoBtn.isHidden { openRepoBtn.isHidden = false }
        if deleteBtn.isHidden { deleteBtn.isHidden = false }

        let installAlpha: CGFloat = (caskName != nil && highlighted) ? 1.0 : 0.0
        let alpha: CGFloat = highlighted ? 1.0 : 0.0
        // During inline delete confirmation, keep deleteBtn visible and skip its hover reset
        let deleteAlpha: CGFloat = isConfirmingDelete ? 1.0 : alpha

        if !highlighted {
            installBtn.resetHoverState()
            notesBtn.resetHoverState()
            openRepoBtn.resetHoverState()
            if !isConfirmingDelete { deleteBtn.resetHoverState() }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.defaultAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                
                self.installBtn.animator().alphaValue = installAlpha
                self.notesBtn.animator().alphaValue = alpha
                self.openRepoBtn.animator().alphaValue = alpha
                self.deleteBtn.animator().alphaValue = deleteAlpha
            }
        } else {
            self.installBtn.alphaValue = installAlpha
            self.notesBtn.alphaValue = alpha
            self.openRepoBtn.alphaValue = alpha
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
        
        if layoutMode == "cards" {
            let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? false
            let isOlderThan90 = displayData.ageSeconds.isInfinite || (displayData.ageSeconds / 86400.0) > 90.0
            let ageColor = highlighted ? .selectedMenuItemTextColor : ((showNewIndicator && !isOlderThan90 && displayData.errorMessage == nil) ? displayData.freshnessColor : .secondaryLabelColor)
            applyOwnerDimming(to: subtitleLabel, baseColor: ageColor, highlighted: highlighted)
        } else {
            applyOwnerDimming(to: subtitleLabel, baseColor: secondaryColor, highlighted: highlighted)
        }
        
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
        openRepoBtn.baseColor = btnBase
        openRepoBtn.hoverColor = btnHover
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
            let ownerColor = highlighted ? baseColor.withAlphaComponent(0.6) : NSColor.tertiaryLabelColor
            attrStr.addAttribute(.foregroundColor, value: ownerColor, range: prefixNSRange)
            
            if let currentFont = label.font {
                let regularFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .regular)
                attrStr.addAttribute(.font, value: regularFont, range: prefixNSRange)
            }
        }
        
        label.attributedStringValue = attrStr
    }
    
    override var wantsUpdateLayer: Bool { return true }
    
    override func updateLayer() {
        if isConfirmingDelete {
            layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.25).cgColor
        } else if lastHighlightState {
            layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        } else if displayData.isNew {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        } else {
            layer?.backgroundColor = nil
        }
    }
    
    override func layout() {
        super.layout()
        
        let unconstrainedNameWidth = titleLabel.cell?.cellSize(forBounds: NSMakeRect(0, 0, .greatestFiniteMagnitude, .greatestFiniteMagnitude)).width ?? titleLabel.intrinsicContentSize.width
        let isNameTruncated = unconstrainedNameWidth > titleLabel.frame.width + 0.5
        
        let unconstrainedVersionWidth = versionLabel.cell?.cellSize(forBounds: NSMakeRect(0, 0, .greatestFiniteMagnitude, .greatestFiniteMagnitude)).width ?? versionLabel.intrinsicContentSize.width
        let isVersionTruncated = unconstrainedVersionWidth > versionLabel.frame.width + 0.5
        
        let hasError = versionLabel.stringValue == "⚠️" || subtitleLabel.stringValue == Translations.get("error") || displayData.errorMessage != nil
        let errorTooltip = displayData.errorMessage
        
        if hasError, let err = errorTooltip {
            titleLabel.toolTip = isNameTruncated ? "\(displayData.formattedName)\n\n⚠️ \(err)" : "⚠️ \(err)"
            versionLabel.toolTip = "⚠️ \(err)"
            subtitleLabel.toolTip = "⚠️ \(err)"
        } else {
            let fullVersion = displayData.version
            
            if isVersionTruncated, let ver = fullVersion {
                // Show full version tooltip on BOTH version badge and repository name
                versionLabel.toolTip = ver
                titleLabel.toolTip = isNameTruncated ? "\(displayData.formattedName)\n\(ver)" : ver
                subtitleLabel.toolTip = isNameTruncated ? displayData.formattedName : nil
            } else if isNameTruncated {
                // Only repository name is truncated
                titleLabel.toolTip = displayData.formattedName
                versionLabel.toolTip = displayData.formattedName
                subtitleLabel.toolTip = displayData.formattedName
            } else {
                titleLabel.toolTip = nil
                versionLabel.toolTip = nil
                subtitleLabel.toolTip = nil
            }
        }
    }
    
    // MARK: - Mouse Events (Selection handled by Parent Controller)
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
    }
    
    // Left click: Selection handled by MainPopoverViewController (mouse events)
    override func mouseUp(with event: NSEvent) {
        // No action on background click anymore, use explicit buttons
    }
    
    // Right click: toggle favorite (via AppDelegate to ensure DataSource sync)
    override func rightMouseUp(with event: NSEvent) {
        toggleFavorite()
    }
    
    func toggleFavorite() {
        appDelegate.handleToggleFavorite(for: repoName)
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
