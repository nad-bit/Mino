import Cocoa

class EmptyMenuPlaceholderView: NSView {
    private let iconView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    
    init() {
        // Standard height for placeholder to feel consistent with repo rows
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.menuDefaultWidth, height: 44))
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        
        iconView.image = NSImage(systemSymbolName: "slash.circle", accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: baseFontSize + 2, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        textLabel.stringValue = Translations.get("noRepos")
        textLabel.font = .systemFont(ofSize: baseFontSize, weight: .medium)
        textLabel.textColor = .secondaryLabelColor
        textLabel.alignment = .center
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let stack = NSStackView(views: [iconView, textLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: baseFontSize + 4),
            iconView.heightAnchor.constraint(equalToConstant: baseFontSize + 4)
        ])
    }
    
    // Ensure the placeholder scales if the user changes settings and the menu is rebuilt
    override func viewWillDraw() {
        super.viewWillDraw()
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        textLabel.font = .systemFont(ofSize: baseFontSize, weight: .medium)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: baseFontSize + 2, weight: .regular)
    }
}
