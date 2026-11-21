import Cocoa

class InteractiveHUDView: NSVisualEffectView {
    var onClick: (() -> Void)?
    
    override func resetCursorRects() {
        super.resetCursorRects()
        if onClick != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if let action = onClick {
            action()
        } else {
            super.mouseUp(with: event)
        }
    }
}

// MARK: - HUDTaskItem Model

class HUDTaskItem {
    let id: String
    var title: String
    var subtitle: String
    var details: String
    var icon: NSImage?
    var iconTintColor: NSColor?
    var progress: Double? // nil: indeterminate, 0.0...1.0: determinate, negative: hidden
    var onCancel: (() -> Void)?
    var isCompleted: Bool = false
    var isSuccess: Bool = true
    var destinationURL: URL?
    var sha: String?
    var autoDismissTimer: Timer?
    
    init(id: String,
         title: String,
         subtitle: String = "",
         details: String = "",
         icon: NSImage? = nil,
         iconTintColor: NSColor? = nil,
         progress: Double? = nil,
         onCancel: (() -> Void)? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.icon = icon
        self.iconTintColor = iconTintColor
        self.progress = progress
        self.onCancel = onCancel
    }
}

// MARK: - Non-Tooltip Label (Suppresses AppKit Truncation/Expansion Tooltips)

class NonTooltipTextFieldCell: NSTextFieldCell {
    override func expansionFrame(withFrame cellFrame: NSRect, in view: NSView) -> NSRect {
        return .zero
    }
}

class HUDLabel: NSTextField {
    override class var cellClass: AnyClass? {
        get { NonTooltipTextFieldCell.self }
        set {}
    }
    
    override func addToolTip(_ rect: NSRect, owner: Any, userData data: UnsafeMutableRawPointer?) -> NSView.ToolTipTag {
        return 0
    }
}

// MARK: - Compact Multi-Task Row View

class HUDTaskRowView: NSView {
    let taskId: String
    
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let detailLabel = HUDLabel(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let cancelBtn = NSButton()
    private let completionIcon = NSImageView()
    
    private let pathBadge = NSStackView()
    private let pathIcon = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let separator = NSBox()
    
    var onCancel: (() -> Void)?
    var onClick: (() -> Void)?
    
    init(task: HUDTaskItem) {
        self.taskId = task.id
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        update(with: task)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true
        
        // Title
        titleLabel.font = .boldSystemFont(ofSize: 12)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // Subtitle / Status
        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.alignment = .right
        
        // Header line (Title + Status on top)
        let headerLine = NSStackView(views: [titleLabel, subtitleLabel])
        headerLine.orientation = .horizontal
        headerLine.alignment = .centerY
        headerLine.distribution = .fill
        headerLine.spacing = 8
        headerLine.translatesAutoresizingMaskIntoConstraints = false
        
        // Progress bar
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0.0
        progressBar.maxValue = 1.0
        progressBar.doubleValue = 0.0
        progressBar.controlSize = .mini
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        
        // Detail label (bytes/speed or progress info)
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Path badge
        if let folderImg = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            pathIcon.image = folderImg.withSymbolConfiguration(config)
        }
        pathIcon.contentTintColor = .systemBlue
        pathIcon.translatesAutoresizingMaskIntoConstraints = false
        pathIcon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        pathIcon.heightAnchor.constraint(equalToConstant: 12).isActive = true
        
        pathLabel.font = .systemFont(ofSize: 10, weight: .medium)
        pathLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        
        pathBadge.addArrangedSubview(pathIcon)
        pathBadge.addArrangedSubview(pathLabel)
        pathBadge.orientation = .horizontal
        pathBadge.alignment = .centerY
        pathBadge.spacing = 4
        pathBadge.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        pathBadge.wantsLayer = true
        pathBadge.layer?.cornerRadius = 6
        pathBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        pathBadge.translatesAutoresizingMaskIntoConstraints = false
        pathBadge.isHidden = true
        
        let bottomLine = NSStackView(views: [detailLabel, pathBadge])
        bottomLine.orientation = .horizontal
        bottomLine.alignment = .centerY
        bottomLine.spacing = 8
        bottomLine.translatesAutoresizingMaskIntoConstraints = false
        
        // Center stack
        let centerStack = NSStackView(views: [headerLine, progressBar, bottomLine])
        centerStack.orientation = .vertical
        centerStack.alignment = .leading
        centerStack.spacing = 4
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Cancel button
        let xImg = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Cancel")
        let xConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        cancelBtn.image = xImg?.withSymbolConfiguration(xConfig)
        cancelBtn.isBordered = false
        cancelBtn.contentTintColor = NSColor.white.withAlphaComponent(0.60)
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelClicked)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.widthAnchor.constraint(equalToConstant: 20).isActive = true
        cancelBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true
        
