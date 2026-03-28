import Cocoa

@MainActor
class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    
    let tokenStatusLabel = NSTextField(labelWithString: "")
    let tokenConnectBtn = NSButton(title: Translations.get("connectGitHub"), target: nil, action: nil)
    let tokenDeleteBtn = NSButton(title: Translations.get("deleteToken"), target: nil, action: nil)
    let oauthCodeLabel = NSTextField(labelWithString: "")
    let oauthActionBtn = NSButton(title: Translations.get("openBrowser"), target: nil, action: nil)
    let oauthCancelBtn = NSButton(title: Translations.get("cancelAuth"), target: nil, action: nil)
    let oauthSpinner = NSProgressIndicator()
    let oauthStack = NSStackView()
    var currentVerificationUri: String?
    
    let intervalLabel = NSTextField(labelWithString: "")
    let intervalSlider = NSSlider()
    var initialIntervalHours: Int = 1
    
    let loginSwitch = NSSwitch()
    private let ownerSwitch = NSSwitch()
    private let newIndicatorSwitch = NSSwitch()
    private let newIndicatorStepper = NSStepper()
    let newIndicatorLabel = NSTextField(labelWithString: "")
    let sortSegment = NSSegmentedControl()
    let layoutSegment = NSSegmentedControl()
    private let compactModeSwitch = NSSwitch()
    
    var tempToken: String?
    private var isUpdatingSelf = false
    
    // Debounce properties for saving settings
    private var intervalSaveWorkItem: DispatchWorkItem?
    private var indicatorSaveWorkItem: DispatchWorkItem?
    private var generalSaveWorkItem: DispatchWorkItem?

    

    
    override init(window: NSWindow?) {
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init() {
        // Adjust window height to accommodate the title and multi-line token
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = Translations.get("preferences")
        window.center()
        self.init(window: window)
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        setupUI()
        loadCurrentSettings()
        
        NotificationCenter.default.addObserver(self, selector: #selector(configDidUpdate), name: Notification.Name("ConfigChanged"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func configDidUpdate() {
        guard !isUpdatingSelf else { return }
        DispatchQueue.main.async {
            self.loadCurrentSettings()
        }
    }
    
    private func setupUI() {
        guard let window = self.window else { return }
        
        let visualEffectView = NSVisualEffectView(frame: window.contentRect(forFrameRect: window.frame))
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        window.contentView = visualEffectView
        
        guard let contentView = window.contentView else { return }
        
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 15
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        // --- 0. About Section ---
        let aboutStack = NSStackView()
        aboutStack.orientation = .vertical
        aboutStack.alignment = .centerX
        aboutStack.spacing = 5
        aboutStack.translatesAutoresizingMaskIntoConstraints = false
        
        let appIconImage = NSImage(named: NSImage.applicationIconName) ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        let iconView = NSImageView(image: appIconImage!)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        aboutStack.addArrangedSubview(iconView)
        
        let appNameLabel = NSTextField(labelWithString: "Mino")
        appNameLabel.font = .boldSystemFont(ofSize: 18)
        aboutStack.addArrangedSubview(appNameLabel)
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let aboutText = Translations.get("aboutMsg").format(with: ["version": version, "build": build])
        
        let appVersionLabel = NSTextField(labelWithString: aboutText)
        appVersionLabel.alignment = .center
        appVersionLabel.textColor = .secondaryLabelColor
        appVersionLabel.font = .systemFont(ofSize: 12)
        aboutStack.addArrangedSubview(appVersionLabel)
        
        stackView.addArrangedSubview(aboutStack)
        
        // Adjust alignment for the rest of the form
        let formStack = NSStackView()
        formStack.orientation = .vertical
        formStack.alignment = .centerX
        formStack.spacing = 18
        formStack.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(formStack)
        formStack.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40).isActive = true
        
        // --- 1. Token Section ---
        let tokenStack = createInnerStack()
        let tokenLabel = NSTextField(labelWithString: Translations.get("configureToken"))
        tokenStatusLabel.textColor = .secondaryLabelColor
        tokenStatusLabel.font = .systemFont(ofSize: 13)
        tokenConnectBtn.target = self
        tokenConnectBtn.action = #selector(startOAuth(_:))
        tokenDeleteBtn.target = self
        tokenDeleteBtn.action = #selector(deleteToken(_:))
        addSettingsRow(to: tokenStack, label: tokenLabel, controls: [tokenStatusLabel, tokenConnectBtn, tokenDeleteBtn])
        
        oauthCodeLabel.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        oauthCodeLabel.isSelectable = true
        oauthActionBtn.target = self
        oauthActionBtn.action = #selector(openGitHubAuth(_:))
        oauthCancelBtn.target = self
        oauthCancelBtn.action = #selector(cancelOAuth(_:))
        
        oauthSpinner.style = .spinning
        oauthSpinner.controlSize = .small
        oauthSpinner.isDisplayedWhenStopped = false
        oauthSpinner.translatesAutoresizingMaskIntoConstraints = false
        
        oauthStack.orientation = .horizontal
        oauthStack.alignment = .top
        oauthStack.translatesAutoresizingMaskIntoConstraints = false
        
        let emptyLabel = NSTextField(labelWithString: "")
        emptyLabel.isBordered = false
        emptyLabel.drawsBackground = false
        emptyLabel.isEditable = false
        oauthStack.addArrangedSubview(emptyLabel)
        
        let spring = NSView()
        spring.setContentHuggingPriority(.defaultLow, for: .horizontal)
        oauthStack.addArrangedSubview(spring)
        
        let oauthButtonStack = NSStackView(views: [oauthActionBtn, oauthCancelBtn, oauthSpinner])
        oauthButtonStack.orientation = .horizontal
        oauthButtonStack.spacing = 10
        
        let oauthContentStack = NSStackView(views: [oauthCodeLabel, oauthButtonStack])
        oauthContentStack.orientation = .vertical
        oauthContentStack.alignment = .trailing
        oauthContentStack.spacing = 10
        
        oauthStack.addArrangedSubview(oauthContentStack)
        oauthStack.isHidden = true
        
        tokenStack.addArrangedSubview(oauthStack)
        
        formStack.addArrangedSubview(createGroupBox(for: tokenStack))
        
        // --- 2. Menu Settings Section ---
        let menuStack = createInnerStack()
        let layoutLabel = NSTextField(labelWithString: Translations.get("layoutLabel"))
        layoutSegment.segmentCount = 4
        layoutSegment.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Columns"), forSegment: 0)
        layoutSegment.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Cards"), forSegment: 1)
        layoutSegment.setImage(NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: "Hybrid"), forSegment: 2)
        layoutSegment.setImage(NSImage(systemSymbolName: "tag", accessibilityDescription: "Tags"), forSegment: 3)
        layoutSegment.segmentStyle = .rounded
        layoutSegment.target = self
        layoutSegment.action = #selector(layoutChanged(_:))
        addSettingsRow(to: menuStack, label: layoutLabel, controls: [layoutSegment])
        
        let indicatorLabel = NSTextField(labelWithString: Translations.get("showNewIndicator"))
        newIndicatorSwitch.target = self
        newIndicatorSwitch.action = #selector(toggleNewIndicator(_:))
        addSettingsRow(to: menuStack, label: indicatorLabel, controls: [newIndicatorSwitch])
        
        newIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        newIndicatorStepper.minValue = 1
        newIndicatorStepper.maxValue = 30
        newIndicatorStepper.valueWraps = false
        newIndicatorStepper.target = self
        newIndicatorStepper.action = #selector(indicatorDaysChanged(_:))
        newIndicatorStepper.translatesAutoresizingMaskIntoConstraints = false
        addSettingsRow(to: menuStack, label: newIndicatorLabel, controls: [newIndicatorStepper])
        
        let ownerLabel = NSTextField(labelWithString: Translations.get("showOwner"))
        ownerSwitch.target = self
        ownerSwitch.action = #selector(toggleOwner(_:))
        addSettingsRow(to: menuStack, label: ownerLabel, controls: [ownerSwitch])
        
        let sortLabel = NSTextField(labelWithString: Translations.get("sortLabel"))
        sortSegment.segmentCount = 2
        sortSegment.setImage(NSImage(systemSymbolName: "textformat.abc", accessibilityDescription: Translations.get("sortNameOnly")), forSegment: 0)
        sortSegment.setImage(NSImage(systemSymbolName: "clock", accessibilityDescription: Translations.get("sortDateOnly")), forSegment: 1)
        sortSegment.segmentStyle = .rounded
        sortSegment.target = self
        sortSegment.action = #selector(sortChanged(_:))
        addSettingsRow(to: menuStack, label: sortLabel, controls: [sortSegment])
        
        let compactLabel = NSTextField(labelWithString: Translations.get("compactModeLabel"))
        compactModeSwitch.target = self
        compactModeSwitch.action = #selector(toggleCompactMode(_:))
        addSettingsRow(to: menuStack, label: compactLabel, controls: [compactModeSwitch])
        
        formStack.addArrangedSubview(createGroupBox(for: menuStack))
        
        // --- 3. Interval Section ---
        let intervalStack = createInnerStack()
        intervalLabel.translatesAutoresizingMaskIntoConstraints = false
        intervalSlider.minValue = 1
        intervalSlider.maxValue = 24
        intervalSlider.numberOfTickMarks = 24
        intervalSlider.allowsTickMarkValuesOnly = true
        intervalSlider.target = self
        intervalSlider.action = #selector(intervalChanged(_:))
        intervalSlider.translatesAutoresizingMaskIntoConstraints = false
        
        intervalStack.addArrangedSubview(intervalLabel)
        intervalStack.addArrangedSubview(intervalSlider)
        
        formStack.addArrangedSubview(createGroupBox(for: intervalStack))
        
        // --- 4. Startup ---
        let startupStack = createInnerStack()
        let loginLabel = NSTextField(labelWithString: Translations.get("startAtLogin"))
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin(_:))
        addSettingsRow(to: startupStack, label: loginLabel, controls: [loginSwitch])
        
        formStack.addArrangedSubview(createGroupBox(for: startupStack))
        
        // Add a bottom spacer to push content up if needed and provide bottom margin
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stackView.addArrangedSubview(spacer)
    }
    
    private func loadCurrentSettings() {
        // Load Token - two exclusive states
        let hasToken = ConfigManager.shared.token != nil && !ConfigManager.shared.token!.isEmpty
        
        if hasToken {
            tokenStatusLabel.stringValue = Translations.get("connected")
            tokenStatusLabel.textColor = .systemGreen
            tokenConnectBtn.isHidden = true
            tokenDeleteBtn.isHidden = false
        } else {
            tokenStatusLabel.stringValue = Translations.get("notConnected")
            tokenStatusLabel.textColor = .secondaryLabelColor
            tokenConnectBtn.isHidden = false
            tokenDeleteBtn.isHidden = true
            tokenConnectBtn.isEnabled = true
        }
        
        oauthStack.isHidden = true
        oauthSpinner.stopAnimation(nil)
        GitHubAuth.shared.cancelPolling()
        
        // Load Interval
        let mins = ConfigManager.shared.config.refreshMinutes
        initialIntervalHours = max(1, min(24, Int(ceil(Double(mins) / 60.0))))
        intervalSlider.integerValue = initialIntervalHours
        updateIntervalLabel()
        
        // Load Start at Login
        loginSwitch.state = isLoginItem() ? .on : .off
        
        // Load Owner
        ownerSwitch.state = ConfigManager.shared.config.showOwner ? .on : .off
        
        // Load Sort By
        sortSegment.selectedSegment = (ConfigManager.shared.config.sortBy == "name") ? 0 : 1
        
        // Load Layout
        let layout = ConfigManager.shared.config.menuLayout ?? "columns"
        let layoutIndex = ["columns", "cards", "hybrid", "tags"].firstIndex(of: layout) ?? 0
        layoutSegment.selectedSegment = layoutIndex
        
        compactModeSwitch.state = (ConfigManager.shared.config.isCompactMode == true) ? .on : .off
        
        let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? true
        newIndicatorSwitch.state = showNewIndicator ? .on : .off
        
        let days = ConfigManager.shared.config.newIndicatorDays ?? Constants.newReleaseThresholdDays
        newIndicatorStepper.integerValue = days
        updateIndicatorDaysLabel()
        updateIndicatorStepperVisibility()
    }
    

    
    @objc private func intervalChanged(_ sender: NSSlider) {
        updateIntervalLabel()
        
        // Cancel any pending save
        intervalSaveWorkItem?.cancel()
        
        // Create a new save action to run after the user stops modifying the slider
        let pendingSave = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isUpdatingSelf = true
            let currentHours = self.intervalSlider.integerValue
            ConfigManager.shared.config.refreshMinutes = currentHours * 60
            ConfigManager.shared.saveConfig()
            
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.setupMenu()
            }
            self.initialIntervalHours = currentHours
            self.isUpdatingSelf = false
        }
        
        intervalSaveWorkItem = pendingSave
        // Delay ensures we only save once the user settles on a value
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: pendingSave)
    }
    
    private func updateIntervalLabel() {
        let hours = intervalSlider.integerValue
        let unit = hours == 1 ? Translations.get("unitHour") : Translations.get("unitHoursPlural")
        intervalLabel.stringValue = Translations.get("intervalDynamic").format(with: ["hours": "\(hours)", "unit": unit])
    }
    
    func windowWillClose(_ notification: Notification) {
        // Save handled instantly by individual control actions to prevent data loss on forced closures
        // Return to accessory mode so Dock auto-hide works
    }
    
    @objc private func closeWindow(_ sender: NSButton) {
        self.window?.close()
    }
    
    @objc private func startOAuth(_ sender: NSButton) {
        tokenConnectBtn.isEnabled = false
        oauthStack.isHidden = false
        oauthSpinner.startAnimation(nil)
        oauthCodeLabel.stringValue = Translations.get("loading")
        oauthActionBtn.isHidden = true
        
        Task {
            do {
                let response = try await GitHubAuth.shared.requestDeviceCode()
                DispatchQueue.main.async {
                    self.oauthCodeLabel.stringValue = Translations.get("oauthInstructions").format(with: ["code": response.userCode])
                    self.currentVerificationUri = response.verificationUri
                    self.oauthActionBtn.isHidden = false
                    
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(response.userCode, forType: .string)
                }
                
                if let token = try await GitHubAuth.shared.pollForToken(deviceCode: response.deviceCode, interval: response.interval, expiresIn: response.expiresIn) {
                    DispatchQueue.main.async {
                        _ = ConfigManager.shared.saveTokenToKeychain(token)
                        ConfigManager.shared.token = token
                        self.loadCurrentSettings()
                        HUDPanel.shared.show(title: Translations.get("configureToken"), subtitle: Translations.get("tokenValidationSuccess"))
                        if let delegate = NSApp.delegate as? AppDelegate {
                             delegate.triggerFullRefresh(nil)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.loadCurrentSettings()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.animateStatusIcon(with: .wiggle)
                    }
                    HUDPanel.shared.show(title: Translations.get("error"), subtitle: Translations.get("authError"))
                    self.loadCurrentSettings()
                }
            }
        }
    }
    
    @objc private func openGitHubAuth(_ sender: NSButton) {
        if let uri = currentVerificationUri, let url = URL(string: uri) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func cancelOAuth(_ sender: NSButton) {
        GitHubAuth.shared.cancelPolling()
        loadCurrentSettings()
    }
    
    @objc private func deleteToken(_ sender: NSButton) {
        // Confirmation dialog
        let confirm = NSAlert()
        confirm.messageText = Translations.get("confirmDeleteToken")
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: Translations.get("deleteToken"))
        confirm.addButton(withTitle: Translations.get("cancel"))
        
        let response = confirm.runModal()
        guard response == .alertFirstButtonReturn else { return }
        
        _ = ConfigManager.shared.deleteTokenFromKeychain()
        ConfigManager.shared.token = nil
        self.loadCurrentSettings()
        
        // Notify user of reverted limits
        HUDPanel.shared.show(title: Translations.get("deleteToken"), subtitle: Translations.get("tokenValidationEmpty"))
        
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.triggerFullRefresh(nil)
        }
        self.window?.makeFirstResponder(nil)
    }
    
    @objc private func toggleLogin(_ sender: NSSwitch) {
        let isEnable = sender.state == .on
        setLoginItemState(enabled: isEnable)
    }
    
    @objc private func toggleOwner(_ sender: NSSwitch) {
        isUpdatingSelf = true
        ConfigManager.shared.config.showOwner = sender.state == .on
        
        generalSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.setupMenu()
            }
            self?.isUpdatingSelf = false
        }
        generalSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: pending)
    }
    
    @objc private func sortChanged(_ sender: NSSegmentedControl) {
        isUpdatingSelf = true
        let isByName = sender.selectedSegment == 0
        ConfigManager.shared.config.sortBy = isByName ? "name" : "date"
        
        generalSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.setupMenu()
            }
            self?.isUpdatingSelf = false
        }
        generalSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: pending)
    }
    
    @objc private func toggleNewIndicator(_ sender: NSSwitch) {
        isUpdatingSelf = true
        ConfigManager.shared.config.showNewIndicator = sender.state == .on
        updateIndicatorStepperVisibility()
        
        generalSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.setupMenu()
            }
            self?.isUpdatingSelf = false
        }
        generalSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: pending)
    }
    
    @objc private func indicatorDaysChanged(_ sender: NSStepper) {
        updateIndicatorDaysLabel()
        
        // Cancel any pending save
        indicatorSaveWorkItem?.cancel()
        
        let pendingSave = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isUpdatingSelf = true
            ConfigManager.shared.config.newIndicatorDays = self.newIndicatorStepper.integerValue
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                 delegate.setupMenu()
            }
            self.isUpdatingSelf = false
        }
        
        indicatorSaveWorkItem = pendingSave
        // Delay ensures holding the button is fast while only the final value is saved
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: pendingSave)
    }
    
    @objc private func layoutChanged(_ sender: NSSegmentedControl) {
        isUpdatingSelf = true
        let layoutModes = ["columns", "cards", "hybrid", "tags"]
        ConfigManager.shared.config.menuLayout = layoutModes[sender.selectedSegment]
        updateIndicatorStepperVisibility()
        
        generalSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.setupMenu()
            }
            self?.isUpdatingSelf = false
        }
        generalSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: pending)
    }
    
    @objc private func toggleCompactMode(_ sender: NSSwitch) {
        isUpdatingSelf = true
        ConfigManager.shared.config.isCompactMode = sender.state == .on
        
        generalSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.setupMenu()
            }
            self?.isUpdatingSelf = false
        }
        generalSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: pending)
    }
    
    private func updateIndicatorDaysLabel() {
        let days = newIndicatorStepper.integerValue
        if days == 1 {
            newIndicatorLabel.stringValue = Translations.get("indicatorDaySingular")
        } else {
            newIndicatorLabel.stringValue = Translations.get("indicatorDays").format(with: ["days": "\(days)"])
        }
    }
    
    private func updateIndicatorStepperVisibility() {
        let layoutIndex = layoutSegment.selectedSegment
        let isColorLayout = (layoutIndex == 2 || layoutIndex == 3) // Hybrid or Tags
        
        if isColorLayout {
            newIndicatorSwitch.isEnabled = false
            newIndicatorSwitch.state = .on // visually indicate feature is structural
            
            newIndicatorStepper.isEnabled = true
            newIndicatorLabel.textColor = .labelColor
        } else {
            newIndicatorSwitch.isEnabled = true
            let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? true
            newIndicatorSwitch.state = showNewIndicator ? .on : .off
            
            let isEnabled = newIndicatorSwitch.state == .on
            newIndicatorStepper.isEnabled = isEnabled
            newIndicatorLabel.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        }
    }
    

    private func addSettingsRow(to stack: NSStackView, label: NSView, controls: [NSView]) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        
        // Allow the label to truncate if the row is tight
        if let textField = label as? NSTextField {
            textField.lineBreakMode = .byTruncatingTail
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        
        row.addArrangedSubview(label)
        
        let spring = NSView()
        spring.translatesAutoresizingMaskIntoConstraints = false
        spring.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spring)
        
        for control in controls {
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(control)
        }
        
        stack.addArrangedSubview(row)
    }
    
    private func createInnerStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 15
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    
    private func createGroupBox(for innerStack: NSStackView) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = NSColor.separatorColor.withAlphaComponent(0.2)
        box.fillColor = NSColor.labelColor.withAlphaComponent(0.04)
        box.titlePosition = .noTitle
        box.translatesAutoresizingMaskIntoConstraints = false
        
        guard let cv = box.contentView else { return box }
        
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(innerStack)
        
        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
            innerStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
            innerStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            innerStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            box.widthAnchor.constraint(equalToConstant: 440)
        ])
        
        return box
    }
    
    // Extracted Login Item Logic for reuse
    private func isLoginItem() -> Bool {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(Constants.launchAgentLabel).plist")
        return FileManager.default.fileExists(atPath: launchAgentPath.path)
    }
    
    private func setLoginItemState(enabled: Bool) {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(Constants.launchAgentLabel).plist")
        
        if !enabled {
            try? FileManager.default.removeItem(at: launchAgentPath)
        } else {
            let bundlePath = Bundle.main.bundlePath
            let executablePath: String
            
            if bundlePath.hasSuffix(".app") {
                executablePath = Bundle.main.executablePath ?? bundlePath
            } else {
                executablePath = bundlePath
            }
            
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(Constants.launchAgentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(executablePath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            
            try? FileManager.default.createDirectory(at: launchAgentPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plistContent.write(to: launchAgentPath, atomically: true, encoding: .utf8)
        }
    }
}
