import Cocoa

@MainActor
protocol OAuthWindowDelegate: AnyObject {
    func oauthFinished(token: String?)
}

class OAuthWindowController: NSWindowController {
    
    weak var delegate: OAuthWindowDelegate?
    
    private let userCode: String
    private let verificationUri: String
    private let deviceCode: String
    private let interval: Int
    private let expiresIn: Int
    
    private let codeLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    
    init(userCode: String, verificationUri: String, deviceCode: String, interval: Int, expiresIn: Int) {
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.deviceCode = deviceCode
        self.interval = interval
        self.expiresIn = expiresIn
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = Translations.get("configureToken")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        
        super.init(window: window)
        setupUI()
        startPolling()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let window = self.window else { return }
        
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .underWindowBackground
        window.contentView = visualEffect
        
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 15
        stackView.edgeInsets = NSEdgeInsets(top: 25, left: 25, bottom: 25, right: 25)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        visualEffect.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            stackView.widthAnchor.constraint(equalToConstant: 320)
        ])
        
        // GitHub Icon (placeholder or symbol)
        let iconView = NSImageView(image: NSImage(systemSymbolName: "person.badge.key.fill", accessibilityDescription: nil)!)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        iconView.contentTintColor = .systemBlue
        stackView.addArrangedSubview(iconView)
        
        // Instructions
        let instructions = NSTextField(labelWithString: Translations.get("oauthInstructions").format(with: ["code": ""]))
        instructions.alignment = .center
        instructions.font = .systemFont(ofSize: 13)
        // Clean up the string to remove the placeholder if needed, or just set it
        instructions.stringValue = Translations.get("oauthInstructions").replacingOccurrences(of: "\n\n{code}", with: "").replacingOccurrences(of: "{code}", with: "")
        stackView.addArrangedSubview(instructions)
        
        // Code
        codeLabel.stringValue = userCode
        codeLabel.font = .systemFont(ofSize: 28, weight: .bold)
        codeLabel.textColor = .labelColor
        codeLabel.isSelectable = true
        stackView.addArrangedSubview(codeLabel)
        
        // Buttons
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        
        let openBtn = NSButton(title: Translations.get("openBrowser"), target: self, action: #selector(openBrowser))
        openBtn.bezelStyle = .rounded
        openBtn.keyEquivalent = "\r"
        
        let cancelBtn = NSButton(title: Translations.get("cancel"), target: self, action: #selector(cancelClicked))
        cancelBtn.bezelStyle = .rounded
        
        buttonStack.addArrangedSubview(cancelBtn)
        buttonStack.addArrangedSubview(openBtn)
        stackView.addArrangedSubview(buttonStack)
        
        // Spinner
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.startAnimation(nil)
        stackView.addArrangedSubview(spinner)
    }
    
    @objc private func openBrowser() {
        if let url = URL(string: verificationUri) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func cancelClicked() {
        GitHubAuth.shared.cancelPolling()
        closeSheet(with: nil)
    }
    
    private func startPolling() {
        Task {
            do {
                if let token = try await GitHubAuth.shared.pollForToken(deviceCode: deviceCode, interval: interval, expiresIn: expiresIn) {
                    DispatchQueue.main.async {
                        self.closeSheet(with: token)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.closeSheet(with: nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.closeSheet(with: nil)
                }
            }
        }
    }
    
    private func closeSheet(with token: String?) {
        delegate?.oauthFinished(token: token)
        self.window?.close()
    }
}
