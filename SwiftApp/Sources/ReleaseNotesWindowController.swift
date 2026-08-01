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
    var onHover: ((Bool) -> Void)?
    
    private var trackingArea: NSTrackingArea?
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

class ClickableTagPill: ClickableTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupHover()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupHover()
    }
    
    private func setupHover() {
        self.onHover = { [weak self] isHovered in
            guard let self = self else { return }
            self.backgroundColor = isHovered ? NSColor.textColor.withAlphaComponent(0.15) : NSColor.textColor.withAlphaComponent(0.08)
            self.textColor = isHovered ? .labelColor : .secondaryLabelColor
        }
    }
}
class ReleaseNotesView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

class ReleaseNotesViewController: NSViewController, NSTextViewDelegate {
    private var textView: NSTextView!
    private var titleLabel: NSTextField!
    private var descriptionLabel: NSTextField!
    private var versionLabel: ClickableTextField!
    private var tagsFooterView: WrappingTagsView!
    private var headerBox: NSBox!
    private var footerBox: NSBox!
    private(set) var currentRepoName: String?
    private var repoReleasesURL: URL?
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func createCardBox(for innerView: NSView, padding: NSEdgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 10
        box.borderWidth = 1
        box.borderColor = NSColor.separatorColor.withAlphaComponent(0.2)
        box.fillColor = NSColor.labelColor.withAlphaComponent(0.04)
        box.titlePosition = .noTitle
        box.translatesAutoresizingMaskIntoConstraints = false
        
        guard let cv = box.contentView else { return box }
        
        innerView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(innerView)
        
        NSLayoutConstraint.activate([
            innerView.topAnchor.constraint(equalTo: cv.topAnchor, constant: padding.top),
            innerView.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -padding.bottom),
            innerView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: padding.left),
            innerView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -padding.right)
        ])
        
        return box
    }
    
    override func loadView() {
        let view = ReleaseNotesView(frame: NSRect(x: 0, y: 0, width: Constants.notesWindowWidth, height: Constants.notesWindowHeight))
        self.view = view
        
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 12
        mainStack.edgeInsets = NSEdgeInsets(top: 16, left: 0, bottom: 16, right: 0)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: Constants.notesWindowWidth)
        ])
        
        // --- 1. Header Card (Title + Description inside box) ---
        let headerStack = NSStackView()
        headerStack.orientation = .vertical
        headerStack.alignment = .centerX
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 21, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerStack.addArrangedSubview(titleLabel)
        titleLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true
        
        descriptionLabel = NSTextField(labelWithString: "")
        descriptionLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.alignment = .center
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.preferredMaxLayoutWidth = Constants.notesWindowWidth - 76
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.isHidden = true
        headerStack.addArrangedSubview(descriptionLabel)
        descriptionLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true
        
        headerBox = createCardBox(for: headerStack, padding: NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        mainStack.addArrangedSubview(headerBox)
        headerBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true
        
        // --- Version Tag Pill (outside the header box) ---
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
        
        versionLabel.onHover = { [weak self] (isHovered: Bool) in
            guard let self = self else { return }
            self.versionLabel.backgroundColor = isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.8) : NSColor.controlAccentColor
        }
        
        // --- 2. Body (ScrollView + TextView) ---
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        mainStack.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        
        // Dynamic height: allow the scrollview to expand and fill all available space
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        textView = ReleaseNotesTextView()
        textView.delegate = self
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        
        // --- 3. Footer Card (Tags inside box) ---
        tagsFooterView = WrappingTagsView()
        tagsFooterView.translatesAutoresizingMaskIntoConstraints = false
        
        footerBox = createCardBox(for: tagsFooterView, padding: NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12))
        mainStack.addArrangedSubview(footerBox)
        footerBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true
        
        tagsFooterView.onTagSelected = { [weak self] tag in
            guard let self = self else { return }
            
            // Close notes and open main menu filtered by tag
            if let appDelegate = NSApp.delegate as? AppDelegate {
                // If it's a popover, close it
                if let window = self.view.window, let popover = window.value(forKey: "popover") as? NSPopover {
                    popover.close()
                } else {
                    self.view.window?.close()
                }
                
                let cleanTag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                let query = cleanTag
                
                appDelegate.currentSearchQuery = query
                appDelegate.searchField?.stringValue = query
                appDelegate.filterMenuBySearchQuery(query)
                appDelegate.headerView?.updateSearchOpacity()
                
                if !appDelegate.popoverIsOpen {
                    appDelegate.togglePopover(nil)
                }
            }
        }
        
        self.preferredContentSize = NSSize(width: Constants.notesWindowWidth, height: Constants.notesWindowHeight)
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        self.view.window?.makeFirstResponder(self.view)
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
        
        // Release previous content's image attachments and WebKit buffers
        // before loading new content to prevent accumulation across repos.
        textView.textStorage?.setAttributedString(NSAttributedString())
        
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
        
        // --- DESCRIPTION (About) ---
        if let configRepo = ConfigManager.shared.config.repos.first(where: { $0.name == info.name }),
           let desc = configRepo.repoDescription,
           !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            descriptionLabel.stringValue = desc
            descriptionLabel.font = .systemFont(ofSize: 13 + (offset * 0.5), weight: .regular)
            descriptionLabel.isHidden = false
        } else {
            descriptionLabel.stringValue = ""
            descriptionLabel.isHidden = true
        }
        
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
            footerBox.isHidden = false
        } else {
            tagsFooterView.set(tags: [])
            tagsFooterView.isHidden = true
            footerBox.isHidden = true
        }
        
        // --- TEXT BODY (Markdown & HTML) ---
        let isLoading = info.body == nil && info.error == nil
        let hasContent = info.body != nil && !info.body!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var rawBody: String
        if isLoading {
            rawBody = Translations.get("loading")
        } else if hasContent {
            rawBody = info.body!
        } else {
            rawBody = Translations.get("noNotes")
        }
        rawBody = rawBody.replacingOccurrences(of: "\r\n", with: "\n")
        
        // Render initial body (immediate text display, images may be missing)
        renderNotesBody(bodyText: rawBody, info: info, preloadedImages: [:])
        
        // Extract all image URLs (Markdown ![alt](url) and HTML <img>)
        // We collect them IN ORDER so the index matches the attachment order
        // created by the HTML parser.
        var imageURLsOrdered: [(raw: String, full: String)] = []
        var seenURLs: Set<String> = []
        
        // Markdown images: ![alt](url)
        let mdPattern = "!\\[[^\\]]*\\]\\(([^\\)]+)\\)"
        if let mdRegex = try? NSRegularExpression(pattern: mdPattern) {
            let matches = mdRegex.matches(in: rawBody, options: [], range: NSRange(location: 0, length: rawBody.utf16.count))
            for match in matches {
                if let urlRange = Range(match.range(at: 1), in: rawBody) {
                    let raw = String(rawBody[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seenURLs.contains(raw) {
                        seenURLs.insert(raw)
                        var full = raw
                        if !full.hasPrefix("http://") && !full.hasPrefix("https://") {
                            full = full.hasPrefix("/") ? "https://github.com\(full)" : "https://github.com/\(info.name)/raw/HEAD/\(full)"
                        }
                        imageURLsOrdered.append((raw: raw, full: full))
                    }
                }
            }
        }
        
        // HTML images: <img src="url">
        let htmlPattern = "<img[^>]+src=[\"']([^\"']+)[\"']"
        if let htmlRegex = try? NSRegularExpression(pattern: htmlPattern, options: .caseInsensitive) {
            let matches = htmlRegex.matches(in: rawBody, options: [], range: NSRange(location: 0, length: rawBody.utf16.count))
            for match in matches {
                if let srcRange = Range(match.range(at: 1), in: rawBody) {
                    let raw = String(rawBody[srcRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seenURLs.contains(raw) {
                        seenURLs.insert(raw)
                        var full = raw
                        if !full.hasPrefix("http://") && !full.hasPrefix("https://") {
                            full = full.hasPrefix("/") ? "https://github.com\(full)" : "https://github.com/\(info.name)/raw/HEAD/\(full)"
                        }
                        imageURLsOrdered.append((raw: raw, full: full))
                    }
                }
            }
        }
        
        // Synchronously check RAM and Disk cache for already-downloaded images
        var initialPreloaded: [String: NSImage] = [:]
        var uncachedEntries: [(raw: String, full: String)] = []
        
        for entry in imageURLsOrdered {
            if let cached = GitHubAPI.shared.getCachedImage(from: entry.full) {
                initialPreloaded[entry.raw] = cached
                initialPreloaded[entry.full] = cached
            } else {
                uncachedEntries.append(entry)
            }
        }
        
        // Render initial body (renders WITH cached images instantly on Frame #1!)
        renderNotesBody(bodyText: rawBody, info: info, preloadedImages: initialPreloaded)
        
        // Asynchronously fetch any remaining uncached images via GitHubAPI
        if !uncachedEntries.isEmpty {
            let repoName = info.name
            Task { [weak self] in
                var preloaded = initialPreloaded
                for entry in uncachedEntries {
                    if let image = await GitHubAPI.shared.fetchImage(from: entry.full) {
                        preloaded[entry.raw] = image
                        preloaded[entry.full] = image
                    }
                }
                
                await MainActor.run {
                    guard let self = self, self.currentRepoName == repoName else { return }
                    self.renderNotesBody(bodyText: rawBody, info: info, preloadedImages: preloaded)
                }
            }
        }
    }
    
    /// Renders the note body text into NSTextView.
    /// `preloadedImages` maps image URLs (as they appear in the source text) to pre-downloaded
    /// NSImage objects. When the HTML parser fails to load an image (rate limit, auth, WebKit
    /// file:// security), the corresponding NSImage is injected directly into the attachment.
    private func renderNotesBody(bodyText: String, info: RepoInfo, preloadedImages: [String: NSImage]) {
        var processedText = bodyText
        
        // 1. Convert Markdown image syntax ![alt](url) to HTML <img src="url" alt="alt">
        let mdImagePattern = "!\\[([^\\]]*)\\]\\(([^\\)]+)\\)"
        if let regex = try? NSRegularExpression(pattern: mdImagePattern) {
            let range = NSRange(location: 0, length: processedText.utf16.count)
            processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: "<img src=\"$2\" alt=\"$1\">")
        }
        
        // 2. Always convert Markdown to HTML so headings (##), lists (-/*), links, tables, and paragraphs format cleanly in WebKit
        processedText = Utils.convertMarkdownToHTML(processedText)
        let hasHTML = true
        
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        let offset = baseFontSize - 13.0
        
        // 3. Extract image URLs from <img> tags IN ORDER (matching attachment index)
        var orderedImgURLs: [String] = []
        var explicitImageSizes: [CGSize?] = []
        if hasHTML {
            let imgRegex = try? NSRegularExpression(pattern: "<img[^>]+>", options: .caseInsensitive)
            let srcRegex = try? NSRegularExpression(pattern: "src=[\"']([^\"']+)[\"']", options: .caseInsensitive)
            let widthRegex = try? NSRegularExpression(pattern: "width=[\"']?(\\d+)[\"']?", options: .caseInsensitive)
            let heightRegex = try? NSRegularExpression(pattern: "height=[\"']?(\\d+)[\"']?", options: .caseInsensitive)
            
            if let matches = imgRegex?.matches(in: processedText, options: [], range: NSRange(location: 0, length: processedText.utf16.count)) {
                for match in matches {
                    guard let range = Range(match.range, in: processedText) else { continue }
                    let imgTag = String(processedText[range])
                    
                    // Extract src URL
                    var srcURL = ""
                    if let srcMatch = srcRegex?.firstMatch(in: imgTag, options: [], range: NSRange(location: 0, length: imgTag.utf16.count)),
                       let srcRange = Range(srcMatch.range(at: 1), in: imgTag) {
                        srcURL = String(imgTag[srcRange])
                    }
                    orderedImgURLs.append(srcURL)
                    
                    // Extract dimensions
                    var width: CGFloat?
                    var height: CGFloat?
                    if let wMatch = widthRegex?.firstMatch(in: imgTag, options: [], range: NSRange(location: 0, length: imgTag.utf16.count)),
                       let wRange = Range(wMatch.range(at: 1), in: imgTag),
                       let wVal = Double(String(imgTag[wRange])) { width = CGFloat(wVal) }
                    if let hMatch = heightRegex?.firstMatch(in: imgTag, options: [], range: NSRange(location: 0, length: imgTag.utf16.count)),
                       let hRange = Range(hMatch.range(at: 1), in: imgTag),
                       let hVal = Double(String(imgTag[hRange])) { height = CGFloat(hVal) }
                    
                    if let w = width {
                        explicitImageSizes.append(CGSize(width: w, height: height ?? 0))
                    } else {
                        explicitImageSizes.append(nil)
                    }
                }
            }
        }
        
        if hasHTML {
            // Sanitize remote image URLs in processedText to prevent NSAttributedString (WebKit)
            // from issuing synchronous blocking HTTP network requests on the main UI thread.
            let remoteImgPattern = "(<img[^>]+src=[\"'])(https?://[^\"']+)([\"'])"
            if let regex = try? NSRegularExpression(pattern: remoteImgPattern, options: .caseInsensitive) {
                let matches = regex.matches(in: processedText, options: [], range: NSRange(location: 0, length: processedText.utf16.count))
                for match in matches.reversed() {
                    guard let fullRange = Range(match.range, in: processedText),
                          let prefixRange = Range(match.range(at: 1), in: processedText),
                          let urlRange = Range(match.range(at: 2), in: processedText),
                          let suffixRange = Range(match.range(at: 3), in: processedText) else { continue }
                    
                    let originalURLStr = String(processedText[urlRange])
                    let prefix = String(processedText[prefixRange])
                    let suffix = String(processedText[suffixRange])
                    
                    var replacementSrc = "about:blank"
                    if let localURL = GitHubAPI.shared.getCachedLocalImageURL(from: originalURLStr) {
                        replacementSrc = localURL.absoluteString
                    }
                    
                    let replacement = "\(prefix)\(replacementSrc)\(suffix)"
                    processedText.replaceSubrange(fullRange, with: replacement)
                }
            }
        }
        
        if hasHTML, let htmlData = processedText.data(using: .utf8) {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            
            do {
                let htmlAttrStr = try NSMutableAttributedString(data: htmlData, options: options, documentAttributes: nil)
                
                htmlAttrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: htmlAttrStr.length), options: .longestEffectiveRangeNotRequired) { value, range, stop in
                    if let font = value as? NSFont {
                        let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                        let newFont = NSFont.systemFont(ofSize: 14 + offset, weight: isBold ? .bold : .regular)
                        htmlAttrStr.addAttribute(.font, value: newFont, range: range)
                    } else {
                        htmlAttrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 14 + offset, weight: .regular), range: range)
                    }
                }
                
                htmlAttrStr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: htmlAttrStr.length), options: []) { value, range, stop in
                    let bodyStyle = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    bodyStyle.lineSpacing = 3.0
                    bodyStyle.paragraphSpacing = 6.0
                    bodyStyle.paragraphSpacingBefore = 2.0
                    bodyStyle.textLists = []
                    htmlAttrStr.addAttribute(.paragraphStyle, value: bodyStyle, range: range)
                }
                
                htmlAttrStr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: htmlAttrStr.length))
                
                // Replace attachments with ResponsiveImageAttachment.
                // 1. ALWAYS prioritize preloadedImages (downloaded via GitHubAPI & disk cached).
                // 2. Ignore Cocoa's broken image placeholder icons (Attachment.png, size <= 32px).
                var imageIndex = 0
                htmlAttrStr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: htmlAttrStr.length), options: []) { value, range, stop in
                    if let oldAttachment = value as? NSTextAttachment {
                        var finalImage: NSImage? = nil
                        
                        // 1. Check preloadedImages first
                        if imageIndex < orderedImgURLs.count {
                            let srcURL = orderedImgURLs[imageIndex]
                            finalImage = preloadedImages[srcURL]
                            if finalImage == nil {
                                var fullURL = srcURL
                                if !fullURL.hasPrefix("http://") && !fullURL.hasPrefix("https://") {
                                    fullURL = fullURL.hasPrefix("/") ? "https://github.com\(fullURL)" : "https://github.com/\(info.name)/raw/HEAD/\(fullURL)"
                                }
                                finalImage = preloadedImages[fullURL]
                            }
                        }
                        
                        // 2. Fallback to WebKit's extracted image ONLY if it's a real image (not broken placeholder icon)
                        if finalImage == nil {
                            if let directImage = oldAttachment.image {
                                finalImage = directImage
                            } else if let wrapper = oldAttachment.fileWrapper,
                                      let data = wrapper.regularFileContents,
                                      let wrapperImage = NSImage(data: data) {
                                let isPlaceholderIcon = (wrapperImage.size.width <= 32 && wrapperImage.size.height <= 32)
                                if !isPlaceholderIcon {
                                    finalImage = wrapperImage
                                }
                            }
                        }
                        
                        let dynamicAttachment = ResponsiveImageAttachment()
                        if let image = finalImage {
                            dynamicAttachment.image = image
                            if imageIndex < explicitImageSizes.count, let explicitSize = explicitImageSizes[imageIndex] {
                                let w = explicitSize.width
                                let h = explicitSize.height > 0 ? explicitSize.height : (image.size.height * (w / image.size.width))
                                dynamicAttachment.bounds = NSRect(x: 0, y: 0, width: w, height: h)
                            } else if oldAttachment.bounds.width > 0 {
                                dynamicAttachment.bounds = oldAttachment.bounds
                            }
                        }
                        
                        htmlAttrStr.addAttribute(.attachment, value: dynamicAttachment, range: range)
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
        
        // Markdown Fallback (clean up raw <img ...> tags so raw HTML code is not shown as text)
        var cleanMarkdown = processedText
        if let imgTagRegex = try? NSRegularExpression(pattern: "<img[^>]+>", options: .caseInsensitive) {
            cleanMarkdown = imgTagRegex.stringByReplacingMatches(in: cleanMarkdown, options: [], range: NSRange(location: 0, length: cleanMarkdown.utf16.count), withTemplate: "")
        }
        
        if #available(macOS 12.0, *) {
            do {
                var options = AttributedString.MarkdownParsingOptions()
                options.interpretedSyntax = .inlineOnlyPreservingWhitespace
                let attrStr = try AttributedString(markdown: cleanMarkdown, options: options)
                let nsAttrStr = NSMutableAttributedString(attrStr)
                let bodyStyle = NSMutableParagraphStyle()
                bodyStyle.lineSpacing = 4.0
                bodyStyle.paragraphSpacing = 12.0
                bodyStyle.paragraphSpacingBefore = 8.0
                nsAttrStr.addAttribute(.paragraphStyle, value: bodyStyle, range: NSRange(location: 0, length: nsAttrStr.length))
                nsAttrStr.enumerateAttribute(.font, in: NSRange(location: 0, length: nsAttrStr.length), options: .longestEffectiveRangeNotRequired) { value, range, stop in
                    if value == nil {
                        nsAttrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 14 + offset, weight: .regular), range: range)
                    }
                }
                nsAttrStr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: nsAttrStr.length))
                textView.textStorage?.setAttributedString(nsAttrStr)
            } catch {
                textView.string = cleanMarkdown
            }
        } else {
            textView.string = cleanMarkdown
        }
        textView.scrollToBeginningOfDocument(nil)
    }
    
    // MARK: - NSTextViewDelegate
    
    func textView(_ view: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        var targetURL: URL? = nil
        if let url = link as? URL {
            targetURL = url
        } else if let urlStr = link as? String {
            targetURL = URL(string: urlStr)
        }
        
        if let url = targetURL {
            if let popover = (NSApp.delegate as? AppDelegate)?.releaseNotesPopover {
                popover.close()
            }
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }
    
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        return nil
    }
    
    override func cancelOperation(_ sender: Any?) {
        if let popover = (NSApp.delegate as? AppDelegate)?.releaseNotesPopover {
            popover.close()
        }
    }
}

