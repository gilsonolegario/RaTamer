# Presets Native/Smooth/Glide/Mos/Flow/Fluid + Pass-through Nativo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir a grade de presets por referências reais (macOS de fábrica, momentum clássico, quase-trackpad, defaults do Mos), com o preset Native como pass-through real no `ScrollSmoother.feed`.

**Architecture:** Mudanças em `SmoothnessLevel.swift` (enum + âncoras + defaultValue), `ScrollSmoother.feed` (early-return de pass-through quando momentum e smoothing estão off) e nos testes. UI (Picker, `PresetMarkers`, RatTest) consome `SmoothnessPreset.allCases` / `SmoothnessLevel.defaultValue` genericamente — atualiza sozinha.

**Tech Stack:** Swift 5.9, SPM (`swift test`), macOS 14+.

## Global Constraints

- Roster (6): **Native(0) · Smooth(35) · Glide(60) · Mos(80) · Flow(90) · Fluid(100)** — copiar verbatim do spec.
- Display name do preset 80 = **"Mos"** (não "MOS").
- Âncoras: Native(0, mom off, smo off, ppn 48, boost 1.0, decay 0.70, sf 0.13, gst 0.5) · Smooth(35, on, off, 45, 2.2, 0.88, 0.13, 0.5) · Glide(60, off, on, 110, 1.2, 0.85, 0.14, 0.5) · Mos(80, off, on, 132, 1.0, 0.85, 0.13, 0.5) · Flow(90, off, on, 145, 1.0, 0.85, 0.14, 0.5) · Fluid(100, off, on, 170, 1.0, 0.85, 0.15, 0.5).
- `defaultValue` = 80 (Mos). `smoothingStartLevel` derivado = 47.5.
- Pass-through: `feed` retorna `notches × ppn` (sem boost, sem `stabilized()`, sem `applyInvert`) quando `!momentumEnabled && !smoothingEnabled`.
- Regra da curva inalterada: contínuos interpolam linearmente; booleanos = âncora mais próxima (empate → maior nível).
- Nenhuma migração de config (nível salvo continua válido).
- Não adicionar comentários novos além dos já existentes; apenas atualizar doc comments que citam presets antigos.

---

### Task 1: Preset enum + defaultValue

**Files:**
- Test: `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`
- Modify: `Sources/RatTamerCore/Core/SmoothnessLevel.swift:5-44`

**Interfaces:**
- Consumes: nada novo.
- Produces: `SmoothnessPreset` com casos `native, smooth, glide, mos, flow, fluid`, `level` 0/35/60/80/90/100, `displayName` Native/Smooth/Glide/Mos/Flow/Fluid, `init?(level:)` inalterado. `SmoothnessLevel.defaultValue == 80`.

- [ ] **Step 1: Escrever os testes falhantes**

Em `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`, substituir `testDefaults`, `testPresetLevelsAndNames` e `testPresetInitMatchesExactLevel` por:

```swift
    func testDefaults() {
        XCTAssertEqual(SmoothnessLevel.min, 0)
        XCTAssertEqual(SmoothnessLevel.max, 100)
        XCTAssertEqual(SmoothnessLevel.defaultValue, 80)
    }

    func testPresetLevelsAndNames() {
        XCTAssertEqual(SmoothnessPreset.native.level, 0)
        XCTAssertEqual(SmoothnessPreset.smooth.level, 35)
        XCTAssertEqual(SmoothnessPreset.glide.level, 60)
        XCTAssertEqual(SmoothnessPreset.mos.level, 80)
        XCTAssertEqual(SmoothnessPreset.flow.level, 90)
        XCTAssertEqual(SmoothnessPreset.fluid.level, 100)
        XCTAssertEqual(SmoothnessPreset.allCases.count, 6)
        XCTAssertEqual(SmoothnessPreset.mos.displayName, "Mos")
        XCTAssertEqual(SmoothnessPreset.glide.displayName, "Glide")
    }

    func testPresetInitMatchesExactLevel() {
        XCTAssertEqual(SmoothnessPreset(level: 0), .native)
        XCTAssertEqual(SmoothnessPreset(level: 80), .mos)
        XCTAssertNil(SmoothnessPreset(level: 55))
    }
```

- [ ] **Step 2: Rodar para confirmar que falha**

