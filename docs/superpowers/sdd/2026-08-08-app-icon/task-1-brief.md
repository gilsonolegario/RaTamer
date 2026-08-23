### Task 1: Create the `IconGen` executable target and render the 1024 master

**Files:**
- Modify: `Package.swift` (add `IconGen` product + executableTarget)
- Create: `Sources/IconGen/main.swift`
- Test: manual (render + inspect via screenshot-analyzer)

**Interfaces:**
- Consumes: nothing (standalone executable, imports only AppKit).
- Produces: `renderIcon(size:) -> NSBitmapImageRep` (draws the full design at the given size), used by Task 2 for all resolutions.

- [ ] **Step 1: Add the `IconGen` target to Package.swift**

```swift
        .executable(name: "IconGen", targets: ["IconGen"])
```

Add to `products` array. Add to `targets`:

```swift
        .executableTarget(
            name: "IconGen",
            dependencies: []
        ),
```

Place after the `RatTest` target.

- [ ] **Step 2: Create `Sources/IconGen/main.swift` with the master render**

```swift
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

    drawMouse(in: canvas)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawMouse(in canvas: NSRect) {
    let s = canvas.width
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = s * 0.05
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.03)

    // Mouse body: elongated rounded shape with left thumb wing (top view).
    let w = s * 0.46, h = s * 0.62
    let cx = s * 0.5, cy = s * 0.52
    let x = cx - w / 2, y = cy - h / 2

    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    let body = NSBezierPath()
    body.appendOval(in: NSRect(x: x, y: y + h * 0.10, width: w, height: h * 0.80))
    body.append(NSBezierPath(ovalIn: NSRect(x: x - w * 0.22, y: y + h * 0.28, width: w * 0.44, height: h * 0.30)))
    NSColor(hex: 0xE8E9ED).setFill()
    body.fill()  // two overlapping ovals fill as a union (nonzero winding)

    NSGraphicsContext.restoreGraphicsState()

    // Gesture button behind the wheel.
    let gesture = NSBezierPath(roundedRect:
        NSRect(x: cx - w * 0.11, y: y + h * 0.55, width: w * 0.22, height: h * 0.10),
        xRadius: w * 0.06, yRadius: w * 0.06)
    NSColor(hex: 0xC9CBD1).setFill()
    gesture.fill()

    // Wheel slot (vertical) with amber ring — the "tamer" collar.
    let slotX = cx - s * 0.035, slotY = y + h * 0.20, slotW = s * 0.07, slotH = s * 0.24
    let ring = NSBezierPath(roundedRect:
        NSRect(x: slotX - s * 0.008, y: slotY - s * 0.008,
               width: slotW + s * 0.016, height: slotH + s * 0.016),
        xRadius: s * 0.012, yRadius: s * 0.012)
    NSColor(hex: 0xFF9F1C).setStroke()
    ring.lineWidth = s * 0.012
    ring.stroke()

    // Anchor dot on the thumb wing.
    NSColor(hex: 0xFF9F1C).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - s * 0.005, y: y + h * 0.36,
                                width: s * 0.022, height: s * 0.022)).fill()
}
```

Add helpers used above (place in the same file):

```swift
extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: alpha)
    }
}
```

- [ ] **Step 3: Write the render-and-save harness**

Append to `main.swift`:

```swift
let arguments = CommandLine.arguments
let outputDir = URL(fileURLWithPath: arguments.dropFirst().first ?? "build/icon")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func savePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url)
}

let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let rep = renderIcon(size: size)
    try savePNG(rep, to: outputDir.appendingPathComponent("icon_\(Int(size)).png"))
    print("wrote icon_\(Int(size)).png")
}
```

- [ ] **Step 4: Build and run the master render**

Run: `swift run IconGen`
Expected: prints `wrote icon_1024.png` (and all other sizes) under `build/icon/`; no errors.

- [ ] **Step 5: Inspect the 1024 render**

Run: `sips -g pixelWidth -g pixelHeight build/icon/icon_1024.png`
Expected: `pixelWidth: 1024`, `pixelHeight: 1024`.

Visually check the master via screenshot-analyzer against the spec: graphite squircle background, silver mouse with thumb wing, no text, amber elements present. If the composition is off, adjust `drawMouse(in:)` (positions/radii in the body path) and re-run Steps 4–5. Iterate until the look is reasonable — precise polish happens in Task 2.

---

