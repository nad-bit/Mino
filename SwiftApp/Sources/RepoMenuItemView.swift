import Cocoa

/// Holds the pre-parsed data for building any layout mode.
struct RepoDisplayData {
    let repoName: String
    let formattedName: String
    let version: String?          // e.g. "v2.12.5"
    let ageLabel: String?         // e.g. "3 days"
    let ageSeconds: Double
    let newIndicator: String      // "✦" or ""
    let isError: Bool
    let isLoading: Bool
    let caskName: String?
    let freshnessColor: NSColor   // 🟢/🟡/⚪ mapped to NSColor
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
    
    // Provide a consistently large hit area regardless of the small icon size
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 26, height: 26) // Matches typical menu action height
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
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = hoverColor.withAlphaComponent(0.15).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        contentTintColor = baseColor
        layer?.backgroundColor = NSColor.clear.cgColor
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
    private let dotLabel = NSTextField(labelWithString: "")        // Hybrid mode color dot
    
    // Data
    private let repoName: String
    private let caskName: String?
    private let appDelegate: AppDelegate
    private let layout: String
    
    // Track last known highlight state
    private var lastHighlightState = false
    
    // Column widths (for columns/hybrid modes, set from outside)
    var nameColumnWidth: CGFloat = 0
    var versionColumnWidth: CGFloat = 0
    
    init(repoName: String, displayData: RepoDisplayData, layout: String, appDelegate: AppDelegate) {
        self.repoName = repoName
        self.caskName = displayData.caskName
        self.appDelegate = appDelegate
        self.layout = layout
        
        let rowHeight: CGFloat = (layout == "cards") ? 40 : 22
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: rowHeight))
        self.autoresizingMask = [.width]
        
        setupButtons()
        
        switch layout {
        case "cards":
            setupCardsView(data: displayData)
        case "hybrid":
            setupHybridView(data: displayData)
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
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupButton(_ btn: MenuActionButton, icon: String, action: Selector, tooltip: String) {
        let imageConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)?.withSymbolConfiguration(imageConfig)
        btn.isBordered = false
        btn.target = self
        btn.action = action
        btn.toolTip = tooltip
        btn.baseColor = .secondaryLabelColor
        btn.hoverColor = .labelColor
        btn.wantsLayer = true
    }
    
    // MARK: - Layout: Tags (Single line with colorful pill)
    
    private func setupTagsView(data: RepoDisplayData) {
        // Name
        titleLabel.stringValue = data.formattedName
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Dynamic freshness pill
        if let ver = data.version {
            versionLabel.stringValue = " \(ver) "
            versionLabel.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
            versionLabel.textColor = .white
            // Fallback to blue if the color is white/gray in dark mode to keep contrast high
            let pillColor = data.freshnessColor == .tertiaryLabelColor ? NSColor.systemBlue : data.freshnessColor
            versionLabel.backgroundColor = pillColor.withAlphaComponent(0.85)
            versionLabel.isBezeled = false
            versionLabel.drawsBackground = true
            versionLabel.alignment = .center
            versionLabel.wantsLayer = true
            versionLabel.layer?.cornerRadius = 6
            versionLabel.layer?.masksToBounds = true
            versionLabel.translatesAutoresizingMaskIntoConstraints = false
            versionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        } else if data.isLoading {
            versionLabel.stringValue = Translations.get("loading")
            versionLabel.font = .systemFont(ofSize: 10)
            versionLabel.textColor = .secondaryLabelColor
            versionLabel.translatesAutoresizingMaskIntoConstraints = false
        } else if data.isError {
            versionLabel.stringValue = "⚠️"
            versionLabel.font = .systemFont(ofSize: 10)
            versionLabel.translatesAutoresizingMaskIntoConstraints = false
        }
        
        let contentStack = NSStackView(views: [titleLabel, versionLabel])
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
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentStack.trailingAnchor, constant: 8)
        ])
    }
    
    // MARK: - Layout: Cards (two-line)
    
    private func setupCardsView(data: RepoDisplayData) {
        // Line 1: bold name + version pill
        titleLabel.stringValue = data.formattedName
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Version pill
        if let ver = data.version {
            versionLabel.stringValue = ver
            versionLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            versionLabel.textColor = .white
            versionLabel.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.7)
            versionLabel.isBezeled = false
            versionLabel.drawsBackground = true
            versionLabel.alignment = .center
            versionLabel.wantsLayer = true
            versionLabel.layer?.cornerRadius = 4
            versionLabel.layer?.masksToBounds = true
            versionLabel.translatesAutoresizingMaskIntoConstraints = false
            versionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            versionLabel.setContentHuggingPriority(.required, for: .horizontal)
        } else if data.isLoading {
            versionLabel.stringValue = Translations.get("loading")
            versionLabel.font = .systemFont(ofSize: 10)
            versionLabel.textColor = .secondaryLabelColor
            versionLabel.translatesAutoresizingMaskIntoConstraints = false
        } else if data.isError {
            versionLabel.stringValue = "⚠️"
            versionLabel.font = .systemFont(ofSize: 10)
            versionLabel.translatesAutoresizingMaskIntoConstraints = false
        }
        
        // Line 2: age + indicator
        if let age = data.ageLabel {
            subtitleLabel.stringValue = "\(age)\(data.newIndicator)"
        } else if data.isError {
            subtitleLabel.stringValue = Translations.get("error")
        } else {
            subtitleLabel.stringValue = ""
        }
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Top row: name + version pill
        let topRow = NSStackView(views: [titleLabel, versionLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .firstBaseline
        topRow.translatesAutoresizingMaskIntoConstraints = false
        
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // Vertical stack: topRow + subtitle
        let vStack = NSStackView(views: [topRow, subtitleLabel])
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
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: vStack.trailingAnchor, constant: 8)
        ])
    }
    
    // MARK: - Layout: Columns (tabular)
    
    private func setupColumnsView(data: RepoDisplayData) {
        setupColumnContent(data: data, showDot: false)
    }
    
    // MARK: - Layout: Hybrid (columns + color dot)
    
    private func setupHybridView(data: RepoDisplayData) {
        setupColumnContent(data: data, showDot: true)
    }
    
    /// Shared setup for Columns and Hybrid modes
    private func setupColumnContent(data: RepoDisplayData, showDot: Bool) {
        // Name column
        titleLabel.stringValue = data.formattedName
        titleLabel.font = .menuBarFont(ofSize: 0)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Version column
        if let ver = data.version {
            versionLabel.stringValue = ver
        } else if data.isLoading {
            versionLabel.stringValue = "…"
        } else if data.isError {
            versionLabel.stringValue = "⚠️"
        }
        versionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .left
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Age column
        if let age = data.ageLabel {
            let indicator = showDot ? "" : data.newIndicator
            ageLabel.stringValue = "\(age)\(indicator)"
        } else {
            ageLabel.stringValue = ""
        }
        ageLabel.font = .systemFont(ofSize: 11)
        ageLabel.textColor = .tertiaryLabelColor
        ageLabel.alignment = .right
        ageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Build row
        var rowViews: [NSView] = []
        
        if showDot {
            dotLabel.stringValue = "●"
            dotLabel.font = .systemFont(ofSize: 8)
            dotLabel.textColor = data.freshnessColor
            dotLabel.alignment = .center
            dotLabel.translatesAutoresizingMaskIntoConstraints = false
            dotLabel.setContentHuggingPriority(.required, for: .horizontal)
            dotLabel.widthAnchor.constraint(equalToConstant: 12).isActive = true
            rowViews.append(dotLabel)
        }
        
        rowViews.append(contentsOf: [titleLabel, versionLabel, ageLabel])
        
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
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
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
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            menuItem.representedObject = repoName
            appDelegate.performAfterMenuClose {
                self.appDelegate.handleDeleteRepo(menuItem)
            }
        }
    }
    
    // MARK: - Highlight Drawing
    
    func menuDidChangeHighlight(highlightedItem: NSMenuItem?) {
        let highlighted = (highlightedItem === enclosingMenuItem)
        if highlighted != lastHighlightState {
            lastHighlightState = highlighted
            applyHighlightState(highlighted)
            needsDisplay = true
        }
    }
    
    private func applyHighlightState(_ highlighted: Bool, animated: Bool = true) {
        // To prevent NSStackView from recalculating layout and causing menu artifacts 
        // on the right edge, we animate alphaValue instead of isHidden.
        // We set the buttons to be fully transparent when not highlighted.
        
        // Ensure they are always part of the layout
        if installBtn.isHidden { installBtn.isHidden = false }
        if notesBtn.isHidden { notesBtn.isHidden = false }
        if openReleasesBtn.isHidden { openReleasesBtn.isHidden = false }
        if deleteBtn.isHidden { deleteBtn.isHidden = false }

        let installAlpha: CGFloat = (caskName != nil && highlighted) ? 1.0 : 0.0
        let alpha: CGFloat = highlighted ? 1.0 : 0.0

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                
                self.installBtn.animator().alphaValue = installAlpha
                self.notesBtn.animator().alphaValue = alpha
                self.openReleasesBtn.animator().alphaValue = alpha
                self.deleteBtn.animator().alphaValue = alpha
            }
        } else {
            self.installBtn.alphaValue = installAlpha
            self.notesBtn.alphaValue = alpha
            self.openReleasesBtn.alphaValue = alpha
            self.deleteBtn.alphaValue = alpha
        }
        
        // Text colors
        let mainColor: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        let secondaryColor: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let tertiaryColor: NSColor = highlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
        
        // Button colors
        let btnBase: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let btnHover: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        
        applyTextWithIndicatorColor(to: titleLabel, baseColor: mainColor, highlighted: highlighted)
        applyTextWithIndicatorColor(to: subtitleLabel, baseColor: secondaryColor, highlighted: highlighted)
        
        versionLabel.textColor = (layout == "cards") ? (highlighted ? mainColor : .white) : secondaryColor
        
        // ageLabel shouldn't normally have the indicator since it's in the title/subtitle, but for safety:
        applyTextWithIndicatorColor(to: ageLabel, baseColor: highlighted ? mainColor : tertiaryColor, highlighted: highlighted)
        
        installBtn.baseColor = btnBase
        installBtn.hoverColor = btnHover
        notesBtn.baseColor = btnBase
        notesBtn.hoverColor = btnHover
        openReleasesBtn.baseColor = btnBase
        openReleasesBtn.hoverColor = btnHover
        deleteBtn.baseColor = btnBase
        deleteBtn.hoverColor = btnHover
        
        // In cards mode, adjust the version pill background
        if layout == "cards" {
            versionLabel.backgroundColor = highlighted ? .clear : NSColor.systemBlue.withAlphaComponent(0.7)
        }
    }
    
    // Applies a base color to the entire string, but if the 'new release indicator' is present and
    // the user requested 'gold', paints just that character yellow.
    private func applyTextWithIndicatorColor(to label: NSTextField, baseColor: NSColor, highlighted: Bool) {
        let text = label.stringValue
        if text.isEmpty { return }
        
        let attrStr = NSMutableAttributedString(string: text)
        
        // Restore truncation line break mode that attributed strings wipe out by default
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let fullRange = NSRange(location: 0, length: attrStr.length)
        
        attrStr.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
        attrStr.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        
        if !highlighted, text.contains(Constants.newReleaseIndicator) {
            let indicatorRange = (text as NSString).range(of: Constants.newReleaseIndicator)
            if indicatorRange.location != NSNotFound {
                attrStr.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: indicatorRange)
            }
        }
        
        label.attributedStringValue = attrStr
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if lastHighlightState {
            NSColor.selectedContentBackgroundColor.set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4)
            path.fill()
        }
        
        super.draw(dirtyRect)
    }
    
    // Click on row opens the repo's main GitHub page
    override func mouseUp(with event: NSEvent) {
        if enclosingMenuItem != nil {
            appDelegate.animateStatusIcon(with: .scale)
            appDelegate.menu.cancelTracking()
            if let url = URL(string: "https://github.com/\(repoName)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