Run: `swift test --filter SmoothnessLevelTests 2>&1 | tail -20`
Expected: FALHA (casos atuais são `native, easy, soft, personal, flow, fluid`; `defaultValue` é 78).

- [ ] **Step 3: Implementar o enum e o defaultValue**

Em `Sources/RatTamerCore/Core/SmoothnessLevel.swift`, substituir o corpo do enum `SmoothnessPreset` (linhas 5-34) por:

```swift
public enum SmoothnessPreset: String, CaseIterable {
    case native, smooth, glide, mos, flow, fluid

    public var level: Double {
        switch self {
        case .native: return 0
        case .smooth: return 35
        case .glide: return 60
        case .mos: return 80
        case .flow: return 90
        case .fluid: return 100
        }
    }

    public var displayName: String {
        switch self {
        case .native: return "Native"
        case .smooth: return "Smooth"
        case .glide: return "Glide"
        case .mos: return "Mos"
        case .flow: return "Flow"
        case .fluid: return "Fluid"
        }
    }

    public init?(level: Double) {
        guard let match = Self.allCases.first(where: { $0.level == level }) else { return nil }
        self = match
    }
}
```

E a linha do `defaultValue`:

```swift
    public static let defaultValue: Double = SmoothnessPreset.mos.level
```

- [ ] **Step 4: Rodar para confirmar que passa**

Run: `swift test --filter SmoothnessLevelTests 2>&1 | tail -20`
Expected: PASS (testAnchorValues etc. ainda passam — não dependem do enum).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/SmoothnessLevel.swift Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift
git commit -m "feat(core): presets Native/Smooth/Glide/Mos/Flow/Fluid e defaultValue 80"
```

---

### Task 2: Tabela de âncoras

**Files:**
- Test: `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`
- Modify: `Sources/RatTamerCore/Core/SmoothnessLevel.swift:75-94`

**Interfaces:**
- Consumes: `SmoothnessPreset` da Task 1.
- Produces: `SmoothnessLevel.anchors` com as 6 âncoras; `smoothingStartLevel == 47.5`; interpolações (ex. `maxBoost(17.5) == 1.6`, `pixelsPerNotch(70) == 121`, `smoothFraction(85) == 0.135`, `pixelsPerNotch(95) == 157.5`).

- [ ] **Step 1: Escrever os testes falhantes**

Em `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`, substituir `testAnchorValues`, `testInterpolationBetweenAnchors`, `testBooleanNearestAnchor`, `testSmoothingStartLevel` e `testParametersDerivesFullSet` por:

```swift
    func testAnchorValues() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(35), 2.2, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(60), 1.2, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(80), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(100), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(60), 0.85, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(0), 48, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(80), 132, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(100), 170, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.smoothFraction(90), 0.14, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.glideStopThreshold(80), 0.5, accuracy: 0.0001)
    }

    func testInterpolationBetweenAnchors() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(17.5), 1.6, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(17.5), 0.79, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(70), 121, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.smoothFraction(85), 0.135, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(95), 157.5, accuracy: 0.0001)
    }

    func testBooleanNearestAnchor() {
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(0))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(17))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(17.5))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(40))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(47.5))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(60))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(100))
        XCTAssertFalse(SmoothnessLevel.smoothingEnabled(0))
        XCTAssertFalse(SmoothnessLevel.smoothingEnabled(47))
        XCTAssertTrue(SmoothnessLevel.smoothingEnabled(47.5))
        XCTAssertTrue(SmoothnessLevel.smoothingEnabled(100))
    }

    func testSmoothingStartLevel() {
        XCTAssertEqual(SmoothnessLevel.smoothingStartLevel, 47.5, accuracy: 0.0001)
        XCTAssertFalse(SmoothnessLevel.smoothingEnabled(47))
        XCTAssertTrue(SmoothnessLevel.smoothingEnabled(47.5))
    }

    func testParametersDerivesFullSet() {
        let p = SmoothnessLevel.parameters(level: 80, multiplier: 8, invert: true)
        XCTAssertEqual(p.multiplier, 8)
        XCTAssertEqual(p.invert, true)
        XCTAssertFalse(p.momentumEnabled)
        XCTAssertTrue(p.smoothingEnabled)
        XCTAssertEqual(p.pixelsPerNotch, 132, accuracy: 0.0001)
        XCTAssertEqual(p.maxBoost, 1.0, accuracy: 0.0001)
        XCTAssertEqual(p.smoothFraction, 0.13, accuracy: 0.0001)
        XCTAssertEqual(p.glideStopThreshold, 0.5, accuracy: 0.0001)
        XCTAssertEqual(p.bounceDamping, 0.15, accuracy: 0.0001)
        XCTAssertEqual(p.reversalConfirmation, 2)
        XCTAssertEqual(p.feedGapTimeout, 0.08, accuracy: 0.0001)
        XCTAssertEqual(p.accelerationWindow, 0.05, accuracy: 0.0001)
        XCTAssertEqual(p.momentumStopThreshold, 0.1, accuracy: 0.0001)
        XCTAssertEqual(p.directionThreshold, 1.0, accuracy: 0.0001)
    }
