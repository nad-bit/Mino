import Cocoa

/// A floating panel that draws a beer mug handle (ASA) next to the main menu popover.
/// Purely decorative — synchronized with the Red Eye (Ojo Rojo / HasUnreadPulse).
@MainActor
class BeerHandlePanel: NSPanel {
    
    private let handleView: BeerHandleView
    private(set) var isCurrentlyVisible = false
    
    init() {
        handleView = BeerHandleView()
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Constants.beerHandleWidth, height: 100),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        // IMPORTANT: Do NOT set level or hidesOnDeactivate here.
        // The level is set dynamically in showAnimated() to match the popover window,
        // and the lifecycle is managed manually. Setting .statusBar level or
        // hidesOnDeactivate = false would interfere with NSPopover's transient
        // dismissal (click-outside-to-close).
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = true // Purely decorative — no interaction
        
        self.contentView = handleView
    }
    
    /// Position the handle relative to the popover window.
    /// - Parameters:
    ///   - popoverWindow: The window of the main popover
    ///   - scrollAreaFrame: The frame of the scroll area in screen coordinates
    ///   - scrollAreaHeight: The visible height of the scroll area (repos section)
    /// - Returns: `true` if the handle was positioned successfully, `false` if the effective height is too small.
    @discardableResult
    func positionRelativeTo(popoverWindow: NSWindow, scrollAreaFrame: NSRect, scrollAreaHeight: CGFloat) -> Bool {
        let effectiveHeight = scrollAreaHeight - (Constants.beerHandleVerticalInset * 2)
        
        // Don't show if the effective height is below minimum
        guard effectiveHeight >= Constants.beerHandleMinHeight else {
            hide()
            return false
        }
        
        let handleWidth = Constants.beerHandleWidth
        let handleHeight = effectiveHeight
        
        // Position to the right of the menu scroll area (content view right edge)
        let handleX = scrollAreaFrame.maxX + Constants.beerHandleGapFromMenu
        
        // Center vertically within the scroll area
        let scrollAreaScreenY = scrollAreaFrame.origin.y
        let handleY = scrollAreaScreenY + Constants.beerHandleVerticalInset
        
        let handleFrame = NSRect(x: handleX, y: handleY, width: handleWidth, height: handleHeight)
        self.setFrame(handleFrame, display: true)
        handleView.frame = NSRect(x: 0, y: 0, width: handleWidth, height: handleHeight)
        handleView.needsDisplay = true
        return true
    }
    
    /// Show the handle with the configured animation.
    /// - Parameter popoverWindow: The popover's window, used to match the window level.
    func showAnimated(relativeTo popoverWindow: NSWindow? = nil) {
        guard !isCurrentlyVisible else { return }
        isCurrentlyVisible = true
        
        // Match the popover's window level so the handle floats at the same z-order
        if let popoverWindow = popoverWindow {
            self.level = popoverWindow.level
        }
        
        let animation = Constants.beerHandleAnimation
        let duration = Constants.beerHandleAnimationDuration
        
        switch animation {
        case .fade:
            self.alphaValue = 0.0
            self.orderFrontRegardless()
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.alphaValue = 1.0
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    self.animator().alphaValue = 1.0
                }
            }
            
        case .slide:
            // Start offset to the right by handleWidth, then slide in
            let finalFrame = self.frame
            var startFrame = finalFrame
            startFrame.origin.x += Constants.beerHandleWidth + 5
            self.setFrame(startFrame, display: false)
            self.alphaValue = 0.0
            self.orderFrontRegardless()
            
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.alphaValue = 1.0
                self.setFrame(finalFrame, display: true)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().alphaValue = 1.0
                    self.animator().setFrame(finalFrame, display: true)
                }
            }
        }
    }
    
    /// Hide the handle with the configured animation
    func hideAnimated() {
        guard isCurrentlyVisible else { return }
        isCurrentlyVisible = false
        
        let animation = Constants.beerHandleAnimation
        let duration = Constants.beerHandleAnimationDuration
        
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            self.alphaValue = 0.0
            self.orderOut(nil)
            return
        }
        
        switch animation {
        case .fade:
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                self.animator().alphaValue = 0.0
            }) { [weak self] in
                Task { @MainActor in
                    self?.orderOut(nil)
                }
            }
            
        case .slide:
            let currentFrame = self.frame
            var endFrame = currentFrame
            endFrame.origin.x += Constants.beerHandleWidth + 5
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0.0
                self.animator().setFrame(endFrame, display: true)
            }) { [weak self] in
                Task { @MainActor in
                    self?.orderOut(nil)
                    // Restore original frame for next show
                    self?.setFrame(currentFrame, display: false)
                }
            }
        }
    }
    
    /// Immediately hide without animation (for popover close)
    func hide() {
        isCurrentlyVisible = false
        self.alphaValue = 0.0
        self.orderOut(nil)
    }
}


// MARK: - BeerHandleView (the actual drawing)

/// Custom NSView that draws the beer mug handle shape using NSVisualEffectView
/// material to match the menu's visual appearance.
private class BeerHandleView: NSView {
    
    private let effectView: NSVisualEffectView
    private var borderLayer: CAShapeLayer?
    
