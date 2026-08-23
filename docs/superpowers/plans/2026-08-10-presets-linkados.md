# Presets Ligados (level ⇄ momentum/smoothing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o nível de smoothness (0–100) derivar todos os parâmetros de scroll via 6 presets-âncora (Subtle, Medium, Personal, Glide, MOS, Fluid), com seletor de presets, ajuda `(?)` estilo macOS e reset para o padrão (Glide).

**Architecture:** `SmoothnessLevel` vira uma curva por partes cujas âncoras são os presets (contínuos interpolam linearmente; booleanos usam a âncora mais próxima, empate → nível maior). `SmoothScrollSettings.isCustom` passa a comparar todos os campos derivados. A aba Advanced troca os botões Glide/Mos-like por um `Picker` de presets e o slider passa a usar o caminho leve (`applyLive`) — o que também corrige o flicker. Presets compartilhados entre General, Advanced e RatTest.

**Tech Stack:** Swift, SwiftUI, AppKit (macOS 14+), XCTest (RatTamerCore).

## Global Constraints

- Presets (nomes EXATOS em inglês): `Subtle`=0, `Medium`=50, `Personal`=60, `Glide`=70, `MOS`=78, `Fluid`=100. Nada de "Discreta/Média/Fluida/Mos-like" em UI nova.
- Default de instalação nova e do botão "Reset to default" = **Glide (nível 70)** → `SmoothnessLevel.defaultValue = 70`.
- `Personal` preserva valores exatos do usuário: momentum ON, smoothing ON, `pixelsPerNotch` 120, `maxBoost` 1.8, `momentumDecay` 0.92, `smoothFraction` 0.13, `glideStopThreshold` 0.5.
- Campos não-sensíveis (feedGapTimeout 0.08, accelerationWindow 0.05, momentumStopThreshold 0.1, bounceWindow 0.04, bounceRatio 0.5, bounceDamping 0.15, reversalConfirmation 2, directionThreshold 1.0) permanecem nos defaults em todos os presets.
- `setLevel` na aba Advanced usa `applyLive()` (nunca `apply()`) — corrige o flicker (não destrói o coordinator).
- Invariante do `applyLive`: `smoothScrollAdvanced = level == nil ? currentParams() : nil`.
- Slider "Pixels per notch" precisa de range `1...200` (presets usam 100–160; hoje `1...40` cortaria).
- `momentumOnThreshold` (20) é REMOVIDO — o flip de momentum vem da curva.
- Sem mudanças em `ConfigStore`/`ConfigEntitlement`: `smoothScrollLevel = nil` já resolve para Glide (70) via fallback.
- Pro gating inalterado.

---

### Task 1: Curva de presets em `SmoothnessLevel` + enum `SmoothnessPreset`

**Files:**
- Modify: `Sources/RatTamerCore/Core/SmoothnessLevel.swift` (reescrever)
- Test: `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift` (reescrever)

**Interfaces:**
- Produces (usado nas Tasks 3–6): `enum SmoothnessPreset: String, CaseIterable` com `var level: Double`, `var displayName: String`, `init?(level: Double)`; e em `SmoothnessLevel`: `static let defaultValue = 70`, `static func maxBoost(_:)`, `momentumDecay(_:)`, `pixelsPerNotch(_:)`, `smoothFraction(_:)`, `glideStopThreshold(_:)`, `momentumEnabled(_:)`, `smoothingEnabled(_:)` (todas `(Double) -> Double/Bool`), e `parameters(level:multiplier:invert:) -> ScrollSmoother.Parameters` derivando TODOS os 17 campos.

- [ ] **Step 1: Reescrever o teste (failing)**

Substitua o conteúdo de `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift` por:

```swift
import XCTest
@testable import RatTamerCore

final class SmoothnessLevelTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(SmoothnessLevel.min, 0)
        XCTAssertEqual(SmoothnessLevel.max, 100)
        XCTAssertEqual(SmoothnessLevel.defaultValue, 70)
    }

    func testPresetLevelsAndNames() {
        XCTAssertEqual(SmoothnessPreset.subtle.level, 0)
        XCTAssertEqual(SmoothnessPreset.medium.level, 50)
        XCTAssertEqual(SmoothnessPreset.personal.level, 60)
        XCTAssertEqual(SmoothnessPreset.glide.level, 70)
        XCTAssertEqual(SmoothnessPreset.mos.level, 78)
        XCTAssertEqual(SmoothnessPreset.fluid.level, 100)
        XCTAssertEqual(SmoothnessPreset.allCases.count, 6)
        XCTAssertEqual(SmoothnessPreset.mos.displayName, "MOS")
        XCTAssertEqual(SmoothnessPreset.glide.displayName, "Glide")
    }

    func testPresetInitMatchesExactLevel() {
        XCTAssertEqual(SmoothnessPreset(level: 0), .subtle)
        XCTAssertEqual(SmoothnessPreset(level: 70), .glide)
        XCTAssertNil(SmoothnessPreset(level: 55))
    }

    func testClampsOutOfRange() {
        XCTAssertEqual(SmoothnessLevel.clamped(-10), 0)
        XCTAssertEqual(SmoothnessLevel.clamped(150), 100)
        XCTAssertEqual(SmoothnessLevel.clamped(50), 50)
    }

    func testAnchorValues() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(0), 1.5, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(50), 3.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(60), 1.8, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(70), 1.5, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(100), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(60), 0.92, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(0), 10, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(60), 120, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(100), 160, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.smoothFraction(100), 0.15, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.glideStopThreshold(70), 0.5, accuracy: 0.0001)
    }

    func testInterpolationBetweenAnchors() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(25), 2.25, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(55), 0.885, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(74), 116, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.smoothFraction(89), 0.14, accuracy: 0.0001)
    }

    func testBooleanNearestAnchor() {
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(0))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(20))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(25))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(64))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(65))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(100))
        XCTAssertFalse(SmoothnessLevel.smoothingEnabled(0))
        XCTAssertFalse(SmoothnessLevel.smoothingEnabled(54))
        XCTAssertTrue(SmoothnessLevel.smoothingEnabled(55))
        XCTAssertTrue(SmoothnessLevel.smoothingEnabled(100))
    }

    func testParametersDerivesFullSet() {
        let p = SmoothnessLevel.parameters(level: 70, multiplier: 8, invert: true)
        XCTAssertEqual(p.multiplier, 8)
        XCTAssertEqual(p.invert, true)
        XCTAssertFalse(p.momentumEnabled)
        XCTAssertTrue(p.smoothingEnabled)
        XCTAssertEqual(p.pixelsPerNotch, 100, accuracy: 0.0001)
        XCTAssertEqual(p.maxBoost, 1.5, accuracy: 0.0001)
        XCTAssertEqual(p.smoothFraction, 0.13, accuracy: 0.0001)
        XCTAssertEqual(p.glideStopThreshold, 0.5, accuracy: 0.0001)
        XCTAssertEqual(p.bounceDamping, 0.15, accuracy: 0.0001)
        XCTAssertEqual(p.reversalConfirmation, 2)
        XCTAssertEqual(p.feedGapTimeout, 0.08, accuracy: 0.0001)
        XCTAssertEqual(p.accelerationWindow, 0.05, accuracy: 0.0001)
        XCTAssertEqual(p.momentumStopThreshold, 0.1, accuracy: 0.0001)
        XCTAssertEqual(p.directionThreshold, 1.0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter SmoothnessLevelTests 2>&1 | tail -20`
Expected: FAIL — `SmoothnessPreset` não existe / `momentumOnThreshold` removido quebra compilação.

- [ ] **Step 3: Implementar `SmoothnessPreset` + curva completa**

Substitua o conteúdo de `Sources/RatTamerCore/Core/SmoothnessLevel.swift` por:

```swift
import Foundation

/// Named preset anchors on the smoothness curve. Each preset is a level; the
/// level is the single source of truth that derives all tuning parameters.
public enum SmoothnessPreset: String, CaseIterable {
    case subtle, medium, personal, glide, mos, fluid

    public var level: Double {
        switch self {
        case .subtle: return 0
        case .medium: return 50
        case .personal: return 60
        case .glide: return 70
        case .mos: return 78
        case .fluid: return 100
        }
    }

    public var displayName: String {
        switch self {
        case .subtle: return "Subtle"
        case .medium: return "Medium"
        case .personal: return "Personal"
        case .glide: return "Glide"
        case .mos: return "MOS"
        case .fluid: return "Fluid"
        }
    }

    public init?(level: Double) {
        guard let match = Self.allCases.first(where: { $0.level == level }) else { return nil }
        self = match
    }
}

/// Pure mapping from a single 0-100 smoothness level to the tuning parameters
/// of `ScrollSmoother`. The curve is piecewise-linear over six preset anchors:
/// Subtle(0), Medium(50), Personal(60), Glide(70), MOS(78), Fluid(100).
/// Continuous fields interpolate between adjacent anchors; boolean fields take
/// the nearest anchor's value (ties resolve to the higher level).
public enum SmoothnessLevel {
    public static let min: Double = 0
    public static let max: Double = 100
    public static let defaultValue: Double = SmoothnessPreset.glide.level

    public struct Anchor {
        public let level: Double
        public let momentumEnabled: Bool
        public let smoothingEnabled: Bool
        public let pixelsPerNotch: Double
        public let maxBoost: Double
        public let momentumDecay: Double
        public let smoothFraction: Double
        public let glideStopThreshold: Double

        public init(level: Double,
                    momentumEnabled: Bool,
                    smoothingEnabled: Bool,
                    pixelsPerNotch: Double,
                    maxBoost: Double,
                    momentumDecay: Double,
                    smoothFraction: Double,
                    glideStopThreshold: Double) {
            self.level = level
            self.momentumEnabled = momentumEnabled
            self.smoothingEnabled = smoothingEnabled
            self.pixelsPerNotch = pixelsPerNotch
            self.maxBoost = maxBoost
            self.momentumDecay = momentumDecay
            self.smoothFraction = smoothFraction
            self.glideStopThreshold = glideStopThreshold
        }
    }

    public static let anchors: [Anchor] = [
        Anchor(level: 0, momentumEnabled: false, smoothingEnabled: false,
               pixelsPerNotch: 10, maxBoost: 1.5, momentumDecay: 0.70,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 50, momentumEnabled: true, smoothingEnabled: false,
               pixelsPerNotch: 12, maxBoost: 3.0, momentumDecay: 0.85,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 60, momentumEnabled: true, smoothingEnabled: true,
               pixelsPerNotch: 120, maxBoost: 1.8, momentumDecay: 0.92,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 70, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 100, maxBoost: 1.5, momentumDecay: 0.85,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 78, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 132, maxBoost: 1.0, momentumDecay: 0.85,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 100, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 160, maxBoost: 1.0, momentumDecay: 0.85,
               smoothFraction: 0.15, glideStopThreshold: 0.5),
    ]

    public static func clamped(_ level: Double) -> Double {
        Swift.min(Swift.max(level, min), max)
    }

    public static func maxBoost(_ level: Double) -> Double {
        interpolate(level, keyPath: \.maxBoost)
    }

    public static func momentumDecay(_ level: Double) -> Double {
        interpolate(level, keyPath: \.momentumDecay)
    }

    public static func pixelsPerNotch(_ level: Double) -> Double {
        interpolate(level, keyPath: \.pixelsPerNotch)
    }

    public static func smoothFraction(_ level: Double) -> Double {
        interpolate(level, keyPath: \.smoothFraction)
    }

    public static func glideStopThreshold(_ level: Double) -> Double {
        interpolate(level, keyPath: \.glideStopThreshold)
    }

    public static func momentumEnabled(_ level: Double) -> Bool {
        nearest(level, keyPath: \.momentumEnabled)
    }

    public static func smoothingEnabled(_ level: Double) -> Bool {
        nearest(level, keyPath: \.smoothingEnabled)
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
            momentumDecay: momentumDecay(l),
            pixelsPerNotch: pixelsPerNotch(l),
            accelerationWindow: ScrollSmoother.defaultAccelerationWindow,
            feedGapTimeout: ScrollSmoother.defaultFeedGapTimeout,
            momentumStopThreshold: ScrollSmoother.defaultMomentumStopThreshold,
            bounceWindow: ScrollSmoother.defaultBounceWindow,
            bounceRatio: ScrollSmoother.defaultBounceRatio,
            bounceDamping: ScrollSmoother.defaultBounceDamping,
            reversalConfirmation: ScrollSmoother.defaultReversalConfirmation,
            directionThreshold: ScrollSmoother.defaultDirectionThreshold,
            smoothingEnabled: smoothingEnabled(l),
            smoothFraction: smoothFraction(l),
            glideStopThreshold: glideStopThreshold(l))
    }

    private static func interpolate(_ level: Double, keyPath: KeyPath<Anchor, Double>) -> Double {
        let l = clamped(level)
        guard let lower = anchors.last(where: { $0.level <= l }),
              let upper = anchors.first(where: { $0.level >= l }) else {
            return anchors[0][keyPath: keyPath]
        }
        if lower.level == upper.level { return lower[keyPath: keyPath] }
        let t = (l - lower.level) / (upper.level - lower.level)
        return lower[keyPath: keyPath] + (upper[keyPath: keyPath] - lower[keyPath: keyPath]) * t
    }

    private static func nearest(_ level: Double, keyPath: KeyPath<Anchor, Bool>) -> Bool {
        let l = clamped(level)
        return anchors.min { lhs, rhs in
            let ld = abs(lhs.level - l)
            let rd = abs(rhs.level - l)
            return ld < rd || (ld == rd && lhs.level > rhs.level)
        }?[keyPath: keyPath] ?? anchors[0][keyPath: keyPath]
    }
}
```