```

- [ ] **Step 2: Rodar para confirmar que falha**

Run: `swift test --filter SmoothnessLevelTests 2>&1 | tail -20`
Expected: FALHA (âncoras atuais são 0/58/68/78/88/100).

- [ ] **Step 3: Implementar as âncoras**

Em `Sources/RatTamerCore/Core/SmoothnessLevel.swift`, substituir o array `anchors` (linhas 75-94) por:

```swift
    public static let anchors: [Anchor] = [
        Anchor(level: 0, momentumEnabled: false, smoothingEnabled: false,
               pixelsPerNotch: 48, maxBoost: 1.0, momentumDecay: 0.70,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 35, momentumEnabled: true, smoothingEnabled: false,
               pixelsPerNotch: 45, maxBoost: 2.2, momentumDecay: 0.88,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 60, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 110, maxBoost: 1.2, momentumDecay: 0.85,
               smoothFraction: 0.14, glideStopThreshold: 0.5),
        Anchor(level: 80, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 132, maxBoost: 1.0, momentumDecay: 0.85,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 90, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 145, maxBoost: 1.0, momentumDecay: 0.85,
               smoothFraction: 0.14, glideStopThreshold: 0.5),
        Anchor(level: 100, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 170, maxBoost: 1.0, momentumDecay: 0.85,
               smoothFraction: 0.15, glideStopThreshold: 0.5),
    ]
```

Atualizar os doc comments que citam as âncoras antigas (linha ~38 e linha ~129 de `smoothingStartLevel`):
- Linha ~38: `Native(0), Easy(58), Soft(68), Personal(78), Flow(88), Fluid(100)` → `Native(0), Smooth(35), Glide(60), Mos(80), Flow(90), Fluid(100)`.
- Linha ~129: `Soft→Personal = 73` → `Smooth→Glide = 47.5`.

- [ ] **Step 4: Rodar para confirmar que passa**

Run: `swift test --filter SmoothnessLevelTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/SmoothnessLevel.swift Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift
git commit -m "feat(core): âncoras Native/Smooth/Glide/Mos/Flow/Fluid (Mos ppn 132, smoothing start 47.5)"
```

---

### Task 3: Pass-through nativo no `feed` + testes do ScrollSmoother

**Files:**
- Test: `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`
- Modify: `Sources/RatTamerCore/Core/ScrollSmoother.swift:113-145`

**Interfaces:**
- Consumes: nada novo (usa `Parameters.momentumEnabled`/`smoothingEnabled`/`pixelsPerNotch`).
- Produces: `feed` com early-return de pass-through quando ambos os flags estão off; comportamento dos parâmetros padrão (ambos off) muda de "boost+bounce+invert" para "pass-through puro".

- [ ] **Step 1: Escrever os testes do bypass (falhantes)**

Em `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`, adicionar no fim da classe (após `testCustomMomentumDecayIsHonored`):

```swift
    func testNativeBypassHasNoBoost() {
        let s = make()
        _ = feed(s, at: 1000)
        let fast = feed(s, at: 1000.01)
        XCTAssertEqual(fast, 10, accuracy: 0.0001)
    }

    func testNativeBypassIgnoresInvert() {
        let s = make(invert: true)
        XCTAssertEqual(feed(s, at: 1000), 10, accuracy: 0.0001)
    }

    func testNativeBypassSkipsBounceDamping() {
        let s = make()
        _ = feed(s, at: 1000)
        let reverse = feed(s, deltaV: -3, at: 1000.01)
        XCTAssertEqual(reverse, -2.0, accuracy: 0.0001)
    }

    func testNativeBypassDoesNotSeedMomentum() {
        let s = make()
        _ = feed(s, at: 1000)
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.2)), 0)
    }
