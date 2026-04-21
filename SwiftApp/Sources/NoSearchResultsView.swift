import Cocoa

@MainActor
class NoSearchResultsView: NSView {
    
    private let errorStack = NSStackView()
    private let iconView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    
    private let tagCloudContainer = FlippedView()
    
    var onTagSelected: ((String) -> Void)?
    var targetWidth: CGFloat = Constants.menuDefaultWidth {
        didSet {
            if oldValue != targetWidth {
                needsLayout = true
            }
        }
    }
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.menuDefaultWidth, height: 40))
        self.autoresizingMask = [.width]
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // --- Error Stack Component ---
        let config = NSImage.SymbolConfiguration(pointSize: Constants.menuBaseFontSize + 1, weight: .semibold)
        let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "No results")?.withSymbolConfiguration(config)
        
        iconView.image = image
        iconView.contentTintColor = .systemRed
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        textLabel.isBezeled = false
        textLabel.drawsBackground = false
        textLabel.isEditable = false
        textLabel.isSelectable = false
        textLabel.usesSingleLineMode = true   // ← Prevents internal line-breaking regardless of container width
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        textLabel.font = .systemFont(ofSize: baseFontSize - 1, weight: .medium)
        textLabel.textColor = .secondaryLabelColor
        textLabel.alignment = .center
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        textLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        errorStack.addArrangedSubview(iconView)
        errorStack.addArrangedSubview(textLabel)
        errorStack.orientation = .horizontal
        errorStack.alignment = .centerY
        errorStack.spacing = 8
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(errorStack)
        
        // --- Tag Cloud Container Component ---
        tagCloudContainer.translatesAutoresizingMaskIntoConstraints = false
        tagCloudContainer.isHidden = true
        addSubview(tagCloudContainer)
        
        NSLayoutConstraint.activate([
            // Center the error stack when visible
            errorStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            errorStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            
            // Tag cloud occupies the full view space when visible
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
        // Clear recycled subviews
        tagCloudContainer.subviews.forEach { $0.removeFromSuperview() }
        
        // Primary search feedback
        textLabel.stringValue = Translations.get("noResults")
        
        if suggestedTags.isEmpty {
            // No tags to show -> show the "No results" message centered
            errorStack.isHidden = false
            tagCloudContainer.isHidden = true
            return
        }
        
        // Tags available -> hide the text message and show ONLY the cloud
        errorStack.isHidden = true
        tagCloudContainer.isHidden = false
        
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        
        for tag in suggestedTags {
            let btn = TagButton(title: tag)
            btn.target = self
            btn.action = #selector(tagClicked(_:))
            
            // Explicit typography measurement using dynamic base
            let font = NSFont.systemFont(ofSize: baseFontSize - 1, weight: .medium)
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
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        if availableWidth <= baseFontSize * 2 || tagCloudContainer.isHidden { return 40.0 }
        
        let paddingX: CGFloat = 18.0
        let paddingY: CGFloat = 16.0
        let spacingY: CGFloat = 10.0
        let minSpacingX: CGFloat = 8.0
        
        let subviews = tagCloudContainer.subviews.filter { !$0.isHidden }
        if subviews.isEmpty { return 40.0 }
        
        var currentY: CGFloat = paddingY
        var i = 0
        while i < subviews.count {
            // 1. Identify which views fit in the current row
            var rowViews: [NSView] = []
            var rowTagsWidth: CGFloat = 0
            var tempX: CGFloat = paddingX
            
            while i < subviews.count {
                let view = subviews[i]
                let vWidth = view.frame.width
                
                // If it's the first item in row or it fits with min spacing
                if rowViews.isEmpty || (tempX + minSpacingX + vWidth + paddingX <= availableWidth) {
                    let space = rowViews.isEmpty ? 0 : minSpacingX
                    tempX += space + vWidth
                    rowTagsWidth += vWidth
                    rowViews.append(view)
                    i += 1
                } else {
                    break
                }
            }
            
            // 2. Layout the row
            let rowHeight = rowViews.map { $0.frame.height }.max() ?? 0
            let isLastRow = i >= subviews.count
            
            if isLastRow || rowViews.count == 1 {
                // Left aligned for last row or single-item row
                var currentX = paddingX
                for view in rowViews {
                    view.setFrameOrigin(NSPoint(x: currentX, y: currentY))
                    currentX += view.frame.width + minSpacingX
                }
            } else {
                // Justified alignment: distribute extra space between tags
                let totalGaps = CGFloat(rowViews.count - 1)
                let actualSpacingX = (availableWidth - 2 * paddingX - rowTagsWidth) / totalGaps
                
                var currentX = paddingX
                for (idx, view) in rowViews.enumerated() {
                    view.setFrameOrigin(NSPoint(x: currentX, y: currentY))
                    if idx < rowViews.count - 1 {
                        currentX += view.frame.width + actualSpacingX
                    }
                }
            }
            
            currentY += rowHeight + spacingY
        }
        
        return max(currentY - spacingY + paddingY, 40.0)
    }
    
    override func layout() {
        super.layout()
        
        let carbonWidth = self.enclosingMenuItem?.menu?.size.width ?? 0
        let availableWidth = max(targetWidth, max(bounds.width, carbonWidth))
        let finalAvailableWidth = max(availableWidth, Constants.menuDefaultWidth)
        
        // Safety: If the width is still too small, force the default width to avoid multi-line glitches
        let effectiveWidth = max(finalAvailableWidth, 250.0)
        
        let finalHeight: CGFloat
        if tagCloudContainer.isHidden {
            // Standard height for centered "No results" message
            finalHeight = 44.0
        } else {
            // Dynamic height based on tag cloud content
            finalHeight = performFlowLayout(width: effectiveWidth)
        }
        
        // If the fluid mathematical height changed due to a UI bounds shift, dynamically kick NSMenu to remeasure!
        if abs(finalHeight - self.frame.size.height) > 1.0 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard let menuItem = self.enclosingMenuItem else { return }
                
                if abs(finalHeight - self.frame.size.height) > 1.0 {
                    // Enforce minimum width before handing back to NSMenu to prevent width collapse
                    let safeWidth = max(self.frame.size.width, Constants.menuDefaultWidth)
                    self.frame.size = NSSize(width: safeWidth, height: finalHeight)
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
