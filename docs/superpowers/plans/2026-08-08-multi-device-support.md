# Multi-device Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the hardcoded "MX Master 2S" assumptions so RatTamer adapts to any Logitech HID++ device (MX Master 3/3S, MX Anywhere, MX Vertical) by feature detection.

**Architecture:** The app already connects to any Logitech HID++ device and queries features dynamically. This plan (1) exposes the real device product name, (2) adds a pure `DeviceCapabilities` struct built after connect, (3) wires it through `EngineController`/`AppModel` into notifications, the About tab and the SmartShift menu, (4) derives DPI cycle defaults from the device's reported DPI list, and (5) updates docs.

**Tech Stack:** Swift 5.9, SwiftPM, macOS 14+, IOKit HID++. No new dependencies. Tested only on MX Master 2S (other models supported by construction — no tester campaign).

## Global Constraints

- Swift 5.9, macOS 14+, SwiftPM. No new dependencies.
- Pure logic lives in `RatTamerCore` and is unit-tested; app-layer code lives in `RatTamerApp`.
- Tests run with `swift test`; release build with `./scripts/build-app.sh`.
- All strings user-visible in English. Never hardcode a device model name in user-facing text.
- Keep the existing mock-based test pattern (`Tests/RatTamerCoreTests/Support/MockHIDDevice.swift`).

---
### Task 1: Expose device product name

**Files:**
- Modify: `Sources/RatTamerCore/HIDPP/HIDDevice.swift` (protocol + extension)
- Modify: `Sources/RatTamerCore/HIDPP/IOHIDDeviceWrapper.swift`
- Modify: `Sources/RatTamerCore/HIDPP/HIDPPSession.swift`
- Test: `Tests/RatTamerCoreTests/Support/MockHIDDevice.swift`
- Test: `Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `HIDDevice.productName: String?` (protocol property, default `nil` via extension); `HIDPPSession.productName: String?` forwarding to `device.productName`. Later tasks read `session.productName`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift`:

```swift
func testProductNameDefaultsToNilForDeviceWithoutName() {
    let session = HIDPPSession(device: MockHIDDevice())
    XCTAssertNil(session.productName)
}

func testProductNameForwardsFromDevice() {
    let mock = MockHIDDevice()
    mock.productName = "MX Master 3S"
    let session = HIDPPSession(device: mock)
    XCTAssertEqual(session.productName, "MX Master 3S")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HIDPPSessionTests`
Expected: FAIL — `value of type 'HIDPPSession' has no member 'productName'`.

- [ ] **Step 3: Add `productName` to the mock**

In `Tests/RatTamerCoreTests/Support/MockHIDDevice.swift`, inside the class body:

```swift
var productName: String?
```

- [ ] **Step 4: Implement protocol property**

In `Sources/RatTamerCore/HIDPP/HIDDevice.swift`, add to the protocol after the `write` requirement:

```swift
    var productName: String? { get }
```

And in the `public extension HIDDevice` block add the default:

```swift
    var productName: String? { nil }
```

- [ ] **Step 5: Implement in the real wrapper**

In `Sources/RatTamerCore/HIDPP/IOHIDDeviceWrapper.swift`, add a stored property and set it in `init`:

```swift
public final class IOHIDDeviceWrapper: HIDDevice {
    public let productName: String?
    ...
    public init(device: IOHIDDevice) {
        self.productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        ...
    }
```

- [ ] **Step 6: Forward through the session**

In `Sources/RatTamerCore/HIDPP/HIDPPSession.swift`, after `public let softwareID: UInt8`:

```swift
    public var productName: String? { device.productName }
```

- [ ] **Step 7: Run test to verify it passes**

Run: `swift test --filter HIDPPSessionTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/RatTamerCore/HIDPP/HIDDevice.swift Sources/RatTamerCore/HIDPP/IOHIDDeviceWrapper.swift Sources/RatTamerCore/HIDPP/HIDPPSession.swift Tests/RatTamerCoreTests/Support/MockHIDDevice.swift Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift
git commit -m "feat: expose device product name via HIDDevice"
```

---
### Task 2: Add DeviceCapabilities struct

