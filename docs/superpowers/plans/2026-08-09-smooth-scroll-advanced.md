# Smooth Scroll Avançado no app principal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portar o painel avançado de smooth scroll do RatTest (18 parâmetros + 5 presets) para o app principal, com persistência no `Config` e atualização ao vivo do `ScrollSmoother`.

**Architecture:** Uma chave nova opcional `Config.smoothScrollAdvanced: ScrollSmoother.Parameters?` persiste o tuning completo. `ScrollSmoother.Parameters` ganha `Codable`. Um helper puro `SmoothScrollSettings` resolve `level + advanced` em parâmetros finais (sempre sobrescrevendo `multiplier`/`invert` derivados do device/config). O `EngineController` usa esse helper no apply e ganha `updateSmoothParameters(_:)` para tweaks ao vivo sem rebuild. A `GeneralTabView` expõe o painel avançado num `DisclosureGroup` com o mesmo modelo de interação do RatTest (nível sincroniza; custom desacopla).

**Tech Stack:** SwiftPM (macOS), SwiftUI, XCTest.

## Global Constraints

- Escopo: **somente** o painel avançado de smooth scroll no app principal. Não alterar RatTest, botões, DPI, wheel mode, thumb wheel.
- `Config.smoothScrollLevel` **nil = custom** (espelha `syncedLevel` do RatTest). Não-nil = "sincronizado nesse nível".
- `multiplier` e `invert` persistidos no struct são **sempre sobrescritos** no apply (derivados do device via `getInfo()` e de `config.invertScrollDirection`). Nunca vêm da UI como-is.
- Decode defensivo: chave ausente ou valores inválidos → defaults/derivação do nível. Nunca crasha.
- Sem mudança no gate Pro (toggle continua Pro; painel avançado herda o estado).
- Build: `swift build`. Testes: `swift test` (suíte completa deve seguir verde — 304 existentes + novos).
- Commits: conventional commits em inglês (`feat:`, `test:`, etc.), mensagem curta, um por task.
- O painel avança o suporte sem reiniciar o coordinator; mudanças de enabled/nível usam `applyConfig()` (rebuild), tweaks custom usam `updateSmoothParameters` (ao vivo).
- Não adicionar comentários ao código além dos doc comments de API existentes.

---

### Task 1: `ScrollSmoother.Parameters` Codable + helper `SmoothScrollSettings`

**Files:**
- Modify: `Sources/RatTamerCore/Core/ScrollSmoother.swift:7` (declaração de `public struct Parameters`)
- Create: `Sources/RatTamerCore/Core/SmoothScrollSettings.swift`
- Create: `Tests/RatTamerCoreTests/Core/SmoothScrollSettingsTests.swift`
- Modify: `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift` (append test de Codable)

**Interfaces:**
- Consumes: `ScrollSmoother.Parameters` (campos e defaults existentes), `SmoothnessLevel.parameters(level:multiplier:invert:)`, `SmoothnessLevel.defaultValue`, `SmoothnessLevel.maxBoost(_:)`, `SmoothnessLevel.momentumDecay(_:)`, `SmoothnessLevel.momentumEnabled(_:)`.
- Produces:
  - `ScrollSmoother.Parameters: Codable` (síntese automática; já é `Equatable`).
  - `public struct SmoothScrollSettings: Equatable` com:
    - `public init(level: Double?, advanced: ScrollSmoother.Parameters?, multiplier: UInt8, invert: Bool)`
    - `public var parameters: ScrollSmoother.Parameters` — `advanced` presente vence (com `multiplier`/`invert` sobrescritos); senão deriva de `SmoothnessLevel.parameters(level: level ?? SmoothnessLevel.defaultValue, multiplier:, invert:)`.
    - `public var isCustom: Bool` — false se `advanced` nil; true se `level` nil; senão true se algum dos 3 parâmetros ligados (`maxBoost`, `momentumDecay`, `momentumEnabled`) divergir da derivação do nível.

- [ ] **Step 1: Escrever os testes que falham**

