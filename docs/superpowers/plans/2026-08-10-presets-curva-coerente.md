# Presets: Curva Coerente de Âncoras Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir os valores das 6 âncoras de `SmoothnessLevel` por uma progressão monotônica e coerente (px/notch crescente, maxBoost decrescente de Smooth em diante, smoothFraction decrescente nos presets de glide), mantendo nomes, níveis, default e UI intactos.

**Architecture:** A mudança é pontual em `SmoothnessLevel.anchors` (fonte da verdade única — General/Advanced/RatTest derivam tudo via helpers). O teste atualiza as expectativas e ganha um teste novo de monotonicidade que trava a propriedade. Os textos de ajuda em `HelpButton.swift` hardcodam os valores antigos e precisam acompanhar.

**Tech Stack:** Swift, SwiftUI, AppKit (macOS 14+), XCTest (RatTamerCore).

## Global Constraints

- Nomes/presets/níveis NÃO mudam: Native=0, Smooth=35, Glide=60, Mos=80, Flow=90, Fluid=100; default = Mos (80).
- Novas âncoras (TABELA EXATA): Native(48, boost 1.0, decay 0.70), Smooth(55, 2.5, 0.88), Glide(90, 1.6, 0.85), Mos(115, 1.2, 0.85), Flow(140, 1.1, 0.85), Fluid(165, 1.0, 0.85); smoothFraction Glide=0.14, Mos=0.13, Flow=0.12, Fluid=0.11, demais 0.13; glideStopThreshold 0.5 em todas.
- Booleanos de momentum/smoothing NÃO mudam (momentum só em Smooth; glide a partir de Glide).
- `momentumDecay` das âncoras sem momentum = 0.85 (inertes).
- Propriedade a preservar (teste novo): px/notch não-decrescente; maxBoost não-crescente do nível 35 em diante; smoothFraction não-crescente nos presets de glide.

---

### Task 1: Âncoras coerentes + testes + textos de ajuda

**Files:**
- Modify: `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift` (testAnchorValues, testInterpolationBetweenAnchors, testParametersDerivesFullSet + novo testAnchorsAreMonotonic)
- Modify: `Sources/RatTamerCore/Core/SmoothnessLevel.swift` (apenas o array `anchors`)
- Modify: `Sources/RatTamerApp/Views/HelpButton.swift` (strings `HelpTexts.preset` e `HelpTexts.pixelsPerNotch`)

**Interfaces:**
- Consumes: nada (valores são auto-contidos em `SmoothnessLevel.anchors`).
- Produces: nenhuma assinatura nova. Âncoras atualizadas alimentam os helpers já existentes (`maxBoost(_:)`, `momentumDecay(_:)`, `pixelsPerNotch(_:)`, `smoothFraction(_:)`, `glideStopThreshold(_:)`, `momentumEnabled(_:)`, `smoothingEnabled(_:)`, `parameters(level:multiplier:invert:)`).

- [ ] **Step 1: Atualizar os testes (failing)**

Em `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`, substitua o corpo de `testAnchorValues` (linhas 35-47) por:

```swift
    func testAnchorValues() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(35), 2.5, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(60), 1.6, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(80), 1.2, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(100), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(60), 0.85, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(0), 48, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(80), 115, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(100), 165, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.smoothFraction(90), 0.12, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.glideStopThreshold(80), 0.5, accuracy: 0.0001)
    }
```

Substitua o corpo de `testInterpolationBetweenAnchors` (linhas 49-55) por:

```swift
    func testInterpolationBetweenAnchors() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(17.5), 1.75, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(17.5), 0.79, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(70), 102.5, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.smoothFraction(85), 0.125, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(95), 152.5, accuracy: 0.0001)
    }
```

Em `testParametersDerivesFullSet`, substitua as linhas 83-84 por:

```swift
        XCTAssertEqual(p.pixelsPerNotch, 115, accuracy: 0.0001)
        XCTAssertEqual(p.maxBoost, 1.2, accuracy: 0.0001)
```

E adicione um teste novo de monotonicidade logo após `testInterpolationBetweenAnchors`:

```swift
    func testAnchorsAreMonotonic() {
        let levels = SmoothnessLevel.anchors.map(\.level)
        XCTAssertEqual(levels, levels.sorted(), "levels must be ascending, got \(levels)")
        let pixelsPerNotch = SmoothnessLevel.anchors.map(\.pixelsPerNotch)
        XCTAssertEqual(pixelsPerNotch, pixelsPerNotch.sorted(),
                       "pixelsPerNotch must be non-decreasing, got \(pixelsPerNotch)")
        let appliedMaxBoost = SmoothnessLevel.anchors.filter { $0.level >= 35 }.map(\.maxBoost)
        XCTAssertEqual(appliedMaxBoost, appliedMaxBoost.sorted(by: >),
                       "maxBoost must be non-increasing from Smooth (level 35), got \(appliedMaxBoost)")
        let appliedSmoothFraction = SmoothnessLevel.anchors.filter { $0.smoothingEnabled }.map(\.smoothFraction)
        XCTAssertEqual(appliedSmoothFraction, appliedSmoothFraction.sorted(by: >),
                       "smoothFraction must be non-increasing on glide presets, got \(appliedSmoothFraction)")
    }
```

E um teste que trava o `momentumDecay` inerte dos glide presets (âncoras com momentum OFF):

```swift
    func testGlidePresetsHaveInertMomentumDecay() {
        let glideDecays = SmoothnessLevel.anchors
            .filter { !$0.momentumEnabled && $0.smoothingEnabled }
            .map(\.momentumDecay)
        XCTAssertFalse(glideDecays.isEmpty, "expected at least one glide preset")
        XCTAssertEqual(Set(glideDecays), [0.85],
                       "glide presets must share the inert momentumDecay 0.85, got \(glideDecays)")
    }
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter SmoothnessLevelTests 2>&1 | tail -25`
Expected: FAIL — `testAnchorValues` e `testInterpolationBetweenAnchors` com valores antigos (ex. `XCTAssertEqual failed: 2.2 != 2.5`).

- [ ] **Step 3: Implementar as novas âncoras**

Em `Sources/RatTamerCore/Core/SmoothnessLevel.swift`, substitua TODO o array `anchors` (linhas 79-90) por:

```swift
    public static let anchors: [Anchor] = [
        Anchor(level: 0, momentumEnabled: false, smoothingEnabled: false,
               pixelsPerNotch: 48, maxBoost: 1.0, momentumDecay: 0.70,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 35, momentumEnabled: true, smoothingEnabled: false,
               pixelsPerNotch: 55, maxBoost: 2.5, momentumDecay: 0.88,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 60, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 90, maxBoost: 1.6, momentumDecay: 0.85,
               smoothFraction: 0.14, glideStopThreshold: 0.5),
        Anchor(level: 80, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 115, maxBoost: 1.2, momentumDecay: 0.85,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 90, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 140, maxBoost: 1.1, momentumDecay: 0.85,
               smoothFraction: 0.12, glideStopThreshold: 0.5),
        Anchor(level: 100, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 165, maxBoost: 1.0, momentumDecay: 0.85,
               smoothFraction: 0.11, glideStopThreshold: 0.5),
    ]
```

- [ ] **Step 4: Atualizar os textos de ajuda**

Em `Sources/RatTamerApp/Views/HelpButton.swift`, substitua `HelpTexts.preset` (linha 27) por:

```swift
    static let preset = "Preset: a named combination of every smoothing parameter. Native = macOS factory behavior with no Logi Options+ — a raw pass-through at ~48 px/detent, no boost, no bounce filter, no invert. Smooth = classic momentum (boost 2.5, decay 0.88). Glide = near-Mac-trackpad feel (90 px/notch). Mos = the Mos app's defaults (115 px/notch, ~3.0 duration). Flow = 140 px/notch. Fluid = 165 px/notch, the strongest glide."
```

E substitua `HelpTexts.pixelsPerNotch` (linha 35) por:

```swift
    static let pixelsPerNotch = "Pixels per notch: base pixels emitted per wheel detent (deltaV == multiplier). Native ≈ 48 (~3 macOS lines); Mos = 115; the curve interpolates 48 → 165."
```

- [ ] **Step 5: Rodar os testes para ver passar**

Run: `swift test 2>&1 | tail -15`
Expected: PASS — todos os testes verdes (inclui `SmoothnessLevelTests` com os novos valores e o teste de monotonicidade). Nenhum outro teste usa os valores antigos (verificado: `132` em ConfigStoreTests/ScrollSmootherTests constrói Parameters de teste customizados, independentes das âncoras).

- [ ] **Step 6: Build sem warnings**

Run: `swift build --product RatTamer 2>&1 | tail -5`
Expected: compila sem erros nem warnings.

- [ ] **Step 7: Commit**

```bash
git add Sources/RatTamerCore/Core/SmoothnessLevel.swift Sources/RatTamerApp/Views/HelpButton.swift Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift
git commit -m "feat(core): âncoras de presets coerentes (px/notch 48→165, boost e smoothFraction monotônicos)"
```