        // Completion Icon
        completionIcon.imageScaling = .scaleProportionallyUpOrDown
        completionIcon.translatesAutoresizingMaskIntoConstraints = false
        completionIcon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        completionIcon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        completionIcon.isHidden = true
        
        let rightStack = NSStackView(views: [cancelBtn, completionIcon])
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Main row stack
        let rowStack = NSStackView(views: [iconView, centerStack, rightStack])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 10
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(rowStack)
        
        // Separator
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            
            headerLine.widthAnchor.constraint(equalTo: centerStack.widthAnchor),
            progressBar.widthAnchor.constraint(equalTo: centerStack.widthAnchor),
            
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 34),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
    
    func update(with task: HUDTaskItem) {
        titleLabel.stringValue = task.title
        subtitleLabel.stringValue = task.subtitle
        subtitleLabel.isHidden = task.subtitle.isEmpty
        
        detailLabel.stringValue = task.details
        detailLabel.isHidden = task.details.isEmpty
        
        self.onCancel = task.onCancel
        cancelBtn.isHidden = (task.onCancel == nil || task.isCompleted)
        
        if let icon = task.icon {
            iconView.image = icon
            iconView.contentTintColor = task.iconTintColor
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
        
        if task.isCompleted {
            progressBar.isHidden = true
            cancelBtn.isHidden = true
            
            let sym = task.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            completionIcon.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            completionIcon.contentTintColor = task.isSuccess ? .systemGreen : .systemRed
            completionIcon.isHidden = false
            
            if let dest = task.destinationURL {
                let folder = dest.deletingLastPathComponent()
                pathLabel.stringValue = "\(HUDPanel.friendlyPath(for: folder)) · \(Translations.get("showInFinder"))"
                pathBadge.isHidden = false
                
                self.onClick = {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            } else {
                pathBadge.isHidden = true
                self.onClick = nil
            }
        } else {
            completionIcon.isHidden = true
            pathBadge.isHidden = true
            self.onClick = nil
            
            if let p = task.progress {
                progressBar.isHidden = (p < 0.0)
                if p <= 0.0 {
                    progressBar.isIndeterminate = true
                    progressBar.startAnimation(nil)
                } else {
                    progressBar.isIndeterminate = false
                    progressBar.doubleValue = max(0.0, min(1.0, p))
                }
            } else {
                progressBar.isHidden = true
            }
        }
        
        resetCursorRects()
    }
    
    func hideSeparator() {
        separator.isHidden = true
    }
    
    @objc private func cancelClicked() {
        onCancel?()
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        if onClick != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if let action = onClick {
            action()
        } else {
            super.mouseUp(with: event)
        }
    }
}

// MARK: - HUDPanel

@MainActor
class HUDPanel: NSPanel {
    static let shared = HUDPanel()
    
    let visualEffect: InteractiveHUDView
    
    // Single-Task Mode Outlets (retained for backward compatibility and Test 12)
    let iconView: NSImageView
    let textLabel: NSTextField
    let subtitleLabel: NSTextField
    let detailLabel: NSTextField
    let progressBar: NSProgressIndicator
    
    let pathBadge: NSStackView
    let pathIcon: NSImageView
    let pathLabel: NSTextField
    let cancelButton: NSButton
    
    // Stack containers
    private let singleStack: NSStackView
    private let multiContainer: NSStackView
    private let multiHeaderStack: NSStackView
    private let multiHeaderTitle: NSTextField
    private let multiHeaderBadge: NSTextField
    private let multiTasksStack: NSStackView
    
    private var visualWidthConstraint: NSLayoutConstraint?
    
    // Multi-task management
    private(set) var tasks: [String: HUDTaskItem] = [:]
    private(set) var taskOrder: [String] = []
    private var rowViews: [String: HUDTaskRowView] = [:]
    
    private var cancelAction: (() -> Void)?
    private var clickAction: (() -> Void)?
    private var hideTimer: Timer?
    private var presentationToken = UUID()
    
    var isMultiTaskMode: Bool {
        return tasks.count > 1
    }
    
    private init() {
        // --- Single Task UI Setup ---
        iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.isHidden = true
        
        textLabel = NSTextField(labelWithString: "")
        textLabel.font = .boldSystemFont(ofSize: 15)
        textLabel.textColor = .white
        textLabel.alignment = .center
        textLabel.lineBreakMode = .byTruncatingMiddle
        textLabel.maximumNumberOfLines = 2
        textLabel.cell?.truncatesLastVisibleLine = true
        textLabel.preferredMaxLayoutWidth = 300
        
        subtitleLabel = NSTextField(labelWithString: "")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.cell?.truncatesLastVisibleLine = true
        subtitleLabel.preferredMaxLayoutWidth = 300
        
        detailLabel = HUDLabel(labelWithString: "")
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.preferredMaxLayoutWidth = 300
        detailLabel.isHidden = true
        
        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0.0
        progressBar.maxValue = 1.0
        progressBar.doubleValue = 0.0
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true
        
        pathIcon = NSImageView()
        if let folderImg = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            pathIcon.image = folderImg.withSymbolConfiguration(config)
        }
        pathIcon.contentTintColor = .systemBlue
        pathIcon.translatesAutoresizingMaskIntoConstraints = false
        pathIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        pathIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true
        
        pathLabel = NSTextField(labelWithString: "")
        pathLabel.font = .systemFont(ofSize: 11, weight: .medium)
        pathLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.alignment = .center
        
        pathBadge = NSStackView(views: [pathIcon, pathLabel])
        pathBadge.orientation = .horizontal
        pathBadge.alignment = .centerY
        pathBadge.spacing = 6
        pathBadge.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        pathBadge.wantsLayer = true
        pathBadge.layer?.cornerRadius = 8
        pathBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        pathBadge.translatesAutoresizingMaskIntoConstraints = false
        pathBadge.isHidden = true
        
        cancelButton = NSButton()
        cancelButton.title = Translations.get("cancel")
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.font = .systemFont(ofSize: 11, weight: .medium)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.isHidden = true
        
        singleStack = NSStackView(views: [iconView, textLabel, progressBar, subtitleLabel, detailLabel, cancelButton, pathBadge])
        singleStack.orientation = .vertical
        singleStack.alignment = .centerX
        singleStack.spacing = 7
        singleStack.translatesAutoresizingMaskIntoConstraints = false
        
        // --- Multi Task UI Setup ---
        let headerIcon = NSImageView()
        let hConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        headerIcon.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?.withSymbolConfiguration(hConfig)
        headerIcon.contentTintColor = .systemBlue
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        headerIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        headerIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        
        multiHeaderTitle = NSTextField(labelWithString: Translations.get("activeTasks") != "activeTasks" ? Translations.get("activeTasks") : "Tareas en curso")
        multiHeaderTitle.font = .systemFont(ofSize: 11, weight: .bold)
        multiHeaderTitle.textColor = NSColor.white.withAlphaComponent(0.80)
        
        multiHeaderBadge = NSTextField(labelWithString: "")
        multiHeaderBadge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        multiHeaderBadge.textColor = .white
        multiHeaderBadge.alignment = .center
        multiHeaderBadge.wantsLayer = true
        multiHeaderBadge.layer?.cornerRadius = 8
        multiHeaderBadge.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.35).cgColor
        multiHeaderBadge.translatesAutoresizingMaskIntoConstraints = false
        multiHeaderBadge.heightAnchor.constraint(equalToConstant: 16).isActive = true
        
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        multiHeaderStack = NSStackView(views: [headerIcon, multiHeaderTitle, headerSpacer, multiHeaderBadge])
        multiHeaderStack.orientation = .horizontal
        multiHeaderStack.alignment = .centerY
        multiHeaderStack.distribution = .fill
        multiHeaderStack.spacing = 6
        multiHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        
        let headerSep = NSBox()
        headerSep.boxType = .separator
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerSep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        multiTasksStack = NSStackView()
        multiTasksStack.orientation = .vertical
        multiTasksStack.alignment = .leading
        multiTasksStack.spacing = 0
        multiTasksStack.translatesAutoresizingMaskIntoConstraints = false
        
        multiContainer = NSStackView(views: [multiHeaderStack, headerSep, multiTasksStack])
        multiContainer.orientation = .vertical
        multiContainer.alignment = .leading
        multiContainer.spacing = 6
        multiContainer.translatesAutoresizingMaskIntoConstraints = false
        multiContainer.isHidden = true
        
        // --- Panel Window Setup ---
        visualEffect = InteractiveHUDView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.appearance = NSAppearance(named: .darkAqua)
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 18
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 140),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonClicked)
        
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.contentView = visualEffect
        
        visualEffect.addSubview(singleStack)
        visualEffect.addSubview(multiContainer)
        
        let widthConstraint = visualEffect.widthAnchor.constraint(equalToConstant: 340)
        self.visualWidthConstraint = widthConstraint
        
        NSLayoutConstraint.activate([
            widthConstraint,
            
            // Single stack pinned with comfortable margins
            singleStack.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 18),
            singleStack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -18),
            singleStack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 20),
            singleStack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -20),
            
            textLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            progressBar.widthAnchor.constraint(equalToConstant: 280),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
            
            // Multi container pinned
            multiContainer.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 14),
            multiContainer.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -14),
            multiContainer.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            multiContainer.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),
            
            multiHeaderStack.widthAnchor.constraint(equalTo: multiContainer.widthAnchor),
            headerSep.widthAnchor.constraint(equalTo: multiContainer.widthAnchor),
            multiTasksStack.widthAnchor.constraint(equalTo: multiContainer.widthAnchor)
        ])
    }
    
    // MARK: - Task Tracking Core
    
    private func registerOrUpdateTask(id: String,
                                      title: String,
                                      subtitle: String = "",
                                      details: String = "",
                                      icon: NSImage? = nil,
                                      iconTintColor: NSColor? = nil,
                                      progress: Double? = nil,
                                      onCancel: (() -> Void)? = nil) -> HUDTaskItem {
        if let existing = tasks[id] {
            existing.title = title
            existing.subtitle = subtitle
            existing.details = details
            if let icon = icon { existing.icon = icon }
            if let color = iconTintColor { existing.iconTintColor = color }
            if let p = progress { existing.progress = p }
            if let c = onCancel { existing.onCancel = c }
            return existing
        } else {
            let item = HUDTaskItem(id: id,
                                   title: title,
                                   subtitle: subtitle,
                                   details: details,
                                   icon: icon,
                                   iconTintColor: iconTintColor,
                                   progress: progress,
                                   onCancel: onCancel)
            tasks[id] = item
            taskOrder.append(id)
            return item
        }
    }
    
    func removeTask(id: String) {
        if let t = tasks[id] {
            t.autoDismissTimer?.invalidate()
            t.autoDismissTimer = nil
        }
        tasks.removeValue(forKey: id)
        taskOrder.removeAll { $0 == id }
        rowViews.removeValue(forKey: id)
        
        if tasks.isEmpty {
            hide()
        } else {
            renderLayout(animated: true)
        }
    }
    
    // MARK: - Presentation and Layout Refresh
    
    private func renderLayout(animated: Bool = true) {
        if isMultiTaskMode {
            // Multi-task mode: Expand to 400pt and render row stack
            singleStack.isHidden = true
            multiContainer.isHidden = false
            visualWidthConstraint?.constant = 400
            
            multiHeaderBadge.stringValue = "  \(tasks.count)  "
            
            // Rebuild rows according to taskOrder
            multiTasksStack.subviews.forEach { $0.removeFromSuperview() }
            
            for (index, id) in taskOrder.enumerated() {
                guard let task = tasks[id] else { continue }
                let row = rowViews[id] ?? HUDTaskRowView(task: task)
                row.update(with: task)
                rowViews[id] = row
                if index == taskOrder.count - 1 {
                    row.hideSeparator()
                }
                multiTasksStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: multiTasksStack.widthAnchor).isActive = true
            }
            
            resetInteraction() // interactions handled per-row
        } else {
            // Single-task mode: 340pt compact view
            multiContainer.isHidden = true
            singleStack.isHidden = false
            visualWidthConstraint?.constant = 340
            
            if let onlyId = taskOrder.first, let task = tasks[onlyId] {
                populateSingleTaskUI(with: task)
            }
        }
        
        updateWindowFrame(animated: animated)
    }
    
    private func populateSingleTaskUI(with task: HUDTaskItem) {
        resetInteraction()
        
        iconView.image = task.icon
        iconView.contentTintColor = task.iconTintColor
        iconView.isHidden = task.icon == nil
        
        textLabel.stringValue = task.title
        subtitleLabel.stringValue = task.subtitle
        subtitleLabel.isHidden = task.subtitle.isEmpty
        
        detailLabel.stringValue = task.details
        detailLabel.isHidden = task.details.isEmpty
        
        if task.isCompleted {
            progressBar.isHidden = true
            cancelButton.isHidden = true
            cancelAction = nil
            
            if let dest = task.destinationURL {
                let folderURL = dest.deletingLastPathComponent()
                let pathStr = HUDPanel.friendlyPath(for: folderURL)
                pathLabel.stringValue = "\(pathStr)  ·  \(Translations.get("showInFinder"))"
                pathBadge.isHidden = false
                
                let fileToReveal = dest
                setClickAction { [weak self] in
                    NSWorkspace.shared.activateFileViewerSelecting([fileToReveal])
                    self?.hide()
                }
            } else {
                pathBadge.isHidden = true
            }
        } else {
            pathBadge.isHidden = true
            if let p = task.progress {
                progressBar.isHidden = (p < 0.0)
                if p <= 0.0 {
                    progressBar.isIndeterminate = true
                    progressBar.startAnimation(nil)
                } else {
                    progressBar.isIndeterminate = false
                    progressBar.doubleValue = max(0.0, min(1.0, p))
                }
            } else {
                progressBar.isHidden = true
            }
            
            if let cancel = task.onCancel {
                self.cancelAction = cancel
                self.cancelButton.title = Translations.get("cancel")
                self.cancelButton.isHidden = false
            } else {
                self.cancelAction = nil
                self.cancelButton.isHidden = true
            }
        }
    }
    
    private func updateWindowFrame(animated: Bool = true) {
        visualEffect.layoutSubtreeIfNeeded()
        let fitting = visualEffect.fittingSize
        let targetWidth: CGFloat = isMultiTaskMode ? 400.0 : 340.0
        let targetHeight: CGFloat = max(110.0, fitting.height)
        
        let screen = NSApp.keyWindow?.screen ?? self.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenRect = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        // Position horizontally centered on screen
        let newX = screenRect.midX - (targetWidth / 2.0)
        
        // Position in upper third (~20-25% from top of visible screen, macOS HUD style)
        // Top-anchored layout ensures smooth downward growth when concurrent tasks arrive
        let topOffset = max(80.0, screenRect.height * 0.20)
        let targetTopY = screenRect.maxY - topOffset
        let newY = targetTopY - targetHeight
        
        let newFrame = NSRect(x: newX, y: newY, width: targetWidth, height: targetHeight)
        
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            self.setFrame(newFrame, display: true)
        }
    }
    
    // MARK: - Public API (Single & Multi-Task)
    
    func show(title: String, subtitle: String = "", image: NSImage? = nil, duration: TimeInterval? = 3.0) {
        if tasks.isEmpty {
            resetInteraction()
            iconView.image = image
            iconView.contentTintColor = nil
            iconView.isHidden = image == nil
            progressBar.isHidden = true
            detailLabel.isHidden = true
            pathBadge.isHidden = true
            
            textLabel.stringValue = title
            subtitleLabel.stringValue = subtitle
            subtitleLabel.font = .systemFont(ofSize: 12)
            subtitleLabel.isHidden = subtitle.isEmpty
            
            renderLayout(animated: false)
            present(duration: duration)
        } else {
            // One-shot toast with ongoing tasks: append as notification task and auto-dismiss
            let id = UUID().uuidString
            let task = registerOrUpdateTask(id: id, title: title, subtitle: subtitle, icon: image)
            task.isCompleted = true
            task.isSuccess = true
            
            renderLayout(animated: true)
            present(duration: nil)
            
            task.autoDismissTimer?.invalidate()
            task.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: duration ?? 3.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeTask(id: id)
                }
            }
        }
    }
    
    func showProgress(id: String? = nil, title: String, subtitle: String = "", image: NSImage? = nil, progress: Double = 0.0) {
        let taskId = id ?? title
        _ = registerOrUpdateTask(id: taskId,
                                 title: title,
                                 subtitle: subtitle,
                                 icon: image,
                                 progress: progress)
        renderLayout(animated: true)
        present(duration: nil)
    }
    
    func updateProgress(id: String? = nil, subtitle: String, progress: Double) {
        let taskId = id ?? taskOrder.first(where: { tasks[$0]?.isCompleted == false }) ?? ""
        guard let task = tasks[taskId] else {
            subtitleLabel.stringValue = subtitle
            subtitleLabel.isHidden = subtitle.isEmpty
            if progress > 0.0 {
                progressBar.isIndeterminate = false
                progressBar.doubleValue = max(0.0, min(1.0, progress))
            }
            return
        }
        
        task.subtitle = subtitle
        task.progress = progress
        
        if isMultiTaskMode {
            rowViews[taskId]?.update(with: task)
        } else {
            subtitleLabel.stringValue = subtitle
            subtitleLabel.isHidden = subtitle.isEmpty
            if progress > 0.0 {
                progressBar.isIndeterminate = false
                progressBar.doubleValue = max(0.0, min(1.0, progress))
            }
        }
    }
    
    func showCompletion(id: String? = nil, title: String, subtitle: String, isSuccess: Bool, duration: TimeInterval = 3.0) {
        let taskId = id ?? taskOrder.first(where: { tasks[$0]?.title == title }) ?? title
        
        let symbolName = isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        let symImg = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        let icon = symImg?.withSymbolConfiguration(config)
        let tint: NSColor = isSuccess ? .systemGreen : .systemRed
        
        if tasks[taskId] != nil || isMultiTaskMode {
            let task = registerOrUpdateTask(id: taskId, title: title, subtitle: subtitle, icon: icon, iconTintColor: tint, progress: nil)
            task.isCompleted = true
            task.isSuccess = isSuccess
            
            renderLayout(animated: true)
            present(duration: nil)
            
            task.autoDismissTimer?.invalidate()
            task.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeTask(id: taskId)
                }
            }
        } else {
            resetInteraction()
            progressBar.isHidden = true
            detailLabel.isHidden = true
            pathBadge.isHidden = true
            
            iconView.image = icon
            iconView.contentTintColor = tint
            iconView.isHidden = false
            
            textLabel.stringValue = title
            subtitleLabel.stringValue = subtitle
            subtitleLabel.font = .systemFont(ofSize: 12)
            subtitleLabel.isHidden = subtitle.isEmpty
            
            renderLayout(animated: false)
            present(duration: duration)
        }
    }
    
    // MARK: - Specialized Download Progression & Completion
    
    func showDownloadProgress(id: String? = nil, title: String, status: String, details: String = "", progress: Double = 0.0, onCancel: (() -> Void)? = nil) {
        let taskId = id ?? title
        let dlImage = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        let icon = dlImage?.withSymbolConfiguration(config)
        
        _ = registerOrUpdateTask(id: taskId,
                                 title: title,
                                 subtitle: status,
                                 details: details,
                                 icon: icon,
                                 iconTintColor: .systemBlue,
                                 progress: progress,
                                 onCancel: onCancel)
        
        renderLayout(animated: true)
        present(duration: nil)
    }
    
    func updateDownloadProgress(id: String? = nil, status: String, details: String, progress: Double) {
        let taskId = id ?? taskOrder.first(where: { tasks[$0]?.isCompleted == false }) ?? ""
        guard let task = tasks[taskId] else {
            subtitleLabel.stringValue = status
            subtitleLabel.isHidden = status.isEmpty
            detailLabel.stringValue = details
            detailLabel.isHidden = details.isEmpty
            if progress > 0.0 {
                progressBar.isIndeterminate = false
                progressBar.doubleValue = max(0.0, min(1.0, progress))
            }
            return
        }
        
        task.subtitle = status
        task.details = details
        task.progress = progress
        
        if isMultiTaskMode {
            rowViews[taskId]?.update(with: task)
        } else {
            subtitleLabel.stringValue = status
            subtitleLabel.isHidden = status.isEmpty
            detailLabel.stringValue = details
            detailLabel.isHidden = details.isEmpty
            if progress > 0.0 {
                progressBar.isIndeterminate = false
                progressBar.doubleValue = max(0.0, min(1.0, progress))
            }
        }
    }
    
    func showDownloadCompletion(id: String? = nil, title: String, subtitle: String, sha: String? = nil, destinationURL: URL, duration: TimeInterval = 4.0) {
        let taskId = id ?? title
        
        let symbolName = "checkmark.circle.fill"
        let symImg = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        let icon = symImg?.withSymbolConfiguration(config)
        
        let formattedSHA: String?
        if let sha = sha, !sha.isEmpty {
            formattedSHA = sha.hasPrefix("SHA-256:") ? sha : "SHA-256: \(sha)"
        } else {
            formattedSHA = nil
        }
        
        let task = registerOrUpdateTask(id: taskId,
                                        title: title,
                                        subtitle: subtitle,
                                        details: formattedSHA ?? "",
                                        icon: icon,
                                        iconTintColor: .systemGreen,
                                        progress: nil)
        task.isCompleted = true
        task.isSuccess = true
        task.destinationURL = destinationURL
        task.sha = formattedSHA
        
        renderLayout(animated: true)
        present(duration: nil)
        
        task.autoDismissTimer?.invalidate()
        task.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeTask(id: taskId)
            }
        }
    }
    
    func showCancellation(id: String? = nil, title: String, subtitle: String = "", duration: TimeInterval = 2.5) {
        let taskId = id ?? title
        
        let symbolName = "xmark.circle.fill"
        let symImg = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        let icon = symImg?.withSymbolConfiguration(config)
        
        let task = registerOrUpdateTask(id: taskId,
                                        title: title,
                                        subtitle: subtitle,
                                        icon: icon,
                                        iconTintColor: .systemOrange,
                                        progress: nil)
        task.isCompleted = true
        task.isSuccess = false
        
        renderLayout(animated: true)
        present(duration: nil)
        
        task.autoDismissTimer?.invalidate()
        task.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeTask(id: taskId)
            }
        }
    }
    
    // MARK: - Helpers & Presentation Animation
    
    static func friendlyPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fullPath = url.path
        if fullPath == home {
            return "~"
        } else if fullPath.hasPrefix(home + "/") {
            return "~/" + fullPath.dropFirst(home.count + 1)
        }
        return url.lastPathComponent
    }
    
    private func resetInteraction() {
        clickAction = nil
        cancelAction = nil
        cancelButton.isHidden = true
        visualEffect.onClick = nil
        visualEffect.discardCursorRects()
        visualEffect.resetCursorRects()
    }
    
    @objc private func cancelButtonClicked() {
        let action = cancelAction
        resetInteraction()
        action?()
    }
    
    private func setClickAction(_ action: @escaping () -> Void) {
        self.clickAction = action
        visualEffect.onClick = action
        visualEffect.discardCursorRects()
        visualEffect.resetCursorRects()
    }
    
    private func present(duration: TimeInterval?) {
        updateWindowFrame(animated: false)
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        
        presentationToken = UUID()
        
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.alphaValue = 1.0
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.animator().alphaValue = 1.0
            }
        }
        
        hideTimer?.invalidate()
        hideTimer = nil
        if let dur = duration, tasks.isEmpty {
            let currentToken = presentationToken
            let newTimer = Timer(timeInterval: dur, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if self?.presentationToken == currentToken {
                        self?.hide()
                    }
                }
            }
            RunLoop.current.add(newTimer, forMode: .common)
            hideTimer = newTimer
        }
    }
    
    func hide() {
        let currentToken = presentationToken
        resetInteraction()
        
        for t in tasks.values {
            t.autoDismissTimer?.invalidate()
            t.autoDismissTimer = nil
        }
        tasks.removeAll()
        taskOrder.removeAll()
        rowViews.removeAll()
        
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.alphaValue = 0.0
            self.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.30
                self.animator().alphaValue = 0.0
            }) { [weak self] in
                Task { @MainActor in
                    if self?.presentationToken == currentToken {
                        self?.orderOut(nil)
                    }
                }
            }
        }
    }
}
