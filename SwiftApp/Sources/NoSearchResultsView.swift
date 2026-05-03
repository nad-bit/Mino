import Cocoa

@MainActor
class NoSearchResultsView: NSView {
    
    private let mainStack = NSStackView() // Vertical container
    private let errorStack = NSStackView()
    private let iconView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    private var tagButtons: [TagButton] = []
    
    var onTagSelected: ((String) -> Void)?
    var targetWidth: CGFloat = Constants.menuDefaultWidth {
        didSet {
            if oldValue != targetWidth {
                invalidateIntrinsicContentSize()
            }
        }
    }
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.menuDefaultWidth, height: 40))
        self.translatesAutoresizingMaskIntoConstraints = false
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 6
        mainStack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Ensure the view hugs its content tightly and doesn't stretch vertically
        mainStack.setContentHuggingPriority(.required, for: .vertical)
        mainStack.setContentCompressionResistancePriority(.required, for: .vertical)
        
        addSubview(mainStack)
        
        // --- Error Stack Component (Icon + Label) ---
        let config = NSImage.SymbolConfiguration(pointSize: Constants.menuBaseFontSize + 1, weight: .semibold)
        let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "No results")?.withSymbolConfiguration(config)
        
        iconView.image = image
        iconView.contentTintColor = .systemRed
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        textLabel.isBezeled = false
        textLabel.drawsBackground = false
        textLabel.isEditable = false
        textLabel.isSelectable = false
        textLabel.usesSingleLineMode = true
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        textLabel.font = .systemFont(ofSize: baseFontSize - 1, weight: .medium)
        textLabel.textColor = .secondaryLabelColor
        textLabel.alignment = .center
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        
        errorStack.addArrangedSubview(iconView)
        errorStack.addArrangedSubview(textLabel)
        errorStack.orientation = .horizontal
        errorStack.alignment = .centerY
        errorStack.spacing = 8
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        
        mainStack.addArrangedSubview(errorStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    override var isFlipped: Bool { return true }
    
    /// Morphs the view into a Tag Suggestion Cloud or Empty State.
    func configure(suggestedTags: [String], isSearching: Bool) {
        // 1. Reset state
        mainStack.arrangedSubviews.filter { $0 !== errorStack }.forEach { $0.removeFromSuperview() }
        
        textLabel.stringValue = isSearching ? Translations.get("noResults") : Translations.get("noRepos")
        iconView.image = NSImage(systemSymbolName: isSearching ? "eye.slash" : "slash.circle", accessibilityDescription: nil)
        
        if suggestedTags.isEmpty {
            errorStack.isHidden = false
        } else {
            errorStack.isHidden = true
            
            let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
            let font = NSFont.systemFont(ofSize: baseFontSize - 1, weight: .medium)
            let paddingX: CGFloat = 32.0 // mainStack.edgeInsets.left + right
            let availableWidth = targetWidth - paddingX
            
            var currentRowStack = createRowStack()
            var currentRowWidth: CGFloat = 0
            let tagSpacing: CGFloat = 8.0
            
            for tag in suggestedTags {
                let btn = getOrCreateButton(title: tag, fontSize: baseFontSize - 1)
                let titleSize = (tag as NSString).size(withAttributes: [.font: font])
                let btnWidth = ceil(titleSize.width) + 16.0
                
                // Check if it fits in current row
                if currentRowWidth + btnWidth > availableWidth && currentRowWidth > 0 {
                    mainStack.addArrangedSubview(currentRowStack)
                    currentRowStack = createRowStack()
                    currentRowWidth = 0
                }
                
                currentRowStack.addArrangedSubview(btn)
                currentRowWidth += btnWidth + tagSpacing
            }
            
            if !currentRowStack.arrangedSubviews.isEmpty {
                mainStack.addArrangedSubview(currentRowStack)
            }
        }
        
        self.invalidateIntrinsicContentSize()
        self.layoutSubtreeIfNeeded()
        
        // Notify popover to resize
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.mainPopoverVC.updatePreferredContentSize()
        }
    }
    
    private func createRowStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.distribution = .equalSpacing
        return stack
    }
    
    private func getOrCreateButton(title: String, fontSize: CGFloat) -> TagButton {
        // Simple reuse pool
        if let reused = tagButtons.first(where: { $0.superview == nil }) {
            reused.title = title
            reused.font = .systemFont(ofSize: fontSize, weight: .medium)
            return reused
        }
        
        let btn = TagButton(title: title)
        btn.target = self
        btn.action = #selector(tagClicked(_:))
        tagButtons.append(btn)
        return btn
    }
    
    override var intrinsicContentSize: NSSize {
        return mainStack.fittingSize
    }
    
    @objc private func tagClicked(_ sender: NSButton) {
        // Strip the hash before passing to the search field so it reads natively
        let cleanTag = sender.title.replacingOccurrences(of: "#", with: "")
        onTagSelected?(cleanTag)
    }
}

/// Simple convenience subview that standardizes coordinates to top-left (0,0)
@MainActor
class FlippedView: NSView {
    override var isFlipped: Bool { return true }
}

// Custom specialized NSButton for native hover responses
class TagButton: NSButton {
    
    init(title: String) {
        super.init(frame: .zero)
        self.title = title 
        self.isBordered = false
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        self.font = .systemFont(ofSize: baseFontSize - 1, weight: .medium)
        self.contentTintColor = .secondaryLabelColor
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.masksToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
    }
    
    override func mouseEntered(with event: NSEvent) {
        self.contentTintColor = .white
        self.layer?.backgroundColor = NSColor.systemBlue.cgColor
        NSCursor.pointingHand.set()
    }
    
    override func mouseExited(with event: NSEvent) {
        self.contentTintColor = .secondaryLabelColor
        self.layer?.backgroundColor = NSColor.clear.cgColor
        NSCursor.arrow.set()
    }
}
