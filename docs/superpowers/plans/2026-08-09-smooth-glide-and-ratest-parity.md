# Smooth Glide no ScrollSmoother + Paridade do RatTest — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar um modo de suavização "glide por alvo com ease-out" ao `ScrollSmoother` (opt-in, sem regressão no legado) e levar o RatTest à paridade com o app final (níveis + presets, catálogo completo de ações, DPI cycle, thumb wheel, modo da roda).

**Architecture:** O `ScrollSmoother` ganha 3 parâmetros novos (`smoothingEnabled`, `smoothFraction`, `glideStopThreshold`) e 2 campos de estado (`target`, `current`, `carry`). No modo glide, `feed` acumula no alvo e retorna 0; `tick` desliza a saída em direção ao alvo com ease-out exponencial + mínimo de 1px + compensação de erro fracionário, parando via epsilon. O modo legado (boost + momentum) permanece byte-a-byte idêntico quando `smoothingEnabled == false`. O RatTest ganha UI wiring usando serviços HID++ já existentes.

**Tech Stack:** Swift 6, SwiftPM puro (sem novas dependências), XCTest, SwiftUI, CoreGraphics/CGEvent, HID++ (HiResWheel 0x2121, SmartShift 0x2110/0x009D, AdjustableDPI 0x2201).

## Global Constraints

- `ScrollSmoother` continua **puro e clock-injected**: sem timers, sem IO, sem DispatchQueue interna — o caller injeta `Date` (via `ScrollSmootherCoordinator`).
- `smoothingEnabled` default **false**; com ele desligado, NENHUM comportamento existente pode mudar (os 284+ testes atuais devem continuar verdes sem edição).
- Valores sãos vindos do reuse report (`docs/superpowers/specs/2026-08-09-smooth-glide-and-ratest-parity-v1.reuse.md`):
  - Default glide: `pixelsPerNotch 120 / maxBoost 1.5 / smoothFraction 0.13 / glideStopThreshold 0.5 / accelerationWindow 0.05`.
  - Preset Mos-like: `pixelsPerNotch 132 / maxBoost 1.0 / smoothFraction 0.13 / glideStopThreshold 0.5 / accelerationWindow 0.05`.
- `smoothFraction` faixa sã: `0.02...0.15` (acima de ~0.2 o glide vira "quase instantâneo").
- `ScrollSmoother.Parameters` **não é Codable** — novos campos entram só no init (com default) e no `Equatable` sintetizado; não há decode legado a tocar.
- Rodar testes: `swift test` (suíte completa precisa ficar verde).
- Build do RatTest: `swift build --target RatTest`.
- Sem comentários no código-fonte a menos que o usuário peça.

---

### Task 1: Parâmetros e estado do glide no ScrollSmoother

**Files:**
- Modify: `Sources/RatTamerCore/Core/ScrollSmoother.swift`
- Test: `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`

**Interfaces:**
- Consumes: `ScrollSmoother.Parameters` existente (init com defaults em `Sources/RatTamerCore/Core/ScrollSmoother.swift:23-51`).
- Produces: `ScrollSmoother.Parameters` com `smoothingEnabled: Bool = false`, `smoothFraction: Double = ScrollSmoother.defaultSmoothFraction`, `glideStopThreshold: Double = ScrollSmoother.defaultGlideStopThreshold`; constantes `ScrollSmoother.defaultSmoothFraction = 0.13` e `ScrollSmoother.defaultGlideStopThreshold = 0.5`; estado privado `target`, `current`, `carry` zerados em `reset()`.

- [ ] **Step 1: Escrever o teste dos defaults e do reset**

Adicione em `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift` (final da classe):

```swift
    func testGlideParameterDefaults() {
        let p = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: false, invert: false)
        XCTAssertEqual(p.smoothingEnabled, false)
        XCTAssertEqual(p.smoothFraction, ScrollSmoother.defaultSmoothFraction)
        XCTAssertEqual(p.glideStopThreshold, ScrollSmoother.defaultGlideStopThreshold)
    }
```

- [ ] **Step 2: Rodar o teste para ver falhar**

Run: `swift test --filter testGlideParameterDefaults 2>&1 | tail -5`
Expected: FAIL — `smoothingEnabled`, `smoothFraction`, `glideStopThreshold`, `defaultSmoothFraction`, `defaultGlideStopThreshold` não existem.

- [ ] **Step 3: Implementar os parâmetros, constantes e estado**

Em `Sources/RatTamerCore/Core/ScrollSmoother.swift`:

Adicione ao struct `Parameters` (após `public var directionThreshold: Double`):

```swift
        /// When true, feed accumulates into a target and tick glides the
        /// output toward it with an exponential ease-out (MOS-style).
        public var smoothingEnabled: Bool
        /// Fraction of the remaining distance approached per tick (120 Hz).
        public var smoothFraction: Double
        /// Distance below which the glide emits the remainder and stops.
        public var glideStopThreshold: Double
```

Atualize o `init` (após `self.directionThreshold = directionThreshold`):

```swift
            self.smoothingEnabled = smoothingEnabled
            self.smoothFraction = smoothFraction
            self.glideStopThreshold = glideStopThreshold
```

