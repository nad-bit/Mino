import Cocoa

@MainActor
class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    
    let tokenField = NSTextField()
    let tokenSaveBtn = NSButton(title: Translations.get("ok"), target: nil, action: nil)
    let tokenDeleteBtn = NSButton(title: Translations.get("deleteToken"), target: nil, action: nil)
    
    let intervalLabel = NSTextField(labelWithString: "")
    let intervalSlider = NSSlider()
    var initialIntervalHours: Int = 1
    
    let loginSwitch = NSSwitch()
    let ownerSwitch = NSSwitch()
    let iconsSwitch = NSSwitch()
    let newIndicatorSwitch = NSSwitch()
    let newIndicatorSlider = NSSlider()
    let newIndicatorLabel = NSTextField(labelWithString: "")
    let sortSegment = NSSegmentedControl()
    
    var tempToken: String?
    
    override init(window: NSWindow?) {
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init() {
        // Adjust window height to accommodate the title and multi-line token
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = Translations.get("preferences")
        window.center()
        self.init(window: window)
        window.delegate = self
        
        setupUI()
        loadCurrentSettings()
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
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
        
        let appNameLabel = NSTextField(labelWithString: "GitHub Watcher")
        appNameLabel.font = .boldSystemFont(ofSize: 18)
        aboutStack.addArrangedSubview(appNameLabel)
        
        let appVersionLabel = NSTextField(labelWithString: Translations.get("aboutMsg"))
        appVersionLabel.alignment = .center
        appVersionLabel.textColor = .secondaryLabelColor
        appVersionLabel.font = .systemFont(ofSize: 12)
        aboutStack.addArrangedSubview(appVersionLabel)
        
        stackView.addArrangedSubview(aboutStack)
        
        let sep0 = NSBox()
        sep0.boxType = .separator
        stackView.addArrangedSubview(sep0)
        sep0.translatesAutoresizingMaskIntoConstraints = false
        sep0.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40).isActive = true
        
        // Adjust alignment for the rest of the form
        let formStack = NSStackView()
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = 15
        formStack.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(formStack)
        
        // --- 1. Token Section ---
        let tokenLabel = NSTextField(labelWithString: Translations.get("configureToken") + ":")
        formStack.addArrangedSubview(tokenLabel)
        
        // Multi-line token field
        tokenField.placeholderString = Translations.get("tokenPlaceholder")
        tokenField.translatesAutoresizingMaskIntoConstraints = false
        tokenField.delegate = self
        tokenField.isEditable = true
        tokenField.isSelectable = true
        tokenField.cell?.wraps = true
        tokenField.cell?.isScrollable = false
        tokenField.maximumNumberOfLines = 2
        
        NSLayoutConstraint.activate([
            tokenField.widthAnchor.constraint(equalToConstant: 380),
            tokenField.heightAnchor.constraint(equalToConstant: 45)
        ])
        formStack.addArrangedSubview(tokenField)
        
        tokenSaveBtn.target = self
        tokenSaveBtn.action = #selector(saveToken(_:))
        
        tokenDeleteBtn.target = self
        tokenDeleteBtn.action = #selector(deleteToken(_:))
        
        let tokenBtnRow = NSStackView(views: [tokenSaveBtn, tokenDeleteBtn])
        tokenBtnRow.orientation = .horizontal
        tokenBtnRow.spacing = 10
        formStack.addArrangedSubview(tokenBtnRow)
        
        let sep1 = NSBox()
        sep1.boxType = .separator
        formStack.addArrangedSubview(sep1)
        sep1.translatesAutoresizingMaskIntoConstraints = false
        sep1.widthAnchor.constraint(equalTo: formStack.widthAnchor, constant: 0).isActive = true
        
        // --- 2. Interval Section ---
        intervalLabel.translatesAutoresizingMaskIntoConstraints = false
        
        intervalSlider.minValue = 1
        intervalSlider.maxValue = 24
        intervalSlider.numberOfTickMarks = 24
        intervalSlider.allowsTickMarkValuesOnly = true
        intervalSlider.target = self
        intervalSlider.action = #selector(sliderChanged(_:))
        intervalSlider.translatesAutoresizingMaskIntoConstraints = false
        intervalSlider.widthAnchor.constraint(equalToConstant: 380).isActive = true
        
        formStack.addArrangedSubview(intervalLabel)
        formStack.addArrangedSubview(intervalSlider)
        
        let sep2 = NSBox()
        sep2.boxType = .separator
        formStack.addArrangedSubview(sep2)
        sep2.translatesAutoresizingMaskIntoConstraints = false
        sep2.widthAnchor.constraint(equalTo: formStack.widthAnchor, constant: 0).isActive = true
        
        // --- 3. UI Toggles ---
        let loginLabel = NSTextField(labelWithString: Translations.get("startAtLogin"))
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin(_:))
        let loginRow = NSStackView(views: [loginSwitch, loginLabel])
        loginRow.orientation = .horizontal
        loginRow.spacing = 10
        formStack.addArrangedSubview(loginRow)
        
        let ownerLabel = NSTextField(labelWithString: Translations.get("showOwner"))
        ownerSwitch.target = self
        ownerSwitch.action = #selector(toggleOwner(_:))
        let ownerRow = NSStackView(views: [ownerSwitch, ownerLabel])
        ownerRow.orientation = .horizontal
        ownerRow.spacing = 10
        formStack.addArrangedSubview(ownerRow)
        
        let iconsLabel = NSTextField(labelWithString: Translations.get("showIcons"))
        iconsSwitch.target = self
        iconsSwitch.action = #selector(toggleIcons(_:))
        let iconsRow = NSStackView(views: [iconsSwitch, iconsLabel])
        iconsRow.orientation = .horizontal
        iconsRow.spacing = 10
        formStack.addArrangedSubview(iconsRow)
        
        // --- New Release Indicator Toggle ---
        let indicatorLabel = NSTextField(labelWithString: Translations.get("showNewIndicator"))
        newIndicatorSwitch.target = self
        newIndicatorSwitch.action = #selector(toggleNewIndicator(_:))
        let indicatorRow = NSStackView(views: [newIndicatorSwitch, indicatorLabel])
        indicatorRow.orientation = .horizontal
        indicatorRow.spacing = 10
        formStack.addArrangedSubview(indicatorRow)
        
        // Indicator Days Slider
        newIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        
        newIndicatorSlider.minValue = 1
        newIndicatorSlider.maxValue = 30
        newIndicatorSlider.numberOfTickMarks = 30
        newIndicatorSlider.allowsTickMarkValuesOnly = true
        newIndicatorSlider.target = self
        newIndicatorSlider.action = #selector(indicatorDaysChanged(_:))
        newIndicatorSlider.translatesAutoresizingMaskIntoConstraints = false
        newIndicatorSlider.widthAnchor.constraint(equalToConstant: 380).isActive = true
        
        formStack.addArrangedSubview(newIndicatorLabel)
        formStack.addArrangedSubview(newIndicatorSlider)
        
        // --- 4. Sort Section ---
        let sortLabel = NSTextField(labelWithString: Translations.get("sortLabel") + ":")
        sortSegment.segmentCount = 2
        sortSegment.setLabel(Translations.get("sortDateOnly"), forSegment: 0)
        sortSegment.setLabel(Translations.get("sortNameOnly"), forSegment: 1)
        sortSegment.segmentStyle = .rounded
        sortSegment.target = self
        sortSegment.action = #selector(sortChanged(_:))
        
        let sortRow = NSStackView(views: [sortLabel, sortSegment])
        sortRow.orientation = .horizontal
        sortRow.spacing = 10
        formStack.addArrangedSubview(sortRow)
        
        // --- 5. Spacer & Bottom Button ---
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stackView.addArrangedSubview(spacer)
        
        let saveCloseBtn = NSButton(title: "Close", target: self, action: #selector(closeWindow(_:)))
        
        let bottomRow = NSStackView(views: [saveCloseBtn])
        bottomRow.alignment = .trailing
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(bottomRow)
        bottomRow.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40).isActive = true
    }
    
    private func loadCurrentSettings() {
        // Load Token - two exclusive states
        let hasToken = ConfigManager.shared.token != nil && !ConfigManager.shared.token!.isEmpty
        
        if hasToken {
            // State: Token stored → read-only masked field, only Delete button
            tokenField.stringValue = maskToken(ConfigManager.shared.token!)
            tokenField.isEditable = false
            tokenField.isSelectable = false
            tokenField.textColor = .secondaryLabelColor
            tokenSaveBtn.isHidden = true
            tokenDeleteBtn.isHidden = false
        } else {
            // State: No token → editable field, only OK button
            tokenField.stringValue = ""
            tokenField.isEditable = true
            tokenField.isSelectable = true
            tokenField.textColor = .labelColor
            tokenSaveBtn.isHidden = false
            tokenDeleteBtn.isHidden = true
            self.tempToken = nil
            checkClipboardForToken()
        }
        
        // Load Interval
        let mins = ConfigManager.shared.config.refreshMinutes
        initialIntervalHours = max(1, min(24, Int(ceil(Double(mins) / 60.0))))
        intervalSlider.integerValue = initialIntervalHours
        updateIntervalLabel()
        
        // Load Start at Login
        loginSwitch.state = isLoginItem() ? .on : .off
        
        // Load Owner
        ownerSwitch.state = ConfigManager.shared.config.showOwner ? .on : .off
        
        // Load Icons
        iconsSwitch.state = (ConfigManager.shared.config.showIcons ?? false) ? .on : .off
        
        // Load New Indicator
        newIndicatorSwitch.state = (ConfigManager.shared.config.showNewIndicator ?? true) ? .on : .off
        let days = ConfigManager.shared.config.newIndicatorDays ?? Constants.newReleaseThresholdDays
        newIndicatorSlider.integerValue = days
        updateIndicatorDaysLabel()
        updateIndicatorSliderVisibility()
        
        // Load Sort
        let isSortedByName = ConfigManager.shared.config.sortBy == "name"
        sortSegment.selectedSegment = isSortedByName ? 1 : 0
    }
    
    private func maskToken(_ t: String) -> String {
        guard t.count > 4 else { return String(repeating: "•", count: t.count) }
        return String(repeating: "•", count: 36) + t.suffix(4)
    }
    
    private func isLikelyGitHubToken(_ t: String) -> Bool {
        return t.hasPrefix("ghp_") || t.hasPrefix("github_pat_") || t.hasPrefix("gho_") || t.hasPrefix("ghu_") || t.hasPrefix("ghs_") || t.hasPrefix("ghr_")
    }
    
    private func checkClipboardForToken() {
        // Only auto-fill from clipboard if no token is currently stored
        guard ConfigManager.shared.token == nil || ConfigManager.shared.token!.isEmpty else { return }
        let pbString = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = pbString, isLikelyGitHubToken(t), t != self.tempToken {
            self.tempToken = t
            tokenField.stringValue = t
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        checkClipboardForToken()
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField, textField == tokenField {
            self.tempToken = textField.stringValue
        }
    }
    
    @objc private func sliderChanged(_ sender: NSSlider) {
        updateIntervalLabel()
    }
    
    private func updateIntervalLabel() {
        let hours = intervalSlider.integerValue
        let unit = hours == 1 ? Translations.get("unitHour") : Translations.get("unitHoursPlural")
        intervalLabel.stringValue = Translations.get("intervalDynamic").format(with: ["hours": "\(hours)", "unit": unit])
    }
    
    func windowWillClose(_ notification: Notification) {
        let currentHours = intervalSlider.integerValue
        if currentHours != initialIntervalHours {
            ConfigManager.shared.config.refreshMinutes = currentHours * 60
            ConfigManager.shared.saveConfig()
            
            // Re-setup timers to reflect interval
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.lastRefreshTime = Date() // Force a refresh evaluation
                delegate.setupMenu()
                delegate.updateCountdown() // Trigger manually just in case
            }
            initialIntervalHours = currentHours
        }
    }
    
    @objc private func closeWindow(_ sender: NSButton) {
        self.window?.close()
    }
    
    @objc private func saveToken(_ sender: NSButton) {
        let t = (tempToken ?? tokenField.stringValue).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        
        Task {
            let valid = await GitHubAPI.shared.validateToken(t)
            DispatchQueue.main.async {
                if valid {
                    _ = ConfigManager.shared.saveTokenToKeychain(t)
                    ConfigManager.shared.token = t
                    self.loadCurrentSettings()
                    UIHandlers.shared.showAlert(title: Translations.get("configureToken"), message: Translations.get("tokenValidationSuccess"))
                    if let delegate = NSApp.delegate as? AppDelegate {
                         delegate.triggerFullRefresh(nil)
                    }
                } else {
                    UIHandlers.shared.showAlert(title: Translations.get("error"), message: Translations.get("tokenValidationError"))
                }
            }
        }
    }
    
    @objc private func deleteToken(_ sender: NSButton) {
        // Confirmation dialog
        let confirm = NSAlert()
        confirm.messageText = Translations.get("confirmDeleteToken")
        confirm.informativeText = Translations.get("tokenValidationEmpty")
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
        ConfigManager.shared.config.showOwner = sender.state == .on
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
    }
    
    @objc private func toggleIcons(_ sender: NSSwitch) {
        ConfigManager.shared.config.showIcons = sender.state == .on
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
    }
    
    @objc private func sortChanged(_ sender: NSSegmentedControl) {
        let isByName = sender.selectedSegment == 1
        ConfigManager.shared.config.sortBy = isByName ? "name" : "date"
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
    }
    
    @objc private func toggleNewIndicator(_ sender: NSSwitch) {
        ConfigManager.shared.config.showNewIndicator = sender.state == .on
        ConfigManager.shared.saveConfig()
        updateIndicatorSliderVisibility()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
    }
    
    @objc private func indicatorDaysChanged(_ sender: NSSlider) {
        ConfigManager.shared.config.newIndicatorDays = sender.integerValue
        ConfigManager.shared.saveConfig()
        updateIndicatorDaysLabel()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
    }
    
    private func updateIndicatorDaysLabel() {
        let days = newIndicatorSlider.integerValue
        let unit = days == 1 ? Translations.get("unitDay") : Translations.get("days")
        newIndicatorLabel.stringValue = Translations.get("indicatorDays").format(with: ["days": "\(days)", "unit": unit])
    }
    
    private func updateIndicatorSliderVisibility() {
        let isEnabled = newIndicatorSwitch.state == .on
        newIndicatorSlider.isEnabled = isEnabled
        newIndicatorLabel.textColor = isEnabled ? .labelColor : .disabledControlTextColor
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
