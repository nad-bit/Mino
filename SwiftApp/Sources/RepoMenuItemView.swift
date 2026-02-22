import Cocoa

@MainActor
class RepoMenuItemView: NSView {
    
    // UI Elements
    private let titleLabel = NSTextField(labelWithString: "")
    private let installBtn = NSButton()
    private let openReleasesBtn = NSButton()
    private let notesBtn = NSButton()
    private let deleteBtn = NSButton()
    private let buttonStack = NSStackView()
    
    // Data constraints
    private let repoName: String
    private let caskName: String?
    private let appDelegate: AppDelegate
    
    // Track last known highlight state to avoid redundant updates
    private var lastHighlightState = false
    
    init(repoName: String, labelText: String, caskName: String?, appDelegate: AppDelegate) {
        self.repoName = repoName
        self.caskName = caskName
        self.appDelegate = appDelegate
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        
        setupView(labelText: labelText)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView(labelText: String) {
        // Build Title Label
        titleLabel.stringValue = labelText
        titleLabel.font = .menuBarFont(ofSize: 0)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Build Buttons
        if caskName != nil {
            setupButton(installBtn, icon: "shippingbox", action: #selector(installClicked), tooltip: Translations.get("installUpdate"))
        }
        setupButton(notesBtn, icon: "doc.text", action: #selector(notesClicked), tooltip: Translations.get("releaseNotes"))
        setupButton(openReleasesBtn, icon: "arrow.up.right.square", action: #selector(openReleasesClicked), tooltip: Translations.get("openReleases"))
        setupButton(deleteBtn, icon: "trash", action: #selector(deleteClicked), tooltip: Translations.get("deleteRepo"))
        
        // Layout Right-Side Stack
        let buttons = [installBtn, notesBtn, openReleasesBtn, deleteBtn].filter { $0.action != nil }
        buttonStack.setViews(buttons, in: .leading)
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(titleLabel)
        addSubview(buttonStack)
        
        // Priority: title truncates before buttons get compressed
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8)
        ])
        
        // Buttons start hidden, will be revealed on hover
        applyHighlightState(false)
    }
    
    private func setupButton(_ btn: NSButton, icon: String, action: Selector, tooltip: String) {
        let imageConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)?.withSymbolConfiguration(imageConfig)
        btn.isBordered = false
        btn.target = self
        btn.action = action
        btn.toolTip = tooltip
        btn.contentTintColor = .secondaryLabelColor
    }
    
    // MARK: - Actions
    @objc private func installClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.menu.cancelTracking()
            menuItem.representedObject = caskName
            appDelegate.handleInstallBrewCask(menuItem)
        }
    }
    
    @objc private func notesClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.menu.cancelTracking()
            menuItem.representedObject = repoName
            appDelegate.handleShowNotes(menuItem)
        }
    }
    
    @objc private func openReleasesClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.menu.cancelTracking()
            menuItem.representedObject = repoName
            appDelegate.handleOpenReleases(menuItem)
        }
    }
    
    @objc private func deleteClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.menu.cancelTracking()
            menuItem.representedObject = repoName
            appDelegate.handleDeleteRepo(menuItem)
        }
    }
    
    // MARK: - Highlight Drawing
    
    /// Called by AppDelegate's menu(_:willHighlight:) via direct reference.
    /// This is the ONLY mechanism that drives highlight state — no tracking areas, no notifications.
    func menuDidChangeHighlight() {
        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        if highlighted != lastHighlightState {
            lastHighlightState = highlighted
            applyHighlightState(highlighted)
            needsDisplay = true
        }
    }
    
    private func applyHighlightState(_ highlighted: Bool) {
        // Show/hide buttons
        let showButtons = highlighted
        installBtn.isHidden = (caskName == nil) ? true : !showButtons
        notesBtn.isHidden = !showButtons
        openReleasesBtn.isHidden = !showButtons
        deleteBtn.isHidden = !showButtons
        
        // Adjust text/icon colors
        titleLabel.textColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        let btnTint: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        installBtn.contentTintColor = btnTint
        notesBtn.contentTintColor = btnTint
        openReleasesBtn.contentTintColor = btnTint
        deleteBtn.contentTintColor = btnTint
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        
        if highlighted {
            NSColor.selectedContentBackgroundColor.set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4)
            path.fill()
        }
        // No need to fill clear — the menu already provides the background
        
        super.draw(dirtyRect)
    }
    
    // Click on empty row area opens releases
    override func mouseUp(with event: NSEvent) {
        openReleasesClicked()
    }
}
