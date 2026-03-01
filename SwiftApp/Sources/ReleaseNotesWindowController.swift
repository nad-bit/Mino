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
    private var scrollContainer: NSVisualEffectView!
    
    init() {
        let windowRect = NSRect(x: 0, y: 0, width: 540, height: 460)
        let window = NSWindow(contentRect: windowRect,
                            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
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
        // 4. Editorial Typography
        textView.font = .systemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        visualEffectView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 36),
            titleLabel.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -20),
            
            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            versionLabel.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            versionLabel.heightAnchor.constraint(equalToConstant: 20),
            
            scrollView.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 0),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -10)
        ])
        
        window.contentView = visualEffectView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func loadNotes(for info: RepoInfo) {
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
        
        // --- TEXT BODY (Markdown & HTML) ---
        let bodyText = info.body ?? Translations.get("noNotes")
        
        // 1. Heuristic HTML Detection
        let hasHTML = bodyText.contains("<div") || bodyText.contains("<img") || bodyText.contains("<h1") || bodyText.contains("<p>")
        
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
        
        if hasHTML, let htmlData = bodyText.data(using: .utf8) {
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
                
                let bodyStyle = NSMutableParagraphStyle()
                bodyStyle.lineSpacing = 4.0
                htmlAttrStr.addAttribute(.paragraphStyle, value: bodyStyle, range: NSRange(location: 0, length: htmlAttrStr.length))
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
    }
}
