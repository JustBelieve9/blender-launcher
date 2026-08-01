import AppKit

let sizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.223

    ctx.saveGState()
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()
    let bgColors = [
        NSColor(calibratedRed: 1.00, green: 0.60, blue: 0.22, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.86, green: 0.32, blue: 0.02, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    ctx.restoreGState()

    // back window
    let backRect = CGRect(x: size * 0.16, y: size * 0.34, width: size * 0.50, height: size * 0.40)
    let backPath = NSBezierPath(roundedRect: backRect, xRadius: size * 0.06, yRadius: size * 0.06)
    NSColor(calibratedWhite: 0.10, alpha: 0.45).setFill()
    backPath.fill()

    // front window (with drop shadow)
    let frontRect = CGRect(x: size * 0.34, y: size * 0.20, width: size * 0.50, height: size * 0.40)
    let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: size * 0.06, yRadius: size * 0.06)
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = size * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    frontPath.fill()
    ctx.restoreGState()

    // play triangle centered on front window
    let triH = frontRect.height * 0.34
    let cx = frontRect.midX + size * 0.012
    let cy = frontRect.midY
    let tri = NSBezierPath()
    tri.move(to: CGPoint(x: cx - triH * 0.42, y: cy + triH * 0.55))
    tri.line(to: CGPoint(x: cx - triH * 0.42, y: cy - triH * 0.55))
    tri.line(to: CGPoint(x: cx + triH * 0.62, y: cy))
    tri.close()
    NSColor(calibratedRed: 0.86, green: 0.32, blue: 0.02, alpha: 1).setFill()
    tri.fill()

    return image
}

func pngData(_ image: NSImage, size: CGFloat) -> Data? {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let iconsetURL = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.removeItem(at: iconsetURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (name, size) in sizes {
    let img = drawIcon(size: size)
    if let data = pngData(img, size: size) {
        try data.write(to: iconsetURL.appendingPathComponent("\(name).png"))
    }
}

print("iconset generated at \(iconsetURL.path)")
