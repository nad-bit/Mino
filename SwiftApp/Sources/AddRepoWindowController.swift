import Cocoa

class AddRepoWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private var inputField: NSTextField!
    private var brewPopup: NSPopUpButton!
    private var radioManual: NSButton!
    private var radioBrew: NSButton!
    private var titleLabel: NSTextField!
    private var eyeImageView: NSImageView!
    
    // Callback to pass data back to AppDelegate
    var completionHandler: ((String?, String?, String?) -> Void)?
    
    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 380, height: 260)
        let window = NSWindow(contentRect: windowRect,
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        window.title = Translations.get("addRepoUnified")
        window.center()
        
        super.init(window: window)
        window.delegate = self
        
        // Setup UI
        let container = NSView(frame: windowRect)
        
        // Animated Eye Icon
        eyeImageView = NSImageView()
        eyeImageView.translatesAutoresizingMaskIntoConstraints = false
        if let eyeImage = NSImage(systemSymbolName: "eye", accessibilityDescription: "Watching Symbol") {
            // Apply a tint color to match the app's accent
            let config = NSImage.SymbolConfiguration(pointSize: 42, weight: .light)
            eyeImageView.image = eyeImage.withSymbolConfiguration(config)
            eyeImageView.contentTintColor = .controlAccentColor
        }
        eyeImageView.imageScaling = .scaleProportionallyUpOrDown
        // We will animate the layer
        eyeImageView.wantsLayer = true
        container.addSubview(eyeImageView)
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(eyeClicked))
        eyeImageView.addGestureRecognizer(clickGesture)
        
        titleLabel = NSTextField(labelWithString: Translations.get("enterRepoMsg"))
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        container.addSubview(titleLabel)
        
        radioManual = NSButton(radioButtonWithTitle: Translations.get("manualOption"), target: self, action: #selector(radioChanged(_:)))
        radioManual.tag = 1
        radioManual.state = .on
        radioManual.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(radioManual)
        
        radioBrew = NSButton(radioButtonWithTitle: Translations.get("brewOption"), target: self, action: #selector(radioChanged(_:)))
        radioBrew.tag = 2
        radioBrew.translatesAutoresizingMaskIntoConstraints = false
        if HomebrewManager.shared.brewPath == nil {
            radioBrew.isEnabled = false
        }
        container.addSubview(radioBrew)
        
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
        
        let okButton = NSButton(title: Translations.get("ok"), target: self, action: #selector(okClicked))
        okButton.keyEquivalent = "\r" // Enter key
        okButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(okButton)
        
        let cancelButton = NSButton(title: Translations.get("cancel"), target: self, action: #selector(cancelClicked))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            eyeImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            eyeImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            eyeImageView.widthAnchor.constraint(equalToConstant: 60),
            eyeImageView.heightAnchor.constraint(equalToConstant: 45),
            
            titleLabel.topAnchor.constraint(equalTo: eyeImageView.bottomAnchor, constant: 15),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            
            radioManual.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 15),
            radioManual.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            
            radioBrew.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 15),
            radioBrew.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
            
            inputField.topAnchor.constraint(equalTo: radioManual.bottomAnchor, constant: 20),
            inputField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            inputField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
            inputField.heightAnchor.constraint(equalToConstant: 24),
            
            brewPopup.topAnchor.constraint(equalTo: radioManual.bottomAnchor, constant: 20),
            brewPopup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            brewPopup.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
            brewPopup.heightAnchor.constraint(equalToConstant: 24),
            
            okButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            okButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
            okButton.widthAnchor.constraint(equalToConstant: 80),
            
            cancelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            cancelButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -10),
            cancelButton.widthAnchor.constraint(equalToConstant: 80)
        ])
        
        window.contentView = container
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func resetAndShow() {
        checkClipboardForRepo()
        
        // Ensure manual is selected by default every time it opens
        radioManual.state = .on
        radioChanged(radioManual)
        
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
                self.eyeImageView.contentTintColor = .controlAccentColor
            }
            // Restart breathing
            self.startEyeAnimation()
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        checkClipboardForRepo()
    }
    private func checkClipboardForRepo() {
        if let clipboardRepo = Utils.getGitHubRepoFromClipboard(), clipboardRepo != inputField.stringValue {
            // Only auto-fill if we aren't already tracking it
            if !ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == clipboardRepo.lowercased() }) {
                inputField.stringValue = clipboardRepo
            }
        }
    }
    
    @objc func radioChanged(_ sender: NSButton) {
        if sender.tag == 1 {
            inputField.isHidden = false
            brewPopup.isHidden = true
            titleLabel.stringValue = Translations.get("enterRepoMsg")
        } else if sender.tag == 2 {
            inputField.isHidden = true
            brewPopup.isHidden = false
            titleLabel.stringValue = Translations.get("addFromBrew")
            
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
        self.window?.orderOut(nil)
        
        if radioManual.state == .on {
            let repo = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !repo.isEmpty {
                completionHandler?(repo, "manual", nil)
            }
        } else {
            if brewPopup.indexOfSelectedItem > 0 {
                let selectedCask = brewPopup.titleOfSelectedItem
                completionHandler?(nil, "brew", selectedCask)
            }
        }
        
        // Empty the field after submitting
        inputField.stringValue = ""
    }
    
    @objc func cancelClicked() {
        self.window?.orderOut(nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Just hide it, keep instance alive
        eyeImageView.layer?.removeAllAnimations()
    }
}
