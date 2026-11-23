import Cocoa

class SettingsView: NSView {
    weak var viewController: SettingsViewController?
    var onAppearanceChanged: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    
    override func cancelOperation(_ sender: Any?) {
        if let popover = (NSApp.delegate as? AppDelegate)?.settingsPopover {
            popover.close()
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if let vc = viewController, vc.handleKeyDown(with: event) {
            return
        }
        if let appDelegate = NSApp.delegate as? AppDelegate, appDelegate.handleGlobalShortcuts(with: event) {
            return
        }
        super.keyDown(with: event)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let vc = viewController, vc.handleKeyDown(with: event) {
            return true
        }
        if let appDelegate = NSApp.delegate as? AppDelegate, appDelegate.handleGlobalShortcuts(with: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }
}

class TextSizePickerView: NSControl {
    let decButton = NSButton()
    let valueLabel = NSTextField(labelWithString: "16")
    let incButton = NSButton()
    
    var onDecrease: (() -> Void)?
    var onIncrease: (() -> Void)?
    
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
    
    override var isEnabled: Bool {
        didSet {
            decButton.isEnabled = isEnabled
            incButton.isEnabled = isEnabled
            valueLabel.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        }
    }
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: 114, height: 24)
    }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        wantsLayer = true
        let chevronCfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        
        decButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Decrease")?.withSymbolConfiguration(chevronCfg)
        decButton.bezelStyle = .rounded
        decButton.controlSize = .regular
        decButton.focusRingType = .none
        decButton.target = self
        decButton.action = #selector(decClicked)
        decButton.translatesAutoresizingMaskIntoConstraints = false
        
        incButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Increase")?.withSymbolConfiguration(chevronCfg)
        incButton.bezelStyle = .rounded
        incButton.controlSize = .regular
        incButton.focusRingType = .none
        incButton.target = self
        incButton.action = #selector(incClicked)
        incButton.translatesAutoresizingMaskIntoConstraints = false
        
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.textColor = .labelColor
        valueLabel.isEditable = false
        valueLabel.isSelectable = false
        valueLabel.drawsBackground = false
        valueLabel.isBezeled = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let stack = NSStackView(views: [decButton, valueLabel, incButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: 114),
            heightAnchor.constraint(equalToConstant: 24),
            decButton.widthAnchor.constraint(equalToConstant: 34),
            decButton.heightAnchor.constraint(equalToConstant: 24),
            incButton.widthAnchor.constraint(equalToConstant: 34),
            incButton.heightAnchor.constraint(equalToConstant: 24),
            valueLabel.widthAnchor.constraint(equalToConstant: 38)
        ])
    }
    
    @objc private func decClicked() {
        onDecrease?()
    }
    
    @objc private func incClicked() {
        onIncrease?()
    }
    
    func setValue(_ value: Int) {
        valueLabel.stringValue = "\(value)"
    }
    
    func setEnabled(canDecrease: Bool, canIncrease: Bool) {
        decButton.isEnabled = canDecrease
        incButton.isEnabled = canIncrease
    }
}

@MainActor
class SettingsViewController: NSViewController, NSTextFieldDelegate, OAuthWindowDelegate {
    
    let tokenStatusLabel = NSTextField(labelWithString: "")
    private let tokenBadge = RateLimitBadge()
    let tokenConnectBtn = NSButton(title: Translations.get("connectGitHub"), target: nil, action: nil)
    let tokenDeleteBtn = NSButton(title: Translations.get("deleteToken"), target: nil, action: nil)
    private var oauthWindowController: OAuthWindowController?
    
    let intervalLabel = NSTextField(labelWithString: "")
    let intervalSlider = NSSlider()
    var initialIntervalHours: Int = 1
    