Crie `Tests/RatTamerCoreTests/Core/SmoothScrollSettingsTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class SmoothScrollSettingsTests: XCTestCase {
    func testLevelOnlyDerivesLevelParams() {
        let settings = SmoothScrollSettings(level: 50, advanced: nil, multiplier: 8, invert: false)
        let p = settings.parameters
        XCTAssertEqual(p.maxBoost, SmoothnessLevel.maxBoost(50))
        XCTAssertEqual(p.momentumDecay, SmoothnessLevel.momentumDecay(50))
        XCTAssertEqual(p.momentumEnabled, SmoothnessLevel.momentumEnabled(50))
        XCTAssertEqual(p.multiplier, 8)
        XCTAssertFalse(settings.isCustom)
    }

    func testAdvancedWinsAndIsCustomWhenDiverging() {
        let advanced = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: true, invert: false,
                                                 maxBoost: 4.2, momentumDecay: 0.9)
        let settings = SmoothScrollSettings(level: 50, advanced: advanced, multiplier: 8, invert: false)
        let p = settings.parameters
        XCTAssertEqual(p.maxBoost, 4.2)
        XCTAssertEqual(p.momentumDecay, 0.9)
        XCTAssertTrue(settings.isCustom)
    }

    func testMultipletAndInvertAlwaysOverwritten() {
        let advanced = ScrollSmoother.Parameters(multiplier: 1, momentumEnabled: true, invert: true,
                                                 maxBoost: 3.0, momentumDecay: 0.85)
        let settings = SmoothScrollSettings(level: 50, advanced: advanced, multiplier: 8, invert: false)
        let p = settings.parameters
        XCTAssertEqual(p.multiplier, 8)
        XCTAssertEqual(p.invert, false)
    }

    func testNilLevelDefaultsToDefaultLevelWhenNoAdvanced() {
        let settings = SmoothScrollSettings(level: nil, advanced: nil, multiplier: 8, invert: false)
        XCTAssertEqual(settings.parameters.maxBoost, SmoothnessLevel.maxBoost(SmoothnessLevel.defaultValue))
        XCTAssertEqual(settings.parameters.momentumDecay, SmoothnessLevel.momentumDecay(SmoothnessLevel.defaultValue))
        XCTAssertEqual(settings.parameters.momentumEnabled, SmoothnessLevel.momentumEnabled(SmoothnessLevel.defaultValue))
        XCTAssertFalse(settings.isCustom)
    }

    func testNilLevelWithAdvancedIsCustom() {
        let advanced = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: false, invert: false,
                                                 maxBoost: 4.2)
        let settings = SmoothScrollSettings(level: nil, advanced: advanced, multiplier: 8, invert: false)
        XCTAssertTrue(settings.isCustom)
        XCTAssertEqual(settings.parameters.maxBoost, 4.2)
    }
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter SmoothScrollSettingsTests`
Expected: FAIL — `cannot find 'SmoothScrollSettings' in scope`

- [ ] **Step 3: Implementar o helper**

Crie `Sources/RatTamerCore/Core/SmoothScrollSettings.swift`:

```swift
import Foundation

/// Resolves the persisted smooth-scroll state (`smoothScrollLevel` +
/// `smoothScrollAdvanced`) into a concrete `ScrollSmoother.Parameters`.
/// `level == nil` means "custom" (advanced diverges from the level).
/// When `advanced` is present it wins; otherwise the three level-linked
/// parameters are derived from the level. `multiplier`/`invert` are always
/// overwritten by the caller-provided values, never trusted from storage.
public struct SmoothScrollSettings: Equatable {
    public let level: Double?
    public let advanced: ScrollSmoother.Parameters?
    public let multiplier: UInt8
    public let invert: Bool

    public init(level: Double?,
                advanced: ScrollSmoother.Parameters?,
                multiplier: UInt8,
                invert: Bool) {
        self.level = level
        self.advanced = advanced
        self.multiplier = multiplier
        self.invert = invert
    }

    public var isCustom: Bool {
        guard let advanced else { return false }
        guard let level else { return true }
        let derived = SmoothnessLevel.parameters(level: level,
                                                 multiplier: multiplier,
                                                 invert: invert)
        return advanced.maxBoost != derived.maxBoost
            || advanced.momentumDecay != derived.momentumDecay
            || advanced.momentumEnabled != derived.momentumEnabled
    }

    public var parameters: ScrollSmoother.Parameters {
        if let advanced {
            var p = advanced
            p.multiplier = multiplier
            p.invert = invert
            return p
        }
        return SmoothnessLevel.parameters(level: level ?? SmoothnessLevel.defaultValue,
                                          multiplier: multiplier,
                                          invert: invert)
    }
}
```

