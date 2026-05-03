import Cocoa

@MainActor
class SettingsViewController: NSViewController, NSTextFieldDelegate, OAuthWindowDelegate {
    
    let tokenStatusLabel = NSTextField(labelWithString: "")
    let tokenConnectBtn = NSButton(title: Translations.get("connectGitHub"), target: nil, action: nil)
    let tokenDeleteBtn = NSButton(title: Translations.get("deleteToken"), target: nil, action: nil)
    private var oauthWindowController: OAuthWindowController?
    
    let intervalLabel = NSTextField(labelWithString: "")
    let intervalSlider = NSSlider()
    var initialIntervalHours: Int = 1
    
    let loginSwitch = NSSwitch()
    private let ownerCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let newIndicatorCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let newIndicatorStepper = NSStepper()
    let sortSegment = NSSegmentedControl()
    let layoutSegment = NSSegmentedControl()
    private let textSizePicker = NSSegmentedControl()
    
    var tempToken: String?
    private var isConfirmingDelete = false
    private var isUpdatingSelf = false
    
    // Debounce properties for saving settings
    private var intervalSaveWorkItem: DispatchWorkItem?
    private var indicatorSaveWorkItem: DispatchWorkItem?
    private var textSizeSaveWorkItem: DispatchWorkItem?
    private var generalSaveWorkItem: DispatchWorkItem?

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 100))
        self.view = view
        setupUI()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
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
        let contentView = self.view
        
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 15
        stackView.detachesHiddenViews = true
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        // Adjust alignment for the rest of the form
        let formStack = NSStackView()
        formStack.orientation = .vertical
        formStack.alignment = .centerX
        formStack.spacing = 18
        formStack.detachesHiddenViews = true
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
        
        formStack.addArrangedSubview(createGroupBox(for: tokenStack))
        
        // --- 2. Menu Settings Section ---
        let menuStack = createInnerStack()
        menuStack.spacing = 16 // Consistent spacing
        
        let layoutLabel = NSTextField(labelWithString: Translations.get("layoutLabel"))
        layoutLabel.font = .systemFont(ofSize: 13, weight: .medium)
        layoutSegment.segmentCount = 3
        layoutSegment.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Columns"), forSegment: 0)
        layoutSegment.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Cards"), forSegment: 1)
        layoutSegment.setImage(NSImage(systemSymbolName: "tag", accessibilityDescription: "Tags"), forSegment: 2)
        layoutSegment.segmentStyle = .rounded
        for i in 0..<3 { layoutSegment.setWidth(38, forSegment: i) }
        layoutSegment.target = self
        layoutSegment.action = #selector(layoutChanged(_:))
        addSettingsRow(to: menuStack, label: layoutLabel, controls: [layoutSegment])
        
        // Text Size Picker Row — same style as layoutSegment
        let textSizeRowLabel = NSTextField(labelWithString: Translations.get("textSizeLabel"))
        textSizeRowLabel.font = .systemFont(ofSize: 13, weight: .medium)
        
        let chevronCfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        textSizePicker.segmentCount = 3
        textSizePicker.setImage(NSImage(systemSymbolName: "chevron.left",  accessibilityDescription: "Decrease")?.withSymbolConfiguration(chevronCfg), forSegment: 0)
        textSizePicker.setLabel("", forSegment: 1)   // value set in loadCurrentSettings
        textSizePicker.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Increase")?.withSymbolConfiguration(chevronCfg), forSegment: 2)
        textSizePicker.segmentStyle = .rounded
        for i in 0..<3 { textSizePicker.setWidth(38, forSegment: i) }
        textSizePicker.trackingMode = .momentary
        textSizePicker.target = self
        textSizePicker.action = #selector(textSizePickerAction(_:))
        addSettingsRow(to: menuStack, label: textSizeRowLabel, controls: [textSizePicker])
        
        // Sorting Row
        let sortLabel = NSTextField(labelWithString: Translations.get("sortLabel"))
        sortLabel.font = .systemFont(ofSize: 13, weight: .medium)
        sortSegment.segmentCount = 2
        sortSegment.setImage(NSImage(systemSymbolName: "textformat.abc", accessibilityDescription: Translations.get("sortNameOnly")), forSegment: 0)
        sortSegment.setImage(NSImage(systemSymbolName: "clock", accessibilityDescription: Translations.get("sortDateOnly")), forSegment: 1)
        sortSegment.segmentStyle = .rounded
        sortSegment.target = self
        sortSegment.action = #selector(sortChanged(_:))
        addSettingsRow(to: menuStack, label: sortLabel, controls: [sortSegment])
        
        // Horizontal separator line inside the box
        let separatorLine = NSBox()
        separatorLine.boxType = .separator
        menuStack.addArrangedSubview(separatorLine)
        separatorLine.widthAnchor.constraint(equalTo: menuStack.widthAnchor).isActive = true
        
        // Binary Options Checklist
        let checklistStack = NSStackView()
        checklistStack.orientation = .vertical
        checklistStack.alignment = .leading
        checklistStack.spacing = 12
        checklistStack.translatesAutoresizingMaskIntoConstraints = false
        
        // 1. New Indicator (Dynamic Checkbox + Right Stepper)
        let indicatorRow = NSStackView()
        indicatorRow.orientation = .horizontal
        indicatorRow.alignment = .centerY
        indicatorRow.translatesAutoresizingMaskIntoConstraints = false
        
        newIndicatorCheckbox.target = self
        newIndicatorCheckbox.action = #selector(toggleNewIndicator(_:))
        
        newIndicatorStepper.minValue = 1
        newIndicatorStepper.maxValue = 30
        newIndicatorStepper.valueWraps = false
        newIndicatorStepper.target = self
        newIndicatorStepper.action = #selector(indicatorDaysChanged(_:))
        newIndicatorStepper.controlSize = .small
        
        let indicatorSpring = NSView()
        indicatorSpring.translatesAutoresizingMaskIntoConstraints = false
        indicatorSpring.setContentHuggingPriority(NSLayoutConstraint.Priority.defaultLow, for: NSLayoutConstraint.Orientation.horizontal)
        
        indicatorRow.addArrangedSubview(newIndicatorCheckbox)
        indicatorRow.addArrangedSubview(indicatorSpring)
        indicatorRow.addArrangedSubview(newIndicatorStepper)
        
        checklistStack.addArrangedSubview(indicatorRow)
        indicatorRow.widthAnchor.constraint(equalTo: checklistStack.widthAnchor).isActive = true
        
        // 2. Owner Checkbox
        ownerCheckbox.title = Translations.get("showOwner")
        ownerCheckbox.target = self
        ownerCheckbox.action = #selector(toggleOwner(_:))
        checklistStack.addArrangedSubview(ownerCheckbox)
        
        menuStack.addArrangedSubview(checklistStack)
        checklistStack.widthAnchor.constraint(equalTo: menuStack.widthAnchor).isActive = true
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
        
    }
    
    private func setOAuthStack(hidden: Bool) {
        // No longer needed with modal OAuth
    }
    
    func updatePreferredContentSize() {
        self.view.invalidateIntrinsicContentSize()
        self.view.layoutSubtreeIfNeeded()
        
        let targetSize = self.view.fittingSize
        self.preferredContentSize = targetSize
        
        // Notify popover if it's shown and force its window to update
        if let popover = (NSApp.delegate as? AppDelegate)?.settingsPopover {
            popover.contentSize = targetSize
            // Some versions of macOS need an extra kick to resize the popover's window
            if let window = popover.contentViewController?.view.window {
                var frame = window.frame
                frame.size = popover.contentSize
                // We don't set the frame directly to avoid fighting with popover positioning,
                // but setting preferredContentSize again can help.
            }
        }
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
        
        isConfirmingDelete = false
        tokenDeleteBtn.attributedTitle = NSAttributedString(string: Translations.get("deleteToken"), attributes: [:])
        tokenDeleteBtn.contentTintColor = nil
        
        // Load Interval
        
        // Load Interval
        let mins = ConfigManager.shared.config.refreshMinutes
        initialIntervalHours = max(1, min(24, Int(ceil(Double(mins) / 60.0))))
        intervalSlider.integerValue = initialIntervalHours
        updateIntervalLabel()
        
        // Load Start at Login
        loginSwitch.state = isLoginItem() ? .on : .off
        
        // Load Owner
        ownerCheckbox.state = ConfigManager.shared.config.showOwner ? .on : .off
        
        // Load Sort By
        sortSegment.selectedSegment = (ConfigManager.shared.config.sortBy == "name") ? 0 : 1
        
        // Load Layout
        let layout = ConfigManager.shared.config.menuLayout ?? "columns"
        let layoutIndex = ["columns", "cards", "tags"].firstIndex(of: layout) ?? 0
        layoutSegment.selectedSegment = layoutIndex
        
        // Load Text Size
        let currentFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        textSizePicker.setLabel("\(Int(currentFontSize))", forSegment: 1)
        updateTextSizePicker()
        
        let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? true
        newIndicatorCheckbox.state = showNewIndicator ? .on : .off
        
        let days = ConfigManager.shared.config.newIndicatorDays ?? Constants.newReleaseThresholdDays
        newIndicatorStepper.integerValue = days
        updateIndicatorDaysLabel()
        updateIndicatorStepperVisibility()
        
        updatePreferredContentSize()
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
            
            self.initialIntervalHours = currentHours
            self.isUpdatingSelf = false
        }
        
        intervalSaveWorkItem = pendingSave
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.interactiveControlDelaySeconds, execute: pendingSave)
    }
    
    private func updateIntervalLabel() {
        let hours = intervalSlider.integerValue
        let unit = hours == 1 ? Translations.get("unitHour") : Translations.get("unitHoursPlural")
        intervalLabel.stringValue = Translations.get("intervalDynamic").format(with: ["hours": "\(hours)", "unit": unit])
    }
    
    @objc private func startOAuth(_ sender: NSButton) {
        // CLOSE POPOVER FIRST to avoid blocking the screen during authentication
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.settingsPopover?.performClose(nil)
        }
        
        Task {
            do {
                let response = try await GitHubAuth.shared.requestDeviceCode()
                DispatchQueue.main.async {
                    // AUTO-COPY CODE to clipboard for convenience
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(response.userCode, forType: .string)
                    
                    self.oauthWindowController = OAuthWindowController(
                        userCode: response.userCode,
                        verificationUri: response.verificationUri,
                        deviceCode: response.deviceCode,
                        interval: response.interval,
                        expiresIn: response.expiresIn
                    )
                    self.oauthWindowController?.delegate = self
                    
                    // Show as standalone window
                    self.oauthWindowController?.showWindow(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } catch {
                DispatchQueue.main.async {
                    sender.isEnabled = true
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.animateStatusIcon(with: .wiggle)
                    }
                    HUDPanel.shared.show(title: Translations.get("error"), subtitle: Translations.get("authError"))
                }
            }
        }
    }
    
    // MARK: - OAuthWindowDelegate
    func oauthFinished(token: String?) {
        self.oauthWindowController = nil
        self.tokenConnectBtn.isEnabled = true
        
        if let token = token {
            _ = ConfigManager.shared.saveTokenToKeychain(token)
            ConfigManager.shared.token = token
            self.loadCurrentSettings()
            HUDPanel.shared.show(title: Translations.get("configureToken"), subtitle: Translations.get("tokenValidationSuccess"))
            if let delegate = NSApp.delegate as? AppDelegate {
                 delegate.triggerFullRefresh(nil)
            }
        } else {
            self.loadCurrentSettings()
        }
    }
    
    @objc private func deleteToken(_ sender: NSButton) {
        if !isConfirmingDelete {
            isConfirmingDelete = true
            
            let title = Translations.get("confirmAction")
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
            sender.attributedTitle = NSAttributedString(string: title, attributes: attributes)
            
            // Auto-reset after 5 seconds if no action is taken
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self, self.isConfirmingDelete else { return }
                self.isConfirmingDelete = false
                self.loadCurrentSettings() 
            }
        } else {
            isConfirmingDelete = false
            _ = ConfigManager.shared.deleteTokenFromKeychain()
            ConfigManager.shared.token = nil
            self.loadCurrentSettings()
            HUDPanel.shared.show(title: Translations.get("configureToken"), subtitle: Translations.get("tokenValidationEmpty"))
            
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.triggerFullRefresh(nil)
            }
        }
    }
    
    @objc private func toggleLogin(_ sender: NSSwitch) {
        let isEnable = sender.state == .on
        setLoginItemState(enabled: isEnable)
    }
    
    @objc private func toggleOwner(_ sender: NSButton) {
        isUpdatingSelf = true
        ConfigManager.shared.config.showOwner = sender.state == .on
        
        generalSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.rebuildMenu()
            }
            self?.isUpdatingSelf = false
        }
        generalSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.menuUpdateBatchDelaySeconds, execute: pending)
    }
    
    @objc private func sortChanged(_ sender: NSSegmentedControl) {
        isUpdatingSelf = true
        let isByName = sender.selectedSegment == 0
        ConfigManager.shared.config.sortBy = isByName ? "name" : "date"
        
        generalSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.rebuildMenu()
            }
            self?.isUpdatingSelf = false
        }
        generalSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.menuUpdateBatchDelaySeconds, execute: pending)
    }
    
    @objc private func toggleNewIndicator(_ sender: NSButton) {
        isUpdatingSelf = true
        ConfigManager.shared.config.showNewIndicator = sender.state == .on
        updateIndicatorStepperVisibility()
        
        generalSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.rebuildMenu()
            }
            self?.isUpdatingSelf = false
        }
        generalSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.menuUpdateBatchDelaySeconds, execute: pending)
    }
    
    @objc private func indicatorDaysChanged(_ sender: NSStepper) {
        updateIndicatorDaysLabel()
        
        indicatorSaveWorkItem?.cancel()
        
        let pendingSave = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isUpdatingSelf = true
            ConfigManager.shared.config.newIndicatorDays = self.newIndicatorStepper.integerValue
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                 delegate.rebuildMenu()
            }
            self.isUpdatingSelf = false
        }
        
        indicatorSaveWorkItem = pendingSave
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.interactiveControlDelaySeconds, execute: pendingSave)
    }
    
    @objc private func layoutChanged(_ sender: NSSegmentedControl) {
        isUpdatingSelf = true
        let layoutModes = ["columns", "cards", "tags"]
        ConfigManager.shared.config.menuLayout = layoutModes[sender.selectedSegment]
        updateIndicatorStepperVisibility()
        
        generalSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.rebuildMenu()
            }
            self?.isUpdatingSelf = false
        }
        generalSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.menuUpdateBatchDelaySeconds, execute: pending)
    }
    
    @objc private func textSizePickerAction(_ sender: NSSegmentedControl) {
        let current = Int(sender.label(forSegment: 1) ?? "") ?? Int(Constants.menuBaseFontSize)
        let newValue: Int
        switch sender.selectedSegment {
        case 0: newValue = max(Int(Constants.menuFontSizeMin), current - 1)
        case 2: newValue = min(Int(Constants.menuFontSizeMax), current + 1)
        default: return
        }
        textSizePicker.setLabel("\(newValue)", forSegment: 1)
        updateTextSizePicker()
        scheduleTextSizeSave(CGFloat(newValue))
    }
    
    private func updateTextSizePicker() {
        let current = Int(textSizePicker.label(forSegment: 1) ?? "") ?? Int(Constants.menuBaseFontSize)
        textSizePicker.setEnabled(current > Int(Constants.menuFontSizeMin), forSegment: 0)
        textSizePicker.setEnabled(current < Int(Constants.menuFontSizeMax), forSegment: 2)
    }
    
    private func scheduleTextSizeSave(_ size: CGFloat) {
        textSizeSaveWorkItem?.cancel()
        let pending = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isUpdatingSelf = true
            ConfigManager.shared.config.menuFontSize = size
            ConfigManager.shared.saveConfig()
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.rebuildMenu()
            }
            self.isUpdatingSelf = false
        }
        textSizeSaveWorkItem = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.menuUpdateBatchDelaySeconds, execute: pending)
    }
    
    private func updateIndicatorDaysLabel() {
        let days = newIndicatorStepper.integerValue
        newIndicatorCheckbox.title = (days == 1) ? Translations.get("indicatorDaySingular") : Translations.get("indicatorDays").format(with: ["days": "\(days)"])
    }
    
    private func updateIndicatorStepperVisibility() {
        let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? true
        newIndicatorCheckbox.isEnabled = true
        newIndicatorCheckbox.state = showNewIndicator ? .on : .off
        newIndicatorStepper.isEnabled = showNewIndicator
    }
    
    private func addSettingsRow(to stack: NSStackView, label: NSView, controls: [NSView]) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        
        if let textField = label as? NSTextField {
            textField.lineBreakMode = .byTruncatingTail
            textField.setContentCompressionResistancePriority(NSLayoutConstraint.Priority.defaultLow, for: NSLayoutConstraint.Orientation.horizontal)
        }
        
        row.addArrangedSubview(label)
        
        let spring = NSView()
        spring.translatesAutoresizingMaskIntoConstraints = false
        spring.setContentHuggingPriority(NSLayoutConstraint.Priority.defaultLow, for: NSLayoutConstraint.Orientation.horizontal)
        row.addArrangedSubview(spring)
        
        for control in controls {
            control.setContentCompressionResistancePriority(NSLayoutConstraint.Priority.required, for: NSLayoutConstraint.Orientation.horizontal)
            row.addArrangedSubview(control)
        }
        
        stack.addArrangedSubview(row)
    }
    
    private func createInnerStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 15
        stack.detachesHiddenViews = true
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
            innerStack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
            innerStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
            innerStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            innerStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            box.widthAnchor.constraint(equalToConstant: 440)
        ])
        
        return box
    }
    
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