Atualize a assinatura do `init` (após o default de `directionThreshold`):

```swift
                    directionThreshold: Double = ScrollSmoother.defaultDirectionThreshold,
                    smoothingEnabled: Bool = false,
                    smoothFraction: Double = ScrollSmoother.defaultSmoothFraction,
                    glideStopThreshold: Double = ScrollSmoother.defaultGlideStopThreshold) {
```

Adicione as constantes (após `defaultDirectionThreshold`, linha ~78):

```swift
    /// Glide ease-out fraction per tick at 120 Hz (≈ Mos Duration 3.0).
    public static let defaultSmoothFraction: Double = 0.13
    /// Consensus stop epsilon from SmoothScroll / LinearMouse.
    public static let defaultGlideStopThreshold: Double = 0.5
```

Adicione o estado (após `private var lastAcceptedMagnitude: Double = 0`):

```swift
    private var target: Double = 0
    private var current: Double = 0
    private var carry: Double = 0
```

Atualize `reset()` (após `lastAcceptedMagnitude = 0`):

```swift
        target = 0
        current = 0
        carry = 0
```

- [ ] **Step 4: Rodar o teste para ver passar**

Run: `swift test --filter testGlideParameterDefaults 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Rodar a suíte inteira (regressão)**

Run: `swift test 2>&1 | grep -E "Executed .* tests|failed" | tail -3`
Expected: todos verdes (nenhuma edição em testes existentes).

- [ ] **Step 6: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSmoother.swift Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift
git commit -m "feat(smooth): add glide params and state to ScrollSmoother"
```

---

### Task 2: `feed` no modo glide — acumula no alvo, retorna 0

**Files:**
- Modify: `Sources/RatTamerCore/Core/ScrollSmoother.swift`
- Test: `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`

**Interfaces:**
- Consumes: `target`/`current`/`carry` (Task 1); `stabilized(_:at:)` interno.
- Produces: `stabilized(_:at:) -> (pixels: Double, isBounce: Bool, reversed: Bool, accepted: Bool)` — novo retorno; `feed` no modo glide retorna `0` e acumula em `target`.

- [ ] **Step 1: Escrever os testes do feed glide**

Adicione em `ScrollSmootherTests.swift`:

```swift
    private func makeGlide(multiplier: UInt8 = 15,
                           fraction: Double = 0.13,
                           stop: Double = 0.5,
                           pixelsPerNotch: Double = 10) -> ScrollSmoother {
        ScrollSmoother(parameters: .init(multiplier: multiplier,
                                         momentumEnabled: false,
                                         invert: false,
                                         smoothingEnabled: true,
                                         smoothFraction: fraction,
                                         glideStopThreshold: stop,
                                         pixelsPerNotch: pixelsPerNotch))
    }

    func testGlideFeedReturnsZeroAndAccumulates() {
        let s = makeGlide()
        XCTAssertEqual(feed(s, at: 1000), 0)
        XCTAssertGreaterThan(s.tick(at: Date(timeIntervalSince1970: 1000.02)), 0)
    }

    func testGlideSameDirectionAccumulates() {
        let s = makeGlide(fraction: 0.5, stop: 0.01)
        _ = feed(s, at: 1000)
        _ = feed(s, at: 1000.01)  // fast arrival → boost
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.02)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertGreaterThan(total, 20)  // 10 + boosted > 10
    }

    func testGlideBounceDoesNotAccumulate() {
        let s = makeGlide(fraction: 0.5, stop: 0.01)
        _ = feed(s, at: 1000)            // +10 target
        _ = feed(s, deltaV: -3, at: 1000.01)  // bounce → not accumulated
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.02)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertEqual(total, 10, accuracy: 1.0)
    }

    func testGlideReversalResetsAndAccumulates() {
        let s = makeGlide(fraction: 0.5, stop: 0.01)
        _ = feed(s, deltaV: 15, at: 1000)      // +10
        _ = feed(s, deltaV: 15, at: 1000.01)   // +boosted
        _ = s.tick(at: Date(timeIntervalSince1970: 1000.02))  // emit some +
        _ = feed(s, deltaV: -15, at: 1000.03)  // opposite, needs confirmation
        _ = feed(s, deltaV: -15, at: 1000.04)  // accepted reversal → reset + target neg
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.05)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertLessThan(total, -10)
    }
```

- [ ] **Step 2: Rodar os testes para ver falhar**

Run: `swift test --filter "testGlide(Feed|SameDirection|Bounce|Reversal)" 2>&1 | tail -8`
Expected: FAIL — glide mode ainda não implementado (feed retorna pixels, tick retorna 0).

- [ ] **Step 3: Implementar o feed do glide + enriquecer `stabilized`**

Em `Sources/RatTamerCore/Core/ScrollSmoother.swift`, substitua o corpo de `feed` (linhas 96-114) por:

```swift
    @discardableResult
    public func feed(_ movement: WheelMovement, at now: Date) -> Double {
        let notches = Double(movement.deltaV) / Double(max(1, parameters.multiplier))
        let raw = notches * parameters.pixelsPerNotch
        let (stabilizedPixels, isBounce, reversed, accepted) = stabilized(raw, at: now)
        var pixels = stabilizedPixels
        if let last = lastFeedAt {
            let dt = now.timeIntervalSince(last)
            if dt > 0 && dt < parameters.accelerationWindow {
                let t = dt / parameters.accelerationWindow
                let boost = 1 + (parameters.maxBoost - 1) * (1 - t)
                pixels *= boost
            }
        }
        lastFeedAt = now
        if parameters.smoothingEnabled {
            if reversed {
                current = 0
                target = 0
                carry = 0
            }
            if accepted && !isBounce {
                target += pixels
            }
            return 0
        }
        if !isBounce {
            velocity = pixels
        }
        return applyInvert(pixels)
    }
```

Substitua a assinatura e o corpo de `stabilized` (linhas 116-163) por:

```swift
    private func stabilized(_ raw: Double, at now: Date)
        -> (pixels: Double, isBounce: Bool, reversed: Bool, accepted: Bool) {
        var pixels = raw
        let sign = raw > 0 ? 1 : (raw < 0 ? -1 : 0)
        let directionBefore = direction
        guard direction != 0, sign != 0 else {
            if sign != 0, abs(pixels) >= parameters.directionThreshold {
                direction = sign
                lastAcceptedAt = now
                lastAcceptedMagnitude = abs(pixels)
            }
            oppositeCount = 0
            return (pixels, false, false, directionBefore == 0 || sign == directionBefore)
        }
        if sign == direction {
            oppositeCount = 0
            if abs(pixels) >= parameters.directionThreshold {
                direction = sign
                lastAcceptedAt = now
                lastAcceptedMagnitude = abs(pixels)
            }
            return (pixels, false, false, true)
        }
        if let last = lastAcceptedAt, now.timeIntervalSince(last) < parameters.bounceWindow {
            if oppositeCount + 1 >= parameters.reversalConfirmation {
                oppositeCount = 0
                direction = sign
                lastAcceptedAt = now
                lastAcceptedMagnitude = abs(pixels)
                return (pixels, false, true, true)
            }
            oppositeCount += 1
            if abs(pixels) < lastAcceptedMagnitude * parameters.bounceRatio {
                pixels *= parameters.bounceDamping
                return (pixels, true, false, false)
            }
            return (pixels, false, false, false)
        }
        oppositeCount = 0
        direction = sign
        lastAcceptedAt = now
        lastAcceptedMagnitude = abs(pixels)
        return (pixels, false, true, true)
    }
```

> Nota: a ramificação `return (pixels, false, false, directionBefore == 0 || sign == directionBefore)` só ocorre quando `direction == 0 || sign == 0`. Se `direction == 0` e `sign != 0`, `directionBefore == 0` → `accepted = true`. Se `sign == 0` (zero delta), `accepted = false` → não acumula zero. O modo legado não usa `accepted`/`reversed` — `if !isBounce { velocity = pixels }` permanece idêntico.

- [ ] **Step 4: Rodar os testes do glide + a suíte legada**

Run: `swift test --filter "testGlide" 2>&1 | tail -8`
Expected: PASS (feed/accumulate/bounce/reversal).

Run: `swift test 2>&1 | grep -E "Executed .* tests|failed" | tail -3`
Expected: todos verdes — a suíte legada não mudou de comportamento.

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSmoother.swift Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift
git commit -m "feat(smooth): glide feed accumulates into target and returns 0"
```

---

### Task 3: `tick` no modo glide — ease-out + mínimo 1px + carry + parada

**Files:**
- Modify: `Sources/RatTamerCore/Core/ScrollSmoother.swift`
- Test: `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`

**Interfaces:**
- Consumes: `target`/`current`/`carry`, `glideStopThreshold`, `smoothFraction` (Tasks 1-2).
- Produces: `tick` no modo glide emite `remaining * smoothFraction` (com mínimo de 1px e compensação de erro fracionário) ou, quando `abs(remaining) <= glideStopThreshold`, emite o restante e zera o alvo.

> **Nota de execução (update 2026-08-09):** A implementação de `tick`/`glideTick` foi antecipada e commitada na Task 2 (`f1f02ba`), porque os testes da Task 2 exercitam a emissão do tick. Esta task agora é: adicionar os 5 testes abaixo (que devem passar de primeira, pois a implementação já existe), rodar a suíte e commitar. NÃO re-implemente o tick. Se o `makeGlide` helper já existe no arquivo de testes, use-o.

- [ ] **Step 1: Adicionar os testes do tick glide**

Adicione em `ScrollSmootherTests.swift` (o helper `makeGlide` já existe — use `makeGlide(fraction: 0.5, stop: 0.01, pixelsPerNotch: 16)` etc., seguindo a ordem de argumentos da declaração):

```swift
    func testGlideTickEmitsFractionOfRemaining() {
        let s = makeGlide(fraction: 0.5, stop: 0.01, pixelsPerNotch: 16)
        _ = feed(s, at: 1000)
        let t0 = Date(timeIntervalSince1970: 1000.02)
        XCTAssertEqual(s.tick(at: t0), 8, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(1.0 / 120)), 4, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(2.0 / 120)), 2, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(3.0 / 120)), 1, accuracy: 0.0001)
    }

    func testGlideConvergesAndStops() {
        let s = makeGlide(fraction: 0.5, stop: 0.01, pixelsPerNotch: 16)
        _ = feed(s, at: 1000)
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.02)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertEqual(total, 16, accuracy: 1.0)
        XCTAssertEqual(s.tick(at: t.addingTimeInterval(1.0 / 120)), 0)
    }

    func testGlideStopThresholdEmitsRemainder() {
        let s = makeGlide(fraction: 0.5, stop: 2.0, pixelsPerNotch: 16)
        _ = feed(s, at: 1000)
        let t0 = Date(timeIntervalSince1970: 1000.02)
        XCTAssertEqual(s.tick(at: t0), 8, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(1.0 / 120)), 4, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(2.0 / 120)), 2, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(3.0 / 120)), 2, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(4.0 / 120)), 0)
    }

    func testGlideMinOnePixel() {
        let s = makeGlide(fraction: 0.13, stop: 0.01, pixelsPerNotch: 1)
        _ = feed(s, at: 1000)
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.02)), 1)
    }

    func testGlideParamsIgnoredWhenSmoothingDisabled() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15,
                                                 momentumEnabled: false,
                                                 invert: false,
                                                 smoothFraction: 0.99,
                                                 glideStopThreshold: 0.99))
        _ = feed(s, at: 1000)
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.02)), 0)
    }
