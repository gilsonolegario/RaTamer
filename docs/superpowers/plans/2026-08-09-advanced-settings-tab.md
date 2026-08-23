# Advanced Settings Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the smooth scroll tuning panel out of the General tab into a new Pro-gated "Advanced" settings tab, and make basic smooth scrolling free.

**Architecture:** The sidebar in `SettingsView.swift` gains an "Advanced" entry. `GeneralTabView.SmoothScrollRow` is slimmed to the free tier (toggle + level slider + 3 presets) and loses its Pro gate, Glide/MOS row and the advanced panel. A new `AdvancedTabView.swift` holds the full tuning panel behind `isPro(.smoothScroll)`, reusing the existing upsell pattern. `ConfigEntitlement.filteringProFeatures` stops stripping the free smooth-scroll fields, stripping only `smoothScrollAdvanced`.

**Tech Stack:** SwiftUI, Swift 5.9, macOS 14+, XCTest.

## Global Constraints

- Version floors: Swift 5.9, macOS 14+.
- Free tier keeps `smoothScrollEnabled` and `smoothScrollLevel`; only `smoothScrollAdvanced` is Pro-stripped.
- Advanced tab is always visible in the sidebar; without Pro it shows a lock + upsell, never the tuning controls.
- The tuning panel must render fully within the 760×560 settings window using a `ScrollView` (pattern from `ButtonsTabView`).
- Rename the "Glide sã" button label to "Glide" wherever it appears.
- No changes to the smoother engine, config schema, or RatTest.
- Dev builds unlock Pro (`AppModel.isPro` already returns `true` — TEMP-DEV), so the tab is testable locally without a license.

---

### Task 1: Free smooth scroll keeps level; only advanced is Pro

Changes the entitlement rule so a free user keeps the basic smooth-scroll toggle and level, and only the advanced parameters are stripped.

**Files:**
- Modify: `Sources/RatTamerCore/Core/ConfigEntitlement.swift:32-36`
- Modify: `Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift:63-89`

**Interfaces:**
- Produces: `Config.filteringProFeatures(entitled:)` — free tier (`entitled(.smoothScroll) == false`) now keeps `smoothScrollEnabled` and `smoothScrollLevel`, strips `smoothScrollAdvanced`.

- [ ] **Step 1: Update the failing tests**

Replace the smooth-scroll tests in `ConfigEntitlementTests.swift` (lines 63-89) with:

```swift
    func testFreeSmoothScrollKeepsEnabledAndLevelStripsAdvanced() {
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 75
        config.smoothScrollAdvanced = ScrollSmoother.Parameters(
            multiplier: 8, momentumEnabled: true, invert: false, maxBoost: 4.2)
        let filtered = config.filteringProFeatures { _ in false }
        XCTAssertEqual(filtered.smoothScrollEnabled, true)
        XCTAssertEqual(filtered.smoothScrollLevel, 75)
        XCTAssertNil(filtered.smoothScrollAdvanced)
    }

    func testProSmoothScrollKeepsEverything() {
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 30
        config.smoothScrollAdvanced = ScrollSmoother.Parameters(
            multiplier: 8, momentumEnabled: true, invert: false, maxBoost: 4.2)
        let filtered = config.filteringProFeatures { _ in true }
        XCTAssertEqual(filtered.smoothScrollEnabled, true)
        XCTAssertEqual(filtered.smoothScrollLevel, 30)
        XCTAssertEqual(filtered.smoothScrollAdvanced, config.smoothScrollAdvanced)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ConfigEntitlementTests 2>&1 | tail -8`
Expected: FAIL — `testFreeSmoothScrollKeepsEnabledAndLevelStripsAdvanced` asserts `XCTAssertEqual(filtered.smoothScrollEnabled, true)` but the current implementation strips it.

- [ ] **Step 3: Change the entitlement rule**

In `ConfigEntitlement.swift`, replace:

```swift
        if !entitled(.smoothScroll) {
            filtered.smoothScrollEnabled = nil
            filtered.smoothScrollLevel = nil
            filtered.smoothScrollAdvanced = nil
        }
```

with:

```swift
        if !entitled(.smoothScroll) {
            filtered.smoothScrollAdvanced = nil
        }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ConfigEntitlementTests 2>&1 | tail -8`
