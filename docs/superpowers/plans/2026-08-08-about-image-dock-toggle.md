# About image bigger + Dock icon toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Increase the About tab icon to 160×160 and add a persisted "Menu bar only" toggle that hides the Dock icon.

**Architecture:** Add a persisted `menuBarOnly: Bool?` field to the existing `Config` Codable struct, apply the activation policy at `applicationDidFinishLaunching` (removing the unreliable pre-`run()` call), and expose the toggle in the Settings General tab via an `@State` row that saves + applies immediately. The About image is a one-line size bump.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI + AppKit, RatTamerCore (Config/ConfigStore).

## Global Constraints

- macOS 14+ target (`.macOS(.v14)` in Package.swift).
- Config must stay backward compatible: any new optional field decodes with `decodeIfPresent` and defaults to `nil`.
- `menuBarOnly == true` → `.accessory` (menu bar only); `nil`/`false` → `.regular` (Dock icon visible).
- No comments in code unless the file's existing style already has them.
- Commit messages follow repo style: capitalized imperative, no conventional-commit prefix (e.g. "Add menu bar only dock option").
- Every task ends with `swift build` (or `swift test` where a test target exists) green.

---
### Task 1: Add `menuBarOnly` to Config

**Files:**
- Modify: `Sources/RatTamerCore/Core/ConfigStore.swift`
- Test: `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`

**Interfaces:**
- Produces: `Config.menuBarOnly: Bool?` — readable/writable, Codable via key `menuBarOnly`, `nil` when absent. `ConfigStore.load()`/`save()` round-trip it.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift` (before the final closing brace):

```swift
    func testMenuBarOnlyDecodesNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-menubar.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertNil(loaded.menuBarOnly)
    }

    func testMenuBarOnlyRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("menubar.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.menuBarOnly = true
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.menuBarOnly, true)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigStoreTests`
Expected: FAIL to compile with "value of type 'Config' has no member 'menuBarOnly'".

- [ ] **Step 3: Implement `menuBarOnly` in Config**

In `Sources/RatTamerCore/Core/ConfigStore.swift`, struct `Config` (around line 172, next to the other optional fields):

```swift
    public var menuBarOnly: Bool?
```

In `CodingKeys` (line 174):

```swift
    private enum CodingKeys: String, CodingKey {
        case version, deviceIndex, buttons, dpiFeatureIndex, dpiDeviceIndex,
             dpiDownValue, dpiAction, swapLeftRight, smartShiftMode, dpiValue,
             invertScrollDirection, thumbWheelLeft, thumbWheelRight,
             smartShiftSensitivity, dpiCycleValues, menuBarOnly
    }
```

In `init(from decoder:)`, after the `invertScrollDirection` decode (line 195):

```swift
        menuBarOnly = try c.decodeIfPresent(Bool.self, forKey: .menuBarOnly)
```

In the explicit memberwise `init` (line 200), next to `self.invertScrollDirection = nil` (line 226):

```swift
        self.menuBarOnly = nil
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass (151 existing + 2 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ConfigStore.swift Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift
git commit -m "Add menuBarOnly config option"
```

---
### Task 2: Apply activation policy at launch

**Files:**
- Modify: `Sources/RatTamerApp/main.swift`
- Modify: `Sources/RatTamerApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `Config.menuBarOnly: Bool?` from Task 1; `AppModel.shared.configStore` (same target, `RatTamerApp`).
- Produces: Dock policy applied at launch: `menuBarOnly == true` → `.accessory`, else `.regular`.

- [ ] **Step 1: Remove the forced policy from main.swift**

In `Sources/RatTamerApp/main.swift`, delete line 6 (`application.setActivationPolicy(.accessory)`), leaving:

```swift
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
```

- [ ] **Step 2: Apply the policy in AppDelegate**

In `Sources/RatTamerApp/AppDelegate.swift`, add `applyActivationPolicy()` as the first line of `applicationDidFinishLaunching` and add the helper method:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()
        Notifier.requestAuthorization()
        AppModel.shared.startEngine()
        ...
    }

    private func applyActivationPolicy() {
        let config = AppModel.shared.configStore.load()
        NSApp.setActivationPolicy(config.menuBarOnly == true ? .accessory : .regular)
    }