    override init(frame frameRect: NSRect) {
        effectView = NSVisualEffectView(frame: frameRect)
        effectView.material = .popover
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        
        super.init(frame: frameRect)
        
        self.wantsLayer = true
        addSubview(effectView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        effectView.frame = bounds
        applyShapeMask()
    }
    
    /// Creates and applies a shape mask to the visual effect view,
    /// cutting it into the handle shape, and overlays a thin border stroke
    /// to match the popover's native edge profile.
    private func applyShapeMask() {
        let path: NSBezierPath
        
        switch Constants.beerHandleDesign {
        case .curved:
            path = curvedHandlePath()
        case .rectangular:
            path = rectangularHandlePath()
        }
        
        let cgPath = path.cgPath
        
        // 1. Mask the visual effect view to the handle shape
        let maskLayer = CAShapeLayer()
        maskLayer.path = cgPath
        effectView.layer?.mask = maskLayer
        
        // 2. Add a thin border stroke matching the popover's native edge profile
        if borderLayer == nil {
            let stroke = CAShapeLayer()
            stroke.fillColor = nil
            stroke.lineWidth = 0.5
            self.layer?.addSublayer(stroke)
            borderLayer = stroke
        }
        borderLayer?.path = cgPath
        borderLayer?.strokeColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        borderLayer?.frame = bounds
    }
    
    /// Draws a D-shaped curved handle (classic beer mug style).
    /// The opening faces left (towards the menu).
    ///
    /// Shape:
    /// ```
    ///  ╮      ← top arc curving right
    ///  │      ← straight right edge
    ///  ╯      ← bottom arc curving right
    /// ```
    private func curvedHandlePath() -> NSBezierPath {
        let w = bounds.width
        let h = bounds.height
        let thickness: CGFloat = Constants.beerHandleThickness
        
        let path = NSBezierPath()
        
        // Outer contour — a D shape open on the left
        let outerRadius = w - 2
        
        // Start at top-left (where it meets the menu)
        path.move(to: NSPoint(x: 0, y: h))
        
        // Top curve going right
        path.curve(to: NSPoint(x: w, y: h - outerRadius),
                    controlPoint1: NSPoint(x: w * 0.1, y: h),
                    controlPoint2: NSPoint(x: w, y: h))
        
        // Straight section down the right side
        path.line(to: NSPoint(x: w, y: outerRadius))
        
        // Bottom curve going left
        path.curve(to: NSPoint(x: 0, y: 0),
                    controlPoint1: NSPoint(x: w, y: 0),
                    controlPoint2: NSPoint(x: w * 0.1, y: 0))
        
        // Left edge going up (the opening side — inner edge)
        path.line(to: NSPoint(x: 0, y: thickness))
        
        // Inner contour — hollows out the D shape
        let innerOuterX = w - thickness
        
        // Bottom inner curve
        path.curve(to: NSPoint(x: innerOuterX, y: outerRadius),
                    controlPoint1: NSPoint(x: innerOuterX * 0.15, y: thickness),
                    controlPoint2: NSPoint(x: innerOuterX, y: thickness))
        
        // Inner straight section up
        path.line(to: NSPoint(x: innerOuterX, y: h - outerRadius))
        
        // Top inner curve
        path.curve(to: NSPoint(x: 0, y: h - thickness),
                    controlPoint1: NSPoint(x: innerOuterX, y: h - thickness),
                    controlPoint2: NSPoint(x: innerOuterX * 0.15, y: h - thickness))
        
        // Close back to start
        path.line(to: NSPoint(x: 0, y: h))
        
        path.windingRule = .evenOdd
        return path
    }
    
    /// Draws a simple rectangular handle with rounded corners.
    /// Open on the left side (towards the menu).
    private func rectangularHandlePath() -> NSBezierPath {
        let w = bounds.width
        let h = bounds.height
        let thickness: CGFloat = Constants.beerHandleThickness
        let r = Constants.beerHandleCornerRadius
        
        let path = NSBezierPath()
        
        // Outer rectangle (open on left)
        // Start top-left
        path.move(to: NSPoint(x: 0, y: h))
        
        // Top edge to top-right corner
        path.line(to: NSPoint(x: w - r, y: h))
        path.curve(to: NSPoint(x: w, y: h - r),
                    controlPoint1: NSPoint(x: w, y: h),
                    controlPoint2: NSPoint(x: w, y: h - r))
        
        // Right edge down
        path.line(to: NSPoint(x: w, y: r))
        path.curve(to: NSPoint(x: w - r, y: 0),
                    controlPoint1: NSPoint(x: w, y: 0),
                    controlPoint2: NSPoint(x: w - r, y: 0))
        
        // Bottom edge back to left
        path.line(to: NSPoint(x: 0, y: 0))
        
        // Left inner edge going up
        path.line(to: NSPoint(x: 0, y: thickness))
        
        // Inner rectangle (open on left)
        let innerW = w - thickness
        let innerR = max(r - thickness, 2)
        
        path.line(to: NSPoint(x: innerW - innerR, y: thickness))
        path.curve(to: NSPoint(x: innerW, y: thickness + innerR),
                    controlPoint1: NSPoint(x: innerW, y: thickness),
                    controlPoint2: NSPoint(x: innerW, y: thickness + innerR))
        
        // Inner right edge up
        path.line(to: NSPoint(x: innerW, y: h - thickness - innerR))
        path.curve(to: NSPoint(x: innerW - innerR, y: h - thickness),
                    controlPoint1: NSPoint(x: innerW, y: h - thickness),
                    controlPoint2: NSPoint(x: innerW - innerR, y: h - thickness))
        
        // Inner top edge to left
        path.line(to: NSPoint(x: 0, y: h - thickness))
        
        // Close
        path.line(to: NSPoint(x: 0, y: h))
        
        path.windingRule = .evenOdd
        return path
    }
}


// MARK: - NSBezierPath → CGPath conversion

extension NSBezierPath {
    /// Converts an NSBezierPath to a CGPath for use with CAShapeLayer masks.
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        
        for i in 0..<self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }
        
        return path
    }
}
