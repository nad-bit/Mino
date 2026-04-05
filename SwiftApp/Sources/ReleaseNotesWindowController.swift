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

class ReleaseNotesWindowController: NSWindowController, NSWindowDelegate {
    private var textView: NSTextView!
    private var titleLabel: NSTextField!
    private var versionLabel: NSTextField!
    private var tagsFooterView: WrappingTagsView!
    private var scrollContainer: NSVisualEffectView!
    private(set) var currentRepoName: String?
    
    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSWindow(contentRect: windowRect,
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                            backing: .buffered,
                            defer: false)
        window.title = Translations.get("releaseNotes")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        
        super.init(window: window)
        window.delegate = self
        
        // 1. Vibrancy Background
        let visualEffectView = NSVisualEffectView(frame: windowRect)
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        
        // Setup UI
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        visualEffectView.addSubview(titleLabel)
        
        // 3. Metadata Pill (Version & Date)
        versionLabel = NSTextField(labelWithString: "")
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
        visualEffectView.addSubview(versionLabel)
        
        // Inner padding for the pill (achieved via constraints on an invisible wrapper or just wide text)
        // We'll just pad the string with spaces, or rely on intrinsic size.
        
        // ScrollView for notes
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        textView = NSTextView()
        textView.isEditable = false
        textView.drawsBackground = false // Transparent to show vibrancy
        textView.textColor = .labelColor // Fallback safety layer
        // 4. Editorial Typography
        textView.font = .systemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        visualEffectView.addSubview(scrollView)
        
        // 5. Footer Tags Container (Flow Layout Wrapping)
        tagsFooterView = WrappingTagsView()
        tagsFooterView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(tagsFooterView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 36),
            titleLabel.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -20),
            
            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            versionLabel.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            versionLabel.heightAnchor.constraint(equalToConstant: 20),
            
            tagsFooterView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 24),
            tagsFooterView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -24),
            tagsFooterView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -16),
            
            scrollView.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 0),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: tagsFooterView.topAnchor, constant: -12)
        ])
        
        window.contentView = visualEffectView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attrString.length))
        attrString.addAttribute(.font, value: NSFont.systemFont(ofSize: 24, weight: .bold), range: NSRange(location: 0, length: attrString.length))
        titleLabel.attributedStringValue = attrString
        
        // --- METADATA PILL ---
        let versionText = "  \(info.version ?? "N/A")  "
        versionLabel.stringValue = versionText
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
                        let newFont = NSFont.systemFont(ofSize: 14, weight: isBold ? .bold : .regular)
                        htmlAttrStr.addAttribute(.font, value: newFont, range: range)
                    } else {
                        htmlAttrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .regular), range: range)
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
                        nsAttrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .regular), range: range)
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
    
    func windowWillClose(_ notification: Notification) {
        self.window?.orderOut(nil)
        
        // Return to accessory mode so Dock auto-hide works
    }
}

// MARK: - WrappingTagsView
class WrappingTagsView: NSView {
    private var cachedHeight: CGFloat = 0.0
    private var lastWidth: CGFloat = 0.0
    
    func set(tags: [String]) {
        subviews.forEach { $0.removeFromSuperview() }
        for tag in tags {
            let pillNode = NSTextField(labelWithString: "  #\(tag)  ")
            pillNode.font = .systemFont(ofSize: 11, weight: .medium)
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
