import Cocoa

@MainActor
class HUDPanel: NSPanel {
    static let shared = HUDPanel()
    
    private let iconView: NSImageView
    private let textLabel: NSTextField
    private let subtitleLabel: NSTextField
    private let progressBar: NSProgressIndicator
    private var hideTimer: Timer?
    private var presentationToken = UUID()
    
    private init() {
        iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.isHidden = true
        
        textLabel = NSTextField(labelWithString: "")
        textLabel.font = .boldSystemFont(ofSize: 15)
        textLabel.textColor = .white
        textLabel.alignment = .center
        textLabel.lineBreakMode = .byTruncatingMiddle
        textLabel.maximumNumberOfLines = 2
        textLabel.cell?.truncatesLastVisibleLine = true
        textLabel.preferredMaxLayoutWidth = 280
        
        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.cell?.truncatesLastVisibleLine = true
        subtitleLabel.preferredMaxLayoutWidth = 280
        
        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0.0
        progressBar.maxValue = 1.0
        progressBar.doubleValue = 0.0
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true
        
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.hidesOnDeactivate = false
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.appearance = NSAppearance(named: .darkAqua)
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 15
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        
        self.contentView = visualEffect
        
        let stackView = NSStackView(views: [iconView, textLabel, progressBar, subtitleLabel])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        visualEffect.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            visualEffect.widthAnchor.constraint(equalToConstant: 320),
            
            stackView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -20),
            stackView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -20),
            
            textLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            progressBar.widthAnchor.constraint(equalToConstant: 260),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
        ])
    }
    
    func show(title: String, subtitle: String = "", image: NSImage? = nil, duration: TimeInterval? = 3.0) {
        iconView.image = image
        iconView.contentTintColor = nil
        iconView.isHidden = image == nil
        progressBar.isHidden = true
        
        textLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        
        self.center()
        
        // Show panel with animation
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        
        presentationToken = UUID()
        
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.alphaValue = 1.0
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.animator().alphaValue = 1.0
            }
        }
        
        hideTimer?.invalidate()
        if let dur = duration {
            let newTimer = Timer(timeInterval: dur, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.hide()
                }
            }
            RunLoop.current.add(newTimer, forMode: .common)
            hideTimer = newTimer
        }
    }
    
    func showProgress(title: String, subtitle: String = "", image: NSImage? = nil, progress: Double = 0.0) {
        iconView.image = image
        iconView.contentTintColor = nil
        iconView.isHidden = image == nil
        textLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        progressBar.doubleValue = max(0.0, min(1.0, progress))
        progressBar.isIndeterminate = (progress <= 0.0)
        if progressBar.isIndeterminate { progressBar.startAnimation(nil) }
        progressBar.isHidden = false
        
        hideTimer?.invalidate()
        hideTimer = nil
        
        self.center()
        self.alphaValue = 1.0
        self.orderFrontRegardless()
        presentationToken = UUID()
    }
    
    func updateProgress(subtitle: String, progress: Double) {
        subtitleLabel.stringValue = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        if progress > 0.0 {
            progressBar.isIndeterminate = false
            progressBar.doubleValue = max(0.0, min(1.0, progress))
        }
    }
    
    func showCompletion(title: String, subtitle: String, isSuccess: Bool, duration: TimeInterval = 3.0) {
        progressBar.isHidden = true
        let symbolName = isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
            iconView.image = image.withSymbolConfiguration(config)
            iconView.contentTintColor = isSuccess ? .systemGreen : .systemRed
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
        
        textLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        
        // Ensure the panel is visible and positioned even when called standalone
        // (not preceded by showProgress).
        self.center()
        self.alphaValue = 1.0
        self.orderFrontRegardless()
        presentationToken = UUID()
        
        hideTimer?.invalidate()
        let newTimer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
        RunLoop.current.add(newTimer, forMode: .common)
        hideTimer = newTimer
    }
    
    func hide() {
        let currentToken = presentationToken
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.alphaValue = 0.0
            self.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                self.animator().alphaValue = 0.0
            }) { [weak self] in
                Task { @MainActor in
                    if self?.presentationToken == currentToken {
                        self?.orderOut(nil)
                    }
                }
            }
        }
    }
}
