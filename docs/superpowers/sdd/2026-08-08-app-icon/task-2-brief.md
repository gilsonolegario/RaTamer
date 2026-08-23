### Task 2: Iconset export, ICNS via iconutil, and bundle wiring

**Files:**
- Modify: `Sources/IconGen/main.swift` (add iconset dir + `iconutil` invocation)
- Modify: `scripts/build-app.sh` (generate ICNS, copy to Resources, set CFBundleIconFile)
- Test: manual (`file`/`iconutil` validation; build-app.sh end-to-end)

**Interfaces:**
- Consumes: `renderIcon(size:)` and `savePNG(_:to:)` from Task 1.
- Produces: `build/icon/RatTamer.iconset/` (naming per iconutil) → `build/icon/RatTamer.icns`; bundle at `build/RatTamer.app/Contents/Resources/RatTamer.icns` with `CFBundleIconFile` in Info.plist.

- [ ] **Step 1: Rewrite `main.swift` to emit an iconset and run iconutil**

Replace the render loop in `main.swift` (from Task 1 Step 3) with:

```swift
let arguments = CommandLine.arguments
let baseDir = URL(fileURLWithPath: arguments.dropFirst().first ?? "build/icon")
let iconsetDir = baseDir.appendingPathComponent("RatTamer.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

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
```

- [ ] **Step 2: Run IconGen and validate the ICNS**

Run: `swift run IconGen`
Then: `file build/icon/RatTamer.icns` and `iconutil -c iconset build/icon/RatTamer.icns -o /tmp/rattamer-check`
Expected: `file` reports a macOS icns; `iconutil` extracts without error.

- [ ] **Step 3: Update `scripts/build-app.sh` to generate and install the icon**

After the `swift build` line (line 6), add:

```bash
swift run IconGen
```

Replace the `mkdir -p "$APP/Contents/MacOS"` block (line 10) so Resources is created too:

```bash
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
```

After the `cp "$BIN"` line, add:

```bash
cp "$ROOT/build/icon/RatTamer.icns" "$APP/Contents/Resources/RatTamer.icns"
```

Add to the Info.plist heredoc (after `CFBundleExecutable` line):

```xml
    <key>CFBundleIconFile</key><string>RatTamer</string>
```

- [ ] **Step 4: Run the full build script**

Run: `scripts/build-app.sh`
Expected: build succeeds; `build/RatTamer.app/Contents/Resources/RatTamer.icns` exists; Info.plist contains `CFBundleIconFile`.

- [ ] **Step 5: Verify the bundle icon is recognized**

Run: `mdls -name kMDItemCFBundleIdentifier -name kMDItemContentType build/RatTamer.app` and `ls build/RatTamer.app/Contents/Resources/`
Expected: Resources contains `RatTamer.icns`; Finder metadata resolves normally.

---