/// Custom NSTextView subclass that allows clicking on links and showing pointing-hand cursor over links,
/// while keeping standard arrow cursor (no text selection I-beam line) over plain text,
/// and providing asymmetrical left/right insets to achieve perfect text symmetry while keeping
/// the vertical scrollbar flush against the right window edge.
class ReleaseNotesTextView: NSTextView {
    private let customLeftInset: CGFloat = 20.0
    private let customRightInset: CGFloat = 5.0
    
    override var textContainerOrigin: NSPoint {
        return NSPoint(x: customLeftInset, y: textContainerInset.height)
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let container = textContainer {
            container.containerSize = NSSize(width: max(0, newSize.width - customLeftInset - customRightInset), height: .greatestFiniteMagnitude)
        }
    }
    
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
        
        guard let layoutManager = layoutManager, let textContainer = textContainer, let storage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.link, in: fullRange, options: []) { value, range, stop in
            if value != nil {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let origin = textContainerOrigin
                let linkRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                addCursorRect(linkRect, cursor: .pointingHand)
            }
        }
    }
}

// MARK: - WrappingTagsView
class WrappingTagsView: NSView {
    var onTagSelected: ((String) -> Void)?
    private var cachedHeight: CGFloat = 0.0
    private var lastWidth: CGFloat = 0.0
    
