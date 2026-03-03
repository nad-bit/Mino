import Cocoa



// AddRepoHandler has been moved to AddRepoWindowController.swift

@MainActor
class UIHandlers {
    static let shared = UIHandlers()
    
    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    func showAbout() {
        appDelegate?.bringToFront()
        let alert = NSAlert()
        alert.messageText = "Mino"
        alert.informativeText = Translations.get("aboutMsg")
        alert.addButton(withTitle: Translations.get("ok"))
        alert.runModal()
        appDelegate?.returnToAccessory()
    }
    
    func confirmDeleteRepo(name: String) -> Bool {
        appDelegate?.bringToFront()
        let alert = NSAlert()
        alert.messageText = Translations.get("deleteRepo")
        alert.informativeText = "\(Translations.get("confirmDelete"))\n\n'\(name)'"
        alert.addButton(withTitle: Translations.get("ok"))
        alert.addButton(withTitle: Translations.get("cancel"))
        let response = alert.runModal()
        appDelegate?.returnToAccessory()
        return response == .alertFirstButtonReturn
    }
    
    func showReleaseNotes(info: RepoInfo) {
        appDelegate?.bringToFront()
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
        appDelegate?.returnToAccessory()
    }
    
    func showAlert(title: String, message: String) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.animateStatusIcon(with: .wiggle)
        }
        appDelegate?.bringToFront()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: Translations.get("ok"))
        alert.runModal()
        appDelegate?.returnToAccessory()
    }
    

    // showUnifiedAddRepoDialog and showReleaseNotes were migrated to standalone WindowControllers
}