Expected: PASS — all `ConfigEntitlementTests` succeed.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ConfigEntitlement.swift Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift
git commit -m "feat(entitlement): basic smooth scroll is free, only advanced tuning is Pro"
```

---

### Task 2: Slim the General tab to the free smooth-scroll tier

Removes the Pro gate, the Glide/MOS row, the "Avançado" disclosure and all advanced state from `SmoothScrollRow`.

**Files:**
- Modify: `Sources/RatTamerApp/Views/GeneralTabView.swift:303-565`

**Interfaces:**
- Consumes: `AppModel.shared.configStore`, `AppModel.shared.engine?.applyConfig()`, `AppModel.shared.engine?.hiResWheelService`, `SmoothnessLevel.min/max/defaultValue`.
- Produces: `SmoothScrollRow` exposes only the free tier: "Smooth scrolling" toggle, Smoothness slider with level/custom label, Discreta/Média/Fluida presets.

- [ ] **Step 1: Replace `SmoothScrollRow` with the slim version**

In `GeneralTabView.swift`, replace the entire `SmoothScrollRow` struct (from `struct SmoothScrollRow: View {` at line 303 through the end of the file — the struct is the last member of the file and includes its own `private func isPro(_:)` helper at the end) with:

```swift
struct SmoothScrollRow: View {
    @State private var enabled = false
    @State private var level: Double?
    @State private var loaded = false
    @State private var unavailable = false

    private var displayedLevel: Double {
        level ?? SmoothnessLevel.defaultValue
    }

    var body: some View {
        Group {
            if unavailable {
                Text("Smooth scrolling unavailable on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Smooth scrolling", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        guard loaded else { return }
                        apply()
                    }
                if enabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Smoothness")
                            Spacer()
                            Text(level == nil ? "custom" : "\(Int(displayedLevel))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { displayedLevel },
                                              set: { setLevel($0) }),
                               in: SmoothnessLevel.min...SmoothnessLevel.max,
                               step: 1)
                        HStack {
                            presetLabel("Discreta", value: SmoothnessLevel.min)
                            Spacer()
                            presetLabel("Média", value: SmoothnessLevel.defaultValue)
                            Spacer()
                            presetLabel("Fluida", value: SmoothnessLevel.max)
                        }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func presetLabel(_ name: String, value: Double) -> some View {
        Text(name)
            .font(.caption)
            .foregroundStyle(level == value ? Color.accentColor : Color.secondary)
            .onTapGesture { setLevel(value) }
    }

    private func setLevel(_ newValue: Double) {
        guard loaded else { return }
        level = newValue
        apply()
    }

    private func apply() {
        var config = AppModel.shared.configStore.load()
        config.smoothScrollEnabled = enabled
        config.smoothScrollLevel = level
        if level != nil {
            config.smoothScrollAdvanced = nil
        }
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func load() {
        guard AppModel.shared.engine?.hiResWheelService != nil else {
            unavailable = true
            return
        }
        let config = AppModel.shared.configStore.load()
            .filteringProFeatures(entitled: AppModel.shared.isPro)
        enabled = config.smoothScrollEnabled == true
        level = config.smoothScrollLevel
        loaded = true
    }
}
```

Note: this replacement removes the `isPro(_:)` helper that lived inside the old `SmoothScrollRow` — no other code in `GeneralTabView.swift` uses it (the other `isPro` lives in `ButtonsTabView`).

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/Views/GeneralTabView.swift
git commit -m "feat(settings): General tab keeps free smooth scroll tier only"
```

---

### Task 3: Create the Advanced tab view

New Pro-gated view hosting the full tuning panel (toggle, level + presets, Glide/MOS, 15 parameters in groups).

**Files:**
- Create: `Sources/RatTamerApp/Views/AdvancedTabView.swift`

**Interfaces:**
- Consumes: `AppModel.shared.configStore`, `AppModel.shared.engine?.applyConfig()`, `AppModel.shared.engine?.updateSmoothParameters(...)`, `AppModel.shared.engine?.hiResWheelService`, `AppModel.shared.isPro`, `ProStore.productURL`, `SmoothnessLevel`, `ScrollSmoother.Parameters`/defaults, `ScrollSmootherCoordinator` (via engine).
- Produces: `AdvancedTabView: View` — used by `SettingsView` in Task 4. No external contract besides the view name.

- [ ] **Step 1: Write the new view file**

Create `Sources/RatTamerApp/Views/AdvancedTabView.swift` with:

```swift
import AppKit
import RatTamerCore
import SwiftUI

struct AdvancedTabView: View {
    @State private var enabled = false
    @State private var level: Double?
    @State private var maxBoost = ScrollSmoother.defaultMaxBoost
    @State private var momentumDecay = ScrollSmoother.defaultMomentumDecay
    @State private var momentumEnabled = false
    @State private var pixelsPerNotch = ScrollSmoother.defaultPixelsPerNotch
    @State private var accelerationWindow = ScrollSmoother.defaultAccelerationWindow
    @State private var feedGapTimeout = ScrollSmoother.defaultFeedGapTimeout
    @State private var momentumStopThreshold = ScrollSmoother.defaultMomentumStopThreshold
    @State private var bounceWindow = ScrollSmoother.defaultBounceWindow
    @State private var bounceRatio = ScrollSmoother.defaultBounceRatio
    @State private var bounceDamping = ScrollSmoother.defaultBounceDamping
    @State private var reversalConfirmation = ScrollSmoother.defaultReversalConfirmation
    @State private var directionThreshold = ScrollSmoother.defaultDirectionThreshold
    @State private var smoothingEnabled = false
    @State private var smoothFraction = ScrollSmoother.defaultSmoothFraction
    @State private var glideStopThreshold = ScrollSmoother.defaultGlideStopThreshold
    @State private var loaded = false
    @State private var unavailable = false

    private var displayedLevel: Double {
        level ?? SmoothnessLevel.defaultValue
    }

    var body: some View {
        Group {
            if !isPro(.smoothScroll) {
                proLockView
            } else if unavailable {
                Text("Smooth scrolling unavailable on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                tuningPanel
            }
        }
        .onAppear(perform: load)
    }

    private var tuningPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Smooth scrolling", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        guard loaded else { return }
                        apply()
                    }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Smoothness")
                        Spacer()
                        Text(level == nil ? "custom" : "\(Int(displayedLevel))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { displayedLevel },
                                          set: { setLevel($0) }),
                           in: SmoothnessLevel.min...SmoothnessLevel.max,
                           step: 1)
                    HStack {
                        presetLabel("Discreta", value: SmoothnessLevel.min)
                        Spacer()
                        presetLabel("Média", value: SmoothnessLevel.defaultValue)
                        Spacer()
                        presetLabel("Fluida", value: SmoothnessLevel.max)
                    }
                    HStack(spacing: 6) {
                        Text("Glide / MOS")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Glide", action: applyGlidePreset)
                        Button("Mos-like", action: applyMosPreset)
                        Spacer()
                    }
                }
                advancedPanel
                    .disabled(!enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var advancedPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Momentum").font(.caption).fontWeight(.semibold)
            Toggle("Momentum", isOn: $momentumEnabled)
                .onChange(of: momentumEnabled) { _, _ in customChange() }
            sliderRow("Max boost", value: $maxBoost, range: 1.0...6.0, step: 0.1)
            sliderRow("Momentum decay", value: $momentumDecay, range: 0.5...0.98, step: 0.01)
            sliderRow("Momentum stop", value: $momentumStopThreshold, range: 0.0...1.0, step: 0.05)

            Text("Glide").font(.caption).fontWeight(.semibold)
            Toggle("Smoothing (glide)", isOn: $smoothingEnabled)
                .onChange(of: smoothingEnabled) { _, _ in customChange() }
            sliderRow("Smooth fraction", value: $smoothFraction, range: 0.02...0.15, step: 0.01)
            sliderRow("Glide stop", value: $glideStopThreshold, range: 0.0...2.0, step: 0.1)

            Text("Feed").font(.caption).fontWeight(.semibold)
            sliderRow("Pixels per notch", value: $pixelsPerNotch, range: 1...40, step: 1)
            sliderRow("Accel window (s)", value: $accelerationWindow, range: 0.01...0.20, step: 0.01)
            sliderRow("Feed gap timeout (s)", value: $feedGapTimeout, range: 0.02...0.30, step: 0.01)

            Text("Bounce").font(.caption).fontWeight(.semibold)
            sliderRow("Bounce window (s)", value: $bounceWindow, range: 0.0...0.20, step: 0.005)
            sliderRow("Bounce ratio", value: $bounceRatio, range: 0.1...1.0, step: 0.05)
            sliderRow("Bounce damping", value: $bounceDamping, range: 0.0...1.0, step: 0.05)

            Text("Direção").font(.caption).fontWeight(.semibold)
            Stepper("Reversal confirmation: \(reversalConfirmation)",
                    value: $reversalConfirmation, in: 1...5)
                .onChange(of: reversalConfirmation) { _, _ in customChange() }
            sliderRow("Direction threshold", value: $directionThreshold, range: 0.0...5.0, step: 0.25)
        }
        .padding(.top, 2)
    }

    private var proLockView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Advanced tuning is a Pro feature.").font(.headline)
            Text("Tune momentum, glide, feed and bounce for trackpad-style scrolling.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Get RatTamer Pro") {
                NSWorkspace.shared.open(ProStore.productURL)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double) -> some View {
        HStack {
            Text(title).frame(width: 150, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .onChange(of: value.wrappedValue) { _, _ in customChange() }
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func presetLabel(_ name: String, value: Double) -> some View {
        Text(name)
            .font(.caption)
            .foregroundStyle(level == value ? Color.accentColor : Color.secondary)
            .onTapGesture { setLevel(value) }
    }

    private func setLevel(_ newValue: Double) {
        guard loaded else { return }
        level = newValue
        let p = SmoothnessLevel.parameters(level: newValue, multiplier: 8, invert: false)
        maxBoost = p.maxBoost
        momentumDecay = p.momentumDecay
        momentumEnabled = p.momentumEnabled
        apply()
    }

    private func applyGlidePreset() {
        guard loaded else { return }
        smoothingEnabled = true
        pixelsPerNotch = 120
        maxBoost = 1.5
        smoothFraction = 0.13
        glideStopThreshold = 0.5
        accelerationWindow = 0.05
        level = nil
        applyLive()
    }

    private func applyMosPreset() {
        guard loaded else { return }
        smoothingEnabled = true
        pixelsPerNotch = 132
        maxBoost = 1.0
        smoothFraction = 0.13
        glideStopThreshold = 0.5
        accelerationWindow = 0.05
        level = nil
        applyLive()
    }

    private func currentParams() -> ScrollSmoother.Parameters {
        ScrollSmoother.Parameters(
            multiplier: 8,
            momentumEnabled: momentumEnabled,
            invert: false,
            maxBoost: maxBoost,
            momentumDecay: momentumDecay,
            pixelsPerNotch: pixelsPerNotch,
            accelerationWindow: accelerationWindow,
            feedGapTimeout: feedGapTimeout,
            momentumStopThreshold: momentumStopThreshold,
            bounceWindow: bounceWindow,
            bounceRatio: bounceRatio,
            bounceDamping: bounceDamping,
            reversalConfirmation: reversalConfirmation,
            directionThreshold: directionThreshold,
            smoothingEnabled: smoothingEnabled,
            smoothFraction: smoothFraction,
            glideStopThreshold: glideStopThreshold)
    }

    private func customChange() {
        guard loaded else { return }
        level = nil
        applyLive()
    }

    private func apply() {
        var config = AppModel.shared.configStore.load()
        config.smoothScrollEnabled = enabled
        config.smoothScrollLevel = level
        config.smoothScrollAdvanced = storedAdvanced
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func applyLive() {
        var config = AppModel.shared.configStore.load()
        config.smoothScrollEnabled = enabled
        config.smoothScrollLevel = level
        config.smoothScrollAdvanced = currentParams()
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.updateSmoothParameters(currentParams())
    }

    private var storedAdvanced: ScrollSmoother.Parameters? {
        level == nil ? currentParams() : nil
    }

    private func load() {
        guard AppModel.shared.engine?.hiResWheelService != nil else {
            unavailable = true
            return
        }
        let config = AppModel.shared.configStore.load()
        enabled = config.smoothScrollEnabled == true
        level = config.smoothScrollLevel
        let params = config.smoothScrollAdvanced
            ?? SmoothnessLevel.parameters(level: level ?? SmoothnessLevel.defaultValue,
                                          multiplier: 8, invert: false)
        maxBoost = params.maxBoost
        momentumDecay = params.momentumDecay
        momentumEnabled = params.momentumEnabled
        pixelsPerNotch = params.pixelsPerNotch
        accelerationWindow = params.accelerationWindow
        feedGapTimeout = params.feedGapTimeout
        momentumStopThreshold = params.momentumStopThreshold
        bounceWindow = params.bounceWindow
        bounceRatio = params.bounceRatio
        bounceDamping = params.bounceDamping
        reversalConfirmation = params.reversalConfirmation
        directionThreshold = params.directionThreshold
        smoothingEnabled = params.smoothingEnabled
        smoothFraction = params.smoothFraction
        glideStopThreshold = params.glideStopThreshold
        loaded = true
    }

    private func isPro(_ feature: ProFeature) -> Bool {
        AppModel.shared.isPro(feature)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors (file not yet referenced, but must compile).

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/Views/AdvancedTabView.swift
git commit -m "feat(settings): add Advanced tab with Pro-gated smooth scroll tuning"
```

---

### Task 4: Register the Advanced tab in the sidebar

Adds the sidebar entry and the detail switch case in `SettingsView.swift`.

**Files:**
- Modify: `Sources/RatTamerApp/SettingsView.swift:13-27`

**Interfaces:**
- Consumes: `AdvancedTabView` (Task 3), `GeneralTabView`, `AboutTabView`, `ProTabView`, `ButtonsTabView`.

- [ ] **Step 1: Add the sidebar entry**

In `SettingsView.swift`, add the Advanced row between Buttons and Pro:

```swift
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag("General")
                Label("Buttons", systemImage: "computermouse").tag("Buttons")
                Label("Advanced", systemImage: "slider.horizontal.3").tag("Advanced")
                Label("Pro", systemImage: "sparkles").tag("Pro")
                Label("About", systemImage: "info.circle").tag("About")
            }
```

- [ ] **Step 2: Add the detail case**

In `SettingsView.swift`, replace the switch so "Advanced" resolves to the new view:

```swift
            switch selection {
            case "General": GeneralTabView()
            case "Advanced": AdvancedTabView()
            case "About": AboutTabView()
            case "Pro": ProTabView()
            default: ButtonsTabView()
            }
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/RatTamerApp/SettingsView.swift
git commit -m "feat(settings): wire Advanced tab into the sidebar"
```

---

### Task 5: Update README docs

Reflects the free basic / Pro advanced boundary in the README.

**Files:**
- Modify: `README.md` ("Smooth scrolling" section and Pricing list)

- [ ] **Step 1: Update the Smooth scrolling section**

In `README.md`, replace the "Smooth scrolling" paragraph (around line 65) with:

```markdown
Trackpad-style vertical smooth scrolling for Logitech wheels. It reads hi-res wheel
deltas over HID++ and re-emits them as continuous pixel scroll events. The free tier
offers a Smoothness slider (0–100) with presets Discreta (0), Média (50, default) and
Fluida (100). Settings → **Advanced** adds Pro tuning of the momentum, glide, feed and
bounce parameters.
```

- [ ] **Step 2: Update the Pricing list**

In `README.md`, update the Pro bullet (around line 115) to:

```markdown
**RatTamer Pro** adds gestures, SmartShift, Run Shortcut, advanced smooth scroll
tuning and (coming soon) multiple profiles — the basic smoothness level slider is free.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: describe free basic smooth scroll and Pro advanced tuning"
```

---

## Final Verification

Run the full suite and build once more after all tasks:

```bash
swift test 2>&1 | grep -E "Executed.*tests|error:" | tail -5
swift build 2>&1 | tail -3
```

Expected: all tests pass (313 existing + 0 new in Task 1, since the two tests are rewrites), build clean.

Manual verification (dev build, `isPro` returns `true`):
1. `./scripts/build-app.sh` and open `build/RatTamer.app`.
2. Settings → Advanced shows the full tuning panel; toggling Smooth scrolling off disables the parameter sliders.
3. Moving a parameter in Advanced shows "custom" on the General slider; picking Discreta/Média/Fluida in General resets the Advanced panel.
4. Free-license simulation (temporarily force `AppModel.isPro` to return `false`): General still has the free toggle + slider; Advanced shows the lock + "Get RatTamer Pro".