- [ ] **Step 4: Rodar os testes do core para ver passar**

Run: `swift test 2>&1 | tail -15`
Expected: PASS — todos os testes verdes (inclui `SmoothScrollSettingsTests` e `ConfigStoreTests`, que usam os helpers mantidos).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/SmoothnessLevel.swift Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift
git commit -m "feat(core): presets-âncora na curva de smoothness (Subtle/Medium/Personal/Glide/MOS/Fluid)"
```

---

### Task 2: `isCustom` compara todos os campos derivados

**Files:**
- Modify: `Sources/RatTamerCore/Core/SmoothScrollSettings.swift:25-34`
- Test: `Tests/RatTamerCoreTests/Core/SmoothScrollSettingsTests.swift`

**Interfaces:**
- Consumes: `SmoothnessLevel.parameters(level:multiplier:invert:)` (Task 1).
- Produces: `SmoothScrollSettings.isCustom: Bool` correto para divergências de glide.

- [ ] **Step 1: Adicionar testes failing**

Adicione ao final de `Tests/RatTamerCoreTests/Core/SmoothScrollSettingsTests.swift`:

```swift
    func testIsCustomFalseWhenAdvancedMatchesDerived() {
        let derived = SmoothnessLevel.parameters(level: 70, multiplier: 8, invert: false)
        let settings = SmoothScrollSettings(level: 70, advanced: derived, multiplier: 8, invert: false)
        XCTAssertFalse(settings.isCustom)
    }

    func testIsCustomTrueWhenGlideDiverges() {
        let advanced = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: false, invert: false,
                                                 maxBoost: 1.5, momentumDecay: 0.85,
                                                 smoothingEnabled: true, pixelsPerNotch: 150)
        let settings = SmoothScrollSettings(level: 70, advanced: advanced, multiplier: 8, invert: false)
        XCTAssertTrue(settings.isCustom)
    }

    func testIsCustomTrueWhenSmoothFractionOrGlideStopDiverges() {
        let advanced = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: false, invert: false,
                                                 maxBoost: 1.5, momentumDecay: 0.85,
                                                 smoothingEnabled: true, pixelsPerNotch: 100,
                                                 smoothFraction: 0.09, glideStopThreshold: 0.8)
        let settings = SmoothScrollSettings(level: 70, advanced: advanced, multiplier: 8, invert: false)
        XCTAssertTrue(settings.isCustom)
    }
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter SmoothScrollSettingsTests 2>&1 | tail -20`
Expected: FAIL — `testIsCustomTrueWhenGlideDiverges` falha (isCustom retorna false hoje).

- [ ] **Step 3: Implementar comparação completa**

Em `Sources/RatTamerCore/Core/SmoothScrollSettings.swift`, substitua o corpo de `isCustom` (linhas 25-34):

```swift
    public var isCustom: Bool {
        guard let advanced else { return false }
        guard let level else { return true }
        let derived = SmoothnessLevel.parameters(level: level,
                                                 multiplier: multiplier,
                                                 invert: invert)
        return advanced.maxBoost != derived.maxBoost
            || advanced.momentumDecay != derived.momentumDecay
            || advanced.momentumEnabled != derived.momentumEnabled
            || advanced.smoothingEnabled != derived.smoothingEnabled
            || advanced.pixelsPerNotch != derived.pixelsPerNotch
            || advanced.smoothFraction != derived.smoothFraction
            || advanced.glideStopThreshold != derived.glideStopThreshold
    }
