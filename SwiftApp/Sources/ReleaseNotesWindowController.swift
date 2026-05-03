import Cocoa

class ResponsiveImageAttachment: NSTextAttachment {
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> NSRect {
        guard let image = self.image else {
            return super.attachmentBounds(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
        }
        
        // If the attachment has explicit bounds (e.g., set by WebKit from HTML width/height attributes), respect them.
        // Otherwise, use the intrinsic size of the raw image.
        let baseSize = (self.bounds.width > 0 && self.bounds.height > 0) ? self.bounds.size : image.size
        
        // Use textContainer width, fallback to the line fragment width
        let containerWidth = textContainer?.size.width ?? lineFrag.width
        let maxWidth = max(containerWidth - 10, 0)
        
        if maxWidth > 0 && baseSize.width > maxWidth {
            let ratio = maxWidth / baseSize.width
            return NSRect(x: 0, y: 0, width: maxWidth, height: baseSize.height * ratio)
        }
        
        return NSRect(x: 0, y: 0, width: baseSize.width, height: baseSize.height)
    }
}

/// NSTextField subclass that shows a pointing-hand cursor on hover.
/// Used for the version pill in the Release Notes window.
class ClickableTextField: NSTextField {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

class ReleaseNotesViewController: NSViewController {
    private var textView: NSTextView!
    private var titleLabel: NSTextField!
    private var versionLabel: NSTextField!
    private var tagsFooterView: WrappingTagsView!
    private(set) var currentRepoName: String?
    private var repoReleasesURL: URL?
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        self.view = view
        
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 16
        mainStack.edgeInsets = NSEdgeInsets(top: 36, left: 0, bottom: 20, right: 0)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: 600)
        ])
        
        // --- 1. Header (Title + Version) ---
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(titleLabel)
        titleLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -48).isActive = true
        
        versionLabel = ClickableTextField(labelWithString: "")
        versionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        versionLabel.textColor = .white
        versionLabel.backgroundColor = NSColor.controlAccentColor
        versionLabel.drawsBackground = true
        versionLabel.isBordered = false
        versionLabel.alignment = .center
        versionLabel.wantsLayer = true
        versionLabel.layer?.cornerRadius = 10
        versionLabel.layer?.masksToBounds = true
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(versionLabel)
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(versionPillClicked))
        versionLabel.addGestureRecognizer(clickGesture)
        versionLabel.toolTip = Translations.get("openReleases")
        
        // --- 2. Body (ScrollView + TextView) ---
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        mainStack.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        
        // Dynamic height: give the scrollview a flexible height that pushes the tags to the bottom
        let scrollHeight = scrollView.heightAnchor.constraint(equalToConstant: 340)
        scrollHeight.priority = .defaultHigh
        scrollHeight.isActive = true
        
        textView = NSTextView()
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 24, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        
        // --- 3. Footer (Tags) ---
        tagsFooterView = WrappingTagsView()
        tagsFooterView.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(tagsFooterView)
        tagsFooterView.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -48).isActive = true
        
        self.preferredContentSize = NSSize(width: 600, height: 500)
    }
    
    @objc func openReleases() {
        guard let url = repoReleasesURL else { return }
        self.view.window?.close()
        NSWorkspace.shared.open(url)
    }
    
    @objc private func versionPillClicked() {
        openReleases()
    }
    
    func isPointInVersionPill(_ pointInWindow: NSPoint) -> Bool {
        let pointInView = self.view.convert(pointInWindow, from: nil)
        return versionLabel.frame.contains(pointInView)
    }
    
    func loadNotes(for info: RepoInfo) {
        self.currentRepoName = info.name
        let caskName = ConfigManager.shared.config.repos.first(where: { $0.name == info.name && $0.source == "brew" })?.cask
        
        // --- TITLE ---
        let attrString = NSMutableAttributedString(string: info.name)
        if let cask = caskName {
            let space = NSAttributedString(string: "  ")
            let attachment = NSTextAttachment()
            if let image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil) {
                let font = NSFont.systemFont(ofSize: 24, weight: .bold)
                let yOffset = round((font.capHeight - image.size.height) / 2.0)
                attachment.image = image
                attachment.bounds = NSRect(x: 0, y: yOffset, width: image.size.width, height: image.size.height)
            }
            attrString.append(space)
            attrString.append(NSAttributedString(attachment: attachment))
            attrString.append(NSAttributedString(string: " \(cask)"))
        }
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        let offset = baseFontSize - 13.0
        let titleFontSize = 24 + (offset * 0.5)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attrString.length))
        attrString.addAttribute(.font, value: NSFont.systemFont(ofSize: titleFontSize, weight: .bold), range: NSRange(location: 0, length: attrString.length))
        titleLabel.attributedStringValue = attrString
        
        // --- METADATA PILL ---
        let releasesURLString = "https://github.com/\(info.name)/releases"
        repoReleasesURL = URL(string: releasesURLString)
        let versionText = "  \(info.version ?? "N/A")  "
        versionLabel.stringValue = versionText
        versionLabel.font = .systemFont(ofSize: 12 + offset, weight: .medium)
        versionLabel.isHidden = (info.version == nil || info.version == "N/A")
        
        // --- FOOTER TAGS (Omni-Search Visuals) ---
        if let configRepo = ConfigManager.shared.config.repos.first(where: { $0.name == info.name }), let tags = configRepo.tags, !tags.isEmpty {
            tagsFooterView.set(tags: tags)
            tagsFooterView.isHidden = false
        } else {
            tagsFooterView.set(tags: [])
            tagsFooterView.isHidden = true
        }
        
        // --- TEXT BODY (Markdown & HTML) ---
        var bodyText = info.body ?? Translations.get("noNotes")
        bodyText = bodyText.replacingOccurrences(of: "\r\n", with: "\n")
        
        // Let markdown natively handle spacing after lists
        
        // 1. Heuristic HTML Detection
        let hasHTML = bodyText.contains("<div") || bodyText.contains("<img") || bodyText.contains("<h") || bodyText.contains("<p>") || bodyText.contains("<ul") || bodyText.contains("<li") || bodyText.contains("<strong")
        
        // 1b. Extract explicit HTML image dimensions because macOS TextKit ignores width/height HTML attributes
        var explicitImageSizes: [CGSize?] = []
        if hasHTML {
            let imgRegex = try? NSRegularExpression(pattern: "<img[^>]+>", options: .caseInsensitive)
            let widthRegex = try? NSRegularExpression(pattern: "width=[\"']?(\\d+)[\"']?", options: .caseInsensitive)
            let heightRegex = try? NSRegularExpression(pattern: "height=[\"']?(\\d+)[\"']?", options: .caseInsensitive)
            
            if let matches = imgRegex?.matches(in: bodyText, options: [], range: NSRange(location: 0, length: bodyText.utf16.count)) {
                for match in matches {
                    guard let range = Range(match.range, in: bodyText) else { continue }
                    let imgTag = String(bodyText[range])
                    
                    var width: CGFloat?
                    var height: CGFloat?
                    
                    if let wMatch = widthRegex?.firstMatch(in: imgTag, options: [], range: NSRange(location: 0, length: imgTag.utf16.count)),
                       let wRange = Range(wMatch.range(at: 1), in: imgTag),
                       let wVal = Double(String(imgTag[wRange])) {
                        width = CGFloat(wVal)
                    }
                    
                    if let hMatch = heightRegex?.firstMatch(in: imgTag, options: [], range: NSRange(location: 0, length: imgTag.utf16.count)),
                       let hRange = Range(hMatch.range(at: 1), in: imgTag),
                       let hVal = Double(String(imgTag[hRange])) {
                        height = CGFloat(hVal)
                    }
                    
                    if let w = width {
                        explicitImageSizes.append(CGSize(width: w, height: height ?? 0))
                    } else {
                        explicitImageSizes.append(nil)
                    }
                }
            }
        }
        
        // Inject explicit line breaks between block elements and headings for NSTextView
        // NSTextView ignores CSS margins if textLists are wiped or due to HTML layout quirks
        var fullHTML = bodyText
        let blockToHeadingRegex = try? NSRegularExpression(pattern: "(</(?:ul|ol|p|div|blockquote)>)(\\s*)(<(?:h[1-6]|p|ul|ol|div|blockquote)\\b[^>]*>)")
        if let r = blockToHeadingRegex {
            fullHTML = r.stringByReplacingMatches(in: fullHTML, options: [], range: NSRange(location: 0, length: fullHTML.utf16.count), withTemplate: "$1<br><br>$3")
        }
        
        // Convert standard Markdown newlines to HTML breaks so text doesn't bunch up in WebKit
        if hasHTML, let htmlData = fullHTML.data(using: .utf8) {
            // Attempt to parse as HTML format natively via WebKit engine bridge
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            
            do {
                let htmlAttrStr = try NSMutableAttributedString(data: htmlData, options: options, documentAttributes: nil)
                
                // Set default foreground color and typography for the parsed HTML elements
                htmlAttrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: htmlAttrStr.length), options: .longestEffectiveRangeNotRequired) { value, range, stop in
                    if let font = value as? NSFont {
                        // Attempt to preserve bold/italic while standardizing the face
                        let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                        let newFont = NSFont.systemFont(ofSize: 14 + offset, weight: isBold ? .bold : .regular)
                        htmlAttrStr.addAttribute(.font, value: newFont, range: range)
                    } else {
                        htmlAttrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 14 + offset, weight: .regular), range: range)
                    }
                }
                
                htmlAttrStr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: htmlAttrStr.length), options: []) { value, range, stop in
                    let bodyStyle = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    bodyStyle.lineSpacing = 4.0
                    // GitHub HTML already writes the bullet/number into the text content.
                    // Wipe WebKit's native text lists to prevent duplicate indices (e.g. "1. 1.").
                    bodyStyle.textLists = []
                    htmlAttrStr.addAttribute(.paragraphStyle, value: bodyStyle, range: range)
                }
                
                htmlAttrStr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: htmlAttrStr.length))
                
                // Swap standard NSTextAttachments for our dynamically resizing ResponsiveImageAttachment
                var imageIndex = 0
                htmlAttrStr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: htmlAttrStr.length), options: []) { value, range, stop in
                    if let oldAttachment = value as? NSTextAttachment {
                        var extractedImage: NSImage? = oldAttachment.image
                        
                        // WebKit HTML parsers often store images in the fileWrapper instead of the direct .image property
                        if extractedImage == nil, let wrapper = oldAttachment.fileWrapper, let data = wrapper.regularFileContents {
                            extractedImage = NSImage(data: data)
                        }
                        
                        if let image = extractedImage {
                            let dynamicAttachment = ResponsiveImageAttachment()
                            dynamicAttachment.image = image
                            
                            // Inherit bounds if we parsed them manually from HTML width/height attributes
                            if imageIndex < explicitImageSizes.count, let explicitSize = explicitImageSizes[imageIndex] {
                                let w = explicitSize.width
                                let h = explicitSize.height > 0 ? explicitSize.height : (image.size.height * (w / image.size.width))
                                dynamicAttachment.bounds = NSRect(x: 0, y: 0, width: w, height: h)
                            } else if oldAttachment.bounds.width > 0 {
                                dynamicAttachment.bounds = oldAttachment.bounds
                            }
                            
                            htmlAttrStr.addAttribute(.attachment, value: dynamicAttachment, range: range)
                        }
                        
                        imageIndex += 1
                    }
                }
                
                textView.textStorage?.setAttributedString(htmlAttrStr)
                textView.scrollToBeginningOfDocument(nil)
                return
            } catch {
                print("HTML Parsing failed: \(error), falling back to Markdown")
            }
        }
        
        if #available(macOS 12.0, *) {
            do {
                // 2. Markdown Rendering
                var options = AttributedString.MarkdownParsingOptions()
                options.interpretedSyntax = .inlineOnlyPreservingWhitespace // Basic formatting
                
                let attrStr = try AttributedString(markdown: bodyText, options: options)
                
                // Convert back to NSAttributedString for NSTextView, preserving markdown formatting,
                // but applying our base editorial font to the unformatted chunks
                let nsAttrStr = NSMutableAttributedString(attrStr)
                
                // Increase line height for editorial feel
                let bodyStyle = NSMutableParagraphStyle()
                bodyStyle.lineSpacing = 4.0
                nsAttrStr.addAttribute(.paragraphStyle, value: bodyStyle, range: NSRange(location: 0, length: nsAttrStr.length))
                
                // Add a default font to the whole range if a specific one wasn't applied by Markdown (like bold)
                nsAttrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: nsAttrStr.length), options: .longestEffectiveRangeNotRequired) { value, range, stop in
                    if value == nil {
                        nsAttrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 14 + offset, weight: .regular), range: range)
                    }
                }
                // Also set text color to adapt to Dark Mode vibrancy
                nsAttrStr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: nsAttrStr.length))
                
                textView.textStorage?.setAttributedString(nsAttrStr)
            } catch {
                // Fallback to plain text if Markdown parsing fails
                textView.string = bodyText
            }
        } else {
            textView.string = bodyText
        }
        
        textView.scrollToBeginningOfDocument(nil)
    }
}