**Files:**
- Create: `Sources/RatTamerCore/Discovery/DeviceCapabilities.swift`
- Test: `Tests/RatTamerCoreTests/Discovery/DeviceCapabilitiesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `DeviceCapabilities` — a public struct with four public `Bool` vars and a memberwise public init. Later tasks build one in `EngineController` and expose it via `AppModel`.

- [ ] **Step 1: Write the failing test**

Create `Tests/RatTamerCoreTests/Discovery/DeviceCapabilitiesTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class DeviceCapabilitiesTests: XCTestCase {
    func testInitStoresValues() {
        let caps = DeviceCapabilities(hasReprogrammableControls: true,
                                      hasBattery: false,
                                      hasDPI: true,
                                      hasSmartShift: true)
        XCTAssertTrue(caps.hasReprogrammableControls)
        XCTAssertFalse(caps.hasBattery)
        XCTAssertTrue(caps.hasDPI)
        XCTAssertTrue(caps.hasSmartShift)
    }

    func testEquatable() {
        let a = DeviceCapabilities(hasReprogrammableControls: false,
                                   hasBattery: false,
                                   hasDPI: false,
                                   hasSmartShift: false)
        let b = DeviceCapabilities(hasReprogrammableControls: false,
                                   hasBattery: false,
                                   hasDPI: false,
                                   hasSmartShift: false)
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DeviceCapabilitiesTests`
Expected: FAIL — cannot find `DeviceCapabilities` in scope.

- [ ] **Step 3: Implement the struct**

Create `Sources/RatTamerCore/Discovery/DeviceCapabilities.swift`:

```swift
import Foundation

public struct DeviceCapabilities: Equatable {
    public var hasReprogrammableControls: Bool
    public var hasBattery: Bool
    public var hasDPI: Bool
    public var hasSmartShift: Bool

    public init(hasReprogrammableControls: Bool, hasBattery: Bool, hasDPI: Bool, hasSmartShift: Bool) {
        self.hasReprogrammableControls = hasReprogrammableControls
        self.hasBattery = hasBattery
        self.hasDPI = hasDPI
        self.hasSmartShift = hasSmartShift
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DeviceCapabilitiesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Discovery/DeviceCapabilities.swift Tests/RatTamerCoreTests/Discovery/DeviceCapabilitiesTests.swift
git commit -m "feat: add DeviceCapabilities struct"
```

---
### Task 3: Wire device name and capabilities through EngineController/AppModel

**Files:**
- Modify: `Sources/RatTamerApp/EngineController.swift`
- Modify: `Sources/RatTamerApp/AppModel.swift`
- Modify: `Sources/RatTamerApp/AppDelegate.swift`
- Modify: `Sources/RatTamerApp/Views/SimpleTabs.swift`

**Interfaces:**
- Consumes: `HIDPPSession.productName: String?` (Task 1); `DeviceCapabilities` (Task 2); `HiResWheel.getInfo() -> WheelInfo` where `WheelInfo.hasSwitch: Bool`.
- Produces: `EngineController.deviceName: String`; `EngineController.capabilities: DeviceCapabilities`; `AppModel.deviceName: String` (`@Published`); `AppModel.capabilities: DeviceCapabilities` (`@Published`). Used by Task 4 and the About tab.

- [ ] **Step 1: Add stored properties to EngineController**

In `Sources/RatTamerApp/EngineController.swift`, near the other `private(set)` properties (after `private(set) var controls: [ControlInfo] = []`):

```swift
    private(set) var deviceName = "HID++ device"
    private(set) var capabilities = DeviceCapabilities(hasReprogrammableControls: false,
                                                       hasBattery: false,
                                                       hasDPI: false,
                                                       hasSmartShift: false)
```

- [ ] **Step 2: Populate them in start()**

In `start()`, right after `self.session = session`:

```swift
            self.deviceName = session.productName ?? "HID++ device"
```

After the `HiResWheel` service block (after `self._hiResWheelService = HiResWheel(...)` inside the `if let wheelIndex` block), compute capabilities. Add this block right after the `if let wheelIndex { ... }` closes (still inside `do`, before `let monitor = ...`):

```swift
            let hasSmartShift = _hiResWheelService.map { ((try? $0.getInfo())?.hasSwitch ?? false) } ?? false
            self.capabilities = DeviceCapabilities(hasReprogrammableControls: true,
                                                   hasBattery: _batteryService != nil,
                                                   hasDPI: _dpiService != nil,
                                                   hasSmartShift: hasSmartShift)
```

- [ ] **Step 3: Publish through AppModel**

In `Sources/RatTamerApp/AppModel.swift`, add published properties after `@Published var remappingEnabled`:

```swift
    @Published var deviceName = "HID++ device"
    @Published var capabilities = DeviceCapabilities(hasReprogrammableControls: false,
                                                     hasBattery: false,
                                                     hasDPI: false,
                                                     hasSmartShift: false)
```

In the `engine.onConnectionState` `.connected` case, set them:

```swift
                case .connected:
                    self?.isConnected = true
                    self?.isReconnecting = false
                    self?.deviceName = engine.deviceName
                    self?.capabilities = engine.capabilities
```

- [ ] **Step 4: Use the device name in notifications**

In `Sources/RatTamerApp/AppDelegate.swift`, replace the two hardcoded bodies:

```swift
        EngineEvents.shared.onConnected = {
            Notifier.post(title: "RatTamer", body: "\(AppModel.shared.deviceName) connected")
        }
        EngineEvents.shared.onDisconnected = {
            Notifier.post(title: "RatTamer", body: "\(AppModel.shared.deviceName) disconnected")
        }
```

- [ ] **Step 5: Use the device name in the About tab**

In `Sources/RatTamerApp/Views/SimpleTabs.swift`, add an observed model to `AboutTabView` and replace line 15:

```swift
struct AboutTabView: View {
    @ObservedObject private var model = AppModel.shared
    ...
            Text("Native replacement for Logitech Options+ for the \(model.deviceName).")
```

(Keep the remaining lines unchanged.)

- [ ] **Step 6: Build and run the full test suite**

Run: `swift build` then `swift test`
Expected: compiles clean; all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/RatTamerApp/EngineController.swift Sources/RatTamerApp/AppModel.swift Sources/RatTamerApp/AppDelegate.swift Sources/RatTamerApp/Views/SimpleTabs.swift
git commit -m "feat: surface device name and capabilities in app"
```

---
### Task 4: Gate the SmartShift (auto) menu option on capability

**Files:**
- Modify: `Sources/RatTamerApp/Views/ButtonsTabView.swift`

**Interfaces:**
- Consumes: `AppModel.shared.capabilities.hasSmartShift: Bool` (Task 3).
- Produces: none (UI behavior change).

- [ ] **Step 1: Write the change**

In `Sources/RatTamerApp/Views/ButtonsTabView.swift`, in `smartShiftMenu(for:)`, wrap the "SmartShift (auto)" Button (lines ~261-268) so it only shows when the device supports it:

```swift
            if model.capabilities.hasSmartShift {
                Button {
                    setSmartShiftMode(.smartshift)
                } label: {
                    Label("SmartShift (auto)", systemImage: "bolt.badge.automatic")
                    if mode == .smartshift {
                        Image(systemName: "checkmark")
                    }
                }
            }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles clean.

- [ ] **Step 3: Manual verification on MX Master 2S**

Run the app (`swift run RatTamer` or `./scripts/build-app.sh` + open the bundle). Open Settings → Buttons, find the SmartShift control (CID 0x00C4): the "SmartShift (auto)" option must still be present (2S supports it). Setting it must still work.

- [ ] **Step 4: Commit**

```bash
git add Sources/RatTamerApp/Views/ButtonsTabView.swift
git commit -m "feat: hide SmartShift auto option on devices without the feature"
```

---
### Task 5: Device-aware DPI cycle presets

**Files:**
- Modify: `Sources/RatTamerCore/Core/DPICycle.swift`
- Modify: `Sources/RatTamerApp/EngineController.swift`
- Test: `Tests/RatTamerCoreTests/Core/DPICycleTests.swift`

**Interfaces:**
- Consumes: `AdjustableDPI.getSensorDpiList(sensor: UInt8) throws -> [UInt16]` (exists).
- Produces: `DPICycle.recommendedPresets(from validList: [UInt16], limit: Int = 4) -> [UInt16]`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/RatTamerCoreTests/Core/DPICycleTests.swift`:

```swift
    func testRecommendedPresetsFallsBackToDefaultsWhenEmpty() {
        XCTAssertEqual(DPICycle.recommendedPresets(from: []), DPICycle.defaultPresets)
    }

    func testRecommendedPresetsReturnsSortedUniqueValuesWhenWithinLimit() {
        XCTAssertEqual(DPICycle.recommendedPresets(from: [1600, 1000, 2000, 1000]),
                       [1000, 1600, 2000])
    }

    func testRecommendedPresetsKeepsMinAndMaxWhenSampling() {
        let dense = Array(stride(from: 200, through: 4000, by: 200)).map { UInt16($0) }
        let presets = DPICycle.recommendedPresets(from: dense)
        XCTAssertEqual(presets.count, 4)
        XCTAssertEqual(presets.first, 200)
        XCTAssertEqual(presets.last, 4000)
        XCTAssertEqual(presets, presets.sorted())
    }

    func testRecommendedPresetsLimitIsRespected() {
        let presets = DPICycle.recommendedPresets(from: [100, 300, 600, 900, 1200], limit: 3)
        XCTAssertEqual(presets.count, 3)
        XCTAssertEqual(presets.first, 100)
        XCTAssertEqual(presets.last, 1200)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DPICycleTests`
Expected: FAIL — `DPICycle` has no member `recommendedPresets`.

- [ ] **Step 3: Implement the function**

In `Sources/RatTamerCore/Core/DPICycle.swift`, after `defaultPresets`:

```swift
    public static func recommendedPresets(from validList: [UInt16], limit: Int = 4) -> [UInt16] {
        guard !validList.isEmpty else { return defaultPresets }
        let values = Array(Set(validList)).sorted()
        guard values.count > limit else { return values }
        let count = max(2, min(limit, values.count))
        var chosen: [UInt16] = []
        for i in 0..<count {
            let index = Int((Double(i) / Double(count - 1) * Double(values.count - 1)).rounded())
            chosen.append(values[index])
        }
        return Array(Set(chosen)).sorted()
    }
```

- [ ] **Step 4: Use it in the engine**

In `Sources/RatTamerApp/EngineController.swift`, `cycleDPI()` — replace:

```swift
            let presets = config.dpiCycleValues ?? DPICycle.defaultPresets
```

with:

```swift
            let sensorList = (try? service.getSensorDpiList(sensor: 0)) ?? []
            let presets = config.dpiCycleValues ?? DPICycle.recommendedPresets(from: sensorList)
```

`recommendedPresets` falls back to `defaultPresets` when `sensorList` is empty, preserving current behavior on the 2S.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter DPICycleTests`
Expected: PASS.

- [ ] **Step 6: Run full suite + build**

Run: `swift test` then `./scripts/build-app.sh`
Expected: all pass; `build/RatTamer.app` produced.

- [ ] **Step 7: Commit**

```bash
git add Sources/RatTamerCore/Core/DPICycle.swift Sources/RatTamerApp/EngineController.swift Tests/RatTamerCoreTests/Core/DPICycleTests.swift
git commit -m "feat: derive DPI cycle presets from device sensor list"
```

---
### Task 6: Update README and technical docs

**Files:**
- Modify: `README.md`
- Modify: `docs/TECHNICAL.md` (only if it names the device — check first)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing (docs).

- [ ] **Step 1: Update the README intro**

In `README.md`, line 5, replace "for the MX Master 2S" with:

```
A native macOS menu bar app that replaces Logitech Options+ for the MX Master 2S. ... adapts to other HID++ Logitech devices (MX Master 3/3S, MX Anywhere, MX Vertical) ...
```

Concretely, change the sentence to:

> A native macOS menu bar app that replaces Logitech Options+ for the MX Master 2S — tested on that model and designed to adapt to other HID++ Logitech devices (MX Master 3/3S, MX Anywhere, MX Vertical). It captures the mouse buttons over HID++ 2.0 and runs your own shortcut, system action or click for each one — no Logitech software required, native behavior restored on quit.

- [ ] **Step 2: Update the macOS compatibility table**

In `README.md`, add a row to the compatibility table noting model scope:

```
| Device | Notes |
|---|---|
| MX Master 2S | fully tested |
| MX Master 3/3S, MX Anywhere, MX Vertical | supported by feature detection, not tested on hardware |
```

- [ ] **Step 3: Check and update docs/TECHNICAL.md**

Run: `grep -n "MX Master 2S" docs/TECHNICAL.md`
If it names the device as a hardcoded requirement, reword the same way (tested on 2S, adapts to other HID++ devices). If the match is a historical note, leave it.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/TECHNICAL.md
git commit -m "docs: describe multi-device support"
```

---
### Task 7: Final verification

**Files:**
- None (verification only).

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: all tests pass (including the three new test files).

- [ ] **Step 2: Release build**

Run: `./scripts/build-app.sh`
Expected: `build/RatTamer.app` built and signed (ad-hoc).

- [ ] **Step 3: Manual regression on MX Master 2S**

Run the app and verify: connect status + notification shows the real device name (not hardcoded "MX Master 2S" text); About tab shows the device name; battery row present; DPI slider works; assign "Cycle DPI" to a button and confirm it cycles 1000 → 1600 → 2000 → 4000; SmartShift menu still offers "SmartShift (auto)"; thumb wheel still triggers its actions; reconnect after unplug works.

- [ ] **Step 4: Final commit if any stragglers**

Run: `git status`
If anything uncommitted remains, commit it with a descriptive message.
