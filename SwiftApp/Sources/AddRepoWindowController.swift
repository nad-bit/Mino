import Cocoa

class AddRepoWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private var inputField: NSTextField!
    private var brewPopup: NSPopUpButton!
    private var segmentedControl: NSSegmentedControl!
    private var eyeImageView: NSImageView!
    private var clipboardTimer: Timer?
    private var okButton: NSButton!
    
    // Callback to pass data back to AppDelegate
    var completionHandler: ((String?, String?, String?, @escaping (Bool) -> Void) -> Void)?
    
    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 380, height: 210)
        let window = NSWindow(contentRect: windowRect,
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered,
                            defer: false)
        window.title = Translations.get("addRepoUnified")
        window.center()
        
        super.init(window: window)
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .floating
        
        // Setup UI with Vibrancy
        let container = NSVisualEffectView(frame: windowRect)
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        
        // Animated Eye Icon
        eyeImageView = NSImageView()
        eyeImageView.translatesAutoresizingMaskIntoConstraints = false
        if let eyeImage = NSImage(systemSymbolName: "eye", accessibilityDescription: "Watching Symbol") {
            // Apply a tint color to match the dynamically generated app icon color
            let config = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
            eyeImageView.image = eyeImage.withSymbolConfiguration(config)
            eyeImageView.contentTintColor = Utils.appIconColor
        }
        eyeImageView.imageScaling = .scaleProportionallyUpOrDown
        // We will animate the layer
        eyeImageView.wantsLayer = true
        container.addSubview(eyeImageView)
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(eyeClicked))
        eyeImageView.addGestureRecognizer(clickGesture)
        
        segmentedControl = NSSegmentedControl(labels: ["GitHub", "Homebrew"], trackingMode: .selectOne, target: self, action: #selector(segmentedChanged(_:)))
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        if HomebrewManager.shared.brewPath == nil {
            segmentedControl.setEnabled(false, forSegment: 1)
        }
        container.addSubview(segmentedControl)
        
        inputField = NSTextField()
        inputField.placeholderString = "owner/repo-name"
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.delegate = self
        container.addSubview(inputField)
        
        brewPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        brewPopup.addItem(withTitle: Translations.get("loadingBrew"))
        brewPopup.isEnabled = false
        brewPopup.isHidden = true
        brewPopup.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(brewPopup)
        
        let okButton = NSButton(title: Translations.get("add"), target: self, action: #selector(okClicked))
        okButton.keyEquivalent = "\r" // Enter key
        okButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(okButton)
        self.okButton = okButton
        
        NSLayoutConstraint.activate([
            eyeImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 15),
            eyeImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            eyeImageView.widthAnchor.constraint(equalToConstant: 60),
            eyeImageView.heightAnchor.constraint(equalToConstant: 45),
            
            segmentedControl.topAnchor.constraint(equalTo: eyeImageView.bottomAnchor, constant: 10),
            segmentedControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            
            inputField.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 15),
            inputField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            inputField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
            inputField.heightAnchor.constraint(equalToConstant: 24),
            
            brewPopup.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 15),
            brewPopup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            brewPopup.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
            brewPopup.heightAnchor.constraint(equalToConstant: 24),
            
            okButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            okButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            okButton.widthAnchor.constraint(equalToConstant: 80)
        ])
        
        window.contentView = container
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func resetAndShow() {
        checkClipboardForRepo()
        
        // Start live polling while floating
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            if self?.window?.isVisible == true {
                self?.checkClipboardForRepo()
            }
        }
        
        // Ensure manual is selected by default every time it opens
        segmentedControl.selectedSegment = 0
        segmentedChanged(segmentedControl)
        
        startEyeAnimation()
        
        self.showWindow(nil)
    }
    
    private func startEyeAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            eyeImageView.layer?.removeAllAnimations()
            eyeImageView.alphaValue = 1.0
            return
        }
        
        // Ensure any previous animation is removed before starting
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
        // Stop the peaceful breathing
        eyeImageView.layer?.removeAllAnimations()
        eyeImageView.alphaValue = 1.0
        
        // Change icon to a slashed/hurt eye in red
        if let strikeEye = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Ouch") {
            let config = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
            eyeImageView.image = strikeEye.withSymbolConfiguration(config)
            eyeImageView.contentTintColor = .systemRed
        }
        
        // Shake it in denial/pain if animations are allowed
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.timingFunction = CAMediaTimingFunction(name: .linear)
            shake.duration = 0.4
            shake.values = [-6.0, 6.0, -5.0, 5.0, -4.0, 4.0, -2.0, 2.0, 0.0]
            eyeImageView.layer?.add(shake, forKey: "shakeNode")
        }
        
        // Recover after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            if let normalEye = NSImage(systemSymbolName: "eye", accessibilityDescription: "Watching Symbol") {
                let config = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
                self.eyeImageView.image = normalEye.withSymbolConfiguration(config)
                self.eyeImageView.contentTintColor = Utils.appIconColor
            }
            // Restart breathing
            self.startEyeAnimation()
        }
    }
    
    private func checkClipboardForRepo() {
        if let clipboardRepo = Utils.getGitHubRepoFromClipboard(), clipboardRepo != inputField.stringValue {
            // Only auto-fill if we aren't already tracking it
            if !ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == clipboardRepo.lowercased() }) {
                inputField.stringValue = clipboardRepo
            }
        }
    }
    
    @objc func segmentedChanged(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            inputField.isHidden = false
            brewPopup.isHidden = true
        } else if sender.selectedSegment == 1 {
            inputField.isHidden = true
            brewPopup.isHidden = false
            
            if brewPopup.numberOfItems <= 1 {
                // Fetch brews asynchronously
                Task {
                    let casks = await HomebrewManager.shared.listCasks()
                    await MainActor.run {
                        self.updateBrewList(caskList: casks)
                    }
                }
            }
        }
    }
    
    func updateBrewList(caskList: [String]) {
        brewPopup.removeAllItems()
        if !caskList.isEmpty {
            let placeholder = Translations.get("selectCaskPlaceholder")
            brewPopup.addItems(withTitles: [placeholder] + caskList)
            brewPopup.isEnabled = true
        } else {
            brewPopup.addItems(withTitles: ["No casks found"])
            brewPopup.isEnabled = false
        }
    }
    
    @objc func okClicked() {
        guard okButton.isEnabled else { return }
        okButton.isEnabled = false
        
        let handler: (Bool) -> Void = { [weak self] success in
            guard let self = self else { return }
            self.okButton.isEnabled = true
            if success {
                self.inputField.stringValue = ""
                self.playSuccessZarpazo()
            }
        }
        
        if segmentedControl.selectedSegment == 0 {
            let repo = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !repo.isEmpty {
                completionHandler?(repo, "manual", nil, handler)
            } else {
                okButton.isEnabled = true
            }
        } else {
            if brewPopup.indexOfSelectedItem > 0 {
                let selectedCask = brewPopup.titleOfSelectedItem
                completionHandler?(nil, "brew", selectedCask, handler)
            } else {
                okButton.isEnabled = true
            }
        }
    }
    
    private func playSuccessZarpazo() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        
        eyeImageView.layer?.removeAllAnimations()
        
        if let pawImage = NSImage(systemSymbolName: "pawprint", accessibilityDescription: "Success") {
            let config = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
            eyeImageView.image = pawImage.withSymbolConfiguration(config)
            eyeImageView.contentTintColor = .systemGreen
        }
        
        let swipe = CABasicAnimation(keyPath: "transform.translation.y")
        swipe.fromValue = 50
        swipe.toValue = -50
        
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        
        let zarpazoGroup = CAAnimationGroup()
        zarpazoGroup.animations = [swipe, fade]
        zarpazoGroup.duration = 0.25
        zarpazoGroup.timingFunction = CAMediaTimingFunction(name: .easeIn)
        zarpazoGroup.fillMode = .forwards
        zarpazoGroup.isRemovedOnCompletion = false
        
        eyeImageView.layer?.add(zarpazoGroup, forKey: "pawScratch")
        
        // Revert to normal eye and breathing immediately after animation finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            if self.window?.isVisible == true {
                self.eyeImageView.layer?.removeAllAnimations()
                self.eyeImageView.alphaValue = 1.0
                
                if let normalEye = NSImage(systemSymbolName: "eye", accessibilityDescription: "Watching Symbol") {
                    let config = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
                    self.eyeImageView.image = normalEye.withSymbolConfiguration(config)
                    self.eyeImageView.contentTintColor = Utils.appIconColor
                }
                self.startEyeAnimation()
            }
        }
    }
    
    @objc func cancelClicked() {
        self.window?.orderOut(nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Stop background activities
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        eyeImageView.layer?.removeAllAnimations()
    }
}
