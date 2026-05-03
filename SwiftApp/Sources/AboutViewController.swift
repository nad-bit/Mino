import Cocoa

class AboutViewController: NSViewController {
    
    class AboutView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }
    
    override func loadView() {
        let container = AboutView()
        self.view = container
        
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        // App Icon
        let appIconImage = NSImage(named: NSImage.applicationIconName) ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        let iconView = NSImageView(image: appIconImage!)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        stackView.addArrangedSubview(iconView)
        
        // App Name (Blue Pill)
        let namePill = createPill(text: "Mino", color: .systemBlue, fontSize: 16)
        namePill.toolTip = "https://github.com/nad-bit/Mino"
        let nameClick = NSClickGestureRecognizer(target: self, action: #selector(openGitHub))
        namePill.addGestureRecognizer(nameClick)
        stackView.addArrangedSubview(namePill)
        
        // Version and Credits Pills
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        let pillsStack = NSStackView()
        pillsStack.orientation = .vertical
        pillsStack.spacing = 8
        pillsStack.alignment = .centerX
        
        pillsStack.addArrangedSubview(createPill(text: Translations.get("versionTitle"), color: .systemGreen))
        pillsStack.addArrangedSubview(createPill(text: version, color: .systemOrange))
        pillsStack.addArrangedSubview(createPill(text: "nad", color: .systemGray))
        
        stackView.addArrangedSubview(pillsStack)
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