- [ ] **Step 4: Rodar para ver passar**

Run: `swift test --filter SmoothScrollSettingsTests`
Expected: PASS (5 testes)

- [ ] **Step 5: Adicionar `Codable` a `ScrollSmoother.Parameters` + teste**

Modify `Sources/RatTamerCore/Core/ScrollSmoother.swift:7`:

```swift
    public struct Parameters: Equatable, Codable {
```

Append em `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`:

```swift
    func testParametersCodableRoundTrip() throws {
        let p = ScrollSmoother.Parameters(
            multiplier: 8, momentumEnabled: true, invert: true,
            maxBoost: 4.2, momentumDecay: 0.91, pixelsPerNotch: 132,
            accelerationWindow: 0.05, feedGapTimeout: 0.09,
            momentumStopThreshold: 0.3, bounceWindow: 0.1,
            bounceRatio: 0.8, bounceDamping: 0.6,
            reversalConfirmation: 3, directionThreshold: 1.5,
            smoothingEnabled: true, smoothFraction: 0.13,
            glideStopThreshold: 0.5)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(ScrollSmoother.Parameters.self, from: data)
        XCTAssertEqual(back, p)
    }
```

- [ ] **Step 6: Rodar a suíte do Core**

Run: `swift test`
Expected: PASS (304 existentes + 6 novos = 310)

- [ ] **Step 7: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSmoother.swift Sources/RatTamerCore/Core/SmoothScrollSettings.swift Tests/RatTamerCoreTests/Core/SmoothScrollSettingsTests.swift Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift
git commit -m "feat: add SmoothScrollSettings and Codable Parameters"
```

---

### Task 2: Chave `smoothScrollAdvanced` no Config + strip Pro

**Files:**
- Modify: `Sources/RatTamerCore/Core/ConfigStore.swift:172` (propriedade), `:177-183` (CodingKeys), `:201` (decode), `:236` (memberwise init)
- Modify: `Sources/RatTamerCore/Core/ConfigEntitlement.swift:32-35`
- Modify: `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift` (append testes)
- Modify: `Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift` (append teste)

**Interfaces:**
- Consumes: `ScrollSmoother.Parameters: Codable` (Task 1).
- Produces: `Config.smoothScrollAdvanced: ScrollSmoother.Parameters?` — persistido via `smoothScrollAdvanced`; nil quando ausente; `filteringProFeatures` limpa junto com os outros campos de smooth scroll.

- [ ] **Step 1: Escrever os testes que falham**

Append em `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`:

```swift
    func testSmoothScrollAdvancedRoundTrips() throws {
        let url = tempDir.appendingPathComponent("smooth-advanced.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 50
        config.smoothScrollAdvanced = ScrollSmoother.Parameters(
            multiplier: 8, momentumEnabled: true, invert: false,
            maxBoost: 4.2, momentumDecay: 0.91, pixelsPerNotch: 132,
            accelerationWindow: 0.05, feedGapTimeout: 0.09,
            momentumStopThreshold: 0.3, bounceWindow: 0.1,
            bounceRatio: 0.8, bounceDamping: 0.6,
            reversalConfirmation: 3, directionThreshold: 1.5,
            smoothingEnabled: true, smoothFraction: 0.13,
            glideStopThreshold: 0.5)
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded, config)
        XCTAssertEqual(loaded.smoothScrollAdvanced?.maxBoost, 4.2)
        XCTAssertEqual(loaded.smoothScrollAdvanced?.reversalConfirmation, 3)
    }

    func testSmoothScrollAdvancedDecodesNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-smooth-advanced.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{},"smoothScrollEnabled":true,"smoothScrollLevel":50}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.smoothScrollEnabled, true)
        XCTAssertEqual(loaded.smoothScrollLevel, 50)
        XCTAssertNil(loaded.smoothScrollAdvanced)
    }