```

- [ ] **Step 4: Rodar para ver passar**

Run: `swift test --filter SmoothScrollSettingsTests 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/SmoothScrollSettings.swift Tests/RatTamerCoreTests/Core/SmoothScrollSettingsTests.swift
git commit -m "fix(core): isCustom compara campos de glide/smoothing além de momentum"
```

---

### Task 3: Componente `HelpButton` (badge `(?)` + popover)

**Files:**
- Create: `Sources/RatTamerApp/Views/HelpButton.swift`

**Interfaces:**
- Produces (usado nas Tasks 4 e 5): `struct HelpButton: View` com `init(text: String)`, e `enum HelpTexts` com `static let` strings para cada controle.

- [ ] **Step 1: Criar o componente**

Crie `Sources/RatTamerApp/Views/HelpButton.swift`:

```swift
import SwiftUI

struct HelpButton: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            Text(text)
                .font(.caption)
                .frame(width: 240, alignment: .leading)
                .padding(10)
        }
    }
}

enum HelpTexts {
    static let smoothness = "Smoothness (0–100): intensidade geral do scroll suave. Baixo = quase nativo; médio = momentum; alto = glide MOS-style. Presets são níveis nomeados."
    static let preset = "Preset: combinação nomeada de parâmetros. Personal preserva sua configuração de uso diário; MOS reproduz o feel do app Mos."
    static let momentum = "Momentum: inércia que mantém a rolagem após parar de girar a roda."
    static let maxBoost = "Max boost: multiplicador máximo aplicado a rolagens rápidas (acima de 1 amplifica)."
    static let momentumDecay = "Momentum decay: fração da velocidade mantida por tick (120 Hz). Mais alto = desliza por mais tempo."
    static let momentumStop = "Momentum stop: velocidade abaixo da qual o momentum para."
    static let smoothing = "Smoothing (glide): suaviza o movimento com ease-out (estilo MOS). Tem prioridade sobre o momentum."
    static let smoothFraction = "Smooth fraction: fração da distância restante percorrida por tick do glide. Menor = mais suave/lento."
    static let glideStop = "Glide stop: distância abaixo da qual o glide emite o restante e para."
    static let pixelsPerNotch = "Pixels per notch: pixels base emitidos por detente da roda."
    static let accelWindow = "Accel window: janela (s) em que feeds são considerados rápidos e recebem boost."
    static let feedGap = "Feed gap timeout: tempo sem feed antes de o momentum poder correr."
    static let bounceWindow = "Bounce window: janela (s) em que deltas opostos são tratados como bounce da catraca."
    static let bounceRatio = "Bounce ratio: bounces menores que essa fração do último pulso aceito são atenuados."
    static let bounceDamping = "Bounce damping: atenuação aplicada a bounces detectados."
    static let reversalConfirmation = "Reversal confirmation: pulsos opostos consecutivos necessários para aceitar inversão de direção."
    static let directionThreshold = "Direction threshold: magnitude mínima para um feed estabelecer/atualizar a direção dominante."
}
```

- [ ] **Step 2: Build**

Run: `swift build --product RatTamer 2>&1 | tail -5`
Expected: compila sem erros.

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/Views/HelpButton.swift
git commit -m "feat(ui): componente HelpButton (?) com popover e textos de ajuda"
```

---

### Task 4: Aba Advanced — Picker de presets, `setLevel`→`applyLive`, invariante, reset

**Files:**
- Modify: `Sources/RatTamerApp/Views/AdvancedTabView.swift`
- Consumes: `SmoothnessPreset` (Task 1), `HelpButton`/`HelpTexts` (Task 3).

**Interfaces:**
- Produces: `AdvancedTabView.setLevel` deriva os 7 campos sensíveis e chama `applyLive()`; `applyLive` grava `smoothScrollAdvanced = storedAdvanced`; Picker de presets com opção "Custom"; botão "Reset to default".

- [ ] **Step 1: `setLevel` deriva tudo e usa `applyLive`**

Em `Sources/RatTamerApp/Views/AdvancedTabView.swift`, substitua `setLevel` (linhas 164-172):

```swift
    private func setLevel(_ newValue: Double) {
        guard loaded else { return }
        level = newValue
        let p = SmoothnessLevel.parameters(level: newValue, multiplier: 8, invert: false)
        maxBoost = p.maxBoost
        momentumDecay = p.momentumDecay
        momentumEnabled = p.momentumEnabled
        smoothingEnabled = p.smoothingEnabled
        pixelsPerNotch = p.pixelsPerNotch
        smoothFraction = p.smoothFraction
        glideStopThreshold = p.glideStopThreshold
        applyLive()
    }
```

- [ ] **Step 2: Corrigir invariante do `applyLive`**

Substitua em `applyLive` (linha 238) `config.smoothScrollAdvanced = currentParams()` por `config.smoothScrollAdvanced = storedAdvanced`:

