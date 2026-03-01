import Cocoa

let iconSize = CGSize(width: 1024, height: 1024)
let image = NSImage(size: iconSize)

image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    print("Failed to get graphics context")
    exit(1)
}

// Draw the squircle background
let bgRect = NSRect(origin: .zero, size: iconSize)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 224, yRadius: 224)

// Gradient from dark slate to deep purple/black (like a stealth night-vision camera body)
let colors = [NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.18, alpha: 1.0).cgColor,
              NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1.0).cgColor] as CFArray
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: iconSize.height), end: CGPoint(x: 0, y: 0), options: [])

bgPath.addClip()

// Configure the "eye.fill" symbol
let symbolConfig = NSImage.SymbolConfiguration(pointSize: 600, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
    let tintColor = NSColor.systemBlue // We can customize this to Mino's accent blue
    let tintedSymbol = NSImage(size: symbol.size)
    tintedSymbol.lockFocus()
    tintColor.set()
    let rect = NSRect(origin: .zero, size: symbol.size)
    rect.fill()
    symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
    tintedSymbol.unlockFocus()
    
    // Center logic
    let xOffset = (iconSize.width - tintedSymbol.size.width) / 2.0
    let yOffset = (iconSize.height - tintedSymbol.size.height) / 2.0
    let symbolRect = NSRect(x: xOffset, y: yOffset, width: tintedSymbol.size.width, height: tintedSymbol.size.height)
    
    // Add subtle shadow for depth
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 15
    shadow.set()
    
    tintedSymbol.draw(in: symbolRect)
} else {
    print("Could not find eye.fill symbol")
    exit(1)
}

image.unlockFocus()

// Save to disk
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG representation")
    exit(1)
}

let fileURL = URL(fileURLWithPath: "../icon.png")
do {
    try pngData.write(to: fileURL)
    print("Successfully generated icon.png")
} catch {
    print("Failed to write icon.png: \(error)")
    exit(1)
}