```

Append em `Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift`:

```swift
    func testFilteringProFeaturesStripsSmoothScrollAdvanced() {
        var config = Config.empty()
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 50
        config.smoothScrollAdvanced = ScrollSmoother.Parameters(
            multiplier: 8, momentumEnabled: true, invert: false, maxBoost: 4.2)
        let filtered = config.filteringProFeatures(entitled: { _ in false })
        XCTAssertNil(filtered.smoothScrollEnabled)
        XCTAssertNil(filtered.smoothScrollLevel)
        XCTAssertNil(filtered.smoothScrollAdvanced)
    }
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter 'ConfigStoreTests|ConfigEntitlementTests'`
Expected: FAIL — 2 testes de round-trip/decode falham (`smoothScrollAdvanced` não compila) e 1 de entitlement não compila (`value of type 'Config' has no member 'smoothScrollAdvanced'`).

- [ ] **Step 3: Implementar**

Modify `Sources/RatTamerCore/Core/ConfigStore.swift`:

a) Após a linha 172 (`public var smoothScrollLevel: Double?`), adicionar:

```swift
    public var smoothScrollAdvanced: ScrollSmoother.Parameters?
```

b) Em `CodingKeys` (linhas 177-183), trocar a linha final:

```swift
             smoothScrollEnabled, smoothScrollLevel
```
por:
```swift
             smoothScrollEnabled, smoothScrollLevel, smoothScrollAdvanced
```

c) No `init(from decoder:)`, após a linha 201 (`smoothScrollLevel = try c.decodeIfPresent(Double.self, forKey: .smoothScrollLevel)`), adicionar:

```swift
        smoothScrollAdvanced = try c.decodeIfPresent(ScrollSmoother.Parameters.self, forKey: .smoothScrollAdvanced)
```

d) No memberwise `init(version:...)`, após a linha 236 (`self.smoothScrollLevel = nil`), adicionar:

```swift
        self.smoothScrollAdvanced = nil
```

Modify `Sources/RatTamerCore/Core/ConfigEntitlement.swift` (linhas 32-35):

```swift
        if !entitled(.smoothScroll) {
            filtered.smoothScrollEnabled = nil
            filtered.smoothScrollLevel = nil
            filtered.smoothScrollAdvanced = nil
        }
```

- [ ] **Step 4: Rodar para ver passar**

Run: `swift test --filter 'ConfigStoreTests|ConfigEntitlementTests'`
Expected: PASS (3 novos)

- [ ] **Step 5: Rodar a suíte completa**

Run: `swift test`
Expected: PASS (310)

- [ ] **Step 6: Commit**

```bash
git add Sources/RatTamerCore/Core/ConfigStore.swift Sources/RatTamerCore/Core/ConfigEntitlement.swift Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift Tests/RatTamerCoreTests/Core/ConfigEntitlementTests.swift
git commit -m "feat: persist advanced smooth scroll parameters in Config"
```

---

### Task 3: `EngineController` — aplicar via `SmoothScrollSettings` + update ao vivo

**Files:**
- Modify: `Sources/RatTamerApp/EngineController.swift:394-412` (`applySmoothScrollIfNeeded`) e adicionar método novo próximo dele

**Interfaces:**
- Consumes: `SmoothScrollSettings` (Task 1), `Config.smoothScrollAdvanced` (Task 2), `config.smoothScrollLevel`, `config.invertScrollDirection`, `service.getInfo()?.multiplier`.
- Produces: `func updateSmoothParameters(_ parameters: ScrollSmoother.Parameters)` — aplica ao vivo no coordinator (via `setParameters`) sobrescrevendo `multiplier` (de `getInfo()`) e `invert` (do config), sem rebuild.

- [ ] **Step 1: Escrever o código**

Modify `Sources/RatTamerApp/EngineController.swift` — trocar o corpo de `applySmoothScrollIfNeeded` (linhas 402-406):

```swift
        let info = try? service.getInfo()
        let settings = SmoothScrollSettings(level: config.smoothScrollLevel,
                                            advanced: config.smoothScrollAdvanced,
                                            multiplier: info?.multiplier ?? 8,
                                            invert: config.invertScrollDirection ?? false)
        let coordinator = ScrollSmootherCoordinator(smoother: ScrollSmoother(parameters: settings.parameters)) { [weak self] pixels in
            self?.postSmoothScroll(pixels)
        }
