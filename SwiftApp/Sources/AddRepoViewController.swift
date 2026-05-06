import Cocoa
import QuartzCore

class AddRepoViewController: NSViewController, NSTextFieldDelegate {
    private var inputField: NSTextField!
    private var eyeImageView: NSImageView!
    private var clipboardTimer: Timer?
    private var okButton: NSButton!
    
    // Callback to pass data back to AppDelegate/Coordinator
    var completionHandler: ((String?, String?, String?, @escaping (Bool) -> Void) -> Void)?
    
    override func loadView() {
        // Use a plain NSView as root — the NSPopover container provides the native
        // translucent material automatically, matching Preferences and Notes windows.
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 145))
        self.view = rootView
        
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: rootView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            
            rootView.widthAnchor.constraint(equalToConstant: 240),
            rootView.heightAnchor.constraint(equalToConstant: 145)
        ])
        
        // Animated Eye Icon - The centerpiece
        eyeImageView = NSImageView()
        eyeImageView.translatesAutoresizingMaskIntoConstraints = false
        if let eyeImage = NSImage(systemSymbolName: "eye", accessibilityDescription: "Watching Symbol") {
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
            eyeImageView.image = eyeImage.withSymbolConfiguration(config)
            eyeImageView.contentTintColor = Utils.appIconColor
        }
        eyeImageView.imageScaling = .scaleProportionallyUpOrDown
        eyeImageView.wantsLayer = true
        mainStack.addArrangedSubview(eyeImageView)
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(eyeClicked))
        eyeImageView.addGestureRecognizer(clickGesture)
        eyeImageView.toolTip = Translations.get("close")
        
        // Input Area - Focused, single-line, efficient
        inputField = NSTextField()
        inputField.placeholderString = Translations.get("repoPlaceholder")
        inputField.font = .systemFont(ofSize: 13, weight: .medium)
        inputField.alignment = .center
        inputField.isBezeled = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.delegate = self
        inputField.usesSingleLineMode = true
        inputField.cell?.wraps = false
        inputField.cell?.isScrollable = true
        mainStack.addArrangedSubview(inputField)
        
        // Subtle Separator / Underline for the input
        let underline = NSView()
        underline.wantsLayer = true
        underline.layer?.backgroundColor = NSColor.separatorColor.cgColor
        underline.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(underline)
        
        okButton = NSButton(title: Translations.get("add").uppercased(), target: self, action: #selector(okClicked))
        okButton.keyEquivalent = "\r"
        okButton.bezelStyle = .rounded
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.controlSize = .small
        
        // Style the button as a premium badge
        let attrTitle = NSAttributedString(string: Translations.get("add").uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.controlTextColor
        ])
        okButton.attributedTitle = attrTitle
        
        mainStack.addArrangedSubview(okButton)
        
        NSLayoutConstraint.activate([
            eyeImageView.widthAnchor.constraint(equalToConstant: 60),
            eyeImageView.heightAnchor.constraint(equalToConstant: 40),
            inputField.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -20),
            underline.heightAnchor.constraint(equalToConstant: 1),
            underline.widthAnchor.constraint(equalTo: inputField.widthAnchor, multiplier: 0.8),
            okButton.widthAnchor.constraint(equalToConstant: 80),
            okButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        resetAndPrepare()
        self.preferredContentSize = NSSize(width: 240, height: 145)
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        eyeImageView.layer?.removeAllAnimations()
    }
    
    func resetAndPrepare() {
        if let normalEye = NSImage(systemSymbolName: "eye", accessibilityDescription: "Watching Symbol") {
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
            eyeImageView.image = normalEye.withSymbolConfiguration(config)
            eyeImageView.contentTintColor = Utils.appIconColor
        }
        
        checkClipboardForRepo()
        
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            if self?.view.window?.isVisible == true {
                self?.checkClipboardForRepo()
            }
        }
        
        startEyeAnimation()
        self.view.window?.makeFirstResponder(inputField)
    }
    
    private func startEyeAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            eyeImageView.layer?.removeAllAnimations()
            eyeImageView.alphaValue = 1.0
            return
        }
        
        eyeImageView.layer?.removeAllAnimations()
        let breatheAnimation = CABasicAnimation(keyPath: "opacity")
        breatheAnimation.fromValue = 1.0
        breatheAnimation.toValue = 0.4
        breatheAnimation.duration = 2.0
        breatheAnimation.autoreverses = true
        breatheAnimation.repeatCount = .infinity
        breatheAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        eyeImageView.layer?.add(breatheAnimation, forKey: "breathingEye")
    }
    
    @objc private func eyeClicked() {
        eyeImageView.layer?.removeAllAnimations()
        eyeImageView.alphaValue = 1.0
        
        if let strikeEye = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Ouch") {
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
            eyeImageView.image = strikeEye.withSymbolConfiguration(config)
            eyeImageView.contentTintColor = .systemRed
        }
        
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.timingFunction = CAMediaTimingFunction(name: .linear)
            shake.duration = 0.4
            shake.values = [-6.0, 6.0, -5.0, 5.0, -4.0, 4.0, -2.0, 2.0, 0.0]
            eyeImageView.layer?.add(shake, forKey: "shakeNode")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard self != nil else { return }
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.addRepoPopover?.performClose(nil)
            }
        }
    }
    
    private func checkClipboardForRepo() {
        // Only auto-fill if the field is empty to avoid fighting with manual typing
        guard inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        if let clipboardRepo = Utils.getGitHubRepoFromClipboard() {
            if !ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == clipboardRepo.lowercased() }) {
                inputField.stringValue = clipboardRepo
            }
        }
    }
    
    @objc func okClicked() {
        guard okButton.isEnabled else { return }
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        okButton.isEnabled = false
        let handler: (Bool) -> Void = { [weak self] success in
            guard let self = self else { return }
            self.okButton.isEnabled = true
            if success {
                self.inputField.stringValue = ""
                self.playSuccessAnimation()
            } else {
                self.playErrorAnimation()
            }
        }
        
        // Pass everything as manual, RepoCoordinator.addRepoSmart will distinguish 
        // between GitHub (owner/repo) and Cask (name) automatically.
        completionHandler?(text, "manual", nil, handler)
    }
    
    private func playSuccessAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if #available(macOS 14.0, *) {
            eyeImageView.addSymbolEffect(.bounce, options: .nonRepeating)
        }
    }
    
    private func playErrorAnimation() {
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.duration = 0.4
            shake.values = [-4.0, 4.0, -3.0, 3.0, 0.0]
            eyeImageView.layer?.add(shake, forKey: "errorShake")
        }
        eyeImageView.contentTintColor = .systemRed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.eyeImageView.contentTintColor = Utils.appIconColor
        }
    }
}