```swift
    private func applyLive() {
        var config = AppModel.shared.configStore.load()
        config.smoothScrollEnabled = enabled
        config.smoothScrollLevel = level
        config.smoothScrollAdvanced = storedAdvanced
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.updateSmoothParameters(currentParams())
    }
```

- [ ] **Step 3: Trocar botões Glide/Mos-like e marcadores por Picker + Reset**

Substitua o bloco de marcadores + botões (linhas 66-80) por:

```swift
                    HStack(spacing: 6) {
                        Picker("Preset", selection: presetSelection) {
                            ForEach(SmoothnessPreset.allCases, id: \.self) { preset in
                                Text(preset.displayName).tag(SmoothnessPreset?.some(preset))
                            }
                            Text("Custom").tag(SmoothnessPreset?.none)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 140)
                        HelpButton(text: HelpTexts.preset)
                        Button("Reset to default") { resetToDefault() }
                            .controlSize(.small)
                        Spacer()
                    }
```

- [ ] **Step 4: Remover `presetLabel` e os presets hardcoded**

Remova:
- a função `presetLabel` (linhas 157-162);
- as funções `applyGlidePreset` e `applyMosPreset` (linhas 174-196).

- [ ] **Step 5: Adicionar `presetSelection` e `resetToDefault`**

Adicione junto a `setLevel`:

```swift
    private var presetSelection: Binding<SmoothnessPreset?> {
        Binding(
            get: {
                guard let level else { return nil }
                return SmoothnessPreset(level: level)
            },
            set: { newPreset in
                guard let newPreset else { return }
                setLevel(newPreset.level)
            }
        )
    }

    private func resetToDefault() {
        guard loaded else { return }
        setLevel(SmoothnessLevel.defaultValue)
    }
```

- [ ] **Step 6: Ajuda `(?)` nos sliders + range do Pixels per notch**

Mude o range do slider "Pixels per notch" (linha 106) de `1...40` para `1...200`. Substitua `sliderRow` (linhas 143-155) por esta versão com `help: String` e `HelpButton(text: help)` após o título:

```swift
    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           help: String) -> some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            HelpButton(text: help)
            Slider(value: value, in: range, step: step)
                .onChange(of: value.wrappedValue) { _, _ in customChange() }
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 52, alignment: .trailing)
        }
    }
```

E atualize cada chamada para incluir `help:` (todos os `sliderRow` do painel avançado):
- Momentum: `sliderRow("Max boost", ..., help: HelpTexts.maxBoost)`, `sliderRow("Momentum decay", ..., help: HelpTexts.momentumDecay)`, `sliderRow("Momentum stop", ..., help: HelpTexts.momentumStop)`.
- Glide: `sliderRow("Smooth fraction", ..., help: HelpTexts.smoothFraction)`, `sliderRow("Glide stop", ..., help: HelpTexts.glideStop)`.
- Feed: `sliderRow("Pixels per notch", ..., help: HelpTexts.pixelsPerNotch)`, `sliderRow("Accel window (s)", ..., help: HelpTexts.accelWindow)`, `sliderRow("Feed gap timeout (s)", ..., help: HelpTexts.feedGap)`.
- Bounce: `sliderRow("Bounce window (s)", ..., help: HelpTexts.bounceWindow)`, `sliderRow("Bounce ratio", ..., help: HelpTexts.bounceRatio)`, `sliderRow("Bounce damping", ..., help: HelpTexts.bounceDamping)`.
- Direção: `sliderRow("Direction threshold", ..., help: HelpTexts.directionThreshold)`.
- Toggles Momentum e Smoothing (glide): adicione `HelpButton(text: HelpTexts.momentum)` e `HelpButton(text: HelpTexts.smoothing)` ao lado de cada `Toggle`.
- Stepper Reversal confirmation: adicione `HelpButton(text: HelpTexts.reversalConfirmation)` ao lado.
- Slider "Smoothness": adicione `HelpButton(text: HelpTexts.smoothness)` no `HStack` do rótulo.

- [ ] **Step 7: Build**

Run: `swift build --product RatTamer 2>&1 | tail -5`
Expected: compila sem erros.

- [ ] **Step 8: Verificação manual**

