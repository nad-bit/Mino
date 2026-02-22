import Cocoa

@MainActor
class RepoMenuItemView: NSView {
    
    // UI Elements
    private let titleLabel = NSTextField(labelWithString: "")
    private let installBtn = NSButton()
    private let openReleasesBtn = NSButton()
    private let notesBtn = NSButton()
    private let deleteBtn = NSButton()
    private let mainStack = NSStackView()
    
    // Data constraints
    private let repoName: String
    private let caskName: String?
    private let appDelegate: AppDelegate
    
    // Interaction states
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    
    init(repoName: String, labelText: String, caskName: String?, appDelegate: AppDelegate) {
        self.repoName = repoName
        self.caskName = caskName
        self.appDelegate = appDelegate
        super.init(frame: .zero) // Size will be determined by intrinsicContentSize
        
        setupView(labelText: labelText)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView(labelText: String) {
        // Build Title Label
        titleLabel.stringValue = labelText
        titleLabel.font = .menuBarFont(ofSize: 0) // Default menu font size
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.backgroundColor = .clear
        
        // Build Buttons
        if let _ = caskName {
            setupButton(installBtn, icon: "shippingbox", action: #selector(installClicked), tooltip: Translations.get("installUpdate"))
        }
        setupButton(notesBtn, icon: "doc.text", action: #selector(notesClicked), tooltip: Translations.get("releaseNotes"))
        setupButton(openReleasesBtn, icon: "arrow.up.right.square", action: #selector(openReleasesClicked), tooltip: Translations.get("openReleases"))
        setupButton(deleteBtn, icon: "trash", action: #selector(deleteClicked), tooltip: Translations.get("deleteRepo"))
        
        // Layout Right-Side Stack
        let buttonStack = NSStackView(views: [installBtn, notesBtn, openReleasesBtn, deleteBtn].filter { $0.action != nil })
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY
        
        // Main Container Stack
        mainStack.setViews([titleLabel, buttonStack], in: .leading)
        mainStack.orientation = .horizontal
        mainStack.spacing = 8
        mainStack.alignment = .centerY
        mainStack.distribution = .fill
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Adjust compression resistance so the label dictates the width instead of artificially truncating
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), // standard inset
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            mainStack.heightAnchor.constraint(equalTo: heightAnchor),
            
            // Force the buttonStack to hug the trailing edge
            mainStack.trailingAnchor.constraint(equalTo: buttonStack.trailingAnchor)
        ])
        
        // Ensure buttons start hidden
        toggleButtons(visible: false)
    }
    
    private func setupButton(_ btn: NSButton, icon: String, action: Selector, tooltip: String) {
        let imageConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)?.withSymbolConfiguration(imageConfig)
        btn.isBordered = false
        btn.target = self
        btn.action = action
        btn.toolTip = tooltip
        btn.contentTintColor = .secondaryLabelColor
        
        // Make the button only visible/clickable in hover mode for a cleaner look natively
        btn.isHidden = ConfigManager.shared.config.showIcons == false ? false : true 
    }
    
    // MARK: - Actions
    @objc private func installClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.menu.cancelTracking() // Dismiss the menu immediately
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
    
    // MARK: - Hover Tracking & Drawing
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let ta = trackingArea {
            addTrackingArea(ta)
        }
    }
    
    // MARK: - Sizing
    override var intrinsicContentSize: NSSize {
        // Calculate the required width based on child views
        let minWidth: CGFloat = 200 // Ensure a minimum readable width
        // Required width = leading margin (18) + Label Width + spacing (8) + Button Stack Width + trailing margin (12)
        // Since mainStack handles spacing, we just ask for its width + insets
        let calculatedWidth = mainStack.fittingSize.width + 30
        
        return NSSize(width: max(minWidth, calculatedWidth), height: 26)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        
        // Show context buttons if we are hovering
        toggleButtons(visible: true)
        // Provide the enclosing NSMenuItem state so keyboard navigation isn't wildly disconnected
        if let _ = enclosingMenuItem {
            // Note: Since setAsHighlightedItem is not accessible, we trigger standard selection natively if needed
            // By doing nothing here, we just rely on our custom draw() highlighting
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
        
        // Hide context buttons when cursor leaves
        toggleButtons(visible: false)
    }
    
    private func toggleButtons(visible: Bool) {
        let desiredVisibility = visible
        
        installBtn.isHidden = (caskName == nil) ? true : !desiredVisibility
        notesBtn.isHidden = !desiredVisibility
        openReleasesBtn.isHidden = !desiredVisibility
        deleteBtn.isHidden = !desiredVisibility
        
        // Highlight logic
        titleLabel.textColor = isHovered ? .selectedMenuItemTextColor : .labelColor
        let btnTint: NSColor = isHovered ? .selectedMenuItemTextColor : .secondaryLabelColor
        installBtn.contentTintColor = btnTint
        notesBtn.contentTintColor = btnTint
        openReleasesBtn.contentTintColor = btnTint
        deleteBtn.contentTintColor = btnTint
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.selectedContentBackgroundColor.set()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4)
            path.fill()
        } else {
            NSColor.clear.set()
            bounds.fill()
        }
        super.draw(dirtyRect)
    }
    
    // Optional: allow row click to do something (like GitHub) if not hitting a specific button
    override func mouseUp(with event: NSEvent) {
        // If the user clicks the empty space of the row, act like normal menu item click
        // Assuming open notes as default action for now, or open repo
        openReleasesClicked() 
    }
}