```

- [ ] **Step 2: Rodar para confirmar que falham**

Run: `swift test --filter ScrollSmootherTests 2>&1 | tail -20`
Expected: FALHA (boost aplica no `fast`, invert aplica, bounce amortece `-3` para `-0.78`).

- [ ] **Step 3: Implementar o pass-through no `feed`**

Em `Sources/RatTamerCore/Core/ScrollSmoother.swift`, no início de `feed` (após calcular `raw`, antes da chamada a `stabilized`):

```swift
        let notches = Double(movement.deltaV) / Double(max(1, parameters.multiplier))
        let raw = notches * parameters.pixelsPerNotch
        if !parameters.momentumEnabled && !parameters.smoothingEnabled {
            return raw
        }
```

- [ ] **Step 4: Migrar os testes existentes de boost/bounce/invert para `momentumEnabled: true`**

Em `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`, trocar o helper usado pelos testes de moldagem. As chamadas `make()`/`make(invert:)` nas seguintes funções devem passar a usar `make(momentum: true)` / `make(momentum: true, invert: true)`:
- `testFeedFastArrivalAccelerates` (linha 31)
- `testFeedSlowArrivalIsPrecise` (linha 39)
- `testDetentBounceReverseDeltaIsDamped` (linha 87)
- `testRealReversalPassesThrough` (linha 96)
- `testBounceAfterWindowPassesNormally` (linha 104)
- `testBounceDoesNotFlipDirection` (linha 112)
- `testReversalRequiresTwoConsecutiveOppositePulses` (linha 121)
- `testInvertFlipsSign` (linha 76) → `make(momentum: true, invert: true)`
- `testCustomMaxBoostIsHonored` (linha 140) → o `Parameters` inicializa com `momentumEnabled: true`

Não alterar `testFeedConvertsDeltaToPixels`, `testFeedScalesByMultiplier`, `testMomentumDisabledReturnsZero`, `testCustomPixelsPerNotchIsHonored` (continuam válidos como bypass: retornam `notches × ppn`).

- [ ] **Step 5: Rodar a suite completa para confirmar**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 318 tests, with 0 failures (0 unexpected)` (314 + 4 novos testes de bypass).

- [ ] **Step 6: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSmoother.swift Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift
git commit -m "feat(core): pass-through nativo no feed quando momentum e smoothing off"
```

---

### Task 4: Verificação completa

**Files:**
- Verificar: `SmoothScrollSettingsTests.swift` (usa `SmoothnessLevel.maxBoost(50)` etc., auto-consistente com a curva nova).
- Verificar: UI (`GeneralTabView.swift`, `AdvancedTabView.swift`, `RatTestView.swift`) consome `SmoothnessPreset.allCases` / `SmoothnessLevel.defaultValue` genericamente.

**Interfaces:**
- Consumes: Tasks 1-3.

- [ ] **Step 1: Rodar a suite completa**

Run: `swift test 2>&1 | tail -5`
Expected: `Executed 318 tests, with 0 failures (0 unexpected)`.

- [ ] **Step 2: Build de todos os produtos**

Run: `swift build 2>&1 | tail -10`
Expected: compila sem erros (RatTamer, RatDiagnose, RatTest, IconGen), sem warnings novos.

- [ ] **Step 3: Commit (se algo foi corrigido nos Steps acima)**

```bash
git add -A
git commit -m "test: alinha testes com a grade final"
```
(Se nada mudou, pular.)

- [ ] **Step 4: Relatar para verificação manual**

Relatar ao usuário:
- `swift test` 100% verde.
- Verificação manual: Picker mostra Native/Smooth/Glide/Mos/Flow/Fluid; **Mos** aplica ppn 132/boost 1.0/sf 0.13 (momentum off, smoothing on); **Native** rola ~48px/detente sem moldar; Reset restaura 80; marcadores na barra nas 6 posições com smoothing start em 47.5; RatTest com 6 botões novos.
