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
    private var isHovered = false
    private var highlightObserver: NSObjectProtocol?
    
    init(repoName: String, labelText: String, caskName: String?, appDelegate: AppDelegate) {
        self.repoName = repoName
        self.caskName = caskName
        self.appDelegate = appDelegate
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 26)) // Temporarily fixed, will be adjusted dynamically by the AppDelegate
        
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
        
        // Direct layout for right-alignment
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(titleLabel)
        addSubview(buttonStack)
        
        // Priority to ensure title compresses before button stack gives up space
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8)
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
    
    // MARK: - AppKit Menu Highlight Lifecycle
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window != nil {
            if highlightObserver == nil {
                highlightObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name("RepoMenuItemHighlighted"), object: nil, queue: .main) { [weak self] notification in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        let highlightedItem = notification.object as? NSMenuItem
                        let isMe = (highlightedItem === self.enclosingMenuItem)
                        
                        if self.isHovered != isMe {
                            self.isHovered = isMe
                            self.needsDisplay = true
                            self.toggleButtons(visible: isMe)
                        }
                    }
                }
            }
        } else {
            if let obs = highlightObserver {
                NotificationCenter.default.removeObserver(obs)
                highlightObserver = nil
            }
            if isHovered {
                isHovered = false
                toggleButtons(visible: false)
            }
        }
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