Run: `swift build -c release --scratch-path "$TMPDIR/rattamer-build" && $TMPDIR/rattamer-build/arm64-apple-macosx/release/RatTamer` (com MOS fechado). Verifique:
1. Selecionar cada preset no Picker atualiza os toggles/sliders avançados (ex. Medium → Momentum ON / Smoothing OFF; Glide → Momentum OFF / Smoothing ON).
2. Arrastar o slider de Smoothness **não treme** a rolagem (flicker corrigido) e o Picker vai para "Custom".
3. "Reset to default" restaura Glide (nível 70).
4. Clicar em cada `(?)` abre o popover com a explicação.
Encerre o app após testar (`osascript -e 'tell application "RatTamer" to quit'`).

- [ ] **Step 9: Commit**

```bash
git add Sources/RatTamerApp/Views/AdvancedTabView.swift
git commit -m "feat(ui): aba Advanced usa Picker de presets, applyLive por tick e ajuda (?)"
```

---

### Task 5: General tab — Picker de presets + Reset no `SmoothScrollRow`

**Files:**
- Modify: `Sources/RatTamerApp/Views/GeneralTabView.swift` (`SmoothScrollRow`, linhas 303-387)
- Consumes: `SmoothnessPreset` (Task 1), `HelpButton`/`HelpTexts` (Task 3).

**Interfaces:**
- Produces: `SmoothScrollRow` com `Picker` de presets + "Custom", slider + `HelpButton(text: HelpTexts.smoothness)`, botão "Reset to default".

- [ ] **Step 1: Substituir marcadores por Picker + Reset**

Em `Sources/RatTamerApp/Views/GeneralTabView.swift`, dentro do `if enabled` do `SmoothScrollRow`, substitua o bloco dos marcadores (linhas 338-344) por:

```swift
                        HStack(spacing: 6) {
                            Picker("Preset", selection: presetSelection) {
                                ForEach(SmoothnessPreset.allCases, id: \.self) { preset in
                                    Text(preset.displayName).tag(SmoothnessPreset?.some(preset))
                                }
                                Text("Custom").tag(SmoothnessPreset?.none)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 140)
                            HelpButton(text: HelpTexts.preset)
                            Button("Reset to default") { resetToDefault() }
                                .controlSize(.small)
                            Spacer()
                        }
```

E adicione `HelpButton(text: HelpTexts.smoothness)` no `HStack` que contém `Text("Smoothness")`.

- [ ] **Step 2: Remover `presetLabel`**

Remova a função `presetLabel` (linhas 352-357) do `SmoothScrollRow`.

- [ ] **Step 3: Adicionar `presetSelection` e `resetToDefault`**

Adicione junto a `setLevel`:

```swift
    private var presetSelection: Binding<SmoothnessPreset?> {
        Binding(
            get: {
                guard let level else { return nil }
                return SmoothnessPreset(level: level)
            },
            set: { newPreset in
                guard let newPreset else { return }
                setLevel(newPreset.level)
            }
        )
    }

    private func resetToDefault() {
        guard loaded else { return }
        setLevel(SmoothnessLevel.defaultValue)
    }
```

- [ ] **Step 4: Build**

Run: `swift build --product RatTamer 2>&1 | tail -5`
Expected: compila sem erros.

- [ ] **Step 5: Verificação manual**

Run o app (mesma forma da Task 4). Verifique: Picker de presets aparece no General; selecionar preset e reset funcionam; `(?)` abre popover.

- [ ] **Step 6: Commit**

```bash
git add Sources/RatTamerApp/Views/GeneralTabView.swift
git commit -m "feat(ui): General tab com Picker de presets e reset no SmoothScrollRow"
```

---

### Task 6: RatTest — presets unificados + `applyLevel` completo

**Files:**
- Modify: `Sources/RatTest/RatTestView.swift`
- Consumes: `SmoothnessPreset`/`SmoothnessLevel` (Task 1).

**Interfaces:**
- Produces: painel "Smooth Scroll" do RatTest com os 6 presets, `applyLevel` derivando os 7 campos sensíveis, range de Pixels per notch `1...200`, estados iniciais derivados do nível default (70).

- [ ] **Step 1: Estados iniciais derivados do default**

Em `Sources/RatTest/RatTestView.swift`, substitua as linhas 12-14 por:

```swift
    @State private var maxBoost: Double = SmoothnessLevel.maxBoost(SmoothnessLevel.defaultValue)
    @State private var momentumDecay: Double = SmoothnessLevel.momentumDecay(SmoothnessLevel.defaultValue)
    @State private var momentumEnabled: Bool = SmoothnessLevel.momentumEnabled(SmoothnessLevel.defaultValue)
```

