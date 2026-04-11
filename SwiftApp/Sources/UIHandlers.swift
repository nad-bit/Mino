import Cocoa



// AddRepoHandler has been moved to AddRepoWindowController.swift

@MainActor
class UIHandlers {
    static let shared = UIHandlers()
    
    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
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
    

    

    // showUnifiedAddRepoDialog and showReleaseNotes were migrated to standalone WindowControllers
}
