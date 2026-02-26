import Cocoa

@MainActor
class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    
    let tokenField = NSTextField()
    let tokenSaveBtn = NSButton(title: Translations.get("ok"), target: nil, action: nil)
    let tokenDeleteBtn = NSButton(title: Translations.get("deleteToken"), target: nil, action: nil)
    private let repoCountLabel = NSTextField(labelWithString: "")
    
    let intervalLabel = NSTextField(labelWithString: "")
    let intervalSlider = NSSlider()
    var initialIntervalHours: Int = 1
    
    let loginSwitch = NSSwitch()
    private let ownerSwitch = NSSwitch()
    private let newIndicatorSwitch = NSSwitch()
    private let newIndicatorSlider = NSSlider(value: 1, minValue: 1, maxValue: 30, target: nil, action: nil)
    let newIndicatorLabel = NSTextField(labelWithString: "")
    let sortSegment = NSSegmentedControl()
    let layoutSegment = NSSegmentedControl()
    
    var tempToken: String?
    private var isUpdatingSelf = false
    
    override init(window: NSWindow?) {
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init() {
        // Adjust window height to accommodate the title and multi-line token
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = Translations.get("preferences")
        window.center()
        self.init(window: window)
        window.delegate = self
        
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
        let tokenLabel = NSTextField(labelWithString: Translations.get("configureToken"))
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
        
        let tokenSpring = NSView()
        tokenSpring.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let tokenBtnRow = NSStackView(views: [tokenSpring, tokenSaveBtn, tokenDeleteBtn])
        tokenBtnRow.orientation = .horizontal
        tokenBtnRow.spacing = 10
        tokenBtnRow.translatesAutoresizingMaskIntoConstraints = false
        formStack.addArrangedSubview(tokenBtnRow)
        tokenBtnRow.widthAnchor.constraint(equalToConstant: 380).isActive = true
        
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
        addSettingsRow(to: formStack, label: loginLabel, controls: [loginSwitch])
        
        let ownerLabel = NSTextField(labelWithString: Translations.get("showOwner"))
        ownerSwitch.target = self
        ownerSwitch.action = #selector(toggleOwner(_:))
        addSettingsRow(to: formStack, label: ownerLabel, controls: [ownerSwitch])
        
        // --- New Release Indicator Toggle ---
        let indicatorLabel = NSTextField(labelWithString: Translations.get("showNewIndicator"))
        newIndicatorSwitch.target = self
        newIndicatorSwitch.action = #selector(toggleNewIndicator(_:))
        
        addSettingsRow(to: formStack, label: indicatorLabel, controls: [newIndicatorSwitch])
        
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
        let sortLabel = NSTextField(labelWithString: Translations.get("sortLabel"))
        sortSegment.segmentCount = 2
        sortSegment.setLabel(Translations.get("sortNameOnly"), forSegment: 0)
        sortSegment.setLabel(Translations.get("sortDateOnly"), forSegment: 1)
        sortSegment.segmentStyle = .rounded
        sortSegment.target = self
        sortSegment.action = #selector(sortChanged(_:))
        
        addSettingsRow(to: formStack, label: sortLabel, controls: [sortSegment])
        
        // --- 5. Layout Mode Section ---
        let layoutLabel = NSTextField(labelWithString: Translations.get("layoutLabel"))
        layoutSegment.segmentCount = 3
        layoutSegment.setLabel(Translations.get("layoutColumns"), forSegment: 0)
        layoutSegment.setLabel(Translations.get("layoutCards"), forSegment: 1)
        layoutSegment.setLabel(Translations.get("layoutHybrid"), forSegment: 2)
        layoutSegment.segmentStyle = .rounded
        layoutSegment.target = self
        layoutSegment.action = #selector(layoutChanged(_:))
        
        addSettingsRow(to: formStack, label: layoutLabel, controls: [layoutSegment])
        
        // Add a bottom spacer to push content up if needed and provide bottom margin
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stackView.addArrangedSubview(spacer)
        
        // --- Bottom Repo Count ---
        repoCountLabel.font = .systemFont(ofSize: 11)
        repoCountLabel.textColor = .tertiaryLabelColor
        repoCountLabel.alignment = .center
        stackView.addArrangedSubview(repoCountLabel)
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
        
        let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? true
        newIndicatorSwitch.state = showNewIndicator ? .on : .off
        
        let days = ConfigManager.shared.config.newIndicatorDays ?? Constants.newReleaseThresholdDays
        newIndicatorSlider.integerValue = days
        updateIndicatorDaysLabel()
        updateIndicatorSliderVisibility()
        
        // Load Sort By
        sortSegment.selectedSegment = (ConfigManager.shared.config.sortBy == "name") ? 0 : 1
        
        // Load Layout
        let layout = ConfigManager.shared.config.menuLayout ?? "columns"
        let layoutIndex = ["columns", "cards", "hybrid"].firstIndex(of: layout) ?? 0
        layoutSegment.selectedSegment = layoutIndex
        
        // Load Repo Count
        let count = ConfigManager.shared.config.repos.count
        if count == 1 {
            repoCountLabel.stringValue = Translations.get("repoCountSingular")
        } else {
            let baseString = Translations.get("repoCount")
            repoCountLabel.stringValue = baseString.replacingOccurrences(of: "{count}", with: "\(count)")
        }
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
                    HUDPanel.shared.show(title: Translations.get("configureToken"), subtitle: Translations.get("tokenValidationSuccess"))
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
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
        isUpdatingSelf = false
    }
    
    @objc private func sortChanged(_ sender: NSSegmentedControl) {
        isUpdatingSelf = true
        let isByName = sender.selectedSegment == 0 // Name is index 0
        ConfigManager.shared.config.sortBy = isByName ? "name" : "date"
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
        isUpdatingSelf = false
    }
    
    @objc private func toggleNewIndicator(_ sender: NSSwitch) {
        isUpdatingSelf = true
        ConfigManager.shared.config.showNewIndicator = sender.state == .on
        ConfigManager.shared.saveConfig()
        updateIndicatorSliderVisibility()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
        isUpdatingSelf = false
    }
    
    @objc private func indicatorDaysChanged(_ sender: NSSlider) {
        isUpdatingSelf = true
        ConfigManager.shared.config.newIndicatorDays = sender.integerValue
        ConfigManager.shared.saveConfig()
        updateIndicatorDaysLabel()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
        isUpdatingSelf = false
    }
    
    @objc private func layoutChanged(_ sender: NSSegmentedControl) {
        isUpdatingSelf = true
        let layoutModes = ["columns", "cards", "hybrid"]
        ConfigManager.shared.config.menuLayout = layoutModes[sender.selectedSegment]
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
             delegate.setupMenu()
        }
        isUpdatingSelf = false
    }
    
    private func updateIndicatorDaysLabel() {
        let days = newIndicatorSlider.integerValue
        if days == 1 {
            newIndicatorLabel.stringValue = Translations.get("indicatorDaySingular")
        } else {
            newIndicatorLabel.stringValue = Translations.get("indicatorDays").format(with: ["days": "\(days)"])
        }
    }
    
    private func updateIndicatorSliderVisibility() {
        let isEnabled = newIndicatorSwitch.state == .on
        newIndicatorSlider.isEnabled = isEnabled
        newIndicatorLabel.textColor = isEnabled ? .labelColor : .disabledControlTextColor
    }
    

    private func addSettingsRow(to stack: NSStackView, label: NSView, controls: [NSView]) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        
        row.addArrangedSubview(label)
        
        let spring = NSView()
        spring.translatesAutoresizingMaskIntoConstraints = false
        spring.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spring)
        
        for control in controls {
            row.addArrangedSubview(control)
        }
        
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalToConstant: 380).isActive = true
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