E substitua as linhas 24-26 por:

```swift
    @State private var smoothingEnabled: Bool = SmoothnessLevel.smoothingEnabled(SmoothnessLevel.defaultValue)
    @State private var smoothFraction: Double = SmoothnessLevel.smoothFraction(SmoothnessLevel.defaultValue)
    @State private var glideStopThreshold: Double = SmoothnessLevel.glideStopThreshold(SmoothnessLevel.defaultValue)
```

E substitua a linha 15 (`pixelsPerNotch: Double = ScrollSmoother.defaultPixelsPerNotch`) por:

```swift
    @State private var pixelsPerNotch: Double = SmoothnessLevel.pixelsPerNotch(SmoothnessLevel.defaultValue)
```

- [ ] **Step 2: Botões de presets → 6 presets**

Substitua o bloco de botões (linhas 154-161) por:

```swift
            HStack(spacing: 6) {
                Text("Presets").frame(width: 160, alignment: .leading)
                ForEach(SmoothnessPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) { applyPreset(preset) }
                }
            }
```

- [ ] **Step 3: `applyPreset` + `applyLevel` completo**

Substitua `applyLevel` (linhas 252-261) por:

```swift
    private func applyPreset(_ preset: SmoothnessPreset) {
        applyLevel(preset.level)
    }

    private func applyLevel(_ level: Double) {
        syncedLevel = level
        let p = SmoothnessLevel.parameters(level: level,
                                           multiplier: engine.wheelMultiplier ?? 8,
                                           invert: false)
        maxBoost = p.maxBoost
        momentumDecay = p.momentumDecay
        momentumEnabled = p.momentumEnabled
        smoothingEnabled = p.smoothingEnabled
        pixelsPerNotch = p.pixelsPerNotch
        smoothFraction = p.smoothFraction
        glideStopThreshold = p.glideStopThreshold
        applySmoothParams()
    }
```

- [ ] **Step 4: Remover `applyGlidePreset`/`applyMosPreset` e alargar range**

Remova `applyGlidePreset` e `applyMosPreset` (linhas 263-287). Mude o range do slider "Pixels per notch" (linha 170) de `1...40` para `1...200`.

- [ ] **Step 5: Build e verificação manual**

Run: `swift build --product RatTest 2>&1 | tail -5` → compila. Depois `nohup .build/debug/RatTest > /tmp/ratest.log 2>&1 &` (MOS e RatTamer fechados) e verifique: os 6 presets aplicam valores coerentes; "Custom" ao mexer em slider avancado; scroll suave com o preset selecionado.

- [ ] **Step 6: Commit**

```bash
git add Sources/RatTest/RatTestView.swift
git commit -m "feat(ratest): presets unificados e applyLevel com curva completa"
```

---

## Self-Review

**Spec coverage:**
- Curva com âncoras de presets → Task 1. ✓
- `isCustom` completo (glide) → Task 2. ✓
- Seletor de presets + slider (General e Advanced) → Tasks 4-5. ✓
- Ajuda `(?)` estilo macOS em cada controle → Tasks 3-5. ✓
- Reset to default (Glide 70) → Tasks 4-5. ✓
- Nomes em inglês (Subtle/Medium/Personal/Glide/MOS/Fluid) → Task 1 (`displayName`), Tasks 4-6. ✓
- Personal preserva valores exatos (momentum ON + smoothing ON, 120/1.8/0.92) → Task 1 âncora 60. ✓
- Default Glide (70) / `defaultValue = 70` → Task 1. ✓
- Flicker: `setLevel` → `applyLive` na Advanced → Task 4. ✓
- Invariante `applyLive` (storedAdvanced) → Task 4 Step 2. ✓
- Migração (config com advanced → Custom; nil → Glide) → sem código (fallback já resolve); coberto pela Task 1 (`defaultValue`). ✓
- RatTest alinhado → Task 6. ✓

**Placeholder scan:** nenhum TBD/TODO; todos os passos de código têm o conteúdo real. ✓

**Type consistency:** `SmoothnessPreset` (String, CaseIterable, `level`, `displayName`, `init?(level:)`) usado de forma idêntica nas Tasks 4-6; helpers `SmoothnessLevel.maxBoost/momentumDecay/momentumEnabled/pixelsPerNotch/smoothFraction/glideStopThreshold/smoothingEnabled` definidos na Task 1 e consumidos consistentemente; `applyLive`/`storedAdvanced` já existiam com esses nomes na AdvancedTabView. ✓
