import Cocoa

class InteractiveHUDView: NSVisualEffectView {
    var onClick: (() -> Void)?
    
    override func resetCursorRects() {
        super.resetCursorRects()
        if onClick != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if let action = onClick {
            action()
        } else {
            super.mouseUp(with: event)
        }
    }
}

@MainActor
class HUDPanel: NSPanel {
    static let shared = HUDPanel()
    
    let visualEffect: InteractiveHUDView
    let iconView: NSImageView
    let textLabel: NSTextField
    let subtitleLabel: NSTextField
    let detailLabel: NSTextField
    let progressBar: NSProgressIndicator
    
    // Path badge for destination folder display & interaction
    let pathBadge: NSStackView
    let pathIcon: NSImageView
    let pathLabel: NSTextField
    
    // Interruptible operation controls (e.g. downloads)
    let cancelButton: NSButton
    private var cancelAction: (() -> Void)?
    
    private var hideTimer: Timer?
    private var presentationToken = UUID()
    private var clickAction: (() -> Void)?
    
    private init() {
        iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.isHidden = true
        
        textLabel = NSTextField(labelWithString: "")
        textLabel.font = .boldSystemFont(ofSize: 15)
        textLabel.textColor = .white
        textLabel.alignment = .center
        textLabel.lineBreakMode = .byTruncatingMiddle
        textLabel.maximumNumberOfLines = 2
        textLabel.cell?.truncatesLastVisibleLine = true
        textLabel.preferredMaxLayoutWidth = 300
        
        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.cell?.truncatesLastVisibleLine = true
        subtitleLabel.preferredMaxLayoutWidth = 300
        
        detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.preferredMaxLayoutWidth = 300
        detailLabel.isHidden = true
        
        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0.0
        progressBar.maxValue = 1.0
        progressBar.doubleValue = 0.0
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true
        
        // Path badge (folder icon + friendly path)
        pathIcon = NSImageView()
        if let folderImg = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            pathIcon.image = folderImg.withSymbolConfiguration(config)
        }
        pathIcon.contentTintColor = .systemBlue
        pathIcon.translatesAutoresizingMaskIntoConstraints = false
        pathIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        pathIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true
        
        pathLabel = NSTextField(labelWithString: "")
        pathLabel.font = .systemFont(ofSize: 11, weight: .medium)
        pathLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.alignment = .center
        
        pathBadge = NSStackView(views: [pathIcon, pathLabel])
        pathBadge.orientation = .horizontal
        pathBadge.alignment = .centerY
        pathBadge.spacing = 6
        pathBadge.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        pathBadge.wantsLayer = true
        pathBadge.layer?.cornerRadius = 8
        pathBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        pathBadge.translatesAutoresizingMaskIntoConstraints = false
        pathBadge.isHidden = true
        
        cancelButton = NSButton()
        cancelButton.title = Translations.get("cancel")
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.font = .systemFont(ofSize: 11, weight: .medium)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.isHidden = true
        
