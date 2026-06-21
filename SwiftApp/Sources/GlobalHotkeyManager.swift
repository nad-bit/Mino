import Cocoa
import Carbon

class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    var onHotkeyTriggered: (() -> Void)?
    
    // Carbon Event Handler signature / ID
    private let hotKeySignature: OSType = 0x4D494E4F // "MINO"
    private let hotKeyID: UInt32 = 1
    
    func register(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        unregister()
        
        let carbonModifiers = translateToCarbonModifiers(modifiers)
        let keyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyID)
        
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(carbonModifiers),
            keyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        
        if status == noErr {
            self.hotKeyRef = ref
            installEventHandlerIfNeeded()
        } else {
            print("Failed to register hotkey with status: \(status)")
        }
    }
    
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
    
    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { (_, eventRef, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if status == noErr {
                if hotKeyID.signature == GlobalHotkeyManager.shared.hotKeySignature && hotKeyID.id == GlobalHotkeyManager.shared.hotKeyID {
                    DispatchQueue.main.async {
                        GlobalHotkeyManager.shared.onHotkeyTriggered?()
                    }
                }
            }
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, nil, &eventHandlerRef)
    }
    
    private func translateToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var carbonFlags = 0
        if flags.contains(.command) { carbonFlags |= cmdKey }
        if flags.contains(.option) { carbonFlags |= optionKey }
        if flags.contains(.control) { carbonFlags |= controlKey }
        if flags.contains(.shift) { carbonFlags |= shiftKey }
        return carbonFlags
    }
}

// MARK: - ShortcutRecorderButton
class ShortcutRecorderButton: NSButton {
    private var isRecording = false
    private var keyMonitor: Any?
    var onShortcutChanged: ((Int, NSEvent.ModifierFlags) -> Void)?
    
    override var acceptsFirstResponder: Bool { return true }
    
    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording(cancelled: true)
        }
        return super.resignFirstResponder()
    }
    
    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            startRecording()
        } else {
            stopRecording(cancelled: true)
        }
    }
    
    private func startRecording() {
        isRecording = true
        self.window?.makeFirstResponder(self)
        updateDisplay()
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Escape cancels the recording
            if event.keyCode == 53 && modifiers.isEmpty {
                self.stopRecording(cancelled: true)
                return nil
            }
            
            // Exigir al menos un modificador que no sea Shift solo (ej: CMD, OPT, CTRL)
            let mainModifiers = modifiers.intersection([.command, .option, .control])
            guard !mainModifiers.isEmpty else {
                return nil // Consume normal keys to prevent beeping
            }
            
            let keyCode = Int(event.keyCode)
            
            UserDefaults.standard.set(keyCode, forKey: "MinoShortcutKeyCode")
            UserDefaults.standard.set(modifiers.rawValue, forKey: "MinoShortcutModifiers")
            
            self.stopRecording(cancelled: false)
            self.onShortcutChanged?(keyCode, modifiers)
            return nil
        }
    }
    
    private func stopRecording(cancelled: Bool) {
        isRecording = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        updateDisplay()
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Local monitor consumes everything when recording, so this is just a fallback.
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return true
    }
    
    func updateDisplay() {
        let titleColor = isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        let titleText: String
        
        if isRecording {
            titleText = Translations.get("shortcutRecording")
        } else {
            let keyCode = UserDefaults.standard.integer(forKey: "MinoShortcutKeyCode")
            let rawModifiers = UserDefaults.standard.integer(forKey: "MinoShortcutModifiers")
            
            if keyCode > 0 {
                let modifiers = NSEvent.ModifierFlags(rawValue: UInt(rawModifiers))
                titleText = ShortcutRecorderButton.stringForShortcut(keyCode: keyCode, modifiers: modifiers)
            } else {
                titleText = Translations.get("shortcutRecordPlaceholder")
            }
        }
        
        let attrTitle = NSAttributedString(string: titleText, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: titleColor
        ])
        
        self.attributedTitle = attrTitle
        self.bezelStyle = .rounded
        self.controlSize = .small
        
        // Highlight background when recording
        if isRecording {
            self.state = .on
        } else {
            self.state = .off
        }
    }
    
    static func stringForShortcut(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var str = ""
        if modifiers.contains(.control) { str += "⌃" }
        if modifiers.contains(.option) { str += "⌥" }
        if modifiers.contains(.shift) { str += "⇧" }
        if modifiers.contains(.command) { str += "⌘" }
        
        if let keyStr = stringForKeyCode(keyCode) {
            str += keyStr.uppercased()
        } else {
            str += "\(keyCode)"
        }
        return str
    }
    
    private static func stringForKeyCode(_ keyCode: Int) -> String? {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: break
        }
        
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutDataRef = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let rawLayout = CFDataGetBytePtr(layoutData)
        
        var deadKeys: UInt32 = 0
        var unicodeString = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        
        let result = UCKeyTranslate(
            unsafeBitCast(rawLayout, to: UnsafePointer<UCKeyboardLayout>.self),
            UInt16(keyCode),
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysMask),
            &deadKeys,
            4,
            &actualLength,
            &unicodeString
        )
        
        if result == noErr && actualLength > 0 {
            return String(utf16CodeUnits: unicodeString, count: actualLength)
        }
        return nil
    }
}
