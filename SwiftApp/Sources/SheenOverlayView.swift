import Cocoa
import QuartzCore

/// An unobtrusive, hit-test transparent overlay that sweeps a liquid-crystal
/// hardware-accelerated reflection across views.
final class SheenOverlayView: NSView {
    
    private let sheenLayer = CAGradientLayer()
    private var isAnimating = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        wantsLayer = true
        layer?.masksToBounds = true
        
        sheenLayer.startPoint = CGPoint(x: 0, y: 0.5)
        sheenLayer.endPoint = CGPoint(x: 1, y: 0.5)
        sheenLayer.opacity = 0
        layer?.addSublayer(sheenLayer)
    }
    
    // Transparent to all user interactions (clicks, hovers, scrolls pass through)
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    override func layout() {
        super.layout()
        if !isAnimating {
            resetSheenOffscreen()
        }
    }
    
    private func resetSheenOffscreen() {
        sheenLayer.opacity = 0
        sheenLayer.removeAllAnimations()
        sheenLayer.position = CGPoint(x: -2000, y: -2000)
    }
    
    /// Sweeps a liquid-crystal reflection band across this view.
    /// - Parameters:
    ///   - delay: Time delay before the sweep begins (relative to current time).
    ///   - duration: Active duration of the sweep across this view.
    ///   - startX: Local starting X coordinate for the beam center.
    ///   - endX: Local ending X coordinate for the beam center.
    func sweep(delay: TimeInterval, duration: TimeInterval, startX: CGFloat, endX: CGFloat) {
        guard bounds.width > 0, bounds.height > 0, duration > 0 else { return }
        
        sheenLayer.removeAllAnimations()
        
        let beamWidth: CGFloat = 65.0
        let layerHeight: CGFloat = bounds.height * 1.5 + 120.0
        
        sheenLayer.bounds = CGRect(x: 0, y: 0, width: beamWidth, height: layerHeight)
        // 12-degree forward tilt
        sheenLayer.transform = CATransform3DMakeRotation(-12.0 * .pi / 180.0, 0, 0, 1)
        
        let midY = bounds.height / 2.0
        let startPoint = CGPoint(x: startX, y: midY)
        let endPoint = CGPoint(x: endX, y: midY)
        
        sheenLayer.position = startPoint
        sheenLayer.opacity = 0.0
        
        // Adaptive liquid crystal specular profile for Dark and Light mode
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let peakAlpha: CGFloat = isDark ? 0.22 : 0.40
        
        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.white.withAlphaComponent(peakAlpha * 0.05).cgColor,
            NSColor.white.withAlphaComponent(peakAlpha * 0.25).cgColor,
            NSColor.white.withAlphaComponent(peakAlpha * 0.70).cgColor,
            NSColor.white.withAlphaComponent(peakAlpha).cgColor,
            NSColor.white.withAlphaComponent(peakAlpha * 0.70).cgColor,
            NSColor.white.withAlphaComponent(peakAlpha * 0.25).cgColor,
            NSColor.white.withAlphaComponent(peakAlpha * 0.05).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        sheenLayer.locations = [
            0.0,
            0.15,
            0.32,
            0.44,
            0.50,
            0.56,
            0.68,
            0.85,
            1.0
        ]
        
        isAnimating = true
        
        let now = CACurrentMediaTime()
        let group = CAAnimationGroup()
        group.beginTime = now + delay
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        
        let posAnim = CABasicAnimation(keyPath: "position")
        posAnim.fromValue = NSValue(point: startPoint)
        posAnim.toValue = NSValue(point: endPoint)
        
        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [0.0, 1.0, 1.0, 0.0]
        opacityAnim.keyTimes = [0.0, 0.05, 0.95, 1.0]
        
        group.animations = [posAnim, opacityAnim]
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self else { return }
            self.resetSheenOffscreen()
            self.isAnimating = false
        }
        sheenLayer.add(group, forKey: "liquidCrystalSweep")
        CATransaction.commit()
    }
    
    /// Compatibility helper to trigger a full local sweep across this view.
    func triggerSheen(duration: TimeInterval = 1.0) {
        let margin: CGFloat = 80.0
        sweep(delay: 0, duration: duration, startX: -margin, endX: bounds.width + margin)
    }
}