    func set(tags: [String]) {
        subviews.forEach { $0.removeFromSuperview() }
        let baseFontSize = ConfigManager.shared.config.menuFontSize ?? Constants.menuBaseFontSize
        let offset = baseFontSize - 13.0
        for tag in tags {
            let pillNode = ClickableTagPill(labelWithString: "  #\(tag)  ")
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
            
            let click = NSClickGestureRecognizer(target: self, action: #selector(tagClicked(_:)))
            pillNode.addGestureRecognizer(click)
            pillNode.identifier = NSUserInterfaceItemIdentifier(tag)
            
            addSubview(pillNode)
        }
        needsLayout = true
    }
    
    @objc private func tagClicked(_ sender: NSClickGestureRecognizer) {
        if let tag = sender.view?.identifier?.rawValue {
            onTagSelected?(tag)
        }
    }
    
    override var isFlipped: Bool { return true }
    
    override func layout() {
        super.layout()
        
        let availableWidth = bounds.width
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        
        var rows: [[NSView]] = []
        var currentRow: [NSView] = []
        
        for view in subviews {
            let bWidth = view.frame.width
            if currentX + bWidth > availableWidth && currentX > 0 {
                rows.append(currentRow)
                currentRow = [view]
                currentX = bWidth + 6.0
            } else {
                currentRow.append(view)
                currentX += bWidth + 6.0
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        for row in rows {
            let rowWidth = row.reduce(0.0) { $0 + $1.frame.width } + CGFloat(max(0, row.count - 1)) * 6.0
            let startX = max(0, (availableWidth - rowWidth) / 2)
            
            var xOffset = startX
            var maxVal: CGFloat = 0
            for view in row {
                view.setFrameOrigin(NSPoint(x: xOffset, y: currentY))
                xOffset += view.frame.width + 6.0
                maxVal = max(maxVal, view.frame.height)
            }
            currentY += maxVal + 6.0
        }
        
        let newHeight = subviews.isEmpty ? 0 : currentY - 6.0
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