// MARK: - WrappingTagsView
class WrappingTagsView: NSView {
    private var cachedHeight: CGFloat = 0.0
    private var lastWidth: CGFloat = 0.0
    
    func set(tags: [String]) {
        subviews.forEach { $0.removeFromSuperview() }
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        let offset = baseFontSize - 13.0
        for tag in tags {
            let pillNode = NSTextField(labelWithString: "  #\(tag)  ")
            pillNode.font = .systemFont(ofSize: 11 + offset, weight: .medium)
            pillNode.textColor = .secondaryLabelColor
            pillNode.backgroundColor = NSColor.textColor.withAlphaComponent(0.08)
            pillNode.drawsBackground = true
            pillNode.isBordered = false
            pillNode.alignment = .center
            pillNode.wantsLayer = true
            pillNode.layer?.cornerRadius = 6
            pillNode.layer?.masksToBounds = true
            pillNode.sizeToFit()
            
            var f = pillNode.frame
            f.size.height = max(f.height, 20)
            pillNode.frame = f
            
            addSubview(pillNode)
        }
        needsLayout = true
    }
    
    override var isFlipped: Bool { return true }
    
    override func layout() {
        super.layout()
        
        let availableWidth = bounds.width
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        
        for view in subviews {
            let bWidth = view.frame.width
            let bHeight = view.frame.height
            
            if currentX + bWidth > availableWidth && currentX > 0 {
                currentX = 0
                currentY += currentRowHeight + 6.0
                currentRowHeight = 0
            }
            
            view.setFrameOrigin(NSPoint(x: currentX, y: currentY))
            currentX += bWidth + 6.0
            currentRowHeight = max(currentRowHeight, bHeight)
        }
        
        let newHeight = subviews.isEmpty ? 0 : currentY + currentRowHeight
        if newHeight != cachedHeight {
            cachedHeight = newHeight
            invalidateIntrinsicContentSize()
        }
    }
    
    override var intrinsicContentSize: NSSize {
        if subviews.isEmpty { return .zero }
        return NSSize(width: NSView.noIntrinsicMetric, height: cachedHeight > 0 ? cachedHeight : 20.0)
    }
}