```

- [ ] **Step 2: Rodar os testes para confirmar que passam**

Run: `swift test --filter "testGlide(Tick|Converges|StopThreshold|MinOnePixel|ParamsIgnored)" 2>&1 | tail -8`
Expected: PASS — a implementação já está commitada; o teste cobre exatamente o código do `glideTick` revisado.

- [ ] **Step 3: (skip — implementação já commitada na Task 2, `f1f02ba`)**

O corpo de `tick`/`glideTick` já está em `Sources/RatTamerCore/Core/ScrollSmoother.swift`. Verifique apenas que `glideTick` corresponde ao código abaixo (se divergir, corrija):

```swift
    @discardableResult
    public func tick(at now: Date) -> Double {
        if parameters.smoothingEnabled {
            return glideTick()
        }
        guard parameters.momentumEnabled else { return 0 }
        if let last = lastFeedAt, now.timeIntervalSince(last) < parameters.feedGapTimeout {
            return 0
        }
        guard abs(velocity) > parameters.momentumStopThreshold else {
            velocity = 0
            return 0
        }
        let out = velocity
        velocity *= parameters.momentumDecay
        return applyInvert(out)
    }

    private func glideTick() -> Double {
        var remaining = target - current
        if abs(remaining) <= parameters.glideStopThreshold {
            target = 0
            current = 0
            carry = 0
            return applyInvert(remaining)
        }
        var step = remaining * parameters.smoothFraction
        if abs(step) < 1 && abs(remaining) >= 1 {
            step = remaining > 0 ? 1 : -1
        }
        carry += step - step.rounded()
        step = step.rounded()
        if abs(carry) >= 1 {
            let whole = carry > 0 ? 1.0 : -1.0
            step += whole
            carry -= whole
        }
        current += remaining * parameters.smoothFraction
        return applyInvert(step)
    }