    let loginSwitch = NSSwitch()
    let shortcutBtn = ShortcutRecorderButton()
    let ownerCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let ownerLabel = NSTextField(labelWithString: "")
    private let newIndicatorLabel = NSTextField(labelWithString: "")
    let newIndicatorStepper = NSStepper()
    let sortSegment = NSSegmentedControl()
    let layoutSegment = NSSegmentedControl()
    let textSizePicker = TextSizePickerView()
    
    var tempToken: String?
    private var isConfirmingDelete = false
    private var isUpdatingSelf = false
    
    // Debounce properties for saving settings
    private var intervalSaveWorkItem: DispatchWorkItem?
    private var indicatorSaveWorkItem: DispatchWorkItem?
    private var textSizeSaveWorkItem: DispatchWorkItem?
    private var generalSaveWorkItem: DispatchWorkItem?
    
    // Throttle properties for rate limit hover checks
    private var lastRateLimitFetchDate: Date?
    private var isFetchingRateLimit = false
    
    // Liquid-crystal reflection overlay
    private let sheenOverlay = SheenOverlayView()

    override func loadView() {
        let view = SettingsView(frame: NSRect(x: 0, y: 0, width: 480, height: 100))
        view.viewController = self
        view.onAppearanceChanged = { [weak self] in
            let hasToken = ConfigManager.shared.token != nil && !ConfigManager.shared.token!.isEmpty
            self?.updateTokenBadgeStyle(hasToken: hasToken)
        }
        self.view = view
        
        sheenOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheenOverlay, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            sheenOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            sheenOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheenOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheenOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        setupUI()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loadCurrentSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(configDidUpdate), name: Notification.Name("ConfigChanged"), object: nil)
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        loadCurrentSettings()
        updateRateLimitToolTip()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        clearControlFocus()
        self.view.window?.makeFirstResponder(self.view)
    }
    
    // MARK: - Keyboard Navigation (Tab, Arrows, Space, Return)
    
    var focusableControls: [NSControl] {
        var controls: [NSControl] = []
        
        // 1. Token (Connect or Delete, whichever is visible)
        if !tokenDeleteBtn.isHidden {
            controls.append(tokenDeleteBtn)
        } else if !tokenConnectBtn.isHidden {
            controls.append(tokenConnectBtn)
        }
        
        // 2. Menu Layout Segment
        controls.append(layoutSegment)
        
        // 3. Text Size Picker Segment
        controls.append(textSizePicker)
        
        // 4. Sort Segment
        controls.append(sortSegment)
        
        // 5. New Indicator Stepper
        controls.append(newIndicatorStepper)
        
        // 6. Show Owner Checkbox
        controls.append(ownerCheckbox)
        
        // 7. Refresh Interval Slider
        controls.append(intervalSlider)
        
        // 8. Global Shortcut Button
        controls.append(shortcutBtn)
        
        // 9. Startup Switch
        controls.append(loginSwitch)
        
        return controls.filter { $0.isEnabled && !$0.isHidden }
    }
    
    private(set) var focusedControlIndex: Int? {
        didSet {
            let controls = focusableControls
            for (i, control) in controls.enumerated() {
                control.wantsLayer = true
                if i == focusedControlIndex {
                    control.layer?.borderWidth = 2.0
                    control.layer?.borderColor = NSColor.controlAccentColor.cgColor
                    control.layer?.cornerRadius = (control is NSButton || control is NSSwitch || control is TextSizePickerView) ? 6 : 4
                } else {
                    control.layer?.borderWidth = 0.0
                    control.layer?.borderColor = nil
                }
            }
        }
    }
    
    func focusControl(at index: Int) {
        let controls = focusableControls
        guard index >= 0 && index < controls.count else { return }
        focusedControlIndex = index
        let control = controls[index]
        self.view.window?.makeFirstResponder(control)
        control.scrollToVisible(control.bounds)
    }
    
    func clearControlFocus() {
        focusedControlIndex = nil
    }
    
    func handleKeyDown(with event: NSEvent) -> Bool {
        // 1. ESC -> Close popover
        if event.keyCode == 53 {
            if let popover = (NSApp.delegate as? AppDelegate)?.settingsPopover {
                popover.close()
                return true
            }
        }
        
        let controls = focusableControls
        guard !controls.isEmpty else { return false }
        
        // 2. TAB (keyCode 48) -> cycle focus
        if event.keyCode == 48 {
            let isShift = event.modifierFlags.contains(.shift)
            let direction = isShift ? -1 : 1
            if let current = focusedControlIndex {
                let next = (current + direction + controls.count) % controls.count
                focusControl(at: next)
            } else {
                focusControl(at: direction > 0 ? 0 : controls.count - 1)
            }
            return true
        }
        
        // If a control is focused, handle contextual action keys (Player 2: WASD + Space)
        guard let currentIdx = focusedControlIndex, currentIdx < controls.count else {
            return false
        }
        
        let control = controls[currentIdx]
        
        switch event.keyCode {
        case 49: // Space (49) -> Toggle / Click / Select
            if let btn = control as? ShortcutRecorderButton {
                if !btn.isRecording {
                    btn.startRecording()
                } else {
                    btn.stopRecording(cancelled: true)
                }
                return true
            } else if let btn = control as? NSButton {
                if btn == ownerCheckbox {
                    btn.state = (btn.state == .on ? .off : .on)
                    toggleOwner(btn)
                } else {
                    btn.performClick(nil)
                }
                return true
            } else if let sw = control as? NSSwitch {
                sw.state = (sw.state == .on ? .off : .on)
                toggleLogin(sw)
                return true
            } else if let picker = control as? TextSizePickerView {
                if picker.incButton.isEnabled {
                    changeTextSize(delta: 1)
                    picker.incButton.highlight(true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        picker.incButton.highlight(false)
                    }
                }
                return true
            } else if let seg = control as? NSSegmentedControl {
                if seg == sortSegment {
                    seg.selectedSegment = (seg.selectedSegment == 0 ? 1 : 0)
                    seg.sendAction(seg.action, to: seg.target)
                    return true
                } else if seg == layoutSegment {
                    seg.selectedSegment = (seg.selectedSegment + 1) % seg.segmentCount
                    seg.sendAction(seg.action, to: seg.target)
                    return true
                }
            }
            
        case 0: // 'A' key (WASD Left)
            if let picker = control as? TextSizePickerView {
                if picker.decButton.isEnabled {
                    changeTextSize(delta: -1)
                    picker.decButton.highlight(true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        picker.decButton.highlight(false)
                    }
                }
                return true
            } else if let seg = control as? NSSegmentedControl {
                if seg.selectedSegment > 0 {
                    seg.selectedSegment -= 1
                    seg.sendAction(seg.action, to: seg.target)
                    return true
                }
            } else if let slider = control as? NSSlider {
                slider.doubleValue = max(slider.minValue, slider.doubleValue - 1)
                intervalChanged(slider)
                return true
            } else if let stepper = control as? NSStepper {
                stepper.integerValue = max(0, stepper.integerValue - 1)
                indicatorDaysChanged(stepper)
                return true
            }
            
        case 2: // 'D' key (WASD Right)
            if let picker = control as? TextSizePickerView {
                if picker.incButton.isEnabled {
                    changeTextSize(delta: 1)
                    picker.incButton.highlight(true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        picker.incButton.highlight(false)
                    }
                }
                return true
            } else if let seg = control as? NSSegmentedControl {
                if seg.selectedSegment < seg.segmentCount - 1 {
                    seg.selectedSegment += 1
                    seg.sendAction(seg.action, to: seg.target)
                    return true
                }
            } else if let slider = control as? NSSlider {
                slider.doubleValue = min(slider.maxValue, slider.doubleValue + 1)
                intervalChanged(slider)
                return true
            } else if let stepper = control as? NSStepper {
                stepper.integerValue = min(30, stepper.integerValue + 1)
                indicatorDaysChanged(stepper)
                return true
            }
            
        case 13: // 'W' key (WASD Up)
            if let picker = control as? TextSizePickerView {
                if picker.incButton.isEnabled {
                    changeTextSize(delta: 1)
                    picker.incButton.highlight(true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        picker.incButton.highlight(false)
                    }
                }
                return true
            } else if let slider = control as? NSSlider {
                slider.doubleValue = min(slider.maxValue, slider.doubleValue + 1)
                intervalChanged(slider)
                return true
            } else if let stepper = control as? NSStepper {
                stepper.integerValue = min(30, stepper.integerValue + 1)
                indicatorDaysChanged(stepper)
                return true
            }
            
        case 1: // 'S' key (WASD Down)
            if let picker = control as? TextSizePickerView {
                if picker.decButton.isEnabled {
                    changeTextSize(delta: -1)
                    picker.decButton.highlight(true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        picker.decButton.highlight(false)
                    }
                }
                return true
            } else if let slider = control as? NSSlider {
                slider.doubleValue = max(slider.minValue, slider.doubleValue - 1)
                intervalChanged(slider)
                return true
            } else if let stepper = control as? NSStepper {
                stepper.integerValue = max(0, stepper.integerValue - 1)
                indicatorDaysChanged(stepper)
                return true
            }
            
        default:
            break
        }
        
        // Unhandled keys (Arrows 123-126, Return 36, etc.) return false
        // so Player 1 can navigate and launch actions on the main repo list!
        return false
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
        stackView.spacing = 12
        stackView.detachesHiddenViews = true
        stackView.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
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
        formStack.spacing = 14
        formStack.detachesHiddenViews = true
        formStack.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(formStack)
        formStack.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -32).isActive = true
        
        // --- 1. Token Section ---
        let tokenStack = createInnerStack()
        
        tokenBadge.onHoverEntered = { [weak self] in
            self?.updateRateLimitToolTip()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(rateLimitUpdated(_:)), name: Notification.Name("RateLimitUpdated"), object: nil)
        
        tokenStatusLabel.textColor = .secondaryLabelColor
        tokenStatusLabel.font = .systemFont(ofSize: 10, weight: .bold)
        tokenStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        tokenBadge.wantsLayer = true
        tokenBadge.layer?.cornerRadius = 5
        tokenBadge.translatesAutoresizingMaskIntoConstraints = false
        tokenBadge.addSubview(tokenStatusLabel)
        
        NSLayoutConstraint.activate([
            tokenStatusLabel.topAnchor.constraint(equalTo: tokenBadge.topAnchor, constant: 2),
            tokenStatusLabel.bottomAnchor.constraint(equalTo: tokenBadge.bottomAnchor, constant: -2),
            tokenStatusLabel.leadingAnchor.constraint(equalTo: tokenBadge.leadingAnchor, constant: 7),
            tokenStatusLabel.trailingAnchor.constraint(equalTo: tokenBadge.trailingAnchor, constant: -7)
        ])
        
        tokenConnectBtn.target = self
        tokenConnectBtn.action = #selector(startOAuth(_:))
        styleButtonAsBadge(tokenConnectBtn, titleKey: "connectOnly")
        
        tokenDeleteBtn.target = self
        tokenDeleteBtn.action = #selector(deleteToken(_:))
        styleButtonAsBadge(tokenDeleteBtn, titleKey: "deleteOnly")
        
        addSettingsRow(to: tokenStack, label: tokenBadge, controls: [tokenConnectBtn, tokenDeleteBtn])
        
        formStack.addArrangedSubview(createGroupBox(for: tokenStack))
        
        // --- 2. Menu Settings Section ---
        let menuStack = createInnerStack()
        menuStack.spacing = 12 // Consistent spacing
        
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
        
        // Text Size Picker Row
        let textSizeRowLabel = NSTextField(labelWithString: Translations.get("textSizeLabel"))
        textSizeRowLabel.font = .systemFont(ofSize: 13, weight: .medium)
        textSizePicker.onDecrease = { [weak self] in
            self?.changeTextSize(delta: -1)
        }
        textSizePicker.onIncrease = { [weak self] in
            self?.changeTextSize(delta: 1)
        }
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
        
        // Binary Options Rows
        
        newIndicatorStepper.minValue = 0
        newIndicatorStepper.maxValue = 30
        newIndicatorStepper.valueWraps = false
        newIndicatorStepper.target = self
        newIndicatorStepper.action = #selector(indicatorDaysChanged(_:))
        newIndicatorStepper.controlSize = .small
        newIndicatorStepper.autorepeat = false
        
        ownerCheckbox.target = self
        ownerCheckbox.action = #selector(toggleOwner(_:))
        ownerCheckbox.title = ""
        ownerLabel.stringValue = Translations.get("showOwner")
        
        addSettingsRow(to: menuStack, label: newIndicatorLabel, controls: [newIndicatorStepper])
        addSettingsRow(to: menuStack, label: ownerLabel, controls: [ownerCheckbox])
        
        formStack.addArrangedSubview(createGroupBox(for: menuStack))
        
        // --- 3. Interval Section ---
        let intervalStack = createInnerStack()
        intervalSlider.minValue = 1
        intervalSlider.maxValue = 24
        intervalSlider.numberOfTickMarks = 24
        intervalSlider.allowsTickMarkValuesOnly = true
        intervalSlider.target = self
        intervalSlider.action = #selector(intervalChanged(_:))
        intervalSlider.translatesAutoresizingMaskIntoConstraints = false
        intervalSlider.widthAnchor.constraint(equalToConstant: 114).isActive = true
        
        addSettingsRow(to: intervalStack, label: intervalLabel, controls: [intervalSlider])
        
        formStack.addArrangedSubview(createGroupBox(for: intervalStack))
        
        // --- 3.5. Shortcut Section ---
        let shortcutStack = createInnerStack()
        let shortcutLabel = NSTextField(labelWithString: Translations.get("shortcutLabel"))
        shortcutLabel.font = .systemFont(ofSize: 13, weight: .medium)
        
        shortcutBtn.onShortcutChanged = { keyCode, modifiers in
            GlobalHotkeyManager.shared.register(keyCode: keyCode, modifiers: modifiers)
        }
        
        addSettingsRow(to: shortcutStack, label: shortcutLabel, controls: [shortcutBtn])
        formStack.addArrangedSubview(createGroupBox(for: shortcutStack))
        
        // --- 4. Startup ---
        let startupStack = createInnerStack()
        let loginLabel = NSTextField(labelWithString: Translations.get("startAtLogin"))
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin(_:))
        addSettingsRow(to: startupStack, label: loginLabel, controls: [loginSwitch])
        formStack.addArrangedSubview(createGroupBox(for: startupStack))
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
    
    private func updateTokenBadgeStyle(hasToken: Bool) {
        if hasToken {
            tokenStatusLabel.stringValue = Translations.get("connected").uppercased()
            let isDark = (view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            let bgAlpha: CGFloat = isDark ? 0.28 : 0.38
            let borderAlpha: CGFloat = isDark ? 0.45 : 0.65
            
            tokenStatusLabel.textColor = isDark ? .systemGreen : NSColor(srgbRed: 0.10, green: 0.50, blue: 0.20, alpha: 1.0)
            tokenBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(bgAlpha).cgColor
            tokenBadge.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(borderAlpha).cgColor
            tokenBadge.layer?.borderWidth = 0.5
            tokenConnectBtn.isHidden = true
            tokenDeleteBtn.isHidden = false
        } else {
            tokenStatusLabel.stringValue = Translations.get("configureToken").uppercased()
            tokenStatusLabel.textColor = .secondaryLabelColor
            tokenBadge.layer?.backgroundColor = nil
            tokenBadge.layer?.borderColor = nil
            tokenBadge.layer?.borderWidth = 0
            tokenConnectBtn.isHidden = false
            tokenDeleteBtn.isHidden = true
            tokenConnectBtn.isEnabled = true
        }
    }
    
    private func loadCurrentSettings() {
        // Load Token - two exclusive states
        let hasToken = ConfigManager.shared.token != nil && !ConfigManager.shared.token!.isEmpty
        
        updateTokenBadgeStyle(hasToken: hasToken)
        
        isConfirmingDelete = false
        styleButtonAsBadge(tokenDeleteBtn, titleKey: "deleteOnly")
        tokenDeleteBtn.contentTintColor = nil
        
        // Load Interval
        
        // Load Interval
        let mins = ConfigManager.shared.config.refreshMinutes
        initialIntervalHours = max(1, min(24, Int(ceil(Double(mins) / 60.0))))
        intervalSlider.integerValue = initialIntervalHours
        updateIntervalLabel()
        
        // Load Start at Login
        loginSwitch.state = isLoginItem() ? .on : .off
        
        // Load Shortcut
        shortcutBtn.updateDisplay()
        
        // Load Owner
        ownerCheckbox.state = ConfigManager.shared.config.showOwner ? .on : .off
        
        // Load Sort By
        sortSegment.selectedSegment = (ConfigManager.shared.config.sortBy == "name") ? 0 : 1
        
        // Load Layout
        let layout = ConfigManager.shared.config.menuLayout ?? "columns"
        let layoutIndex = ["columns", "cards", "tags"].firstIndex(of: layout) ?? 0
        layoutSegment.selectedSegment = layoutIndex
        
        // Load Text Size
        updateTextSizePicker()
        
        let showNewIndicator = ConfigManager.shared.config.showNewIndicator ?? true
        let days = ConfigManager.shared.config.newIndicatorDays ?? Constants.newReleaseThresholdDays
        newIndicatorStepper.integerValue = showNewIndicator ? days : 0
        updateIndicatorDaysLabel()
        
        updatePreferredContentSize()
        updateRateLimitToolTip()
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
        intervalLabel.stringValue = Translations.get("intervalDynamic").format(with: ["hours": "\(hours)", "unit": unit]).uppercased()
    }
    
    @objc private func startOAuth(_ sender: NSButton) {
        // Prevent duplicate OAuth windows — bring the existing one to front
        if let existing = oauthWindowController, existing.window?.isVisible == true {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
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
            GitHubAPI.shared.clearRateLimits()
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
            styleButtonAsBadge(sender, titleKey: "confirmDisconnect", color: .systemRed)
            
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
            GitHubAPI.shared.clearRateLimits()
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
        
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.rebuildMenu()
        }
        self.isUpdatingSelf = false
    }
    
    @objc private func sortChanged(_ sender: NSSegmentedControl) {
        isUpdatingSelf = true
        let isByName = sender.selectedSegment == 0
        ConfigManager.shared.config.sortBy = isByName ? "name" : "date"
        
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.rebuildMenu()
        }
        self.isUpdatingSelf = false
    }
    @objc private func indicatorDaysChanged(_ sender: NSStepper) {
        updateIndicatorDaysLabel()
        
        let days = sender.integerValue
        self.isUpdatingSelf = true
        ConfigManager.shared.config.showNewIndicator = (days > 0)
        ConfigManager.shared.config.newIndicatorDays = days
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.rebuildMenu()
        }
        self.isUpdatingSelf = false
    }
    
    @objc private func layoutChanged(_ sender: NSSegmentedControl) {
        isUpdatingSelf = true
        let layoutModes = ["columns", "cards", "tags"]
        ConfigManager.shared.config.menuLayout = layoutModes[sender.selectedSegment]
        
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.rebuildMenu()
        }
        self.isUpdatingSelf = false
    }
    
    func changeTextSize(delta: Int) {
        let current = Int(ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize)
        let newValue = max(Int(Constants.menuFontSizeMin), min(Int(Constants.menuFontSizeMax), current + delta))
        guard newValue != current else { return }
        scheduleTextSizeSave(CGFloat(newValue))
        updateTextSizePicker()
    }
    
    func updateTextSizePicker() {
        let current = Int(ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize)
        textSizePicker.setValue(current)
        textSizePicker.setEnabled(
            canDecrease: current > Int(Constants.menuFontSizeMin),
            canIncrease: current < Int(Constants.menuFontSizeMax)
        )
    }
    
    private func scheduleTextSizeSave(_ size: CGFloat) {
        self.isUpdatingSelf = true
        ConfigManager.shared.config.menuFontSize = size
        ConfigManager.shared.saveConfig()
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.rebuildMenu()
        }
        self.isUpdatingSelf = false
    }
    
    private func updateIndicatorDaysLabel() {
        let days = newIndicatorStepper.integerValue
        if days == 0 {
            newIndicatorLabel.stringValue = Translations.get("noNewIndicator").uppercased()
        } else {
            let text = (days == 1) ? Translations.get("indicatorDaySingular") : Translations.get("indicatorDays").format(with: ["days": "\(days)"])
            newIndicatorLabel.stringValue = text.uppercased()
        }
    }
    
    
    private func createBadgeLabel(for textField: NSTextField) -> NSView {
        textField.font = .systemFont(ofSize: 10, weight: .bold)
        textField.stringValue = textField.stringValue.uppercased()
        textField.textColor = .secondaryLabelColor
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }
    
    private func addSettingsRow(to stack: NSStackView, label: NSView, controls: [NSView], subtitle: NSView? = nil) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        
        let labelContainer = NSStackView()
        labelContainer.orientation = .vertical
        labelContainer.alignment = .leading
        labelContainer.spacing = 4
        labelContainer.detachesHiddenViews = true
        
        var finalLabel = label
        if let textField = label as? NSTextField {
            textField.lineBreakMode = .byTruncatingTail
            textField.setContentCompressionResistancePriority(NSLayoutConstraint.Priority.defaultLow, for: NSLayoutConstraint.Orientation.horizontal)
            finalLabel = createBadgeLabel(for: textField)
        }
        
        labelContainer.addArrangedSubview(finalLabel)
        if let sub = subtitle {
            labelContainer.addArrangedSubview(sub)
        }
        
        row.addArrangedSubview(labelContainer)
        
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
        stack.spacing = 12
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    
    private func styleButtonAsBadge(_ button: NSButton, titleKey: String, color: NSColor? = nil) {
        let title = Translations.get(titleKey).uppercased()
        let attrTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: color ?? NSColor.controlTextColor
        ])
        button.attributedTitle = attrTitle
        button.bezelStyle = .rounded
        button.controlSize = .small
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
            innerStack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 10),
            innerStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -10),
            innerStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 14),
            innerStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -14),
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
    
    @objc private func rateLimitUpdated(_ notif: Notification) {
        if let info = notif.object as? RateLimitInfo {
            applyRateLimitToUI(info)
        }
    }
    
    private func updateRateLimitToolTip(force: Bool = false) {
        let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasToken = token != nil && !token!.isEmpty
        
        // 1. Immediately apply the lowest/most constrained count observed for the current auth scope
        if let current = GitHubAPI.shared.currentRateLimit {
            if !hasToken || (current.hasToken && current.limit > 60) {
                applyRateLimitToUI(current)
            } else {
                showInitialRateLimitTip(hasToken: hasToken)
            }
        } else {
            showInitialRateLimitTip(hasToken: hasToken)
        }
        
        // Check cooldown and in-flight status unless forced
        if !force {
            if isFetchingRateLimit { return }
            if let lastFetch = lastRateLimitFetchDate, Date().timeIntervalSince(lastFetch) < 3.0 {
                return
            }
        }
        
        // 2. Fetch fresh headers from GitHub in background using /rate_limit endpoint
        // (works without scopes, supports Bearer auth, doesn't consume rate limit quota)
        let endpoint = "\(Constants.githubAPIBaseURL)/rate_limit"
        guard let url = URL(string: endpoint) else { return }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        if hasToken {
            request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        }
        
        isFetchingRateLimit = true
        lastRateLimitFetchDate = Date()
        
        Task {
            defer {
                Task { @MainActor in
                    self.isFetchingRateLimit = false
                }
            }
            do {
                let (_, response) = try await GitHubAPI.shared.session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { return }
                
                await MainActor.run {
                    if httpResponse.statusCode == 200 {
                        GitHubAPI.shared.recordRateLimit(from: httpResponse, wasAuthenticated: hasToken)
                        if let best = GitHubAPI.shared.currentRateLimit {
                            self.applyRateLimitToUI(best)
                        }
                    } else if httpResponse.statusCode == 401 && hasToken {
                        // Token rejected by GitHub
                        let title = Translations.get("rateLimitTitle")
                        let unauth = Translations.get("rateLimitStatusPublic")
                        let tip = "\(title)\n\(unauth)\n\n\(Translations.get("tokenValidationEmpty"))"
                        self.tokenBadge.toolTip = tip
                        self.tokenStatusLabel.toolTip = tip
                    }
                }
            } catch {
                print("Error al consultar el rate limit de GitHub: \(error)")
            }
        }
    }
    
    private func showInitialRateLimitTip(hasToken: Bool) {
        let title = Translations.get("rateLimitTitle")
        let status = Translations.get(hasToken ? "rateLimitStatusAuth" : "rateLimitStatusPublic")
        let tip = hasToken ? "" : Translations.get("rateLimitTip")
        let initialTip = "\(title)\n\(status)\(tip)"
        self.tokenBadge.toolTip = initialTip
        self.tokenStatusLabel.toolTip = initialTip
    }
    
    private func applyRateLimitToUI(_ info: RateLimitInfo) {
        let resetDate = info.resetDate
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeString = formatter.string(from: resetDate)
        
        let minutesRemaining = max(0, Int(resetDate.timeIntervalSinceNow / 60))
        let currentRemaining = info.currentRemaining
        
        let token = ConfigManager.shared.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasToken = token != nil && !token!.isEmpty
        
        // Guard against displaying "Conectado" if limit is <= 60
        let isAuth = info.hasToken && (info.limit > 60 || !hasToken)
        let title = Translations.get("rateLimitTitle")
        let status = Translations.get(isAuth ? "rateLimitStatusAuth" : "rateLimitStatusPublic")
        let remainingText = Translations.get("rateLimitRemaining").format(with: ["remaining": "\(currentRemaining)", "limit": "\(info.limit)"])
        let resetText = Translations.get("rateLimitReset").format(with: ["minutes": "\(minutesRemaining)", "time": timeString])
        let tip = isAuth ? "" : Translations.get("rateLimitTip")
        
        let tooltipText = """
        \(title)
        \(status)
        \(remainingText)
        \(resetText)\(tip)
        """
        
        self.tokenBadge.toolTip = tooltipText
        self.tokenStatusLabel.toolTip = tooltipText
    }
    
    override func cancelOperation(_ sender: Any?) {
        if let popover = (NSApp.delegate as? AppDelegate)?.settingsPopover {
            popover.close()
        }
    }
    
    /// Sweeps a liquid-crystal reflection band across the Settings view.
    func sweepSheen(delay: TimeInterval, duration: TimeInterval, startX: CGFloat, endX: CGFloat) {
        sheenOverlay.sweep(delay: delay, duration: duration, startX: startX, endX: endX)
    }
}

// MARK: - RateLimitBadge
class RateLimitBadge: NSView {
    var onHoverEntered: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        onHoverEntered?()
    }
}
