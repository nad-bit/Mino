import Cocoa

/// Custom vector icon generator for Mino's signature Feline Eye menu bar icon.
/// Native Bézier paths ensure subpixel rendering, resolution independence,
/// and automatic adaptation to macOS menu bar appearance.
enum FelineEyeIcon {
    
    /// Generates the signature Feline Eye icon for the macOS menu bar or UI dialogs.
    /// - Parameters:
    ///   - size: Canvas size (defaults to 18x16 pt for menu bar).
    ///   - hasUpdates: When `true`, the vertical slit pupil lights up in alert red and widens.
    ///                 When `false`, returns a template image for automatic theme adaptation.
    static func createIcon(size: NSSize = NSSize(width: 18, height: 16), hasUpdates: Bool = false) -> NSImage {
        let img = NSImage(size: size, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            
            ctx.saveGState()
            let scaleX = bounds.width / 18.0
            let scaleY = bounds.height / 16.0
            ctx.scaleBy(x: scaleX, y: scaleY)
            
            // 1. Cat Eye Contour (Variant 2: Feline Tilt with subtle 1.6pt upward lift)
            let eyePath = NSBezierPath()
            let left = CGPoint(x: 1.5, y: 7.2)
            let right = CGPoint(x: 16.5, y: 8.8)
            
            eyePath.move(to: left)
            eyePath.curve(to: right,
                          controlPoint1: CGPoint(x: 6.0, y: 14.8),
                          controlPoint2: CGPoint(x: 12.5, y: 14.8))
            eyePath.curve(to: left,
                          controlPoint1: CGPoint(x: 12.0, y: 2.2),
                          controlPoint2: CGPoint(x: 6.0, y: 1.2))
            eyePath.close()
            
            eyePath.lineWidth = 1.35
            eyePath.lineCapStyle = .round
            eyePath.lineJoinStyle = .round
            
            NSColor.labelColor.setStroke()
            eyePath.stroke()
            
            // 2. Feline Slit Pupil (Vertical ahusada / elliptical spindle)
            // Generous width for striking feline look: 2.6pt idle, 4.8pt active red
            let pupilPath = createPupilPath(hasUpdates: hasUpdates)
            if hasUpdates {
                NSColor.systemRed.setFill()
            } else {
                NSColor.labelColor.withAlphaComponent(0.85).setFill()
            }
            pupilPath.fill()
            
            ctx.restoreGState()
            return true
        }
        
        // Template mode allows macOS to handle light/dark mode and selection tinting.
        // When active (hasUpdates = true), isTemplate is false so the red pupil pops.
        img.isTemplate = !hasUpdates
        return img
    }
    
    /// Generates the Feline Eye icon with a diagonal slash for transition animations and error states.
    static func createSlashIcon(size: NSSize = NSSize(width: 18, height: 16)) -> NSImage {
        let img = NSImage(size: size, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            
            ctx.saveGState()
            let scaleX = bounds.width / 18.0
            let scaleY = bounds.height / 16.0
            ctx.scaleBy(x: scaleX, y: scaleY)
            
            let eyePath = NSBezierPath()
            let left = CGPoint(x: 1.5, y: 7.2)
            let right = CGPoint(x: 16.5, y: 8.8)
            
            eyePath.move(to: left)
            eyePath.curve(to: right,
                          controlPoint1: CGPoint(x: 6.0, y: 14.8),
                          controlPoint2: CGPoint(x: 12.5, y: 14.8))
            eyePath.curve(to: left,
                          controlPoint1: CGPoint(x: 12.0, y: 2.2),
                          controlPoint2: CGPoint(x: 6.0, y: 1.2))
            eyePath.close()
            
            eyePath.lineWidth = 1.35
            eyePath.lineCapStyle = .round
            eyePath.lineJoinStyle = .round
            
            NSColor.labelColor.setStroke()
            eyePath.stroke()
            
            // Pupil
            let pupilPath = createPupilPath(hasUpdates: false)
            NSColor.labelColor.withAlphaComponent(0.85).setFill()
            pupilPath.fill()
            
            // Diagonal Slash
            let slash = NSBezierPath()
            slash.move(to: CGPoint(x: 3.5, y: 14.5))
            slash.line(to: CGPoint(x: 14.5, y: 1.5))
            slash.lineWidth = 1.4
            slash.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            slash.stroke()
            
            ctx.restoreGState()
            return true
        }
        img.isTemplate = true
        return img
    }
    
    private static func createPupilPath(hasUpdates: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        let center = CGPoint(x: 9.0, y: 8.0)
        // Widened pupils: 2.6pt idle, 4.8pt active red
        let pWidth: CGFloat = hasUpdates ? 4.8 : 2.6
        let pHeight: CGFloat = 8.4
        let top = CGPoint(x: center.x, y: center.y + pHeight / 2.0)
        let bottom = CGPoint(x: center.x, y: center.y - pHeight / 2.0)
        let halfW = pWidth / 2.0
        
        path.move(to: top)
        path.curve(to: bottom,
                   controlPoint1: CGPoint(x: center.x + halfW * 1.3, y: center.y + pHeight * 0.15),
                   controlPoint2: CGPoint(x: center.x + halfW * 1.3, y: center.y - pHeight * 0.15))
        path.curve(to: top,
                   controlPoint1: CGPoint(x: center.x - halfW * 1.3, y: center.y - pHeight * 0.15),
                   controlPoint2: CGPoint(x: center.x - halfW * 1.3, y: center.y + pHeight * 0.15))
        path.close()
        return path
    }
}
