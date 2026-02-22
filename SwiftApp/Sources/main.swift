import Cocoa

@main
struct AppRunner {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        // Required so the app remains active in the menu bar and doesn't get minimized or ignored
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
