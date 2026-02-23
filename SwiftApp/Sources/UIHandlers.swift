import Cocoa

@MainActor
class IntervalDialogHandler: NSObject {
    var label: NSTextField!
    
    @objc func sliderChanged(_ sender: NSSlider) {
        let val = Int(sender.intValue)
        if val == 1 {
            label.stringValue = "1 \(Translations.get("unitHour"))"
        } else {
            label.stringValue = "\(val) \(Translations.get("hours"))"
        }
    }
}

@MainActor
class AddRepoHandler: NSObject {
    var inputField: NSTextField!
    var brewPopup: NSPopUpButton!
    var appRef: Any!
    var alert: NSAlert!
    
    @objc func radioChanged(_ sender: NSButton) {
        if sender.tag == 1 {
            inputField.isHidden = false
            brewPopup.isHidden = true
            alert.informativeText = Translations.get("enterRepoMsg")
        } else if sender.tag == 2 {
            inputField.isHidden = true
            brewPopup.isHidden = false
            alert.informativeText = Translations.get("addFromBrew")
            
            if brewPopup.numberOfItems <= 1 {
                // Fetch brews
                Task {
                    let casks = await HomebrewManager.shared.listCasks()
                    self.updateBrewList(caskList: casks)
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
}

@MainActor
class UIHandlers {
    static let shared = UIHandlers()
    
    func showTokenDialog(currentToken: String?, completion: @escaping (String?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        
        var maskedIndicator: String? = nil
        if let token = currentToken, token.count > 4 {
            let suffix = String(token.suffix(4))
            maskedIndicator = "••••••••\(suffix)"
        } else if currentToken != nil {
            maskedIndicator = "••••••••"
        }
        
        let alert = NSAlert()
        alert.messageText = Translations.get("configureToken")
        
        if let prefix = maskedIndicator {
            alert.informativeText = "\(Translations.get("enterTokenMsg"))\n\n\(Translations.get("currentToken")): \(prefix)"
        } else {
            alert.informativeText = Translations.get("enterTokenMsg")
        }
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 50))
        inputField.placeholderString = Translations.get("tokenPlaceholder")
        
        // Smart Paste logic simplified for Swift
        if let clipboardString = NSPasteboard.general.string(forType: .string) {
            let regex = try? NSRegularExpression(pattern: "((?:gh[ps]_|github_pat_)[a-zA-Z0-9_-]{36,})|([0-9a-fA-F]{40})")
            let range = NSRange(location: 0, length: clipboardString.utf16.count)
            if let match = regex?.firstMatch(in: clipboardString, options: [], range: range) {
                if let r = Range(match.range, in: clipboardString) {
                    inputField.stringValue = String(clipboardString[r])
                }
            }
        }
        
        alert.accessoryView = inputField
        alert.addButton(withTitle: Translations.get("ok"))
        alert.addButton(withTitle: Translations.get("cancel"))
        
        if currentToken != nil {
            alert.addButton(withTitle: Translations.get("deleteToken"))
        }
        
        let response = alert.runModal()
        // NSAlertFirstButtonReturn = 1000, Second = 1001, Third = 1002
        if response == .alertFirstButtonReturn {
            let nwToken = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nwToken.isEmpty {
                completion(nwToken)
            } else {
                completion(nil) // empty field, do nothing
            }
        } else if response == .alertThirdButtonReturn {
            // Delete token
            let _ = ConfigManager.shared.deleteTokenFromKeychain()
            ConfigManager.shared.token = nil
            let infoAlert = NSAlert()
            infoAlert.messageText = Translations.get("configureToken")
            infoAlert.informativeText = Translations.get("tokenValidationEmpty")
            infoAlert.runModal()
            completion("") // Signal explicitly to trigger refresh without token
        }
    }
    
    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "GitHub Watcher"
        alert.informativeText = Translations.get("aboutMsg")
        alert.addButton(withTitle: Translations.get("ok"))
        alert.runModal()
    }
    
    func confirmDeleteRepo(name: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = Translations.get("deleteRepo")
        alert.informativeText = "\(Translations.get("confirmDelete"))\n\n'\(name)'"
        alert.addButton(withTitle: Translations.get("ok"))
        alert.addButton(withTitle: Translations.get("cancel"))
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }
    
    func showReleaseNotes(info: RepoInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = Translations.get("releaseNotes")
        
        let caskName = ConfigManager.shared.config.repos.first(where: { $0.name == info.name && $0.source == "brew" })?.cask
        var infoText = info.name
        if let cask = caskName {
            infoText += "\nCask: \(cask)"
        }
        alert.informativeText = infoText
        alert.addButton(withTitle: Translations.get("ok"))
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 450, height: 250))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 430, height: 250))
        textView.string = info.body ?? Translations.get("noNotes")
        textView.isEditable = false
        textView.font = NSFont.systemFont(ofSize: 12)
        
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        
        alert.runModal()
    }
    
    func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: Translations.get("ok"))
        alert.runModal()
    }
    
    func showIntervalDialog(currentMinutes: Int) -> Int? {
        NSApp.activate(ignoringOtherApps: true)
        let currentHours = max(1, min(24, currentMinutes / 60))
        
        let alert = NSAlert()
        alert.messageText = Translations.get("changeInterval")
        alert.informativeText = Translations.get("enterIntervalMsg")
        
        let customView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 50))
        
        let slider = NSSlider(frame: NSRect(x: 50, y: 20, width: 200, height: 24))
        slider.minValue = 1.0
        slider.maxValue = 24.0
        slider.numberOfTickMarks = 24
        slider.allowsTickMarkValuesOnly = true
        slider.intValue = Int32(currentHours)
        
        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 20))
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.alignment = .center
        
        let handler = IntervalDialogHandler()
        handler.label = label
        slider.target = handler
        slider.action = #selector(IntervalDialogHandler.sliderChanged(_:))
        
        // Initial setup
        handler.sliderChanged(slider)
        
        customView.addSubview(slider)
        customView.addSubview(label)
        alert.accessoryView = customView
        
        alert.addButton(withTitle: Translations.get("ok"))
        alert.addButton(withTitle: Translations.get("cancel"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return Int(slider.intValue) * 60
        }
        return nil
    }
    
    func showUnifiedAddRepoDialog(hasBrew: Bool, completion: @escaping (String?, String?, String?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        
        let handler = AddRepoHandler()
        let alert = NSAlert()
        alert.messageText = Translations.get("addRepoUnified")
        alert.informativeText = Translations.get("enterRepoMsg")
        
        handler.alert = alert
        
        let mainView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        
        let radioManual = NSButton(radioButtonWithTitle: Translations.get("manualOption"), target: handler, action: #selector(AddRepoHandler.radioChanged(_:)))
        radioManual.frame = NSRect(x: 0, y: 70, width: 150, height: 24)
        radioManual.tag = 1
        radioManual.state = .on
        
        let radioBrew = NSButton(radioButtonWithTitle: Translations.get("brewOption"), target: handler, action: #selector(AddRepoHandler.radioChanged(_:)))
        radioBrew.frame = NSRect(x: 150, y: 70, width: 150, height: 24)
        radioBrew.tag = 2
        
        if !hasBrew {
            radioBrew.isEnabled = false
        }
        
        mainView.addSubview(radioManual)
        mainView.addSubview(radioBrew)
        
        var prefillText = ""
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            let regex = try? NSRegularExpression(pattern: "(?:github\\.com/)?([^/\\s\"]+/[^/\\s\"]+)")
            let range = NSRange(location: 0, length: clipboard.utf16.count)
            if let match = regex?.firstMatch(in: clipboard, options: [], range: range) {
                if let r = Range(match.range(at: 1), in: clipboard) {
                    var candidate = String(clipboard[r]).replacingOccurrences(of: ".git", with: "")
                    if let index = candidate.firstIndex(of: "?") {
                        candidate = String(candidate[..<index])
                    }
                    if let index = candidate.firstIndex(of: "#") {
                        candidate = String(candidate[..<index])
                    }
                    if candidate.split(separator: "/").count == 2 {
                        prefillText = candidate
                    }
                }
            }
        }
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 30, width: 300, height: 24))
        inputField.stringValue = prefillText
        inputField.placeholderString = "owner/repo-name"
        mainView.addSubview(inputField)
        handler.inputField = inputField
        
        let brewPopup = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 300, height: 24), pullsDown: false)
        brewPopup.addItem(withTitle: Translations.get("loadingBrew"))
        brewPopup.isEnabled = false
        brewPopup.isHidden = true
        mainView.addSubview(brewPopup)
        handler.brewPopup = brewPopup
        
        alert.accessoryView = mainView
        alert.addButton(withTitle: Translations.get("ok"))
        alert.addButton(withTitle: Translations.get("cancel"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if radioManual.state == .on {
                let repo = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !repo.isEmpty {
                    completion(repo, "manual", nil)
                }
            } else {
                if brewPopup.indexOfSelectedItem > 0 {
                    let selectedCask = brewPopup.titleOfSelectedItem
                    completion(nil, "brew", selectedCask)
                }
            }
        }
    }
}
