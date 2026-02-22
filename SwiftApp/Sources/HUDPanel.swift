import Cocoa

@MainActor
class HUDPanel: NSPanel {
    static let shared = HUDPanel()
    
    private let textLabel: NSTextField
    private let subtitleLabel: NSTextField
    private var hideTimer: Timer?
    
    private init() {
        textLabel = NSTextField(labelWithString: "")
        textLabel.font = .boldSystemFont(ofSize: 15)
        textLabel.textColor = .white
        textLabel.alignment = .center
        
        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .white
        subtitleLabel.alignment = .center
        subtitleLabel.cell?.wraps = true
        
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.appearance = NSAppearance(named: .darkAqua)  // HUDs are always dark, like macOS system HUDs
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 15
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        
        self.contentView = visualEffect
        
        let stackView = NSStackView(views: [textLabel, subtitleLabel])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        visualEffect.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            visualEffect.widthAnchor.constraint(equalToConstant: 320),
            visualEffect.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
            
            stackView.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: visualEffect.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: visualEffect.trailingAnchor, constant: -20)
        ])
    }
    
    func show(title: String, subtitle: String = "", duration: TimeInterval = 3.0) {
        textLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        
        self.center()
        
        // Show panel with animation
        self.alphaValue = 0.0
        self.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 1.0
        }
        
        // Setup hide timer
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
    }
    
    private func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            self.animator().alphaValue = 0.0
        }) {
            self.orderOut(nil)
        }
    }
}
