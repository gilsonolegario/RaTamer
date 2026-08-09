# Smooth Scroll (HID++ hi-res) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add trackpad-style smooth vertical scrolling to the main wheel by reading high-resolution deltas via HID++ feature `0x2121`, re-emitting them as synthetic continuous pixel scroll events, with optional momentum. Pro feature.

**Architecture:** The device is put in hi-res HID++ mode (`setWheelMode(target: 1, resolution: 1)`) which also suppresses native HID wheel output (no double scroll). `DivertedButtonMonitor.feed` routes `0x2121` `wheelMovement` notifications to a pure, clock-injected state machine (`ScrollSmoother`) that converts deltaV → pixels with an arrival-rate acceleration curve and exponential momentum decay. An App-layer `ScrollSmootherCoordinator` owns a ~120 Hz timer, feeds/ticks the smoother, and posts `CGEventCreateScrollWheelEvent` (units `.pixel`, `isContinuous`). Restoring `setWheelMode(target: 0, resolution: 0)` on disable/quit returns the wheel to native behavior.

**Tech Stack:** Swift 5.9, macOS 14+, SwiftPM. SwiftUI (App), XCTest (RatTamerCoreTests). No new dependencies.

## Global Constraints

- macOS 14+; Swift tools 5.9 (see `Package.swift`). No new dependencies.
- All pure/testable logic goes in `RatTamerCore`; timers, CGEvent posting and SwiftUI go in `RatTamerApp`.
- `setWheelMode` mode byte: bit 0 `target` (1 = HID++ notification), bit 1 `resolution` (1 = hi-res), bit 2 `invert`. Always read current mode first (fn `0x01`) and preserve the invert bit — same read-modify-write pattern as the existing `setInverted`.
- `wheelMovement` report: `11 <dev> <feat> 00 <flags> <deltaV_hi> <deltaV_lo>`; `flags` bits 0-3 `periods` (cap 15), bit 4 `resolution`; `deltaV` Int16 big-endian signed.
- When smooth scrolling is enabled the device emits **no** native wheel events (target=1 suppresses them) — no CGEventTap needed in v1; the synthetic events are the only scroll output.
- `invert` on the device only affects the native HID path; for the HID++ path inversion is applied in the smoother from `Config.invertScrollDirection`.
- Restore `setWheelMode(target: 0, resolution: 0)` whenever smooth scroll is disabled, the engine stops, or the app quits.
- Pro gating in TWO places: UI write gate (toggle shows lock + alert) and runtime apply gate (`Config.filteringProFeatures` strips the fields without `.smoothScroll` entitlement).
- UI copy in English (existing app convention).
- Test command: `swift test` (whole suite) or `swift test --filter <TestClass>` for a single class. Build: `swift build`.
- Works on `main`.

---

### Task 1: HiResWheel — `WheelMovement`, `parseWheelMovement`, `setWheelMode`

**Files:**
- Modify: `Sources/RatTamerCore/HIDPP/HiResWheel.swift`
- Test: `Tests/RatTamerCoreTests/HIDPP/HiResWheelTests.swift`

**Interfaces:**
- Produces: `public struct WheelMovement: Equatable { public let deltaV: Int16; public let periods: UInt8; public let resolution: Bool; public init(deltaV: Int16, periods: UInt8, resolution: Bool) }`; `HiResWheel.parseWheelMovement(_ bytes: [UInt8], deviceIndex: UInt8, featureIndex: UInt8) -> WheelMovement?` (static); `HiResWheel.setWheelMode(highResolution: Bool, target: Bool) throws` (instance).
- Consumes: existing `HIDPPSession.request`, `HIDPP.reportIDLong`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/RatTamerCoreTests/HIDPP/HiResWheelTests.swift`:

```swift
    func testParseWheelMovementParsesDeltaAndFlags() {
        // flags 0x1F -> periods 15, resolution 1; deltaV 0x002C = 44
        let m = HiResWheel.parseWheelMovement(
            [0x11, 0x01, 0x0E, 0x00, 0x1F, 0x00, 0x2C],
            deviceIndex: 1, featureIndex: 0x0E)
        XCTAssertEqual(m?.deltaV, 44)
        XCTAssertEqual(m?.periods, 15)
        XCTAssertEqual(m?.resolution, true)
    }

    func testParseWheelMovementNegativeDelta() {
        // flags 0x01 -> periods 1, resolution 0; deltaV 0xFF38 = -200
        let m = HiResWheel.parseWheelMovement(
            [0x11, 0x01, 0x0E, 0x00, 0x01, 0xFF, 0x38],
            deviceIndex: 1, featureIndex: 0x0E)
        XCTAssertEqual(m?.deltaV, -200)
        XCTAssertEqual(m?.periods, 1)
        XCTAssertEqual(m?.resolution, false)
    }

    func testParseWheelMovementRejectsOtherFeature() {
        XCTAssertNil(HiResWheel.parseWheelMovement(
            [0x11, 0x01, 0x0A, 0x00, 0x01, 0x00, 0x2C],
            deviceIndex: 1, featureIndex: 0x0E))
    }

    func testParseWheelMovementRejectsShortReport() {
        XCTAssertNil(HiResWheel.parseWheelMovement(
            [0x11, 0x01, 0x0E, 0x00, 0x01],
            deviceIndex: 1, featureIndex: 0x0E))
    }

    func testSetWheelModeHighResDiverted() throws {
        let mock = MockHIDDevice()
        // current mode 0x00 (native low) -> set high + target -> 0x03
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x00]]
        try makeService(mock).setWheelMode(highResolution: true, target: true)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(7)), [0x11, 0x01, 0x0E, 0x21, 0x03, 0x00, 0x00])
    }

    func testSetWheelModePreservesInvert() throws {
        let mock = MockHIDDevice()
        // current mode 0x04 (inverted, native low) -> set high + target -> 0x07
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x04]]
        try makeService(mock).setWheelMode(highResolution: true, target: true)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(7)), [0x11, 0x01, 0x0E, 0x21, 0x07, 0x00, 0x00])
    }

    func testSetWheelModeRestoresNative() throws {
        let mock = MockHIDDevice()
        // current mode 0x03 (diverted high) -> set native low -> 0x00
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x03]]
        try makeService(mock).setWheelMode(highResolution: false, target: false)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(7)), [0x11, 0x01, 0x0E, 0x21, 0x00, 0x00, 0x00])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HiResWheelTests`
Expected: FAIL — `parseWheelMovement`, `setWheelMode` and `WheelMovement` don't exist (compile error).

- [ ] **Step 3: Implement**

Add to `Sources/RatTamerCore/HIDPP/HiResWheel.swift`:

```swift
public struct WheelMovement: Equatable {
    public let deltaV: Int16
    public let periods: UInt8
    public let resolution: Bool

