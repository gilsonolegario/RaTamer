import AppKit

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size),
                               pixelsHigh: Int(size),
                               bitsPerSample: 8,
                               samplesPerPixel: 4,
                               hasAlpha: true,
                               isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0,
                               bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)

    // Background squircle with vertical gradient.
    let bg = NSBezierPath(roundedRect: canvas, xRadius: size * 0.225, yRadius: size * 0.225)
    let gradient = NSGradient(starting: NSColor(hex: 0x23262E), ending: NSColor(hex: 0x16181C))!
    gradient.draw(in: bg, angle: -90)

    // The bitmap context is y-up (origin bottom-left) but the PNG output is
    // top-down, so drawing "nose at low y" would render the mouse upside down.
    // Flip y so drawMouse's low-y geometry appears at the top of the image.
    NSGraphicsContext.saveGraphicsState()
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: size)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()
    drawMouse(in: canvas)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawMouse(in canvas: NSRect) {
    let s = canvas.width
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = s * 0.05
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.03)

    // Mouse body (top view, nose pointing up): ONE continuous outline — an
    // elongated main ellipse with an integrated lower-left thumb wing bulge
    // (no two-oval union). Main body 0.40s x 0.58s (h/w ~ 1.45), centered.
    // Full silhouette ~0.50s wide (0.20s..0.70s) x 0.58s tall (0.21s..0.79s).
    let cx = s * 0.50, cy = s * 0.50
    let rx = s * 0.20, ry = s * 0.29
    let top = cy - ry, bottom = cy + ry
    let left = cx - rx, right = cx + rx
    let kx = rx * 0.5523  // cubic-bezier ellipse constant (horizontal)
    let ky = ry * 0.5523  // (vertical)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    let body = NSBezierPath()
    // Nose -> right flank -> rear.
    body.move(to: NSPoint(x: cx, y: top))
    body.curve(to: NSPoint(x: right, y: cy),
               controlPoint1: NSPoint(x: cx + kx, y: top),
               controlPoint2: NSPoint(x: right, y: cy - ky))
    body.curve(to: NSPoint(x: cx, y: bottom),
               controlPoint1: NSPoint(x: right, y: cy + ky),
               controlPoint2: NSPoint(x: cx + kx, y: bottom))
    // Rear -> thumb wing tip (lower-left) -> left flank -> nose.
    body.curve(to: NSPoint(x: s * 0.20, y: s * 0.59),
               controlPoint1: NSPoint(x: s * 0.44, y: bottom),
               controlPoint2: NSPoint(x: s * 0.185, y: s * 0.70))
    body.curve(to: NSPoint(x: left, y: cy),
               controlPoint1: NSPoint(x: s * 0.17, y: s * 0.56),
               controlPoint2: NSPoint(x: s * 0.27, y: s * 0.52))
    body.curve(to: NSPoint(x: cx, y: top),
               controlPoint1: NSPoint(x: left, y: cy - ky),
               controlPoint2: NSPoint(x: cx - kx, y: top))
    NSColor(hex: 0xE8E9ED).setFill()
    body.fill()

    NSGraphicsContext.restoreGraphicsState()

    // Gesture button behind the wheel (toward the rear).
    let gesture = NSBezierPath(roundedRect:
        NSRect(x: s * 0.405, y: s * 0.565, width: s * 0.19, height: s * 0.09),
        xRadius: s * 0.03, yRadius: s * 0.03)
    NSColor(hex: 0xC9CBD1).setFill()
    gesture.fill()

    // Wheel slot (vertical, upper-front center) with amber ring — the "tamer" collar.
    let slotX = s * 0.465, slotY = s * 0.30, slotW = s * 0.07, slotH = s * 0.22
    let ring = NSBezierPath(roundedRect:
        NSRect(x: slotX - s * 0.008, y: slotY - s * 0.008,
               width: slotW + s * 0.016, height: slotH + s * 0.016),
        xRadius: s * 0.012, yRadius: s * 0.012)
    NSColor(hex: 0xFF9F1C).setStroke()
    ring.lineWidth = s * 0.012
    ring.stroke()

    // Anchor dot on the thumb wing.
    NSColor(hex: 0xFF9F1C).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.224, y: s * 0.604, width: s * 0.022, height: s * 0.022)).fill()
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: alpha)
    }
}

let arguments = CommandLine.arguments
let baseDir = URL(fileURLWithPath: arguments.dropFirst().first ?? "build/icon")
let iconsetDir = baseDir.appendingPathComponent("RatTamer.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func savePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url)
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in sizes {
    let rep = renderIcon(size: size)
    try savePNG(rep, to: iconsetDir.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(1)
}
print("wrote \(baseDir.appendingPathComponent("RatTamer.icns").path)")