```

> Nota: `remaining` é recalculado de `target - current` a cada chamada; `current` avança pelo valor real (`remaining * smoothFraction`) para que `remaining` sempre reflita a distância que falta — nunca perdendo a fração por arredondamento.

- [ ] **Step 4: Rodar os testes do glide + a suíte legada**

Run: `swift test --filter "testGlide" 2>&1 | tail -8`
Expected: PASS.

Run: `swift test 2>&1 | grep -E "Executed .* tests|failed" | tail -3`
Expected: todos verdes.

- [ ] **Step 5: Commit**

```bash
git add Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift
git commit -m "test(smooth): cover glide tick emission, convergence and stop"
```

---

### Task 4: Mover `ActionCatalog` para o Core e expor catálogo completo

**Files:**
- Move: `Sources/RatTamerApp/ActionCatalog.swift` → `Sources/RatTamerCore/ActionCatalog.swift`
- Modify: `Sources/RatTamerCore/ActionCatalog.swift` (tornar `public`)
- Test: novo `Tests/RatTamerCoreTests/Core/ActionCatalogTests.swift`

**Interfaces:**
- Consumes: `ButtonAction` (Core).
- Produces: `public enum ActionCatalog` com `public static func title(for:) -> String`, `public static func icon(for:) -> String`, `public static var allActions: [ButtonAction]` (todas as system actions + `.click(3)`/`.click(4)` + `.gesture(default)` + `.cycleDPI` + `.disabled`).

- [ ] **Step 1: Escrever o teste do catálogo**

Crie `Tests/RatTamerCoreTests/Core/ActionCatalogTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class ActionCatalogTests: XCTestCase {
    func testAllActionsCoversSystemCatalog() {
        for action in ActionCatalog.allActions {
            XCTAssertFalse(ActionCatalog.title(for: action).isEmpty)
        }
        XCTAssertTrue(ActionCatalog.allActions.contains(.cycleDPI))
        XCTAssertTrue(ActionCatalog.allActions.contains(.click(button: 3)))
        XCTAssertTrue(ActionCatalog.allActions.contains(.click(button: 4)))
    }
}
```

- [ ] **Step 2: Rodar o teste para ver falhar**

Run: `swift test --filter ActionCatalogTests 2>&1 | tail -5`
Expected: FAIL — `ActionCatalog` não existe no módulo RatTamerCore.

- [ ] **Step 3: Mover e tornar público**

Mova o arquivo com `git mv`:

```bash
git mv Sources/RatTamerApp/ActionCatalog.swift Sources/RatTamerCore/ActionCatalog.swift
```

No arquivo movido:
- Troque `enum ActionCatalog` por `public enum ActionCatalog`.
- Troque os três `static func` por `public static func`.
- Adicione a constante `allActions` (use `ButtonAction.system("...")` para as 12 system actions, os clicks, gesture default e cycleDPI):

```swift
    public static var allActions: [ButtonAction] {
        let systems: [String] = [
            "missionControl", "appExpose", "showDesktop", "launchpad",
            "previousSpace", "nextSpace", "spotlight", "lockScreen",
            "volumeUp", "volumeDown", "volumeUpSmall", "volumeDownSmall", "volumeMute",
        ]
        let defaultGesture = GestureConfig(
            click: .disabled,
            up: .system("missionControl"),
            down: .system("showDesktop"),
            left: .click(button: 3),
            right: .click(button: 4))
        var actions: [ButtonAction] = [.disabled]
        actions.append(contentsOf: systems.map { .system($0) })
        actions.append(.click(button: 3))
        actions.append(.click(button: 4))
        actions.append(.gesture(defaultGesture))
        actions.append(.cycleDPI)
        return actions
    }
```

- [ ] **Step 4: Rodar o teste + build completo**

Run: `swift test --filter ActionCatalogTests 2>&1 | tail -5`
Expected: PASS.

Run: `swift build 2>&1 | tail -3`
Expected: build completo verde (o app continua usando `ActionCatalog` normalmente).

- [ ] **Step 5: Commit**

```bash
git add -A Sources/RatTamerApp Sources/RatTamerCore Tests
git commit -m "refactor(core): move ActionCatalog to Core and expose allActions"
```

---

### Task 5: Serviços do RatTestEngine — SmartShift, DPI, thumb wheel

**Files:**
- Modify: `Sources/RatTest/RatTestEngine.swift`

**Interfaces:**
- Consumes: `AdjustableDPI` (0x2201), `SmartShiftControls` (0x2110/0x009D), `ScrollWheelTap`, `ThumbWheel`, `HiResWheel.getInfo().hasSwitch`, `DPICycle` — padrões copiados de `Sources/RatTamerApp/EngineController.swift:135-178`.
- Produces (novos membros públicos de `RatTestEngine`):
  - `private(set) var hasSmartShift: Bool`
  - `private(set) var wheelModeDescription: String`
  - `private(set) var currentDPI: UInt16?`
  - `private(set) var dpiCycleValues: [UInt16]`
  - `var onThumbWheel: ((ThumbWheel.Direction) -> Void)?`
  - `func setWheelMode(ratcheted: Bool)`
  - `func refreshWheelModeStatus()`
  - `func cycleDPI()`
  - `func refreshDPI()`

> Nota de testabilidade: `RatTestEngine` hardcoda `HIDPPSession` (não-injetável). O wiring é validado por build + teste manual no hardware — não há teste unitário aqui. As partes puras já são cobertas por `DPICycleTests` (existentes).

- [ ] **Step 1: Adicionar campos de serviço e callbacks**

Em `RatTestEngine.swift`, adicione após `private(set) var wheelMultiplier: UInt8?`:

```swift
    private var smartShiftService: SmartShiftControls?
    private var dpiService: AdjustableDPI?
    private var thumbWheelTap: ScrollWheelTap?
    private(set) var hasSmartShift = false
    private(set) var wheelModeDescription = "unknown"
    private(set) var currentDPI: UInt16?
    private(set) var dpiCycleValues: [UInt16] = []
    var onThumbWheel: ((ThumbWheel.Direction) -> Void)?
```

- [ ] **Step 2: Descobrir os serviços em `start()`**

Dentro do `do` de `start()`, após o bloco do `HiResWheel` (após `self.wheelMultiplier = ...`), adicione:

```swift
            if let ssIndex = try? session.getFeatureIndex(
                featureID: SmartShiftControls.enhancedFeatureID, deviceIndex: deviceIndex
            ) {
                self.smartShiftService = SmartShiftControls(session: session,
                                                            deviceIndex: deviceIndex,
                                                            featureIndex: ssIndex,
                                                            featureID: SmartShiftControls.enhancedFeatureID)
            } else if let ssIndex = try? session.getFeatureIndex(
                featureID: SmartShiftControls.featureID, deviceIndex: deviceIndex
            ) {
                self.smartShiftService = SmartShiftControls(session: session,
                                                            deviceIndex: deviceIndex,
                                                            featureIndex: ssIndex)
            }
            if let dpiIndex = try? session.getFeatureIndex(
                featureID: AdjustableDPI.featureID, deviceIndex: deviceIndex
            ) {
                self.dpiService = AdjustableDPI(session: session,
                                                deviceIndex: deviceIndex,
                                                featureIndex: dpiIndex)
            }
