import Cocoa

@MainActor
class FooterMenuItemView: NSView {
    
    private let settingsBtn = MenuActionButton()
    private let quitBtn = MenuActionButton()
    private let appDelegate: AppDelegate
    
    // Track states
    private var lastHighlightState = false
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 32)) // slightly taller for safe framing at bottom
        self.autoresizingMask = [.width]
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // Settings Button
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        settingsBtn.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: Translations.get("preferences"))?.withSymbolConfiguration(config)
        settingsBtn.isBordered = false
        settingsBtn.target = self
        settingsBtn.action = #selector(settingsClicked)
        settingsBtn.toolTip = Translations.get("preferences")
        settingsBtn.baseColor = .secondaryLabelColor
        settingsBtn.hoverColor = .labelColor
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // Quit Button
        quitBtn.image = NSImage(systemSymbolName: "power", accessibilityDescription: Translations.get("quit"))?.withSymbolConfiguration(config)
        quitBtn.isBordered = false
        quitBtn.target = self
        quitBtn.action = #selector(quitClicked)
        quitBtn.toolTip = Translations.get("quit")
        quitBtn.baseColor = .secondaryLabelColor
        quitBtn.hoverColor = .labelColor
        quitBtn.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(settingsBtn)
        addSubview(quitBtn)
        
        NSLayoutConstraint.activate([
            settingsBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            settingsBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            settingsBtn.widthAnchor.constraint(equalToConstant: 24),
            settingsBtn.heightAnchor.constraint(equalToConstant: 24),
            
            quitBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            quitBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            quitBtn.widthAnchor.constraint(equalToConstant: 24),
            quitBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    @objc private func settingsClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            appDelegate.performAfterMenuClose {
                self.appDelegate.openSettingsWindow(menuItem)
            }
        }
    }
    
    @objc private func quitClicked() {
        if let menuItem = enclosingMenuItem {
            appDelegate.animateStatusIcon(with: .scale)
            appDelegate.performAfterMenuClose {
                self.appDelegate.quitApp(menuItem)
            }
        }
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
        let btnBase: NSColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let btnHover: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        
        settingsBtn.baseColor = btnBase
        settingsBtn.hoverColor = btnHover
        quitBtn.baseColor = btnBase
        quitBtn.hoverColor = btnHover
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
