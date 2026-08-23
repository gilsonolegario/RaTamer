# Níveis de Smoothness — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar níveis de smoothness: slider 0–100 com presets no app principal (substituindo o toggle Momentum) e painel de tuning ao vivo com todos os parâmetros no RatTest.

**Architecture:** `SmoothnessLevel` (puro, RatTamerCore) mapeia um nível 0–100 para `ScrollSmoother.Parameters`, que vira a superfície completa de tuning (todos os knobs com defaults = valores atuais). A config troca `smoothScrollMomentum` por `smoothScrollLevel`. O app usa `SmoothnessLevel.parameters(...)`; o RatTest monta `Parameters` de sliders ao vivo e aplica via novo `setParameters` no coordinator (movido para RatTamerCore para ser reutilizado).

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI (AppKit host), HID++ (IOKit), CGEvent (CoreGraphics), XCTest.

## Global Constraints

- Plataforma: macOS 14+, arm64e (arm64-apple-macos14.0 nos testes).
- pt-BR para textos de UI; nomes de código em inglês.
- Pro gating inalterado: `ProFeature.smoothScroll` continua; debug builds liberam via `AppModel.isPro` (`#if DEBUG return true`).
- Nenhum toggle "Momentum" deve sobrar no app principal (substituído pelo nível).
- `swift test` 100% verde e `swift build` sem warnings novos ao final.
- Não alterar `HiResWheel`, `DivertedButtonMonitor` ou `EngineController.restoreSmoothScroll` (fora do escopo).

---

### Task 1: `ScrollSmoother.Parameters` — superfície completa de tuning

**Files:**
- Modify: `Sources/RatTamerCore/Core/ScrollSmoother.swift`
- Modify: `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`

**Interfaces:**
- Produces: `ScrollSmoother.Parameters` com campos `multiplier: UInt8`, `momentumEnabled: Bool`, `invert: Bool`, `maxBoost: Double`, `momentumDecay: Double`, `pixelsPerNotch: Double`, `accelerationWindow: TimeInterval`, `feedGapTimeout: TimeInterval`, `momentumStopThreshold: Double`, `bounceWindow: TimeInterval`, `bounceRatio: Double`, `bounceDamping: Double`, `reversalConfirmation: Int`, `directionThreshold: Double`. O `init` mantém os 3 primeiros argumentos originais e dá default aos demais.
- Produces: estáticas renomeadas `ScrollSmoother.defaultPixelsPerNotch` (=10), `defaultAccelerationWindow` (=0.05), `defaultMaxBoost` (=3.0), `defaultFeedGapTimeout` (=0.08), `defaultMomentumDecay` (=0.85), `defaultMomentumStopThreshold` (=0.1), `defaultBounceWindow` (=0.04), `defaultBounceRatio` (=0.5), `defaultBounceDamping` (=0.15), `defaultReversalConfirmation` (=2), `defaultDirectionThreshold` (=1.0).
- Consumes: `WheelMovement` (inalterado).

- [ ] **Step 1: Write the failing tests**

Adicione ao final de `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`:

```swift
    func testCustomPixelsPerNotchIsHonored() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15, momentumEnabled: false, invert: false,
                                                 pixelsPerNotch: 20))
        XCTAssertEqual(feed(s, at: 1000), 20, accuracy: 0.0001)
    }

    func testCustomMaxBoostIsHonored() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15, momentumEnabled: false, invert: false,
                                                 maxBoost: 2.0))
        _ = feed(s, at: 1000)
        // 10ms gap -> boost = 1 + (2-1)*(1 - 0.01/0.05) = 1.8 -> 18
        XCTAssertEqual(feed(s, at: 1000.01), 18, accuracy: 0.0001)
    }

    func testCustomMomentumDecayIsHonored() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15, momentumEnabled: true, invert: false,
                                                 momentumDecay: 0.5))
        _ = feed(s, at: 1000)
        let t1 = Date(timeIntervalSince1970: 1000.2)
        let t2 = Date(timeIntervalSince1970: 1000.2 + 1.0 / 120.0)
        XCTAssertEqual(s.tick(at: t1), 10, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t2), 5, accuracy: 0.0001) // 10 * 0.5
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScrollSmootherTests`
Expected: compile error — `Parameters` não tem `pixelsPerNotch`/`maxBoost`/`momentumDecay`.

- [ ] **Step 3: Implement**

Em `Sources/RatTamerCore/Core/ScrollSmoother.swift`, substitua o struct `Parameters` (linhas 7-17) por:

```swift
    public struct Parameters: Equatable {
        public var multiplier: UInt8
        public var momentumEnabled: Bool
        public var invert: Bool
        public var maxBoost: Double
        public var momentumDecay: Double
        public var pixelsPerNotch: Double
        public var accelerationWindow: TimeInterval
        public var feedGapTimeout: TimeInterval
        public var momentumStopThreshold: Double
        public var bounceWindow: TimeInterval
        public var bounceRatio: Double
        public var bounceDamping: Double
        public var reversalConfirmation: Int
        public var directionThreshold: Double

        public init(multiplier: UInt8,
                    momentumEnabled: Bool,
                    invert: Bool,
                    maxBoost: Double = ScrollSmoother.defaultMaxBoost,
                    momentumDecay: Double = ScrollSmoother.defaultMomentumDecay,
                    pixelsPerNotch: Double = ScrollSmoother.defaultPixelsPerNotch,
                    accelerationWindow: TimeInterval = ScrollSmoother.defaultAccelerationWindow,
                    feedGapTimeout: TimeInterval = ScrollSmoother.defaultFeedGapTimeout,
                    momentumStopThreshold: Double = ScrollSmoother.defaultMomentumStopThreshold,
                    bounceWindow: TimeInterval = ScrollSmoother.defaultBounceWindow,
                    bounceRatio: Double = ScrollSmoother.defaultBounceRatio,
                    bounceDamping: Double = ScrollSmoother.defaultBounceDamping,
                    reversalConfirmation: Int = ScrollSmoother.defaultReversalConfirmation,
                    directionThreshold: Double = ScrollSmoother.defaultDirectionThreshold) {
            self.multiplier = multiplier
            self.momentumEnabled = momentumEnabled
            self.invert = invert
            self.maxBoost = maxBoost
            self.momentumDecay = momentumDecay
            self.pixelsPerNotch = pixelsPerNotch
            self.accelerationWindow = accelerationWindow
            self.feedGapTimeout = feedGapTimeout
            self.momentumStopThreshold = momentumStopThreshold
            self.bounceWindow = bounceWindow
            self.bounceRatio = bounceRatio
            self.bounceDamping = bounceDamping
            self.reversalConfirmation = reversalConfirmation
            self.directionThreshold = directionThreshold
        }
    }
```

Substitua o bloco de estáticas (linhas 19-43) por:

```swift
    /// Base pixels emitted per full notch (deltaV == multiplier).
    public static let defaultPixelsPerNotch: Double = 10
    /// Feeds arriving inside this window are considered fast and get boosted.
    public static let defaultAccelerationWindow: TimeInterval = 0.05
    /// Max multiplier applied to a feed arriving ~instantly.
    public static let defaultMaxBoost: Double = 3.0
    /// Time without a feed before momentum may run.
    public static let defaultFeedGapTimeout: TimeInterval = 0.08
    /// Exponential decay per tick (120 Hz).
    public static let defaultMomentumDecay: Double = 0.85
    /// Below this absolute velocity momentum stops.
    public static let defaultMomentumStopThreshold: Double = 0.1
    /// Opposite-direction deltas arriving within this window of the last
    /// accepted feed are treated as mechanical detent bounce (ratcheted wheel).
    public static let defaultBounceWindow: TimeInterval = 0.04
    /// Bounces smaller than this fraction of the last accepted magnitude are
    /// strongly attenuated; bigger opposite pulses pass but still need
    /// confirmation before flipping the dominant direction.
    public static let defaultBounceRatio: Double = 0.5
    /// Attenuation applied to detected bounces.
    public static let defaultBounceDamping: Double = 0.15
    /// Consecutive opposite pulses required to accept a direction reversal.
    public static let defaultReversalConfirmation: Int = 2
    /// Minimum magnitude for a feed to establish/refresh the dominant direction.
    public static let defaultDirectionThreshold: Double = 1.0
```

Agora troque todas as referências às estáticas antigas por `parameters.*`:

No `feed` (linhas 61-79), troque `Self.pixelsPerNotch` → `parameters.pixelsPerNotch`, `Self.accelerationWindow` → `parameters.accelerationWindow` (2 ocorrências), `Self.maxBoost` → `parameters.maxBoost`.

No `stabilized` (linhas 87-128), troque `Self.directionThreshold` → `parameters.directionThreshold` (3 ocorrências), `Self.bounceWindow` → `parameters.bounceWindow`, `Self.reversalConfirmation` → `parameters.reversalConfirmation`, `Self.bounceRatio` → `parameters.bounceRatio`, `Self.bounceDamping` → `parameters.bounceDamping`.

No `tick` (linhas 133-145), troque `Self.feedGapTimeout` → `parameters.feedGapTimeout`, `Self.momentumStopThreshold` → `parameters.momentumStopThreshold`, `Self.momentumDecay` → `parameters.momentumDecay`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ScrollSmootherTests`
Expected: todos os testes (14 existentes + 3 novos) passam. Os existentes não mudam de comportamento porque o `init` default reproduz os valores atuais.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSmoother.swift Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift
git commit -m "refactor(smooth): make ScrollSmoother.Parameters the full tuning surface"
```