```

- [ ] **Step 3: Iniciar o tap de thumb wheel**

Após `startLoopThread(monitor: monitor)` e antes de `onStatus?("Connected...")`, adicione:

```swift
            let tap = ScrollWheelTap(
                shouldIntercept: { _ in true },
                onNotch: { [weak self] direction in self?.onThumbWheel?(direction) }
            )
            self.thumbWheelTap = tap
            if AXIsProcessTrusted() {
                tap.start()
                refreshWheelModeStatus()
                refreshDPI()
            }
```

- [ ] **Step 4: Implementar os métodos públicos**

Adicione ao final da classe `RatTestEngine`:

```swift
    func setWheelMode(ratcheted: Bool) {
        guard let service = smartShiftService else { return }
        let status = SmartShiftStatus.status(for: ratcheted ? .ratcheted : .freespin, sensitivity: 0)
        try? service.setRatchetControlMode(status: status)
        refreshWheelModeStatus()
    }

    func refreshWheelModeStatus() {
        guard let service = smartShiftService,
              let status = try? service.getRatchetControlMode() else {
            wheelModeDescription = hasSmartShift ? "unavailable" : "no SmartShift"
            return
        }
        wheelModeDescription = status.wheelMode == 1 ? "free-spin" : "ratcheted"
    }

    func refreshDPI() {
        guard let service = dpiService else { return }
        let sensors = (try? service.getSensorCount()) ?? 0
        guard sensors > 0 else { return }
        currentDPI = (try? service.getSensorDpi(sensor: 0))?.dpi
        if let valid = try? service.getSensorDpiList(sensor: 0), !valid.isEmpty {
            dpiCycleValues = DPICycle.recommendedPresets(from: valid)
        } else if let current = currentDPI {
            dpiCycleValues = DPICycle.defaultPresets
            _ = current
        }
    }

    func cycleDPI() {
        guard let service = dpiService, let current = currentDPI,
              let next = DPICycle.next(current: current, presets: dpiCycleValues) else { return }
        try? service.setSensorDpi(sensor: 0, dpi: next)
        refreshDPI()
    }
```

- [ ] **Step 5: Parar o tap em `stop()`**

Em `stop()`, antes de `session = nil`, adicione:

```swift
        thumbWheelTap?.stop()
        thumbWheelTap = nil
```

- [ ] **Step 6: Build e commit**

Run: `swift build --target RatTest 2>&1 | tail -3`
Expected: build verde.

```bash
git add Sources/RatTest/RatTestEngine.swift
git commit -m "feat(ratest): wire SmartShift, DPI and thumb wheel services into engine"
```

---

### Task 6: RatTestView — níveis, presets e controles de smoothing

**Files:**
- Modify: `Sources/RatTest/RatTestView.swift`

**Interfaces:**
- Consumes: `ScrollSmoother.Parameters` com os campos novos (Task 1-3), `SmoothnessLevel`, `engine.setSmoothScroll/setSmoothParameters` (existentes).
- Produces: seção Smooth Scroll com slider de nível + presets (Discreta/Média/Fluida/Glide sã/Mos-like), toggle "Smoothing (glide)", sliders "Smooth fraction" (`0.02...0.15`) e "Glide stop" (`0.0...2.0`); `currentParams` inclui os 3 campos novos; sincronização nível↔sliders crus.

- [ ] **Step 1: Adicionar estado novo**

Em `RatTestView.swift`, após `@State private var directionThreshold...`:

```swift
    @State private var smoothingEnabled = false
    @State private var smoothFraction: Double = ScrollSmoother.defaultSmoothFraction
    @State private var glideStopThreshold: Double = ScrollSmoother.defaultGlideStopThreshold
    @State private var syncedLevel: Double?