    public init(deltaV: Int16, periods: UInt8, resolution: Bool) {
        self.deltaV = deltaV
        self.periods = periods
        self.resolution = resolution
    }
}
```

Inside `HiResWheel` (after `setInverted`):

```swift
    /// Sets the wheel target (native HID vs HID++ notification) and resolution
    /// (low vs high). Bit 2 (invert) is preserved from the current mode. With
    /// `target = true` the device stops emitting native HID wheel events, which
    /// is the double-scroll suppression mechanism.
    public func setWheelMode(highResolution: Bool, target: Bool) throws {
        var mode: UInt8 = 0
        if let resp = try session.request(deviceIndex: deviceIndex,
                                          featureIndex: featureIndex,
                                          functionID: 0x01),
           resp.count >= 5 {
            mode = resp[4]
        }
        if highResolution {
            mode |= 0x02
        } else {
            mode &= ~0x02
        }
        if target {
            mode |= 0x01
        } else {
            mode &= ~0x01
        }
        _ = try session.request(deviceIndex: deviceIndex,
                                featureIndex: featureIndex,
                                functionID: 0x02,
                                params: [mode, 0x00, 0x00])
    }

    /// Decodes a wheelMovement notification (notification ID 0x00).
    public static func parseWheelMovement(_ bytes: [UInt8],
                                          deviceIndex: UInt8,
                                          featureIndex: UInt8) -> WheelMovement? {
        guard bytes.count >= 7,
              bytes[0] == HIDPP.reportIDLong,
              bytes[1] == deviceIndex,
              bytes[2] == featureIndex,
              bytes[3] == 0x00 else { return nil }
        let flags = bytes[4]
        let periods = flags & 0x0F
        let resolution = (flags >> 4) & 1 == 1
        let deltaV = Int16(bytes[5]) << 8 | Int16(bytes[6])
        return WheelMovement(deltaV: deltaV, periods: periods, resolution: resolution)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HiResWheelTests`
Expected: PASS (all existing + new).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/HIDPP/HiResWheel.swift Tests/RatTamerCoreTests/HIDPP/HiResWheelTests.swift
git commit -m "feat(hidpp): add wheelMovement parse and setWheelMode for hi-res wheel"
```

---

### Task 2: ScrollSmoother — pure state machine

**Files:**
- Create: `Sources/RatTamerCore/Core/ScrollSmoother.swift`
- Test: `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`

**Interfaces:**
- Produces: `public struct ScrollSmoother.Parameters: Equatable { public var multiplier: UInt8; public var momentumEnabled: Bool; public var invert: Bool; public init(...) }`; `public final class ScrollSmoother { public static let pixelsPerNotch: Double; public static let accelerationWindow: TimeInterval; public static let maxBoost: Double; public static let feedGapTimeout: TimeInterval; public static let momentumDecay: Double; public static let momentumStopThreshold: Double; public static let bounceWindow: TimeInterval; public static let bounceRatio: Double; public static let bounceDamping: Double; public static let reversalConfirmation: Int; public static let directionThreshold: Double; public var parameters: Parameters; public init(parameters: Parameters); @discardableResult public func feed(_ movement: WheelMovement, at now: Date) -> Double; @discardableResult public func tick(at now: Date) -> Double; public func reset() }`.
- Consumes: `WheelMovement` (Task 1).
- Semantics: `feed` converts deltaV → pixels (`deltaV / multiplier * pixelsPerNotch`), stabilizes against mechanical detent bounce, boosts by arrival-rate curve, seeds momentum, and returns the value the coordinator should post NOW (sign-inverted if `invert`). `tick` returns 0 unless momentum is enabled AND a `feedGapTimeout` has elapsed since the last feed; then it returns the decaying velocity (sign-inverted). Constants are public so tests and tuning can reference them.

**Bounce stabilization (added after device testing; see notes below):** ratcheted wheels emit a brief opposite-direction ricochet when a detent lands. The smoother treats opposite-direction deltas arriving within `bounceWindow` (0.04s) of the last accepted feed as suspects: those smaller than `bounceRatio` (0.5×) of the last accepted magnitude are attenuated by `bounceDamping` (0.15) and do not reseed momentum; a reversal is only accepted after `reversalConfirmation` (2) consecutive opposite pulses (confirmation pattern from MOS PR #908). Stabilization runs on the raw pre-boost value so the arrival-rate boost cannot defeat it.

- [ ] **Step 1: Write the failing test**

Create `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class ScrollSmootherTests: XCTestCase {
    private func make(multiplier: UInt8 = 15,
                      momentum: Bool = false,
                      invert: Bool = false) -> ScrollSmoother {
        ScrollSmoother(parameters: .init(multiplier: multiplier,
                                         momentumEnabled: momentum,
                                         invert: invert))
    }

    private func feed(_ smoother: ScrollSmoother, deltaV: Int16 = 15, at time: TimeInterval) -> Double {
        smoother.feed(WheelMovement(deltaV: deltaV, periods: 1, resolution: true),
                      at: Date(timeIntervalSince1970: time))
    }

    func testFeedConvertsDeltaToPixels() {
        // multiplier 15, deltaV 15 -> 1 notch * 10 px
        let s = make()
        XCTAssertEqual(feed(s, at: 1000), 10, accuracy: 0.0001)
    }

    func testFeedScalesByMultiplier() {
        // multiplier 8, deltaV 8 -> 1 notch * 10 px
        let s = make(multiplier: 8)
        XCTAssertEqual(feed(s, deltaV: 8, at: 1000), 10, accuracy: 0.0001)
    }

    func testFeedFastArrivalAccelerates() {
        let s = make()
        _ = feed(s, at: 1000)
        // 10ms gap -> boost = 1 + 2*(1 - 0.01/0.05) = 2.6
        let fast = feed(s, at: 1000.01)
        XCTAssertGreaterThan(fast, 10)
    }

    func testFeedSlowArrivalIsPrecise() {
        let s = make()
        _ = feed(s, at: 1000)
        // 500ms gap -> no boost
        let slow = feed(s, at: 1000.5)
        XCTAssertEqual(slow, 10, accuracy: 0.0001)
    }

    func testMomentumDecaysToZero() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000)
        var now = 1000.2 // past feedGapTimeout
        var ticks = 0
        while true {
            let px = s.tick(at: Date(timeIntervalSince1970: now))
            if px == 0 { break }
            ticks += 1
            now += 1.0 / 120.0
        }
        XCTAssertGreaterThan(ticks, 0)
    }

    func testMomentumDisabledReturnsZero() {
        let s = make(momentum: false)
        _ = feed(s, at: 1000)
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.2)), 0)
    }

    func testMomentumOnlyAfterFeedGap() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000)
        // still inside feedGapTimeout -> no momentum
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.02)), 0)
        // after gap -> momentum fires
        XCTAssertGreaterThan(s.tick(at: Date(timeIntervalSince1970: 1000.2)), 0)
    }

    func testInvertFlipsSign() {
        let s = make(invert: true)
        XCTAssertEqual(feed(s, at: 1000), -10, accuracy: 0.0001)
    }

    func testInvertAppliesToMomentum() {
        let s = make(momentum: true, invert: true)
        _ = feed(s, at: 1000)
        XCTAssertLessThan(s.tick(at: Date(timeIntervalSince1970: 1000.2)), 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScrollSmootherTests`
Expected: FAIL — `ScrollSmoother` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/RatTamerCore/Core/ScrollSmoother.swift`:

```swift
import Foundation

/// Pure, clock-injected wheel smoother. No timers, no I/O — the caller feeds
/// raw wheel movements and ticks at a fixed rate; both return the pixels to
/// post right now. Time comes from the caller so tests use fictional clocks.
public final class ScrollSmoother {
    public struct Parameters: Equatable {
        public var multiplier: UInt8
        public var momentumEnabled: Bool
        public var invert: Bool

        public init(multiplier: UInt8, momentumEnabled: Bool, invert: Bool) {
            self.multiplier = multiplier
            self.momentumEnabled = momentumEnabled
            self.invert = invert
        }
    }

    /// Base pixels emitted per full notch (deltaV == multiplier).
    public static let pixelsPerNotch: Double = 10
    /// Feeds arriving inside this window are considered fast and get boosted.
    public static let accelerationWindow: TimeInterval = 0.05
    /// Max multiplier applied to a feed arriving ~instantly.
    public static let maxBoost: Double = 3.0
    /// Time without a feed before momentum may run.
    public static let feedGapTimeout: TimeInterval = 0.08
    /// Exponential decay per tick (120 Hz).
    public static let momentumDecay: Double = 0.85
    /// Below this absolute velocity momentum stops.
    public static let momentumStopThreshold: Double = 0.1

    public var parameters: Parameters

    private var lastFeedAt: Date?
    private var velocity: Double = 0

    public init(parameters: Parameters) {
        self.parameters = parameters
    }

    /// Converts a wheel movement to pixels, applies the acceleration curve,
    /// seeds momentum, and returns the pixels to post now.
    @discardableResult
    public func feed(_ movement: WheelMovement, at now: Date) -> Double {
        let notches = Double(movement.deltaV) / Double(max(1, parameters.multiplier))
        var pixels = notches * Self.pixelsPerNotch
        if let last = lastFeedAt {
            let dt = now.timeIntervalSince(last)
            if dt > 0 && dt < Self.accelerationWindow {
                let t = dt / Self.accelerationWindow
                let boost = 1 + (Self.maxBoost - 1) * (1 - t)
                pixels *= boost
            }
        }
        lastFeedAt = now
        velocity = pixels
        return applyInvert(pixels)
    }

    /// Returns decaying momentum pixels, or 0 when momentum is off, the wheel
    /// is still being fed, or velocity has drained below the stop threshold.
    @discardableResult
    public func tick(at now: Date) -> Double {
        guard parameters.momentumEnabled else { return 0 }
        if let last = lastFeedAt, now.timeIntervalSince(last) < Self.feedGapTimeout {
            return 0
        }
        guard abs(velocity) > Self.momentumStopThreshold else {
            velocity = 0
            return 0
        }
        let out = velocity
        velocity *= Self.momentumDecay
        return applyInvert(out)
    }

    public func reset() {
        lastFeedAt = nil
        velocity = 0
    }

    private func applyInvert(_ value: Double) -> Double {
        parameters.invert ? -value : value
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ScrollSmootherTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSmoother.swift Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift
git commit -m "feat(smooth): add pure ScrollSmoother state machine with momentum"
```

---

### Task 3: DivertedButtonMonitor — route wheel notifications

**Files:**
- Modify: `Sources/RatTamerCore/Discovery/DivertedButtonMonitor.swift`
- Test: `Tests/RatTamerCoreTests/Discovery/DivertedButtonMonitorTests.swift`

**Interfaces:**
- Produces: `DivertedButtonMonitor.init(deviceIndex: UInt8, featureIndex: UInt8, wheelFeatureIndex: UInt8? = nil)`; new callback `onWheelMovement: ((WheelMovement) -> Void)?`. `feed` returns `true` for wheel reports (routed to `onWheelMovement`) before falling through to raw-XY/diverted parsing.
- Consumes: `HiResWheel.parseWheelMovement` (Task 1).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/RatTamerCoreTests/Discovery/DivertedButtonMonitorTests.swift`:

```swift
    func testWheelMovementRoutesToCallback() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A,
                                            wheelFeatureIndex: 0x0E)
        var movements: [WheelMovement] = []
        monitor.onWheelMovement = { movements.append($0) }
        // 11 01 0E 00 13 00 2C -> periods 3, resolution 1, deltaV 44
        let bytes: [UInt8] = [0x11, 0x01, 0x0E, 0x00, 0x13, 0x00, 0x2C, 0, 0, 0, 0, 0]
        XCTAssertTrue(monitor.feed(bytes))
        XCTAssertEqual(movements.count, 1)
        XCTAssertEqual(movements[0].deltaV, 44)
        XCTAssertEqual(movements[0].periods, 3)
        XCTAssertEqual(movements[0].resolution, true)
    }

    func testWheelReportDoesNotTriggerPress() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A,
                                            wheelFeatureIndex: 0x0E)
        var presses = 0
        monitor.onControlPressed = { _ in presses += 1 }
        let bytes: [UInt8] = [0x11, 0x01, 0x0E, 0x00, 0x01, 0x00, 0x2C, 0, 0, 0, 0, 0]
        XCTAssertTrue(monitor.feed(bytes))
        XCTAssertEqual(presses, 0)
        XCTAssertEqual(monitor.pressed, [])
    }

    func testWheelRoutingIgnoredWithoutWheelFeatureIndex() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A)
        var movements = 0
        monitor.onWheelMovement = { _ in movements += 1 }
        let bytes: [UInt8] = [0x11, 0x01, 0x0E, 0x00, 0x01, 0x00, 0x2C, 0, 0, 0, 0, 0]
        XCTAssertFalse(monitor.feed(bytes))
        XCTAssertEqual(movements, 0)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DivertedButtonMonitorTests`
Expected: FAIL — `DivertedButtonMonitor` has no `wheelFeatureIndex:`/`onWheelMovement`.

- [ ] **Step 3: Implement**

Edit `Sources/RatTamerCore/Discovery/DivertedButtonMonitor.swift`:

```swift
public final class DivertedButtonMonitor {
    public var onControlPressed: ((_ cid: UInt16) -> Void)?
    public var onControlReleased: ((_ cid: UInt16) -> Void)?
    public var onRawXY: ((_ dx: Int16, _ dy: Int16) -> Void)?
    public var onWheelMovement: ((WheelMovement) -> Void)?

    public private(set) var pressed = Set<UInt16>()

    private let deviceIndex: UInt8
    private let featureIndex: UInt8
    private let wheelFeatureIndex: UInt8?

    public init(deviceIndex: UInt8, featureIndex: UInt8, wheelFeatureIndex: UInt8? = nil) {
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
        self.wheelFeatureIndex = wheelFeatureIndex
    }

    @discardableResult
    public func feed(_ bytes: [UInt8]) -> Bool {
        if let wheelFeatureIndex,
           let movement = HiResWheel.parseWheelMovement(
               bytes, deviceIndex: deviceIndex, featureIndex: wheelFeatureIndex
           ) {
            onWheelMovement?(movement)
            return true
        }
        if let raw = ReprogrammableControls.parseRawXYEvent(
            bytes, deviceIndex: deviceIndex, featureIndex: featureIndex
        ) {
            onRawXY?(raw.dx, raw.dy)
            return true
        }
        guard let cids = ReprogrammableControls.parseDivertedEvent(
            bytes, deviceIndex: deviceIndex, featureIndex: featureIndex
        ) else { return false }
        let now = Set(cids)
        for cid in cids where !pressed.contains(cid) {
            onControlPressed?(cid)
        }
        for cid in pressed.subtracting(now) {
            onControlReleased?(cid)
        }
        pressed = now
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DivertedButtonMonitorTests`
Expected: PASS (all existing + new).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Discovery/DivertedButtonMonitor.swift Tests/RatTamerCoreTests/Discovery/DivertedButtonMonitorTests.swift
git commit -m "feat(smooth): route hi-res wheel notifications through DivertedButtonMonitor"
```

---

### Task 4: Config fields + ProFeature + entitlement filter

**Files:**
- Modify: `Sources/RatTamerCore/Core/ConfigStore.swift`
- Modify: `Sources/RatTamerCore/Core/LicenseKeyStore.swift`
- Modify: `Sources/RatTamerCore/Core/ConfigEntitlement.swift`
- Test: `Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift`
- Test: `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`
- Test: `Tests/RatTamerCoreTests/Core/LicenseKeyStoreTests.swift`

**Interfaces:**
- Produces: `Config.smoothScrollEnabled: Bool?`, `Config.smoothScrollMomentum: Bool?` (decoded `decodeIfPresent`, default nil); `ProFeature.smoothScroll`; `filteringProFeatures` strips both smooth fields when not entitled to `.smoothScroll`.
- Consumes: existing `Config` Codable pattern (decoder must stay backward compatible — no new required keys).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift`:

```swift
    func testStripsSmoothScrollWithoutEntitlement() {
        config.smoothScrollEnabled = true
        config.smoothScrollMomentum = true
        let filtered = config.filteringProFeatures { _ in false }
        XCTAssertNil(filtered.smoothScrollEnabled)
        XCTAssertNil(filtered.smoothScrollMomentum)
    }

    func testKeepsSmoothScrollWithEntitlement() {
        config.smoothScrollEnabled = true
        config.smoothScrollMomentum = false
        let filtered = config.filteringProFeatures { _ in true }
        XCTAssertEqual(filtered.smoothScrollEnabled, true)
        XCTAssertEqual(filtered.smoothScrollMomentum, false)
    }
```

Append to `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`:

```swift
    func testSmoothScrollFieldsRoundTrip() throws {
        let url = tempDir.appendingPathComponent("smooth.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.smoothScrollEnabled = true
        config.smoothScrollMomentum = false
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.smoothScrollEnabled, true)
        XCTAssertEqual(loaded.smoothScrollMomentum, false)
    }
```

Edit the existing test in `Tests/RatTamerCoreTests/Core/LicenseKeyStoreTests.swift`:

```swift
    func testProFeatureCases() {
        XCTAssertEqual(ProFeature.allCases, [.gestures, .smartShift, .runShortcut, .profiles, .smoothScroll])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigEntitlementTests --filter ConfigStoreTests --filter LicenseKeyStoreTests`
Expected: FAIL — smooth fields/property don't exist; `allCases` mismatch.

- [ ] **Step 3: Implement**

Edit `Sources/RatTamerCore/Core/LicenseKeyStore.swift` — add the case:

```swift
public enum ProFeature: String, CaseIterable, Sendable {
    case gestures
    case smartShift
    case runShortcut
    case profiles
    case smoothScroll
}
```

Edit `Sources/RatTamerCore/Core/ConfigStore.swift`:

1. Add stored properties after `invertScrollDirection`:

```swift
    public var invertScrollDirection: Bool?
    public var smoothScrollEnabled: Bool?
    public var smoothScrollMomentum: Bool?
```

2. Add to `CodingKeys`:

```swift
    private enum CodingKeys: String, CodingKey {
        case version, deviceIndex, buttons, dpiFeatureIndex, dpiDeviceIndex,
             dpiDownValue, dpiAction, swapLeftRight, smartShiftMode, dpiValue,
             invertScrollDirection, thumbWheelLeft, thumbWheelRight,
             smartShiftSensitivity, dpiCycleValues, menuBarOnly,
             smoothScrollEnabled, smoothScrollMomentum
    }
```

3. Add to `init(from decoder:)` after the `invertScrollDirection` line:

```swift
        invertScrollDirection = try c.decodeIfPresent(Bool.self, forKey: .invertScrollDirection)
        smoothScrollEnabled = try c.decodeIfPresent(Bool.self, forKey: .smoothScrollEnabled)
        smoothScrollMomentum = try c.decodeIfPresent(Bool.self, forKey: .smoothScrollMomentum)
```

4. Add to the memberwise `init` body after `self.invertScrollDirection = nil`:

```swift
        self.smoothScrollEnabled = nil
        self.smoothScrollMomentum = nil
```

Edit `Sources/RatTamerCore/Core/ConfigEntitlement.swift` — after the `smartShift` block:

```swift
        if !entitled(.smoothScroll) {
            filtered.smoothScrollEnabled = nil
            filtered.smoothScrollMomentum = nil
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConfigEntitlementTests --filter ConfigStoreTests --filter LicenseKeyStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ConfigStore.swift Sources/RatTamerCore/Core/LicenseKeyStore.swift Sources/RatTamerCore/Core/ConfigEntitlement.swift Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift Tests/RatTamerCoreTests/Core/LicenseKeyStoreTests.swift
git commit -m "feat(smooth): add smooth scroll config, ProFeature.smoothScroll and entitlement filter"
```

---

### Task 5: ScrollSmootherCoordinator — App-layer timer + CGEvent poster

**Files:**
- Create: `Sources/RatTamerApp/ScrollSmootherCoordinator.swift`

**Interfaces:**
- Produces: `ScrollSmootherCoordinator.init(smoother: ScrollSmoother, now: @escaping () -> Date = Date.init, poster: @escaping (Double) -> Void)`; `onWheelMovement(_ movement: WheelMovement)` (async — posts via smoother.feed); `start()` (120 Hz timer on a private serial queue); `stop()` (cancels timer + resets smoother). Serializes all smoother access on its own queue so the loop thread and the timer never race.
- Consumes: `ScrollSmoother` (Task 2), `WheelMovement` (Task 1). Not unit-tested (App layer has no test target) — verify via `swift build` and manual hardware test.

- [ ] **Step 1: Create the file**

Create `Sources/RatTamerApp/ScrollSmootherCoordinator.swift`:

```swift
import Foundation
import os
import RatTamerCore

/// Owns the ~120 Hz scroll timer, feeds the pure `ScrollSmoother` with wheel
/// movements, and posts the resulting deltas via the injected poster closure.
/// All smoother access happens on this coordinator's private queue so the
/// HID++ loop thread and the timer never race on the smoother's state.
final class ScrollSmootherCoordinator {
    private static let log = Logger(subsystem: "com.rattamer", category: "smoothscroll")
    private static let tickInterval: TimeInterval = 1.0 / 120.0

    private let smoother: ScrollSmoother
    private let now: () -> Date
    private let poster: (Double) -> Void
    private let queue = DispatchQueue(label: "com.rattamer.smoothscroll")
    private var timer: DispatchSourceTimer?

    init(smoother: ScrollSmoother,
         now: @escaping () -> Date = Date.init,
         poster: @escaping (Double) -> Void) {
        self.smoother = smoother
        self.now = now
        self.poster = poster
    }

    func onWheelMovement(_ movement: WheelMovement) {
        queue.async { [weak self] in
            guard let self else { return }
            self.poster(self.smoother.feed(movement, at: self.now()))
        }
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.tickInterval,
                       repeating: Self.tickInterval,
                       leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.poster(self.smoother.tick(at: self.now()))
        }
        timer.resume()
        self.timer = timer
        Self.log.info("smooth scroll timer started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in
            self?.smoother.reset()
        }
        Self.log.info("smooth scroll timer stopped")
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/ScrollSmootherCoordinator.swift
git commit -m "feat(smooth): add App-layer ScrollSmootherCoordinator (120Hz timer + poster)"
```

---

### Task 6: EngineController wiring

**Files:**
- Modify: `Sources/RatTamerApp/EngineController.swift`

**Interfaces:**
- Consumes: `HiResWheel.setWheelMode`, `DivertedButtonMonitor` wheel routing, `ScrollSmoother`, `ScrollSmootherCoordinator`.
- Behavior:
  - `start()` passes the resolved `0x2121` feature index into the monitor and wires `onWheelMovement`.
  - `applyAll` calls `applySmoothScrollIfNeeded(service:)` (after `applyScrollInversionIfNeeded`) — applies `setWheelMode` and (re)creates/stops the coordinator based on filtered config.
  - `enabled` setter false branch and `stop()` call `restoreSmoothScroll()` — stops the coordinator and restores `setWheelMode(target: 0, resolution: 0)`.
  - `postSmoothScroll` builds a `CGEvent(scrollWheelEvent2Source:units:.pixel...)`, sets `.scrollWheelEventIsContinuous = 1`, posts to `.cghidEventTap` (guarded by Accessibility trust).

- [ ] **Step 1: Edit `start()` — pass wheel feature index and wire callback**

In `start()`, the `0x2121` feature lookup currently discards the index. Capture it in a local so the monitor can route wheel reports:

```swift
            var wheelFeatureIndex: UInt8?
            if let wheelIndex = try? session.getFeatureIndex(
                featureID: HiResWheel.featureID, deviceIndex: deviceIndex
            ) {
                wheelFeatureIndex = wheelIndex
                self._hiResWheelService = HiResWheel(session: session,
                                                     deviceIndex: deviceIndex,
                                                     featureIndex: wheelIndex)
            }
```

Replace the monitor construction (currently `let monitor = DivertedButtonMonitor(deviceIndex: deviceIndex, featureIndex: featureIndex)`) and the callback wiring with:

```swift
            let monitor = DivertedButtonMonitor(deviceIndex: deviceIndex,
                                                featureIndex: featureIndex,
                                                wheelFeatureIndex: wheelFeatureIndex)
            monitor.onControlPressed = { [weak self] cid in
                self?.handlePress(cid)
            }
            monitor.onControlReleased = { [weak self] cid in
                self?.handleRelease(cid)
            }
            monitor.onRawXY = { [weak self] dx, dy in
                self?.handleRawXY(dx: dx, dy: dy)
            }
            monitor.onWheelMovement = { [weak self] movement in
                self?.handleWheelMovement(movement)
            }
            self.monitor = monitor
```

- [ ] **Step 2: Edit `applyAll`, add apply/restore/handle/post helpers**

In `applyAll`, after the `applyScrollInversionIfNeeded` block add:

```swift
        if let service = _hiResWheelService {
            applySmoothScrollIfNeeded(service: service)
        }
```

Add the following private helpers (place near `applyScrollInversionIfNeeded`):

```swift
    private var smoothCoordinator: ScrollSmootherCoordinator?

    private func applySmoothScrollIfNeeded(service: HiResWheel) {
        let config = currentConfig()
        let enabled = config.smoothScrollEnabled == true
        Self.log.info("smooth scroll: \(enabled ? "on" : "off")")
        try? service.setWheelMode(highResolution: enabled, target: enabled)
        smoothCoordinator?.stop()
        smoothCoordinator = nil
        guard enabled else { return }
        let info = try? service.getInfo()
        let params = ScrollSmoother.Parameters(multiplier: info?.multiplier ?? 8,
                                               momentumEnabled: config.smoothScrollMomentum == true,
                                               invert: config.invertScrollDirection ?? false)
        let coordinator = ScrollSmootherCoordinator(smoother: ScrollSmoother(parameters: params)) { [weak self] pixels in
            self?.postSmoothScroll(pixels)
        }
        coordinator.start()
        smoothCoordinator = coordinator
    }

    private func restoreSmoothScroll() {
        smoothCoordinator?.stop()
        smoothCoordinator = nil
        guard let service = _hiResWheelService else { return }
        try? service.setWheelMode(highResolution: false, target: false)
    }

    private func handleWheelMovement(_ movement: WheelMovement) {
        guard enabled else { return }
        smoothCoordinator?.onWheelMovement(movement)
    }

    private func postSmoothScroll(_ pixels: Double) {
        guard Permissions.isAccessibilityTrusted() else { return }
        let value = Int32(pixels.rounded())
        guard value != 0 else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 1, wheel1: value, wheel2: 0, wheel3: 0) else {
            return
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
    }
```

- [ ] **Step 3: Edit the `enabled` setter and `stop()`**

In the `enabled` setter's `else` branch (currently `self.restoreNativeDiverts()`), also restore smooth scroll:

```swift
            } else {
                ioQueue.async { [weak self] in
                    guard let self else { return }
                    self.restoreNativeDiverts()
                    self.restoreSmoothScroll()
                }
            }
```

In `stop()`, after `restoreNativeDiverts()` add:

```swift
        restoreNativeDiverts()
        restoreSmoothScroll()
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: PASS (all suites).

- [ ] **Step 6: Commit**

```bash
git add Sources/RatTamerApp/EngineController.swift
git commit -m "feat(smooth): wire smooth scroll into engine (apply/restore/post CGEvents)"
```

---

### Task 7: General tab UI — Scrolling section

**Files:**
- Modify: `Sources/RatTamerApp/Views/GeneralTabView.swift`
- Modify: `Sources/RatTamerApp/Views/ProTabView.swift` (feature list copy)

**Interfaces:**
- Consumes: `ProStore.productURL`, `AppModel.shared.license.isPro`, `AppModel.shared.configStore`, `AppModel.shared.engine?.applyConfig()`, `AppModel.shared.engine?.hiResWheelService` (availability check). Follows the existing Pro lock pattern from `ButtonsTabView` (lock icon + "RatTamer Pro" alert).

- [ ] **Step 1: Add the Scrolling row**

Edit `Sources/RatTamerApp/Views/GeneralTabView.swift`:

1. In `body`, replace the Scrolling section:

```swift
            Section("Scrolling") {
                ScrollDirectionToggleRow()
                SmoothScrollRow()
            }
```

2. Add `SmoothScrollRow` at the end of the file (after `ScrollDirectionToggleRow`):

```swift
struct SmoothScrollRow: View {
    @State private var enabled = false
    @State private var momentum = false
    @State private var loaded = false
    @State private var unavailable = false
    @State private var showProAlert = false

    var body: some View {
        Group {
            if unavailable {
                Text("Smooth scrolling unavailable on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Smooth scrolling", isOn: $enabled)
                    .onChange(of: enabled) { _, newValue in
                        guard loaded else { return }
                        if newValue, !isPro(.smoothScroll) {
                            showProAlert = true
                            enabled = false
                            return
                        }
                        apply()
                    }
                if enabled {
                    Toggle("Momentum", isOn: $momentum)
                        .onChange(of: momentum) { _, _ in
                            guard loaded else { return }
                            apply()
                        }
                }
            }
        }
        .onAppear(perform: load)
        .alert("RatTamer Pro", isPresented: $showProAlert) {
            Button("Get RatTamer Pro") {
                NSWorkspace.shared.open(ProStore.productURL)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Smooth scrolling is a Pro feature.")
        }
    }

    private func load() {
        guard AppModel.shared.engine?.hiResWheelService != nil else {
            unavailable = true
            return
        }
        let config = AppModel.shared.configStore.load()
        enabled = config.smoothScrollEnabled == true
        momentum = config.smoothScrollMomentum == true
        loaded = true
    }

    private func apply() {
        var config = AppModel.shared.configStore.load()
        config.smoothScrollEnabled = enabled
        config.smoothScrollMomentum = momentum
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func isPro(_ feature: ProFeature) -> Bool {
        AppModel.shared.license.isPro(feature)
    }
}
```

- [ ] **Step 2: Update Pro tab copy**

Edit `Sources/RatTamerApp/Views/ProTabView.swift`:

```swift
            Text("Pro features: Gestures, SmartShift, Run Shortcut, Smooth Scrolling, multiple profiles.")
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerApp/Views/GeneralTabView.swift Sources/RatTamerApp/Views/ProTabView.swift
git commit -m "feat(smooth): add smooth scroll + momentum toggles in General tab"
```

---

### Task 8: README note + full verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a limitations note**

Append a short section to `README.md` (before or after the feature list), English, mirroring the existing tone:

```markdown
## Smooth scrolling

Trackpad-style vertical smooth scrolling for Logitech wheels is a Pro feature. It reads hi-res wheel deltas over HID++ and re-emits them as continuous pixel scroll events, with optional momentum.

> Do not run RatTamer together with Logitech Options+, BetterMouse or similar mouse-config tools: they reprogram the same HID++ features and will fight over wheel mode.
```

- [ ] **Step 2: Full verification**

Run: `swift build && swift test`
Expected: BUILD SUCCESSFUL, all tests PASS.

- [ ] **Step 3: Manual hardware validation checklist** (for the human; not automated)

1. Enable "Smooth scrolling" → wheel scrolls continuously; no native notches bleed through (setWheelMode target=1 suppresses them).
2. Disable it → native notch scrolling returns immediately (setWheelMode target=0 restored).
3. Toggle "Momentum" → after a fast flick, scrolling continues and decays to zero.
4. Invert scroll direction toggle → smooth scrolling flips direction.
5. Quit RatTamer → wheel scrolls natively (no leftover hi-res mode).
6. Without a Pro license → toggle shows lock + alert; smooth fields stay nil in config.
7. `swift run RatTest` connectivity path still connects/diverts normally.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document smooth scrolling and the coexistence warning"
```

---

## Post-plan validation (self-review)

- Spec coverage: setWheelMode (T1), parseWheelMovement (T1), monitor routing (T3), ScrollSmoother + momentum + invert (T2), config fields (T4), Pro gating UI+runtime (T4/T7), coordinator + CGEvent posting (T5/T6), restore on disable/quit (T6), UI toggles (T7), README coexistence warning (T8). Out-of-scope items (thumb wheel, sensitivity slider, ratchetSwitch, notarization) are untouched.
- No placeholders: every code step has full source.
- Type consistency: `WheelMovement`/`ScrollSmoother.Parameters`/`ScrollSmootherCoordinator` signatures match across tasks; `smoothScrollEnabled`/`smoothScrollMomentum` naming is consistent in Config, entitlement and UI.
