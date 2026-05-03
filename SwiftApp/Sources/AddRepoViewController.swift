import Cocoa
import QuartzCore

class AddRepoViewController: NSViewController, NSTextFieldDelegate {
    private var inputField: NSTextField!
    private var brewPopup: NSPopUpButton!
    private var segmentedControl: NSSegmentedControl!
    private var eyeImageView: NSImageView!
    private var clipboardTimer: Timer?
    private var okButton: NSButton!
    
    // Callback to pass data back to AppDelegate
    var completionHandler: ((String?, String?, String?, @escaping (Bool) -> Void) -> Void)?
    
    override func loadView() {
        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        
        // Increased transparency as requested by user
        container.alphaValue = 0.75
        
        self.view = container
        
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 8
        mainStack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mainStack)
        
        // Animated Eye Icon
        eyeImageView = NSImageView()
        eyeImageView.translatesAutoresizingMaskIntoConstraints = false
        if let eyeImage = NSImage(systemSymbolName: "eye", accessibilityDescription: "Watching Symbol") {
            let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .light)
            eyeImageView.image = eyeImage.withSymbolConfiguration(config)
            eyeImageView.contentTintColor = Utils.appIconColor
        }
        eyeImageView.imageScaling = .scaleProportionallyUpOrDown
        eyeImageView.wantsLayer = true
        mainStack.addArrangedSubview(eyeImageView)
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(eyeClicked))
        eyeImageView.addGestureRecognizer(clickGesture)
        eyeImageView.toolTip = Translations.get("close")
        
        segmentedControl = NSSegmentedControl(labels: ["GitHub", "Homebrew"], trackingMode: .selectOne, target: self, action: #selector(segmentedChanged(_:)))
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.controlSize = .small
        if HomebrewManager.shared.brewPath == nil {
            segmentedControl.setEnabled(false, forSegment: 1)
        }
        mainStack.addArrangedSubview(segmentedControl)
        
        // Input Container
        let inputContainer = NSView()
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(inputContainer)
        
        inputField = NSTextField()
        inputField.placeholderString = Translations.get("repoPlaceholder")
        inputField.font = .systemFont(ofSize: 11)
        inputField.isBezeled = true
        inputField.bezelStyle = .roundedBezel
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.delegate = self
        inputContainer.addSubview(inputField)
        
        brewPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        brewPopup.addItem(withTitle: Translations.get("loadingBrew"))
        brewPopup.font = .systemFont(ofSize: 11)
        brewPopup.isEnabled = false
        brewPopup.isHidden = true
        brewPopup.translatesAutoresizingMaskIntoConstraints = false
        brewPopup.controlSize = .small
        inputContainer.addSubview(brewPopup)
        
        okButton = NSButton(title: Translations.get("add"), target: self, action: #selector(okClicked))
        okButton.keyEquivalent = "\r"
        okButton.bezelStyle = .rounded
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.controlSize = .small
        mainStack.addArrangedSubview(okButton)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: container.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            eyeImageView.widthAnchor.constraint(equalToConstant: 48),
            eyeImageView.heightAnchor.constraint(equalToConstant: 32),
            
            inputContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 20),
            
            inputField.centerXAnchor.constraint(equalTo: inputContainer.centerXAnchor),
            inputField.widthAnchor.constraint(equalTo: inputContainer.widthAnchor),
            inputField.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            
            brewPopup.centerXAnchor.constraint(equalTo: inputContainer.centerXAnchor),
            brewPopup.widthAnchor.constraint(equalTo: inputContainer.widthAnchor),
            brewPopup.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            
            okButton.widthAnchor.constraint(equalToConstant: 70),
            okButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        resetAndPrepare()
        
        // Dynamic resize based on content
        self.preferredContentSize = self.view.fittingSize
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        eyeImageView.layer?.removeAllAnimations()
    }
    
    func resetAndPrepare() {
        // Reset eye icon to normal state
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
        
        segmentedControl.selectedSegment = 0
        segmentedChanged(segmentedControl)
        startEyeAnimation()
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
        // Stop the peaceful breathing
        eyeImageView.layer?.removeAllAnimations()
        eyeImageView.alphaValue = 1.0
        
        // Change icon to a slashed/hurt eye in red
        if let strikeEye = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Ouch") {
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
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
        
        // Close after the animation (allow seeing the "ouch" state)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard self != nil else { return }
            // Tell AppDelegate to close this popover
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.addRepoPopover?.performClose(nil)
            }
        }
    }
    
    private func checkClipboardForRepo() {
        if let clipboardRepo = Utils.getGitHubRepoFromClipboard(), clipboardRepo != inputField.stringValue {
            if !ConfigManager.shared.config.repos.contains(where: { $0.name.lowercased() == clipboardRepo.lowercased() }) {
                inputField.stringValue = clipboardRepo
            }
        }
    }
    
    @objc func segmentedChanged(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            inputField.isHidden = false
            brewPopup.isHidden = true
            // Auto-focus input when switching to GitHub
            self.view.window?.makeFirstResponder(inputField)
        } else if sender.selectedSegment == 1 {
            inputField.isHidden = true
            brewPopup.isHidden = false
            
            if brewPopup.numberOfItems <= 1 {
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
                self.playSuccessAnimation()
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
    
    private func playSuccessAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if #available(macOS 14.0, *) {
            eyeImageView.addSymbolEffect(.bounce, options: .nonRepeating)
        }
    }
}
