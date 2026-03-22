import Cocoa

@MainActor
class NoSearchResultsView: NSView {
    
    private let iconView = NSImageView()
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 32))
        self.autoresizingMask = [.width]
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "No results")?.withSymbolConfiguration(config)
        
        iconView.image = image
        iconView.contentTintColor = .systemRed
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(iconView)
        
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
}