```

(`AppModel` is in the same module — no new import needed.)

- [ ] **Step 3: Build**

Run: `swift build`
Expected: compiles without warnings/errors.

- [ ] **Step 4: Manual verification (Dock behavior)**

Run: `swift run RatTamer`, then quit via the popover.
Expected: Dock icon visible (default `nil` config → `.regular`).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerApp/main.swift Sources/RatTamerApp/AppDelegate.swift
git commit -m "Apply dock activation policy at launch"
```

---
### Task 3: Enlarge the About icon

**Files:**
- Modify: `Sources/RatTamerApp/Views/SimpleTabs.swift`

**Interfaces:**
- Produces: `AboutTabView` shows the app icon at 160×160 with corner radius 35.

- [ ] **Step 1: Bump the About image size**

In `Sources/RatTamerApp/Views/SimpleTabs.swift`, `AboutTabView.body`:

```swift
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .cornerRadius(35)
            }
```

(change `100` → `160` and `22` → `35`).

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles.

- [ ] **Step 3: Manual verification**

Run: `swift run RatTamer`, open Settings → About.
Expected: icon rendered noticeably larger than before.

- [ ] **Step 4: Commit**

```bash
git add Sources/RatTamerApp/Views/SimpleTabs.swift
git commit -m "Enlarge About icon"
```

---
### Task 4: Add "Menu bar only" toggle to General settings

**Files:**
- Modify: `Sources/RatTamerApp/Views/GeneralTabView.swift`

**Interfaces:**
- Consumes: `Config.menuBarOnly: Bool?` from Task 1.
- Produces: `DockIconRow` — a `Toggle("Menu bar only (hide from Dock)")` in the General tab that persists the config and immediately applies `NSApp.setActivationPolicy`.

- [ ] **Step 1: Add the import and the new section**

In `Sources/RatTamerApp/Views/GeneralTabView.swift`, change the first line to:

```swift
import AppKit
import SwiftUI
import RatTamerCore
```

In `GeneralTabView.body`, after the "Login" `Section` (line 37), add:

```swift
            Section("Dock") {
                DockIconRow()
                Text("Hides the Dock icon and keeps RatTamer accessible only from the menu bar and popover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 2: Add the DockIconRow view**

Append `DockIconRow` at the end of `Sources/RatTamerApp/Views/GeneralTabView.swift` (follow the `@State` + `loaded` pattern of `ScrollDirectionToggleRow`):

```swift
struct DockIconRow: View {
    @State private var menuBarOnly = false
    @State private var loaded = false

    var body: some View {
        Toggle("Menu bar only (hide from Dock)", isOn: $menuBarOnly)
            .onChange(of: menuBarOnly) { _, _ in
                guard loaded else { return }
                apply()
            }
            .onAppear(perform: load)
    }

    private func load() {
        menuBarOnly = AppModel.shared.configStore.load().menuBarOnly == true
        loaded = true
    }

    private func apply() {
        var config = AppModel.shared.configStore.load()
        config.menuBarOnly = menuBarOnly
        try? AppModel.shared.configStore.save(config)
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: compiles.

- [ ] **Step 4: Manual verification**

Run: `swift run RatTamer` (Dock icon visible). Open Settings → General, toggle "Menu bar only (hide from Dock)" on:
- Dock icon disappears immediately; Settings window stays open.
Toggle it off: Dock icon returns.
Quit, relaunch `swift run RatTamer` with the toggle on: Dock icon stays hidden from launch.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerApp/Views/GeneralTabView.swift
git commit -m "Add menu bar only dock option"
```

---
### Task 5: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: all green.

- [ ] **Step 2: Full manual pass**

Repeat the Task 4 manual scenario end-to-end (default Dock visible; toggle hides/persists; About icon large).

- [ ] **Step 3: Update screenshots if the user asks**

Note: `screenshots/settings-about.png` and `screenshots/settings-*.png` are stale relative to the new UI; regenerate/refresh only if the user requests it.