```

- [ ] **Step 2: Adicionar nível + presets + smoothing no painel**

Dentro de `smoothPanel`, logo após o `Toggle("Enabled (diverts wheel to HID++)"...` e o texto do Multiplier, insira:

```swift
            HStack {
                Text("Level").frame(width: 160, alignment: .leading)
                Slider(value: levelBinding, in: 0...100, step: 1)
                Text(levelLabel).font(.caption.monospaced()).frame(width: 56, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text("Presets").frame(width: 160, alignment: .leading)
                Button("Discreta") { applyLevel(0) }
                Button("Média") { applyLevel(50) }
                Button("Fluida") { applyLevel(100) }
                Button("Glide sã") { applyGlidePreset() }
                Button("Mos-like") { applyMosPreset() }
            }
```

Após o `Toggle("Momentum"...` e antes de `sliderRow("Pixels per notch"...`, insira:

```swift
            Toggle("Smoothing (glide)", isOn: $smoothingEnabled)
                .onChange(of: smoothingEnabled) { _, _ in applySmoothParams() }
            sliderRow("Smooth fraction", value: $smoothFraction, range: 0.02...0.15, step: 0.01)
            sliderRow("Glide stop", value: $glideStopThreshold, range: 0.0...2.0, step: 0.1)
```

- [ ] **Step 3: Adicionar os helpers de binding/presets/nível**

Adicione ao final da `RatTestView`:

```swift
    private var levelBinding: Binding<Double> {
        Binding(
            get: {
                if let syncedLevel { return syncedLevel }
                return SmoothnessLevel.defaultValue
            },
            set: { applyLevel($0) }
        )
    }

    private var levelLabel: String {
        if let syncedLevel { return String(format: "%.0f", syncedLevel) }
        return "custom"
    }

    private func applyLevel(_ level: Double) {
        syncedLevel = level
        let p = SmoothnessLevel.parameters(level: level,
                                           multiplier: engine.wheelMultiplier ?? 8,
                                           invert: false)
        maxBoost = p.maxBoost
        momentumDecay = p.momentumDecay
        momentumEnabled = p.momentumEnabled
        applySmoothParams()
    }

    private func applyGlidePreset() {
        syncedLevel = nil
        smoothingEnabled = true
        pixelsPerNotch = 120
        maxBoost = 1.5
        smoothFraction = 0.13
        glideStopThreshold = 0.5
        accelerationWindow = 0.05
        applySmoothParams()
    }

    private func applyMosPreset() {
        syncedLevel = nil
        smoothingEnabled = true
        pixelsPerNotch = 132
        maxBoost = 1.0
        smoothFraction = 0.13
        glideStopThreshold = 0.5
        accelerationWindow = 0.05
        applySmoothParams()
    }
```

- [ ] **Step 4: Sincronizar sliders crus → nível "custom" e incluir campos novos em `currentParams`**

Em cada `sliderRow` do painel que já tem `.onChange(of: value.wrappedValue)`, o handler deve também descelecionar o nível. Crie um helper e use nos `onChange` dos sliders crus:

```swift
    private func syncRawSliderChange() {
        if syncedLevel != nil { syncedLevel = nil }
        applySmoothParams()
    }
```

Substitua em `sliderRow` o `.onChange(of: value.wrappedValue) { _, _ in applySmoothParams() }` por `.onChange(of: value.wrappedValue) { _, _ in syncRawSliderChange() }`.

Em `currentParams`, adicione os campos novos (após `directionThreshold:`):

```swift
            directionThreshold: directionThreshold,
            smoothingEnabled: smoothingEnabled,
            smoothFraction: smoothFraction,
            glideStopThreshold: glideStopThreshold)
```

- [ ] **Step 5: Build**

Run: `swift build --target RatTest 2>&1 | tail -3`
Expected: build verde.

- [ ] **Step 6: Commit**

```bash
git add Sources/RatTest/RatTestView.swift
git commit -m "feat(ratest): smoothness level slider, presets and glide controls"
```

---

### Task 7: RatTestView — catálogo completo de ações

**Files:**
- Modify: `Sources/RatTest/RatTestView.swift`

**Interfaces:**
- Consumes: `ActionCatalog.allActions` + `ActionCatalog.title(for:)` (Task 4).
- Produces: picker de ações por botão com todas as actions do catálogo.

- [ ] **Step 1: Substituir `actionOptions`**

Em `RatTestView.swift`, substitua o corpo de `actionOptions` por:

```swift
    private var actionOptions: some View {
        ForEach(ActionCatalog.allActions, id: \.self) { action in
            Text(ActionCatalog.title(for: action)).tag(action)
        }
    }
```

- [ ] **Step 2: Build**

Run: `swift build --target RatTest 2>&1 | tail -3`
Expected: build verde.

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTest/RatTestView.swift
git commit -m "feat(ratest): full action catalog in button picker"
```

---

### Task 8: RatTestView — seções Wheel Mode, DPI e Thumb Wheel

**Files:**
- Modify: `Sources/RatTest/RatTestView.swift`

**Interfaces:**
- Consumes: `engine.hasSmartShift`, `engine.wheelModeDescription`, `engine.setWheelMode(ratcheted:)`, `engine.currentDPI`, `engine.dpiCycleValues`, `engine.cycleDPI()`, `engine.refreshDPI()`, `engine.onThumbWheel` (Task 5), `ThumbWheel.Direction` (Core).
- Produces: novas seções no corpo da view.

- [ ] **Step 1: Adicionar estado do thumb wheel**

Em `RatTestView.swift`, após `@State private var syncedLevel: Double?`:

```swift
    @State private var thumbWheelLog: [String] = []
```

- [ ] **Step 2: Wire do callback no `onAppear`**

Em `body`/`.onAppear`, após `engine.onRelease = ...`:

```swift
            engine.onThumbWheel = { direction in
                DispatchQueue.main.async {
                    let label = direction == .left ? "left" : "right"
                    thumbWheelLog.append(label)
                    if thumbWheelLog.count > 20 { thumbWheelLog.removeFirst(thumbWheelLog.count - 20) }
                }
            }
```

- [ ] **Step 3: Adicionar as seções ao corpo**

Após o `Divider()`/`Text("Smooth Scroll")` + `smoothPanel`, adicione ao `VStack` (antes do fechamento):

```swift
            Divider()
            Text("Wheel Mode").font(.headline)
            wheelModePanel
            Divider()
            Text("DPI").font(.headline)
            dpiPanel
            Divider()
            Text("Thumb Wheel").font(.headline)
            thumbWheelPanel
```

- [ ] **Step 4: Implementar os painéis**

```swift
    private var wheelModePanel: some View {
        Group {
            if engine.hasSmartShift {
                HStack {
                    Text("Mode: \(engine.wheelModeDescription)")
                        .frame(width: 200, alignment: .leading)
                    Button("Ratchet") { engine.setWheelMode(ratcheted: true) }
                    Button("Free-spin") { engine.setWheelMode(ratcheted: false) }
                    Spacer()
                }
            } else {
                Text("Device has no SmartShift.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dpiPanel: some View {
        HStack {
            Text("Current: \(engine.currentDPI.map(String.init) ?? "—")")
                .frame(width: 200, alignment: .leading)
            Text("Cycle: \(engine.dpiCycleValues.map(String.init).joined(separator: " → "))")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
            Button("Cycle DPI") { engine.cycleDPI() }
                .disabled(engine.dpiCycleValues.isEmpty)
            Spacer()
        }
    }

    private var thumbWheelPanel: some View {
        HStack {
            Text(thumbWheelLog.isEmpty
                 ? "Spin the thumb wheel."
                 : "Notches: " + thumbWheelLog.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(thumbWheelLog.isEmpty ? .secondary : .primary)
            Spacer()
        }
    }
```

- [ ] **Step 5: Build**

Run: `swift build --target RatTest 2>&1 | tail -3`
Expected: build verde.

- [ ] **Step 6: Commit**

```bash
git add Sources/RatTest/RatTestView.swift
git commit -m "feat(ratest): wheel mode, DPI and thumb wheel panels"
```

---

### Task 9: Verificação final e validação manual no hardware

**Files:**
- (nenhum código novo)

**Interfaces:**
- Consumes: tudo acima.

- [x] **Step 1: Suíte completa + build de todos os targets**

Run: `swift test 2>&1 | grep -E "Executed .* tests|failed" | tail -3`
Expected: todos verdes (contagem maior que antes — novos testes do glide + catálogo).
> **Resultado (2026-08-09):** 295 testes, 0 falhas.

Run: `swift build 2>&1 | tail -3`
Expected: build completo verde.
> **Resultado (2026-08-09):** build completo verde.

- [x] **Step 2: Relançar o RatTest**

```bash
pkill -f "debug/RatTest" || true
nohup swift run RatTest > /tmp/ratetest.log 2>&1 &
```
> **Resultado (2026-08-09):** relançado; janela auto-dimensiona (660×1184) com todas as seções visíveis (Buttons, Smooth Scroll, Wheel Mode, DPI, Thumb Wheel) sem scroll.

- [ ] **Step 3: Checklist manual (usuário)**

1. Botões: picker agora lista todas as ações (sistema, clicks, gesture, cycleDPI).
2. Smooth Scroll: slider de nível + presets; "Glide sã" ativa o glide com valores sãos; "Mos-like" replica a config do Mos; toggle "Smoothing (glide)" liga/desliga; sliders de fraction/stop funcionam ao vivo.
3. Wheel Mode: mostra free-spin/ratcheted; botões alternam o modo.
4. DPI: mostra DPI atual; "Cycle DPI" alterna pelos presets.
5. Thumb Wheel: girar a roda lateral exibe "left"/"right" ao vivo.

- [ ] **Step 4: Commit final (se houver ajustes)**

```bash
git add -A
git commit -m "chore(ratest): final validation tweaks"
```

---

## Self-Review

**Cobertura da spec:**
- Parte A (glide): Task 1 (params/estado), Task 2 (feed), Task 3 (tick) ✓ — incluindo `glideStopThreshold` dedicado, min 1px e carry.
- Parte B.1 (níveis+presets): Task 6 ✓ — presets Discreta/Média/Fluida/Glide sã/Mos-like com valores reconciliados (132/1.0 Mos-like; 120/1.5 glide).
- Parte B.2 (controles de smoothing): Task 6 ✓ — toggle + sliders fraction (`0.02...0.15`) e glide stop.
- Parte B.3 (catálogo completo): Task 4 (mover ActionCatalog + allActions) + Task 7 ✓ — runShortcut fora de escopo conforme spec.
- Parte B.4 (DPI + thumb wheel): Task 5 + Task 8 ✓.
- Parte B.5 (modo da roda): Task 5 + Task 8 ✓ — só com `hasSmartShift`.
- Backward compat (default false + suíte legada verde): Tasks 1-3 ✓.

**Sem placeholders:** todos os steps têm código concreto.

**Consistência de tipos:** `smoothingEnabled`/`smoothFraction`/`glideStopThreshold` usados com os mesmos nomes em todas as tasks; `ActionCatalog.allActions` definido na Task 4 e consumido na 7; callbacks do engine na Task 5 consumidos na 8.
