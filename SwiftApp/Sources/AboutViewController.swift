import Cocoa

class AboutViewController: NSViewController {
    
    class AboutView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }
    
    override func loadView() {
        let container = AboutView(frame: NSRect(x: 0, y: 0, width: 280, height: 380))
        self.view = container
        
        // The NSPopover container provides native translucent material automatically,
        // matching Preferences and Notes windows — no manual NSVisualEffectView needed.
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 24
        mainStack.edgeInsets = NSEdgeInsets(top: 40, left: 30, bottom: 40, right: 30)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: container.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            container.widthAnchor.constraint(equalToConstant: 280)
        ])
        
        // --- Identity Group (Icon + Name) ---
        let identityStack = NSStackView()
        identityStack.orientation = .vertical
        identityStack.spacing = 16
        identityStack.alignment = .centerX
        
        let appIconImage = NSImage(named: NSImage.applicationIconName) ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        let iconView = NSImageView(image: appIconImage!)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        identityStack.addArrangedSubview(iconView)
        
        let namePill = createPill(text: "Mino", color: .systemBlue, fontSize: 18)
        namePill.toolTip = "https://github.com/nad-bit/Mino"
        let nameClick = NSClickGestureRecognizer(target: self, action: #selector(openGitHub))
        namePill.addGestureRecognizer(nameClick)
        identityStack.addArrangedSubview(namePill)
        
        mainStack.addArrangedSubview(identityStack)
        
        // --- Info Group (Version + Credits) ---
        let infoStack = NSStackView()
        infoStack.orientation = .vertical
        infoStack.spacing = 8
        infoStack.alignment = .centerX
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "???"
        
        // Version "Combo" Pill
        let versionLabel = createPill(text: "\(Translations.get("versionTitle")) \(version)", color: .systemOrange.withAlphaComponent(0.8), fontSize: 11)
        infoStack.addArrangedSubview(versionLabel)
        
        // Author Pill
        let authorPill = createPill(text: "nad", color: .secondaryLabelColor, fontSize: 10)
        infoStack.addArrangedSubview(authorPill)
        
        mainStack.addArrangedSubview(infoStack)
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        self.preferredContentSize = self.view.fittingSize
    }
    
    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/nad-bit/Mino") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func createPill(text: String, color: NSColor, fontSize: CGFloat = 11) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = .white
        field.translatesAutoresizingMaskIntoConstraints = false
        
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = color.cgColor
        container.layer?.cornerRadius = 10
        container.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(field)
        
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14)
        ])
        
        return container
    }
}