```

Adicionar imediatamente após `applySmoothScrollIfNeeded` (após a linha 412):

```swift
    /// Applies a new parameter set live without rebuilding the coordinator,
    /// so slider tweaks take effect without stopping in-flight momentum.
    /// `multiplier` and `invert` are always re-derived here, never trusted
    /// from the caller.
    func updateSmoothParameters(_ parameters: ScrollSmoother.Parameters) {
        guard let service = _hiResWheelService else { return }
        var params = parameters
        params.multiplier = (try? service.getInfo())?.multiplier ?? 8
        params.invert = currentConfig().invertScrollDirection ?? false
        smoothCoordinator?.setParameters(params)
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete, sem erros.

- [ ] **Step 3: Suíte completa (sem regressão)**

Run: `swift test`
Expected: PASS (310)

- [ ] **Step 4: Commit**

```bash
git add Sources/RatTamerApp/EngineController.swift
git commit -m "feat: apply advanced smooth scroll params and live updates"
```

---

### Task 4: Painel avançado na `GeneralTabView`

**Files:**
- Modify: `Sources/RatTamerApp/Views/GeneralTabView.swift:303-396` (substituir a struct `SmoothScrollRow` inteira)

**Interfaces:**
- Consumes: `AppModel.shared.configStore`, `AppModel.shared.engine?.hiResWheelService`, `AppModel.shared.engine?.updateSmoothParameters(_:)` (Task 3), `AppModel.shared.engine?.applyConfig()`, `AppModel.shared.isPro(_:)`, `SmoothnessLevel.*`, `ScrollSmoother.Parameters`, defaults `ScrollSmoother.default*`.
- Produces: `SmoothScrollRow` v2 — toggle + slider de nível (label `custom` quando `level == nil`) + 5 presets (Discreta, Média, Fluida, Glide sã, Mos-like) + `DisclosureGroup("Avançado")` com os 18 controles agrupados (Momentum, Glide, Feed, Bounce, Direção).

- [ ] **Step 1: Escrever o código**

Substituir a struct `SmoothScrollRow` (linhas 303-396) em `Sources/RatTamerApp/Views/GeneralTabView.swift` por:

```swift
struct SmoothScrollRow: View {
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
    @State private var showProAlert = false

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
                        HStack {
                            Text("Glide / MOS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Glide sã", action: applyGlidePreset)
                            Button("Mos-like", action: applyMosPreset)
                            Spacer()
                        }
                        DisclosureGroup("Avançado") {
                            advancedPanel
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .filteringProFeatures(entitled: AppModel.shared.isPro)
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

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete, sem erros (após possíveis ajustes triviais de `@State` init).

- [ ] **Step 3: Suíte completa**

Run: `swift test`
Expected: PASS (310)

- [ ] **Step 4: Commit**

```bash
git add Sources/RatTamerApp/Views/GeneralTabView.swift
git commit -m "feat: add advanced smooth scroll panel to settings"
```

---

## Self-Review (para o orquestrador)

1. **Cobertura do spec:**
   - §1.1 `Parameters: Codable` → Task 1. ✓
   - §1.2 chave `smoothScrollAdvanced` + semântica nil=custom + decode retrocompatível + override de multiplier/invert → Tasks 1 e 2. ✓
   - §1.3 `SmoothScrollSettings` (parameters, isCustom) → Task 1. ✓
   - §2 `applySmoothScrollIfNeeded` via settings + `updateSmoothParameters` ao vivo → Task 3. ✓
   - §3 UI (toggle, slider custom, 5 presets, DisclosureGroup com 5 grupos, custom desacopla) → Task 4. ✓
   - §4 testes (round-trip, legacy decode, isCustom, sem regressão) → Tasks 1, 2, verificação final. ✓
   - §5 erros/compatibilidade (decode defensivo, strip Pro) → Tasks 2 e 4 (`filteringProFeatures` + nil custom). ✓
   - "Fora de escopo" (não mexer em RatTest/outros) → garantido por Global Constraints. ✓

2. **Placeholders:** nenhum TBD/TODO; todos os steps têm código real e comandos exatos.

3. **Consistência de tipos:** `SmoothScrollSettings(level:advanced:multiplier:invert:)`, `updateSmoothParameters(_:)`, `Config.smoothScrollAdvanced`, `ScrollSmoother.Parameters` e defaults `ScrollSmoother.default*` usados com os mesmos nomes em todas as tasks. Task 3 produz `updateSmoothParameters` que a Task 4 consome; Task 1 produz `SmoothScrollSettings` que a Task 3 consome.
