import Cocoa

@MainActor
class NoSearchResultsView: NSView {
    
    private let errorStack = NSStackView()
    private let iconView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    
    private let tagCloudContainer = FlippedView()
    
    var onTagSelected: ((String) -> Void)?
    var targetWidth: CGFloat = 400.0 {
        didSet {
            if oldValue != targetWidth {
                needsLayout = true
            }
        }
    }
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        self.autoresizingMask = [.width]
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // --- Error Stack Component ---
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "No results")?.withSymbolConfiguration(config)
        
        iconView.image = image
        iconView.contentTintColor = .systemRed
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        textLabel.isBezeled = false
        textLabel.drawsBackground = false
        textLabel.isEditable = false
        textLabel.isSelectable = false
        textLabel.font = .systemFont(ofSize: 12, weight: .medium)
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
        
        addSubview(errorStack)
        
        NSLayoutConstraint.activate([
            errorStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            errorStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
        
        // --- Tag Cloud Container Component ---
        tagCloudContainer.translatesAutoresizingMaskIntoConstraints = false
        tagCloudContainer.isHidden = true
        addSubview(tagCloudContainer)
        
        NSLayoutConstraint.activate([
            tagCloudContainer.topAnchor.constraint(equalTo: topAnchor),
            tagCloudContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            tagCloudContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            tagCloudContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    // Reverse Cocoa's Y coordinate system so elements lay out naturally top-to-bottom
    override var isFlipped: Bool { return true }
    
    /// Morphs the view into a Tag Suggestion Cloud when a search yields zero repository results.
    func configure(suggestedTags: [String]) {
        // Tag Cloud Mode Defaults
        errorStack.isHidden = true
        tagCloudContainer.isHidden = false
        
        // Clear recycled subviews
        tagCloudContainer.subviews.forEach { $0.removeFromSuperview() }
        
        if suggestedTags.isEmpty {
            // Clean fallback if the user has literally 0 tags indexed in their database
            textLabel.stringValue = Translations.get("noRepos") // or noTagsFound
            iconView.isHidden = true // Hide the red slashed eye completely
            errorStack.isHidden = false
            tagCloudContainer.isHidden = true
            return
        }
        
        for tag in suggestedTags {
            let btn = TagButton(title: tag)
            btn.target = self
            btn.action = #selector(tagClicked(_:))
            
            // Explicit typography measurement
            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let titleSize = (tag as NSString).size(withAttributes: [.font: font])
            let btnWidth = ceil(titleSize.width) + 16.0 
            let btnHeight = max(ceil(titleSize.height) + 8.0, 22.0)
            
            btn.frame = NSRect(x: 0, y: 0, width: btnWidth, height: btnHeight)
            tagCloudContainer.addSubview(btn)
        }
        
        // --- CRITICAL SYNC LAYOUT ---
        // Calculate and set height immediately so NSMenu reads the CORRECT height 
        // the very first time it traces the view during menuWillOpen.
        let calculatedHeight = performFlowLayout(width: targetWidth)
        self.frame.size = NSSize(width: targetWidth, height: calculatedHeight)
        
        needsLayout = true
    }
    
    @discardableResult
    private func performFlowLayout(width: CGFloat) -> CGFloat {
        let availableWidth = width
        if availableWidth <= 32.0 || tagCloudContainer.isHidden { return 40.0 }
        
        let paddingX: CGFloat = 18.0
        let paddingY: CGFloat = 16.0
        let spacingX: CGFloat = 8.0
        let spacingY: CGFloat = 10.0
        
        var currentX: CGFloat = paddingX
        var currentY: CGFloat = paddingY
        var currentRowHeight: CGFloat = 0.0
        
        for view in tagCloudContainer.subviews {
            if view.isHidden { continue }
            let bWidth = view.frame.width
            let bHeight = view.frame.height
            
            if currentX + bWidth + paddingX > availableWidth && currentX > paddingX {
                currentX = paddingX
                currentY += currentRowHeight + spacingY
                currentRowHeight = 0
            }
            
            view.setFrameOrigin(NSPoint(x: currentX, y: currentY))
            currentX += bWidth + spacingX
            currentRowHeight = max(currentRowHeight, bHeight)
        }
        
        let newHeight = currentY + currentRowHeight + paddingY
        return max(newHeight, 40.0)
    }
    
    override func layout() {
        super.layout()
        
        // Prioritize our calculated targetWidth (Backup Inteligente) as the primary source of truth.
        // We only use Carbon's menu.size.width if it happens to be GREATER than our target.
        // This prevents the "1-line wrap" bug where macOS reports a premature small width.
        let carbonWidth = self.enclosingMenuItem?.menu?.size.width ?? 0
        let availableWidth = max(targetWidth, max(bounds.width, carbonWidth))
        
        // Final guard against 0 or negative values to prevent infinite recursion
        let finalAvailableWidth = max(availableWidth, 400.0)
        
        let finalHeight = performFlowLayout(width: finalAvailableWidth)
        
        // If the fluid mathematical height changed due to a UI bounds shift, dynamically kick NSMenu to remeasure!
        if abs(finalHeight - self.frame.size.height) > 1.0 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard let menuItem = self.enclosingMenuItem else { return }
                
                if abs(finalHeight - self.frame.size.height) > 1.0 {
                    self.frame.size.height = finalHeight
                    menuItem.view = self 
                }
            }
        }
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
        self.title = title // Title ALREADY includes `#` from AppDelegate cache
        self.isBordered = false
        self.font = .systemFont(ofSize: 12, weight: .medium)
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
