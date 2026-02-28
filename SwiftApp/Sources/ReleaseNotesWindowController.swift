import Cocoa

class ReleaseNotesWindowController: NSWindowController, NSWindowDelegate {
    private var textView: NSTextView!
    private var titleLabel: NSTextField!
    
    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 500, height: 400)
        let window = NSWindow(contentRect: windowRect,
                            styleMask: [.titled, .closable, .resizable, .miniaturizable],
                            backing: .buffered,
                            defer: false)
        window.title = Translations.get("releaseNotes")
        window.center()
        
        super.init(window: window)
        window.delegate = self
        
        // Setup UI
        let container = NSView(frame: windowRect)
        
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        container.addSubview(titleLabel)
        
        // ScrollView for notes
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        textView = NSTextView()
        textView.isEditable = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        container.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20)
        ])
        
        window.contentView = container
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func loadNotes(for info: RepoInfo) {
        let caskName = ConfigManager.shared.config.repos.first(where: { $0.name == info.name && $0.source == "brew" })?.cask
        var infoText = info.name
        if let cask = caskName {
            infoText += " (📦 \(cask))"
        }
        titleLabel.stringValue = infoText
        textView.string = info.body ?? Translations.get("noNotes")
        
        // Ensure scroll jumps back to top on recycle
        textView.scrollToBeginningOfDocument(nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Just hide it, do not destroy
        self.window?.orderOut(nil)
    }
}