        visualEffect = InteractiveHUDView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.appearance = NSAppearance(named: .darkAqua)
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 18
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 140),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonClicked)
        
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.contentView = visualEffect
        
        let stackView = NSStackView(views: [iconView, textLabel, progressBar, subtitleLabel, detailLabel, cancelButton, pathBadge])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 7
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        visualEffect.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            visualEffect.widthAnchor.constraint(equalToConstant: 340),
            
            stackView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 18),
            stackView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -18),
            stackView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -20),
            
            textLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            progressBar.widthAnchor.constraint(equalToConstant: 280),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
        ])
    }
    
    // MARK: - Generic Presentation Methods
    
    func show(title: String, subtitle: String = "", image: NSImage? = nil, duration: TimeInterval? = 3.0) {
        resetInteraction()
        
        iconView.image = image
        iconView.contentTintColor = nil
        iconView.isHidden = image == nil
        progressBar.isHidden = true
        detailLabel.isHidden = true
        pathBadge.isHidden = true
        
        textLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.isHidden = subtitle.isEmpty
        
        present(duration: duration)
    }
    
    func showProgress(title: String, subtitle: String = "", image: NSImage? = nil, progress: Double = 0.0) {
        resetInteraction()
        
        iconView.image = image
        iconView.contentTintColor = nil
        iconView.isHidden = image == nil
        textLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.isHidden = subtitle.isEmpty
        detailLabel.isHidden = true
        pathBadge.isHidden = true
        
        progressBar.doubleValue = max(0.0, min(1.0, progress))
        progressBar.isIndeterminate = (progress <= 0.0)
        if progressBar.isIndeterminate { progressBar.startAnimation(nil) }
        progressBar.isHidden = false
        
        present(duration: nil)
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
        resetInteraction()
        progressBar.isHidden = true
        detailLabel.isHidden = true
        pathBadge.isHidden = true
        
        let symbolName = isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
            iconView.image = image.withSymbolConfiguration(config)
            iconView.contentTintColor = isSuccess ? .systemGreen : .systemRed
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
        
        textLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.isHidden = subtitle.isEmpty
        
        present(duration: duration)
    }
    
    // MARK: - Specialized Download Progression & Completion
    
    func showDownloadProgress(title: String, status: String, details: String = "", progress: Double = 0.0, onCancel: (() -> Void)? = nil) {
        resetInteraction()
        
        let dlImage = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        iconView.image = dlImage?.withSymbolConfiguration(config)
        iconView.contentTintColor = .systemBlue
        iconView.isHidden = false
        
        textLabel.stringValue = title
        
        subtitleLabel.stringValue = status
        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        subtitleLabel.isHidden = status.isEmpty
        
        detailLabel.stringValue = details
        detailLabel.isHidden = details.isEmpty
        
        pathBadge.isHidden = true
        
        progressBar.doubleValue = max(0.0, min(1.0, progress))
        progressBar.isIndeterminate = (progress <= 0.0)
        if progressBar.isIndeterminate { progressBar.startAnimation(nil) }
        progressBar.isHidden = false
        
        if let onCancel = onCancel {
            self.cancelAction = onCancel
            self.cancelButton.title = Translations.get("cancel")
            self.cancelButton.isHidden = false
        } else {
            self.cancelAction = nil
            self.cancelButton.isHidden = true
        }
        
        present(duration: nil)
    }
    
    func updateDownloadProgress(status: String, details: String, progress: Double) {
        subtitleLabel.stringValue = status
        subtitleLabel.isHidden = status.isEmpty
        detailLabel.stringValue = details
        detailLabel.isHidden = details.isEmpty
        if progress > 0.0 {
            progressBar.isIndeterminate = false
            progressBar.doubleValue = max(0.0, min(1.0, progress))
        }
    }
    
    func showDownloadCompletion(title: String, subtitle: String, sha: String? = nil, destinationURL: URL, duration: TimeInterval = 4.0) {
        resetInteraction()
        progressBar.isHidden = true
        cancelButton.isHidden = true
        cancelAction = nil
        
        let symbolName = "checkmark.circle.fill"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
            iconView.image = image.withSymbolConfiguration(config)
            iconView.contentTintColor = .systemGreen
            iconView.isHidden = false
        }
        
        textLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.isHidden = subtitle.isEmpty
        
        if let sha = sha, !sha.isEmpty {
            let formattedSHA = sha.hasPrefix("SHA-256:") ? sha : "SHA-256: \(sha)"
            detailLabel.stringValue = formattedSHA
            detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            detailLabel.textColor = NSColor.white.withAlphaComponent(0.7)
            detailLabel.toolTip = formattedSHA
            detailLabel.isHidden = false
        } else {
            detailLabel.isHidden = true
        }
        
        // Format path and setup click-to-reveal
        let folderURL = destinationURL.deletingLastPathComponent()
        let pathStr = HUDPanel.friendlyPath(for: folderURL)
        let finderHint = Translations.get("showInFinder")
        pathLabel.stringValue = "\(pathStr)  ·  \(finderHint)"
        pathBadge.isHidden = false
        
        let fileToReveal = destinationURL
        setClickAction { [weak self] in
            NSWorkspace.shared.activateFileViewerSelecting([fileToReveal])
            self?.hide()
        }
        
        present(duration: duration)
    }
    
    func showCancellation(title: String, subtitle: String = "", duration: TimeInterval = 2.5) {
        resetInteraction()
        progressBar.isHidden = true
        cancelButton.isHidden = true
        cancelAction = nil
        pathBadge.isHidden = true
        detailLabel.isHidden = true
        
        let symbolName = "xmark.circle.fill"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
            iconView.image = image.withSymbolConfiguration(config)
            iconView.contentTintColor = .systemOrange
            iconView.isHidden = false
        }
        
        textLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.isHidden = subtitle.isEmpty
        
        present(duration: duration)
    }
    
    // MARK: - Helpers
    
    static func friendlyPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fullPath = url.path
        if fullPath == home {
            return "~"
        } else if fullPath.hasPrefix(home + "/") {
            return "~/" + fullPath.dropFirst(home.count + 1)
        }
        return url.lastPathComponent
    }
    
    private func resetInteraction() {
        clickAction = nil
        cancelAction = nil
        cancelButton.isHidden = true
        visualEffect.onClick = nil
        visualEffect.discardCursorRects()
        visualEffect.resetCursorRects()
    }
    
    @objc private func cancelButtonClicked() {
        let action = cancelAction
        resetInteraction()
        action?()
    }
    
    private func setClickAction(_ action: @escaping () -> Void) {
        self.clickAction = action
        visualEffect.onClick = action
        visualEffect.discardCursorRects()
        visualEffect.resetCursorRects()
    }
    
    private func present(duration: TimeInterval?) {
        self.center()
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        
        presentationToken = UUID()
        
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.alphaValue = 1.0
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.animator().alphaValue = 1.0
            }
        }
        
        hideTimer?.invalidate()
        hideTimer = nil
        if let dur = duration {
            let currentToken = presentationToken
            let newTimer = Timer(timeInterval: dur, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if self?.presentationToken == currentToken {
                        self?.hide()
                    }
                }
            }
            RunLoop.current.add(newTimer, forMode: .common)
            hideTimer = newTimer
        }
    }
    
    func hide() {
        let currentToken = presentationToken
        resetInteraction()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.alphaValue = 0.0
            self.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
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