---

### Task 2: `SmoothnessLevel` — mapeamento puro nível → parâmetros

**Files:**
- Create: `Sources/RatTamerCore/Core/SmoothnessLevel.swift`
- Create: `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`

**Interfaces:**
- Consumes: `ScrollSmoother.Parameters` (Task 1).
- Produces: `public enum SmoothnessLevel` com `min/max/defaultValue: Double` (0/100/50), `momentumOnThreshold: Double` (20), `clamped(_:)`, `momentumEnabled(_:) -> Bool`, `maxBoost(_:) -> Double`, `momentumDecay(_:) -> Double`, `parameters(level:multiplier:invert:) -> ScrollSmoother.Parameters`.

- [ ] **Step 1: Write the failing test**

Crie `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class SmoothnessLevelTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(SmoothnessLevel.min, 0)
        XCTAssertEqual(SmoothnessLevel.max, 100)
        XCTAssertEqual(SmoothnessLevel.defaultValue, 50)
        XCTAssertEqual(SmoothnessLevel.momentumOnThreshold, 20)
    }

    func testClampsOutOfRange() {
        XCTAssertEqual(SmoothnessLevel.clamped(-10), 0)
        XCTAssertEqual(SmoothnessLevel.clamped(150), 100)
        XCTAssertEqual(SmoothnessLevel.clamped(50), 50)
    }

    func testAnchorMaxBoost() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(0), 1.5, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(50), 3.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(100), 5.0, accuracy: 0.0001)
    }

    func testAnchorMomentumDecay() {
        XCTAssertEqual(SmoothnessLevel.momentumDecay(20), 0.75, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(50), 0.85, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(100), 0.92, accuracy: 0.0001)
    }

    func testMomentumThreshold() {
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(0))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(19))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(20))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(100))
    }

    func testInterpolationIsMonotonic() {
        let levels = stride(from: 0.0, through: 100.0, by: 10.0)
        let boosts = levels.map(SmoothnessLevel.maxBoost)
        let decays = levels.map(SmoothnessLevel.momentumDecay)
        for i in 1..<boosts.count {
            XCTAssertGreaterThan(boosts[i], boosts[i - 1])
            XCTAssertGreaterThan(decays[i], decays[i - 1])
        }
    }

    func testMidpointInterpolation() {
        // between 0 (1.5) and 50 (3.0): t = 0.5 -> 2.25
        XCTAssertEqual(SmoothnessLevel.maxBoost(25), 2.25, accuracy: 0.0001)
        // between 50 (0.85) and 100 (0.92): t = 0.5 -> 0.885
        XCTAssertEqual(SmoothnessLevel.momentumDecay(75), 0.885, accuracy: 0.0001)
    }

    func testParametersForDefaultLevel() {
        let p = SmoothnessLevel.parameters(level: 50, multiplier: 8, invert: true)
        XCTAssertEqual(p.multiplier, 8)
        XCTAssertEqual(p.invert, true)
        XCTAssertEqual(p.momentumEnabled, true)
        XCTAssertEqual(p.maxBoost, 3.0, accuracy: 0.0001)
        XCTAssertEqual(p.momentumDecay, 0.85, accuracy: 0.0001)
    }

    func testParametersDiscretaHasNoMomentum() {
        let p = SmoothnessLevel.parameters(level: 0, multiplier: 8, invert: false)
        XCTAssertFalse(p.momentumEnabled)
        XCTAssertEqual(p.maxBoost, 1.5, accuracy: 0.0001)
    }

    func testParametersKeepsTuningDefaults() {
        let p = SmoothnessLevel.parameters(level: 50, multiplier: 15, invert: false)
        XCTAssertEqual(p.pixelsPerNotch, 10, accuracy: 0.0001)
        XCTAssertEqual(p.bounceDamping, 0.15, accuracy: 0.0001)
        XCTAssertEqual(p.reversalConfirmation, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SmoothnessLevelTests`
Expected: compile error — `SmoothnessLevel` não existe.

- [ ] **Step 3: Implement**

Crie `Sources/RatTamerCore/Core/SmoothnessLevel.swift`:

```swift
import Foundation

/// Pure mapping from a single 0-100 smoothness level to the tuning parameters
/// of `ScrollSmoother`. Higher levels amplify more and glide longer. Anchors:
/// 0 = Discreta, 50 = Média (current defaults), 100 = Fluida.
public enum SmoothnessLevel {
    public static let min: Double = 0
    public static let max: Double = 100
    public static let defaultValue: Double = 50
    /// Momentum (glide) only engages at or above this level.
    public static let momentumOnThreshold: Double = 20

    /// maxBoost anchors: level -> value.
    public static let maxBoostAnchors: [(level: Double, value: Double)] = [
        (0, 1.5), (50, 3.0), (100, 5.0),
    ]
    /// momentumDecay anchors: level -> value.
    public static let momentumDecayAnchors: [(level: Double, value: Double)] = [
        (20, 0.75), (50, 0.85), (100, 0.92),
    ]

    public static func clamped(_ level: Double) -> Double {
        min(max(level, min), max)
    }

    public static func momentumEnabled(_ level: Double) -> Bool {
        clamped(level) >= momentumOnThreshold
    }

    public static func maxBoost(_ level: Double) -> Double {
        interpolate(anchors: maxBoostAnchors, level: clamped(level))
    }

    public static func momentumDecay(_ level: Double) -> Double {
        interpolate(anchors: momentumDecayAnchors, level: clamped(level))
    }

    public static func parameters(level: Double,
                                  multiplier: UInt8,
                                  invert: Bool) -> ScrollSmoother.Parameters {
        let l = clamped(level)
        return ScrollSmoother.Parameters(
            multiplier: multiplier,
            momentumEnabled: momentumEnabled(l),
            invert: invert,
            maxBoost: maxBoost(l),
            momentumDecay: momentumDecay(l))
    }

    private static func interpolate(anchors: [(level: Double, value: Double)],
                                    level: Double) -> Double {
        if level <= anchors[0].level { return anchors[0].value }
        if level >= anchors[anchors.count - 1].level { return anchors[anchors.count - 1].value }
        for i in 0..<(anchors.count - 1) {
            let a = anchors[i]
            let b = anchors[i + 1]
            if level >= a.level, level <= b.level {
                let t = (level - a.level) / (b.level - a.level)
                return a.value + (b.value - a.value) * t
            }
        }
        return anchors[anchors.count - 1].value
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SmoothnessLevelTests`
Expected: 10 testes passam.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/SmoothnessLevel.swift Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift
git commit -m "feat(smooth): add pure SmoothnessLevel mapping (slider value -> parameters)"
```

---

### Task 3: Config — `smoothScrollLevel` substitui `smoothScrollMomentum`

**Files:**
- Modify: `Sources/RatTamerCore/Core/ConfigStore.swift`
- Modify: `Sources/RatTamerCore/Core/ConfigEntitlement.swift`
- Modify: `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`
- Modify: `Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift`

**Interfaces:**
- Consumes: nada de Tasks anteriores (self-contained).
- Produces: `Config.smoothScrollLevel: Double?` (0–100, `decodeIfPresent`, default implícito 50 quando `nil`). Remove `Config.smoothScrollMomentum`.

- [ ] **Step 1: Write the failing tests**

Em `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`, substitua `testSmoothScrollFieldsRoundTrip` (linhas 336-346) por:

```swift
    func testSmoothScrollFieldsRoundTrip() throws {
        let url = tempDir.appendingPathComponent("smooth.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 75
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.smoothScrollEnabled, true)
        XCTAssertEqual(loaded.smoothScrollLevel, 75)
    }

    func testLegacySmoothScrollMomentumConfigDecodes() throws {
        let json = """
        {"version":1,"smoothScrollEnabled":true,"smoothScrollMomentum":true}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(config.smoothScrollEnabled, true)
        XCTAssertNil(config.smoothScrollLevel)
    }
```

Em `Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift`, substitua `testStripsSmoothScrollWithoutEntitlement` (63-69) e `testKeepsSmoothScrollWithEntitlement` (71-77) por:

```swift
    func testStripsSmoothScrollWithoutEntitlement() {
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 75
        let filtered = config.filteringProFeatures { _ in false }
        XCTAssertNil(filtered.smoothScrollEnabled)
        XCTAssertNil(filtered.smoothScrollLevel)
    }

    func testKeepsSmoothScrollWithEntitlement() {
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 30
        let filtered = config.filteringProFeatures { _ in true }
        XCTAssertEqual(filtered.smoothScrollEnabled, true)
        XCTAssertEqual(filtered.smoothScrollLevel, 30)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigStoreTests --filter ConfigEntitlementTests`
Expected: compile errors — `smoothScrollLevel` não existe e `smoothScrollMomentum` foi referenciado.

- [ ] **Step 3: Implement**

Em `Sources/RatTamerCore/Core/ConfigStore.swift`:
1. Linha 172: troque `public var smoothScrollMomentum: Bool?` → `public var smoothScrollLevel: Double?`.
2. Linha 182: no `CodingKeys`, troque `smoothScrollEnabled, smoothScrollMomentum` → `smoothScrollEnabled, smoothScrollLevel`.
3. Linha 201: troque `smoothScrollMomentum = try c.decodeIfPresent(Bool.self, forKey: .smoothScrollMomentum)` → `smoothScrollLevel = try c.decodeIfPresent(Double.self, forKey: .smoothScrollLevel)`.
4. Linha 236: troque `self.smoothScrollMomentum = nil` → `self.smoothScrollLevel = nil`.

Em `Sources/RatTamerCore/Core/ConfigEntitlement.swift`, linha 34: troque `filtered.smoothScrollMomentum = nil` → `filtered.smoothScrollLevel = nil`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConfigStoreTests --filter ConfigEntitlementTests`
Expected: todos passam (incluindo os 2 novos).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ConfigStore.swift Sources/RatTamerCore/Core/ConfigEntitlement.swift \
       Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift
git commit -m "feat(smooth): replace smoothScrollMomentum config with smoothScrollLevel"
```

---

### Task 4: `EngineController` usa `SmoothnessLevel`

**Files:**
- Modify: `Sources/RatTamerApp/EngineController.swift:394-411`

**Interfaces:**
- Consumes: `SmoothnessLevel.parameters(level:multiplier:invert:)` (Task 2).
- Produces: nada novo — comportamento equivalente com level default 50.

- [ ] **Step 1: Implement**

Em `Sources/RatTamerApp/EngineController.swift`, no método `applySmoothScrollIfNeeded`, substitua o trecho (linhas 402-405):

```swift
        let params = ScrollSmoother.Parameters(multiplier: info?.multiplier ?? 8,
                                               momentumEnabled: config.smoothScrollMomentum == true,
                                               invert: config.invertScrollDirection ?? false)
```

por:

```swift
        let level = config.smoothScrollLevel ?? SmoothnessLevel.defaultValue
        let params = SmoothnessLevel.parameters(level: level,
                                                multiplier: info?.multiplier ?? 8,
                                                invert: config.invertScrollDirection ?? false)
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compila sem erros (a referência a `config.smoothScrollMomentum` sumiu; `SmoothnessLevel` vindo de RatTamerCore).

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/EngineController.swift
git commit -m "feat(smooth): build smoother parameters from SmoothnessLevel in engine"
```

---

### Task 5: App UI — slider de Smoothness com presets

**Files:**
- Modify: `Sources/RatTamerApp/Views/GeneralTabView.swift:303-370`

**Interfaces:**
- Consumes: `SmoothnessLevel.defaultValue/min/max` (Task 2), `config.smoothScrollLevel` (Task 3).
- Produces: `SmoothScrollRow` com slider 0–100 e marcadores Discreta/Média/Fluida; sem toggle Momentum.

- [ ] **Step 1: Implement**

Substitua `struct SmoothScrollRow` inteiro (linhas 303-370) de `Sources/RatTamerApp/Views/GeneralTabView.swift` por:

```swift
struct SmoothScrollRow: View {
    @State private var enabled = false
    @State private var level: Double = SmoothnessLevel.defaultValue
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
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Smoothness")
                            Spacer()
                            Text("\(Int(level))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $level, in: SmoothnessLevel.min...SmoothnessLevel.max, step: 1)
                            .onChange(of: level) { _, _ in
                                guard loaded else { return }
                                apply()
                            }
                        HStack {
                            presetLabel("Discreta", value: SmoothnessLevel.min)
                            Spacer()
                            presetLabel("Média", value: 50)
                            Spacer()
                            presetLabel("Fluida", value: SmoothnessLevel.max)
                        }
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

    private func presetLabel(_ name: String, value: Double) -> some View {
        Text(name)
            .font(.caption)
            .foregroundStyle(level == value ? Color.accentColor : Color.secondary)
            .onTapGesture {
                level = value
                apply()
            }
    }

    private func load() {
        guard AppModel.shared.engine?.hiResWheelService != nil else {
            unavailable = true
            return
        }
        let config = AppModel.shared.configStore.load()
            .filteringProFeatures(entitled: AppModel.shared.isPro)
        enabled = config.smoothScrollEnabled == true
        level = config.smoothScrollLevel ?? SmoothnessLevel.defaultValue
        loaded = true
    }

    private func apply() {
        var config = AppModel.shared.configStore.load()
        config.smoothScrollEnabled = enabled
        config.smoothScrollLevel = level
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func isPro(_ feature: ProFeature) -> Bool {
        AppModel.shared.isPro(feature)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compila sem erros.

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/Views/GeneralTabView.swift
git commit -m "feat(smooth): replace momentum toggle with smoothness slider + presets in General tab"
```

---

### Task 6: Coordinator para RatTamerCore + `setParameters`

**Files:**
- Move: `Sources/RatTamerApp/ScrollSmootherCoordinator.swift` → `Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift`
- Create: `Tests/RatTamerCoreTests/Core/ScrollSmootherCoordinatorTests.swift`

**Interfaces:**
- Produces: `ScrollSmootherCoordinator` (internal) em RatTamerCore com `init(smoother:now:poster:)`, `onWheelMovement(_:)`, `start()`, `stop()`, e novo `setParameters(_ parameters: ScrollSmoother.Parameters)`.
- Consumes: `ScrollSmoother.Parameters` (Task 1). O RatTest (Task 7/8) e o app usam o mesmo tipo.

- [ ] **Step 1: Write the failing test**

Crie `Tests/RatTamerCoreTests/Core/ScrollSmootherCoordinatorTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class ScrollSmootherCoordinatorTests: XCTestCase {
    func testSetParametersAppliesLive() {
        let now = Date()
        var posted: [Double] = []
        let exp = expectation(description: "posted")
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: false,
                                                        invert: false))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother,
                                                    now: { now },
                                                    poster: { posted.append($0); exp.fulfill() })
        coordinator.setParameters(.init(multiplier: 15,
                                        momentumEnabled: false,
                                        invert: false,
                                        pixelsPerNotch: 20))
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(posted.first ?? 0, 20, accuracy: 0.0001)
    }

    func testStopResetsSmootherState() {
        let now = Date()
        let exp = expectation(description: "stopped")
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: true,
                                                        invert: false))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother,
                                                    now: { now },
                                                    poster: { _ in })
        _ = smoother.feed(WheelMovement(deltaV: 15, periods: 1, resolution: true), at: now)
        coordinator.stop()
        // After reset, momentum is gone: tick after the feed gap returns 0.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let out = smoother.tick(at: Date(timeIntervalSince1970: now.timeIntervalSince1970 + 0.2))
            XCTAssertEqual(out, 0, accuracy: 0.0001)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScrollSmootherCoordinatorTests`
Expected: compile error — `ScrollSmootherCoordinator` não é visível em RatTamerCoreTests (ainda está no target do app) e não tem `setParameters`.

- [ ] **Step 3: Implement**

1. Mova o arquivo e remova o self-import:
   ```bash
   git mv Sources/RatTamerApp/ScrollSmootherCoordinator.swift Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift
   ```
2. Em `Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift`, remova a linha `import RatTamerCore` (viraria self-import no novo target). Mantenha `import Foundation` e `import os`.
3. Adicione o método `setParameters` após `onWheelMovement`:

```swift
    /// Applies a new parameter set live, resetting the smoother so stale
    /// direction/momentum state from the previous tuning does not leak over.
    func setParameters(_ parameters: ScrollSmoother.Parameters) {
        queue.async { [weak self] in
            guard let self else { return }
            self.smoother.parameters = parameters
            self.smoother.reset()
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ScrollSmootherCoordinatorTests` e depois `swift build` (o app precisa continuar compilando sem o arquivo no target dele).
Expected: os 2 testes passam; `swift build` compila.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift \
       Tests/RatTamerCoreTests/Core/ScrollSmootherCoordinatorTests.swift
git commit -m "refactor(smooth): move coordinator to Core; add live setParameters"
```

(`git mv` no Step 3 já registra a rename no index; só é preciso adicionar o novo teste.)

---

### Task 7: RatTestEngine — HiResWheel + smooth scroll wiring

**Files:**
- Modify: `Sources/RatTest/RatTestEngine.swift`

**Interfaces:**
- Consumes: `HiResWheel`, `DivertedButtonMonitor(wheelFeatureIndex:)`, `ScrollSmoother`, `ScrollSmootherCoordinator` (Tasks 1, 6).
- Produces em `RatTestEngine`:
  - `private var hiResWheelService: HiResWheel?`
  - `private var smoothCoordinator: ScrollSmootherCoordinator?`
  - `var wheelMultiplier: UInt8?` (lido de `getInfo`)
  - `func smoothScrollEnabled` / `func setSmoothScroll(enabled: Bool, parameters: ScrollSmoother.Parameters)`
  - `func setSmoothParameters(_ parameters: ScrollSmoother.Parameters)`

- [ ] **Step 1: Implement**

Em `Sources/RatTest/RatTestEngine.swift`:

1. Adicione as propriedades ao final da lista de `private var` (após `controls`):

```swift
    private var hiResWheelService: HiResWheel?
    private var smoothCoordinator: ScrollSmootherCoordinator?
    private(set) var wheelMultiplier: UInt8?
```

2. Em `start()`, após obter o `controlsService` e antes de criar o `monitor`, adicione a descoberta do wheel:

```swift
            var wheelFeatureIndex: UInt8?
            if let wheelIndex = try? session.getFeatureIndex(
                featureID: HiResWheel.featureID, deviceIndex: deviceIndex
            ) {
                wheelFeatureIndex = wheelIndex
                let service = HiResWheel(session: session,
                                         deviceIndex: deviceIndex,
                                         featureIndex: wheelIndex)
                self.hiResWheelService = service
                self.wheelMultiplier = (try? service.getInfo())?.multiplier
            }
```

3. Troque a criação do monitor (linhas 43-46) por:

```swift
            let monitor = DivertedButtonMonitor(deviceIndex: deviceIndex,
                                                featureIndex: featureIndex,
                                                wheelFeatureIndex: wheelFeatureIndex)
            monitor.onControlPressed = { [weak self] cid in self?.onPress?(cid) }
            monitor.onControlReleased = { [weak self] cid in self?.onRelease?(cid) }
            monitor.onWheelMovement = { [weak self] movement in
                self?.smoothCoordinator?.onWheelMovement(movement)
            }
```

4. Adicione ao final da classe (antes do `private func startLoopThread`):

```swift
    func setSmoothScroll(enabled: Bool, parameters: ScrollSmoother.Parameters) {
        guard let service = hiResWheelService else { return }
        try? service.setWheelMode(highResolution: enabled, target: enabled)
        smoothCoordinator?.stop()
        smoothCoordinator = nil
        guard enabled else { return }
        let coordinator = ScrollSmootherCoordinator(
            smoother: ScrollSmoother(parameters: parameters)
        ) { [weak self] pixels in
            self?.postPixels(pixels)
        }
        coordinator.start()
        smoothCoordinator = coordinator
    }

    func setSmoothParameters(_ parameters: ScrollSmoother.Parameters) {
        smoothCoordinator?.setParameters(parameters)
    }

    private func postPixels(_ pixels: Double) {
        guard AXIsProcessTrusted() else { return }
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

5. Em `stop()`, adicione ao final (antes de `session = nil`):

```swift
        smoothCoordinator?.stop()
        smoothCoordinator = nil
        if let service = hiResWheelService {
            try? service.setWheelMode(highResolution: false, target: false)
        }
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compila. `CGEvent` (CoreGraphics) e `AXIsProcessTrusted` (ApplicationServices) precisam de import — adicione no topo de `RatTestEngine.swift`:

```swift
import ApplicationServices
import CoreGraphics
```

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTest/RatTestEngine.swift
git commit -m "feat(ratest): wire smooth scroll (HiResWheel + coordinator) into RatTest engine"
```

---

### Task 8: RatTestView — painel "Smooth Scroll" com todos os knobs

**Files:**
- Modify: `Sources/RatTest/RatTestView.swift`
- Modify: `Sources/RatTest/main.swift`

**Interfaces:**
- Consumes: `RatTestEngine.setSmoothScroll(enabled:parameters:)`, `setSmoothParameters`, `wheelMultiplier` (Task 7); `ScrollSmoother.Parameters` (Task 1); `SmoothnessLevel` (Task 2).
- Produces: seção "Smooth Scroll" na UI do RatTest.

- [ ] **Step 1: Implement**

1. Em `Sources/RatTest/RatTestView.swift`, adicione estados após `pressed` (o `multiplier` é exibido direto do engine, sem `@State`):

```swift
    @State private var smoothEnabled = false
    @State private var maxBoost: Double = ScrollSmoother.defaultMaxBoost
    @State private var momentumDecay: Double = ScrollSmoother.defaultMomentumDecay
    @State private var momentumEnabled = false
    @State private var pixelsPerNotch: Double = ScrollSmoother.defaultPixelsPerNotch
    @State private var accelerationWindow: Double = ScrollSmoother.defaultAccelerationWindow
    @State private var feedGapTimeout: Double = ScrollSmoother.defaultFeedGapTimeout
    @State private var momentumStopThreshold: Double = ScrollSmoother.defaultMomentumStopThreshold
    @State private var bounceWindow: Double = ScrollSmoother.defaultBounceWindow
    @State private var bounceRatio: Double = ScrollSmoother.defaultBounceRatio
    @State private var bounceDamping: Double = ScrollSmoother.defaultBounceDamping
    @State private var reversalConfirmation: Int = ScrollSmoother.defaultReversalConfirmation
    @State private var directionThreshold: Double = ScrollSmoother.defaultDirectionThreshold
```

2. No `body`, após o `Text(footerText)` e antes do fechamento do `VStack`, adicione:

```swift
            Divider()
            Text("Smooth Scroll").font(.headline)
            smoothPanel
```

3. Adicione o painel e os helpers ao final da struct:

```swift
    private var smoothPanel: some View {
        Group {
            Toggle("Enabled (diverts wheel to HID++)", isOn: $smoothEnabled)
                .onChange(of: smoothEnabled) { _, _ in applySmoothEnable() }
            Text("Multiplier: \(engine.wheelMultiplier ?? 8)")
                .font(.caption)
                .foregroundStyle(.secondary)
            sliderRow("Max boost", value: $maxBoost, range: 1.0...6.0, step: 0.1)
            sliderRow("Momentum decay", value: $momentumDecay, range: 0.5...0.98, step: 0.01)
            Toggle("Momentum", isOn: $momentumEnabled)
                .onChange(of: momentumEnabled) { _, _ in applySmoothParams() }
            sliderRow("Pixels per notch", value: $pixelsPerNotch, range: 1...40, step: 1)
            sliderRow("Accel window (s)", value: $accelerationWindow, range: 0.01...0.20, step: 0.01)
            sliderRow("Feed gap timeout (s)", value: $feedGapTimeout, range: 0.02...0.30, step: 0.01)
            sliderRow("Momentum stop", value: $momentumStopThreshold, range: 0.0...1.0, step: 0.05)
            sliderRow("Bounce window (s)", value: $bounceWindow, range: 0.0...0.20, step: 0.005)
            sliderRow("Bounce ratio", value: $bounceRatio, range: 0.1...1.0, step: 0.05)
            sliderRow("Bounce damping", value: $bounceDamping, range: 0.0...1.0, step: 0.05)
            Stepper("Reversal confirmation: \(reversalConfirmation)",
                    value: $reversalConfirmation, in: 1...5)
                .onChange(of: reversalConfirmation) { _, _ in applySmoothParams() }
            sliderRow("Direction threshold", value: $directionThreshold, range: 0.0...5.0, step: 0.25)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).frame(width: 160, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .onChange(of: value.wrappedValue) { _, _ in applySmoothParams() }
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var currentParams: ScrollSmoother.Parameters {
        ScrollSmoother.Parameters(
            multiplier: engine.wheelMultiplier ?? 8,
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
            directionThreshold: directionThreshold)
    }

    private func applySmoothEnable() {
        engine.setSmoothScroll(enabled: smoothEnabled, parameters: currentParams)
    }

    private func applySmoothParams() {
        engine.setSmoothParameters(currentParams)
    }
```

4. Em `Sources/RatTest/main.swift`, ajuste o tamanho da janela (linha 15) para caber o painel:

```swift
        window.setContentSize(NSSize(width: 660, height: 720))
```

Se os controles ultrapassarem a altura, envolva o `smoothPanel` num `ScrollView` com `frame(maxHeight: 420)`. O toggle "Enabled" liga/desliga o divert e o coordinator; os sliders atualizam ao vivo via `setSmoothParameters` sem reiniciar o loop.

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: compila (RatTest target). Erros de tipo vêm de nomes errados de `Parameters` — confira contra Task 1.

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: 100% verde (266 anteriores + novos de Tasks 1, 2, 3, 6).

- [ ] **Step 4: Commit**

```bash
git add Sources/RatTest/RatTestView.swift Sources/RatTest/main.swift
git commit -m "feat(ratest): add live smooth scroll tuning panel with all parameters"
```

---

### Task 9: Documentação e verificação final

**Files:**
- Modify: `README.md` (seção smooth scroll)

- [ ] **Step 1: Update README**

Na seção de smooth scroll do `README.md`, substitua a menção ao toggle "Momentum" e acrescente: slider de Smoothness 0–100 com presets Discreta (0) / Média (50, default) / Fluida (100) — amplificação e inércia crescem com o nível; e note que o RatTest (`swift run RatTest`) tem painel de tuning com todos os parâmetros para calibrar.

- [ ] **Step 2: Full verification**

Run: `swift test`
Expected: 100% verde, 0 falhas.

Run: `swift build`
Expected: sem warnings novos.

Run: `swift build --target RatTest`
Expected: RatTest compila.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(smooth): document smoothness levels and RatTest tuning panel"
```

- [ ] **Step 4: Manual verification (hardware)**

Peça ao usuário para rodar:
1. `swift run RatTamer` → General → habilitar Smooth scrolling → arrastar o slider e clicar nos presets; confirmar que Discreta/Média/Fluida mudam o feel e que não há mais toggle "Momentum".
2. `swift run RatTest` → painel "Smooth Scroll" → habilitar, mexer em `maxBoost`/`momentumDecay`/`pixelsPerNotch` ao vivo e girar a roda em modo ratcheted; confirmar resposta imediata.
