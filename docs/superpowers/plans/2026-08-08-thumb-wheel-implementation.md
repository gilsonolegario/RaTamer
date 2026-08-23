# Thumb Wheel Configurável — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tornar o thumb wheel (scroll horizontal) do MX Master 2S um controle configurável no RatTamer, com volume pequeno por notch como padrão.

**Architecture:** Um event tap CGEvent (`ScrollWheelTap`) filtra scroll horizontal discreto (`ScrollWheelTap` + `ThumbWheel` classificador/acumulador puros em RatTamerCore), suprime o scroll nativo e dispara ações do `ActionEngine` conforme `Config.thumbWheelLeft/Right`. O `EngineController` conecta o tap ao estado (enabled/connected) e à configuração. A UI adiciona a seção "Thumb Wheel" na aba Buttons.

**Tech Stack:** Swift 5.9 (SPM), macOS 14+, CoreGraphics (`CGEventTap`), osascript (volume), SwiftUI (app).

## Global Constraints

- macOS 14+, `swift-tools-version: 5.9`; builds via `swift build`, testes via `swift test`.
- Nenhuma dependência nova; sem comentários no código a menos que o padrão existente exija.
- Nomes das actions novos: **exatamente** `volumeUpSmall` / `volumeDownSmall` (referenciados pela migração de config e pelo catálogo).
- Passo de volume pequeno fixo: **±3** por notch.
- `Config.thumbWheelLeft`/`thumbWheelRight` são `ButtonAction?`; `nil`/`.disabled` = scroll nativo.
- Migração: se ambos os lados do thumb wheel forem `nil` → `volumeDownSmall` (esquerda) / `volumeUpSmall` (direita).
- **A pasta do projeto não é um repositório git.** Os passos "Commit" são pontos de verificação: pule o `git commit` se o repositório não estiver inicializado.
- Não há gestão do passo de volume na UI (fixo ±3), nem toggle de direção (usuário troca Esquerda/Direita).

---

### Task 1: `ThumbWheel` (classificador + acumulador puros)

**Files:**
- Create: `Sources/RatTamerCore/Core/ThumbWheelClassifier.swift`
- Test: `Tests/RatTamerCoreTests/Core/ThumbWheelClassifierTests.swift`

**Interfaces:**
- Produces (usado pelas Tasks 4 e 5):
  - `ThumbWheel.Direction` (`enum`, `.left` / `.right`, `Equatable`)
  - `ThumbWheel.isThumbWheel(deltaX: Int64, deltaY: Int64, isContinuous: Int64, phase: Int64) -> Bool`
  - `ThumbWheel.direction(forDeltaX: Int64) -> Direction`
  - `ThumbWheel.NotchAccumulator` com `init()`, `mutating push(pixels: Int64, direction: Direction) -> Int`, `mutating reset()`
  - `ThumbWheel.notchThreshold: Int64` (= 10)

- [ ] **Step 1: Escrever o teste que falha**

Crie `Tests/RatTamerCoreTests/Core/ThumbWheelClassifierTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class ThumbWheelClassifierTests: XCTestCase {
    func testIsThumbWheelAcceptsDiscreteHorizontalScroll() {
        XCTAssertTrue(ThumbWheel.isThumbWheel(deltaX: 1, deltaY: 0, isContinuous: 0, phase: 0))
        XCTAssertTrue(ThumbWheel.isThumbWheel(deltaX: -10, deltaY: 0, isContinuous: 0, phase: 0))
    }

    func testIsThumbWheelRejectsTrackpadContinuous() {
        XCTAssertFalse(ThumbWheel.isThumbWheel(deltaX: 10, deltaY: 0, isContinuous: 1, phase: 0))
    }

    func testIsThumbWheelRejectsVerticalAndZero() {
        XCTAssertFalse(ThumbWheel.isThumbWheel(deltaX: 0, deltaY: 1, isContinuous: 0, phase: 0))
        XCTAssertFalse(ThumbWheel.isThumbWheel(deltaX: 0, deltaY: 0, isContinuous: 0, phase: 0))
    }

    func testIsThumbWheelRejectsScrollPhase() {
        XCTAssertFalse(ThumbWheel.isThumbWheel(deltaX: 10, deltaY: 0, isContinuous: 0, phase: 1))
    }

    func testDirectionFromDeltaX() {
        XCTAssertEqual(ThumbWheel.direction(forDeltaX: 10), .right)
        XCTAssertEqual(ThumbWheel.direction(forDeltaX: -10), .left)
    }

    func testAccumulatorFiresNotchAtThreshold() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 10, direction: .right), 1)
    }

    func testAccumulatorFiresPerThreshold() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 10, direction: .right), 1)
        XCTAssertEqual(acc.push(pixels: 10, direction: .right), 1)
    }

    func testAccumulatorKeepsRemainder() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 15, direction: .right), 1)
        XCTAssertEqual(acc.push(pixels: 5, direction: .right), 1)
    }

    func testAccumulatorHandlesLargeSingleDelta() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 25, direction: .right), 2)
    }

    func testAccumulatorLeftDirection() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 10, direction: .left), 1)
    }

    func testAccumulatorSignFlushDiscardsOppositeRemainder() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 5, direction: .right), 0)
        XCTAssertEqual(acc.push(pixels: 10, direction: .left), 1)
    }

    func testAccumulatorIgnoresZeroPixels() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 0, direction: .right), 0)
        XCTAssertEqual(acc.push(pixels: 0, direction: .right), 0)
    }

    func testResetClearsPending() {
        var acc = ThumbWheel.NotchAccumulator()
        _ = acc.push(pixels: 5, direction: .right)
        acc.reset()
        XCTAssertEqual(acc.push(pixels: 5, direction: .right), 0)
    }
}
```

- [ ] **Step 2: Rodar para confirmar que falha**

Run: `swift test --filter ThumbWheelClassifierTests`
Expected: FAIL — `ThumbWheel` não existe.

- [ ] **Step 3: Implementar o mínimo**

Crie `Sources/RatTamerCore/Core/ThumbWheelClassifier.swift`:

```swift
import Foundation

public enum ThumbWheel {
    public enum Direction: Equatable {
        case left
        case right
    }

    public static let notchThreshold: Int64 = 10

    public static func isThumbWheel(deltaX: Int64, deltaY: Int64, isContinuous: Int64, phase: Int64) -> Bool {
        deltaX != 0 && isContinuous == 0 && phase == 0
    }

    public static func direction(forDeltaX deltaX: Int64) -> Direction {
        deltaX > 0 ? .right : .left
    }

    public struct NotchAccumulator {
        private var pending: Int64 = 0

        public init() {}

        public mutating func push(pixels: Int64, direction: Direction) -> Int {
            guard pixels != 0 else { return 0 }
            let signed = direction == .right ? abs(pixels) : -abs(pixels)
            if pending != 0 && (pending > 0) != (signed > 0) {
                pending = 0
            }
            pending += signed
            var notches = 0
            while abs(pending) >= ThumbWheel.notchThreshold {
                pending -= (pending > 0 ? ThumbWheel.notchThreshold : -ThumbWheel.notchThreshold)
                notches += 1
            }
            return notches
        }

        public mutating func reset() {
            pending = 0
        }
    }
}
```

- [ ] **Step 4: Rodar para confirmar que passa**

Run: `swift test --filter ThumbWheelClassifierTests`
Expected: PASS (12 testes).

- [ ] **Step 5: Commit (checkpoint — pule se o repo não for git)**

```bash
git add Sources/RatTamerCore/Core/ThumbWheelClassifier.swift Tests/RatTamerCoreTests/Core/ThumbWheelClassifierTests.swift
git commit -m "feat: add thumb wheel classifier and notch accumulator"
```

---

### Task 2: Config — campos `thumbWheelLeft/Right` + migração

**Files:**
- Modify: `Sources/RatTamerCore/Core/ConfigStore.swift`
- Test: `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: (nenhum novo; só tipos já existentes)
- Produces (usado pelas Tasks 5 e 6):
  - `ThumbWheelSide` enum público (`.left` / `.right`, `String`-raw, `Equatable`, `Identifiable` com `id: String`)
  - `Config.thumbWheelLeft: ButtonAction?` e `Config.thumbWheelRight: ButtonAction?`
  - `Config.thumbWheelAction(for side: ThumbWheelSide) -> ButtonAction?`
  - `Config.setThumbWheelAction(_ action: ButtonAction?, for side: ThumbWheelSide)`
  - `Config.migrateLegacy()` agora também aplica defaults de volume quando ambos os lados são `nil`

- [ ] **Step 1: Escrever/atualizar os testes**

Edite `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`:

(a) Atualize `testSaveThenLoadRoundTrip` — o round trip passa a incluir os campos novos para a migração não alterar nada:

```swift
    func testSaveThenLoadRoundTrip() throws {
        let url = tempDir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.deviceIndex = 1
        config.buttons["0x00C3"] = .shortcut(key: "w", modifiers: ["command"])
        config.thumbWheelLeft = .system("volumeDownSmall")
        config.thumbWheelRight = .system("volumeUpSmall")
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded, config)
    }
```

(b) Atualize `testLoadsLegacyConfigWithoutDPIFields` — a migração agora também seta o thumb wheel e bumpeia a versão:

```swift
    func testLoadsLegacyConfigWithoutDPIFields() throws {
        let url = tempDir.appendingPathComponent("legacy.json")
        try #"""
        {"version":1,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(loaded.deviceIndex, 1)
        XCTAssertNil(loaded.dpiFeatureIndex)
        XCTAssertNil(loaded.dpiDeviceIndex)
        XCTAssertNil(loaded.dpiDownValue)
        XCTAssertNil(loaded.dpiAction)
        XCTAssertEqual(loaded.thumbWheelLeft, .system("volumeDownSmall"))
        XCTAssertEqual(loaded.thumbWheelRight, .system("volumeUpSmall"))
    }
```

(c) Substitua `testMigrateLegacyDoesNothingWhenNoLegacyFields` por:

```swift
    func testMigrateLegacySetsThumbWheelDefaultsWhenAbsent() {
        var config = Config(version: 1, deviceIndex: 1, buttons: ["0x0052": .disabled])
        XCTAssertTrue(config.migrateLegacy())
        XCTAssertEqual(config.thumbWheelLeft, .system("volumeDownSmall"))
        XCTAssertEqual(config.thumbWheelRight, .system("volumeUpSmall"))
        XCTAssertEqual(config.version, 2)
    }

    func testMigrateLegacyPreservesThumbWheelWhenConfigured() {
        var config = Config(version: 2, deviceIndex: 1, buttons: [:])
        config.thumbWheelLeft = .disabled
        XCTAssertFalse(config.migrateLegacy())
        XCTAssertEqual(config.thumbWheelLeft, .disabled)
        XCTAssertNil(config.thumbWheelRight)
    }
```

(d) Adicione no final da classe:

```swift
    func testThumbWheelFieldsRoundTripThroughStore() throws {
        let url = tempDir.appendingPathComponent("thumbwheel.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.setThumbWheelAction(.system("volumeDownSmall"), for: .left)
        config.setThumbWheelAction(.shortcut(key: "w", modifiers: ["command"]), for: .right)
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.thumbWheelAction(for: .left), .system("volumeDownSmall"))
        XCTAssertEqual(loaded.thumbWheelAction(for: .right), .shortcut(key: "w", modifiers: ["command"]))
    }

    func testThumbWheelFieldsDecodeNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-thumbwheel.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{},"thumbWheelLeft":{"action":"disabled"}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.thumbWheelLeft, .disabled)
        XCTAssertNil(loaded.thumbWheelRight)
    }
```

- [ ] **Step 2: Rodar para confirmar que falha**

Run: `swift test --filter ConfigStoreTests`
Expected: FAIL — `thumbWheelLeft` não existe (erros de compilação).

- [ ] **Step 3: Implementar o mínimo**

Edite `Sources/RatTamerCore/Core/ConfigStore.swift`:

(1) Adicione o enum `ThumbWheelSide` logo após o `public extension ButtonAction` (antes de `SmartShiftMode`):

```swift
public enum ThumbWheelSide: String, Codable, Equatable, Identifiable {
    case left
    case right

    public var id: String { rawValue }
}
```

(2) No struct `Config`, adicione os campos após `invertScrollDirection`:

```swift
    public var thumbWheelLeft: ButtonAction?
    public var thumbWheelRight: ButtonAction?
```

(3) Atualize `CodingKeys`:

```swift
    private enum CodingKeys: String, CodingKey {
        case version, deviceIndex, buttons, dpiFeatureIndex, dpiDeviceIndex,
             dpiDownValue, dpiAction, swapLeftRight, smartShiftMode, dpiValue,
             invertScrollDirection, thumbWheelLeft, thumbWheelRight
    }
```

(4) No `init(from:)`, após `invertScrollDirection`:

```swift
        thumbWheelLeft = try c.decodeIfPresent(ButtonAction.self, forKey: .thumbWheelLeft)
        thumbWheelRight = try c.decodeIfPresent(ButtonAction.self, forKey: .thumbWheelRight)
```

(5) No `init(version:...)`, adicione os parâmetros com default após `dpiValue`:

```swift
                 dpiValue: UInt16? = nil,
                 thumbWheelLeft: ButtonAction? = nil,
                 thumbWheelRight: ButtonAction? = nil) {
```

e as atribuições:

```swift
        self.invertScrollDirection = nil
        self.thumbWheelLeft = thumbWheelLeft
        self.thumbWheelRight = thumbWheelRight
    }
```

(6) Adicione os helpers ao struct `Config` (após `setAction`):

```swift
    public func thumbWheelAction(for side: ThumbWheelSide) -> ButtonAction? {
        side == .left ? thumbWheelLeft : thumbWheelRight
    }

    public mutating func setThumbWheelAction(_ action: ButtonAction?, for side: ThumbWheelSide) {
        if side == .left {
            thumbWheelLeft = action
        } else {
            thumbWheelRight = action
        }
    }
```

(7) Atualize `migrateLegacy()`:

```swift
    public mutating func migrateLegacy() -> Bool {
        var changed = false
        if let dpiAction, buttons[cidKey(0x00C4)] == nil {
            buttons[cidKey(0x00C4)] = dpiAction
            self.dpiAction = nil
            changed = true
        } else if dpiFeatureIndex != nil, buttons[cidKey(0x00C4)] == nil {
            buttons[cidKey(0x00C4)] = .shortcut(key: "w", modifiers: ["command"])
            changed = true
        }
        if thumbWheelLeft == nil && thumbWheelRight == nil {
            thumbWheelLeft = .system("volumeDownSmall")
            thumbWheelRight = .system("volumeUpSmall")
            changed = true
        }
        if changed {
            version = 2
        }
        return changed
    }
```

> Nota: o `encode(to:)` do `Config` continua sintetizado (os campos são `Optional` → omitidos quando `nil`); não adicione `encode(to:)` manual.

- [ ] **Step 4: Rodar para confirmar que passa**

Run: `swift test --filter ConfigStoreTests`
Expected: PASS (todos, incluindo os atualizados).

- [ ] **Step 5: Commit (checkpoint)**

```bash
git add Sources/RatTamerCore/Core/ConfigStore.swift Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift
git commit -m "feat: add configurable thumb wheel actions with volume defaults"
```

---

### Task 3: `ActionEngine` — actions `volumeUpSmall`/`volumeDownSmall`

**Files:**
- Modify: `Sources/RatTamerCore/Core/ActionEngine.swift`
- Test: `Tests/RatTamerCoreTests/Core/ActionEngineTests.swift`

**Interfaces:**
- Consumes: (nada novo)
- Produces (usado pelas Tasks 5 e 6): system actions `"volumeUpSmall"` / `"volumeDownSmall"` executadas via `ButtonAction.system(...)`

- [ ] **Step 1: Escrever o teste que falha**

Adicione ao final de `Tests/RatTamerCoreTests/Core/ActionEngineTests.swift` (dentro da classe):

```swift
    func testVolumeSmallActionsRunScripts() throws {
        func scripts(for action: ButtonAction) throws -> [String] {
            let runner = MockScriptRunner()
            try ActionEngine(poster: MockEventPoster(), scriptRunner: runner).execute(action)
            return runner.scripts
        }
        XCTAssertEqual(try scripts(for: .system("volumeUpSmall")), [
            "set volume output volume ((output volume of (get volume settings)) + 3)"
        ])
        XCTAssertEqual(try scripts(for: .system("volumeDownSmall")), [
            "set volume output volume ((output volume of (get volume settings)) - 3)"
        ])
    }
```

- [ ] **Step 2: Rodar para confirmar que falha**

Run: `swift test --filter ActionEngineTests`
Expected: FAIL — scripts vazios (o switch cai no `default`).

- [ ] **Step 3: Implementar o mínimo**

Em `Sources/RatTamerCore/Core/ActionEngine.swift`, dentro de `executeSystemAction`, logo após o case `"volumeDown"`:

```swift
        case "volumeUpSmall":
            try runScript("set volume output volume ((output volume of (get volume settings)) + 3)")
        case "volumeDownSmall":
            try runScript("set volume output volume ((output volume of (get volume settings)) - 3)")
```

- [ ] **Step 4: Rodar para confirmar que passa**

Run: `swift test --filter ActionEngineTests`
Expected: PASS (incluindo o novo teste).

- [ ] **Step 5: Commit (checkpoint)**

```bash
git add Sources/RatTamerCore/Core/ActionEngine.swift Tests/RatTamerCoreTests/Core/ActionEngineTests.swift
git commit -m "feat: add small-step volume system actions"
```

---

### Task 4: `ScrollWheelTap` (event tap CGEvent + pipeline testável)

**Files:**
- Create: `Sources/RatTamerCore/Core/ScrollWheelTap.swift`
- Test: `Tests/RatTamerCoreTests/Core/ScrollWheelTapTests.swift`

**Interfaces:**
- Consumes: `ThumbWheel` da Task 1 (`Direction`, `isThumbWheel`, `direction(forDeltaX:)`, `NotchAccumulator`, `notchThreshold`)
- Produces (usado pela Task 5):
  - `ScrollWheelTap(shouldIntercept: @escaping (ThumbWheel.Direction) -> Bool, onNotch: @escaping (ThumbWheel.Direction) -> Void)`
  - `func start()` / `func stop()` (instala/remove o tap no main run loop)
  - `var isActive: Bool`
  - `func process(deltaX: Int64, deltaY: Int64, isContinuous: Int64, phase: Int64, pointDeltaX: Int64) -> Bool` — **internal** (testável via `@testable`); retorna `true` se o evento deve ser suprimido.

- [ ] **Step 1: Escrever o teste que falha**

Crie `Tests/RatTamerCoreTests/Core/ScrollWheelTapTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class ScrollWheelTapTests: XCTestCase {
    func testPassesThroughNonThumbWheelEvents() {
        let tap = ScrollWheelTap(shouldIntercept: { _ in true },
                                 onNotch: { _ in XCTFail("unexpected notch") })
        XCTAssertFalse(tap.process(deltaX: 0, deltaY: 1, isContinuous: 0, phase: 0, pointDeltaX: 0))
        XCTAssertFalse(tap.process(deltaX: 10, deltaY: 0, isContinuous: 1, phase: 0, pointDeltaX: 10))
    }

    func testPassesThroughWhenDirectionNotConfigured() {
        let tap = ScrollWheelTap(shouldIntercept: { _ in false },
                                 onNotch: { _ in XCTFail("unexpected notch") })
        XCTAssertFalse(tap.process(deltaX: 10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: 10))
    }

    func testSuppressesAndFiresNotchAfterPixelAccumulation() {
        var notches: [ThumbWheel.Direction] = []
        let tap = ScrollWheelTap(shouldIntercept: { _ in true }, onNotch: { notches.append($0) })
        XCTAssertTrue(tap.process(deltaX: 1, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: 1))
        XCTAssertEqual(notches, [])
        XCTAssertTrue(tap.process(deltaX: 10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: 10))
        XCTAssertEqual(notches, [.right])
    }

    func testSuppressesLeftDirection() {
        var notches: [ThumbWheel.Direction] = []
        let tap = ScrollWheelTap(shouldIntercept: { _ in true }, onNotch: { notches.append($0) })
        XCTAssertTrue(tap.process(deltaX: -10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: -10))
        XCTAssertEqual(notches, [.left])
    }

    func testOnlyConfiguredDirectionIsIntercepted() {
        var notches: [ThumbWheel.Direction] = []
        let tap = ScrollWheelTap(shouldIntercept: { $0 == .right }, onNotch: { notches.append($0) })
        XCTAssertFalse(tap.process(deltaX: -10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: -10))
        XCTAssertTrue(tap.process(deltaX: 10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: 10))
        XCTAssertEqual(notches, [.right])
    }
}
```

- [ ] **Step 2: Rodar para confirmar que falha**

Run: `swift test --filter ScrollWheelTapTests`
Expected: FAIL — `ScrollWheelTap` não existe.

- [ ] **Step 3: Implementar o mínimo**

Crie `Sources/RatTamerCore/Core/ScrollWheelTap.swift`:

```swift
import CoreGraphics
import Foundation
import os

public final class ScrollWheelTap {
    public typealias Direction = ThumbWheel.Direction

    private static let log = Logger(subsystem: "com.rattamer", category: "thumbwheel")

    private let shouldIntercept: (Direction) -> Bool
    private let onNotch: (Direction) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accumulator = ThumbWheel.NotchAccumulator()

    public init(shouldIntercept: @escaping (Direction) -> Bool,
                onNotch: @escaping (Direction) -> Void) {
        self.shouldIntercept = shouldIntercept
        self.onNotch = onNotch
    }

    public var isActive: Bool { tap != nil }

    public func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.handle,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.error("tapCreate failed (Accessibility not granted?)")
            return
        }
        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        Self.log.info("scroll wheel tap started")
    }

    public func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        accumulator.reset()
        Self.log.info("scroll wheel tap stopped")
    }

    func process(deltaX: Int64, deltaY: Int64, isContinuous: Int64,
                 phase: Int64, pointDeltaX: Int64) -> Bool {
        guard ThumbWheel.isThumbWheel(deltaX: deltaX, deltaY: deltaY,
                                      isContinuous: isContinuous, phase: phase) else {
            return false
        }
        let direction = ThumbWheel.direction(forDeltaX: deltaX)
        guard shouldIntercept(direction) else { return false }
        let notches = accumulator.push(pixels: pointDeltaX, direction: direction)
        for _ in 0..<notches {
            onNotch(direction)
        }
        return true
    }

    private static let handle: CGEventTapCallBack = { _, _, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<ScrollWheelTap>.fromOpaque(refcon).takeUnretainedValue()
        let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let pointDeltaX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let suppress = tap.process(deltaX: deltaX, deltaY: deltaY,
                                   isContinuous: isContinuous, phase: phase,
                                   pointDeltaX: pointDeltaX)
        return suppress ? nil : Unmanaged.passUnretained(event)
    }
}
```

- [ ] **Step 4: Rodar para confirmar que passa**

Run: `swift test --filter ScrollWheelTapTests`
Expected: PASS (5 testes). Não chame `start()` nos testes (exige Accessibility).

- [ ] **Step 5: Commit (checkpoint)**

```bash
git add Sources/RatTamerCore/Core/ScrollWheelTap.swift Tests/RatTamerCoreTests/Core/ScrollWheelTapTests.swift
git commit -m "feat: add scroll wheel event tap with notch pipeline"
```

---

### Task 5: `EngineController` — fiação do tap (App)

**Files:**
- Modify: `Sources/RatTamerApp/EngineController.swift`

**Interfaces:**
- Consumes: `ScrollWheelTap` (Task 4), `ThumbWheel.Direction` (Task 1), `Config.thumbWheelAction(for:)` (Task 2), `ActionEngine` (Task 3)
- Produces: tap ativo somente quando `enabled && isConnected`; notches executam a action configurada na `ioQueue`. Sem saída para outras tasks.

- [ ] **Step 1: Implementar**

Em `Sources/RatTamerApp/EngineController.swift`:

(1) Adicione a propriedade junto às demais (`private let gestureCID: UInt16?`):

```swift
    private var scrollWheelTap: ScrollWheelTap?
```

(2) No `init`, logo após `self.gestureDetector = ...`:

```swift
        let tap = ScrollWheelTap(
            shouldIntercept: { [weak self] direction in
                guard let self, self.enabled, self.isConnected else { return false }
                return self.hasThumbWheelAction(direction)
            },
            onNotch: { [weak self] direction in
                self?.executeThumbWheelNotch(direction)
            }
        )
        self.scrollWheelTap = tap
```

(3) Em `start()`, imediatamente antes de `return true`:

```swift
            scrollWheelTap?.start()
```

(4) Em `stop()`, após `gestureCID = nil`:

```swift
        scrollWheelTap?.stop()
```

(5) Adicione os helpers privados (no fim da classe, junto de `handleRawXY`):

```swift
    private func hasThumbWheelAction(_ direction: ThumbWheel.Direction) -> Bool {
        let action = currentConfig().thumbWheelAction(for: direction)
        return action != nil && action != .disabled
    }

    private func executeThumbWheelNotch(_ direction: ThumbWheel.Direction) {
        let config = currentConfig()
        guard let action = config.thumbWheelAction(for: direction), action != .disabled else { return }
        ioQueue.async { [weak self] in
            guard let self, !self.stopped else { return }
            do {
                try self.actionEngine.execute(action)
            } catch {
                Self.log.error("thumb wheel execute failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
```

> `ThumbWheel` está em `RatTamerCore` (já importado); a assinatura dos closures é inferida de `ScrollWheelTap.init`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: sucesso (nenhum warning novo).

- [ ] **Step 3: Testes gerais**

Run: `swift test`
Expected: PASS (108 existentes + novos).

- [ ] **Step 4: Commit (checkpoint)**

```bash
git add Sources/RatTamerApp/EngineController.swift
git commit -m "feat: wire scroll wheel tap into engine lifecycle"
```

---

### Task 6: UI — `ActionCatalog` + seção "Thumb Wheel" (App)

**Files:**
- Modify: `Sources/RatTamerApp/ActionCatalog.swift`
- Modify: `Sources/RatTamerApp/Views/ButtonsTabView.swift`

**Interfaces:**
- Consumes: `Config.thumbWheelAction(for:)`, `setThumbWheelAction(_:for:)`, `ThumbWheelSide` (Task 2); system actions `volumeUpSmall`/`volumeDownSmall` (Task 3)
- Produces: seção "Thumb Wheel" com Esquerda/Direita selecionáveis; `ActionCatalog` mostra "Volume Up (small)"/"Volume Down (small)".

- [ ] **Step 1: Atualizar `ActionCatalog`**

Em `Sources/RatTamerApp/ActionCatalog.swift`, em `systemTitle`, após o case `"volumeDown"`:

```swift
        case "volumeUpSmall": return "Volume Up (small)"
        case "volumeDownSmall": return "Volume Down (small)"
```

Em `systemIcon`, após o case `"volumeDown"`:

```swift
        case "volumeUpSmall": return "speaker.wave.2"
        case "volumeDownSmall": return "speaker.wave.1"
```

- [ ] **Step 2: Refatorar `ButtonsTabView` — builder compartilhado de menu de ação**

Em `Sources/RatTamerApp/Views/ButtonsTabView.swift`:

(1) Adicione o state para o sheet de shortcut do thumb wheel, junto de `shortcutControl`:

```swift
    @State private var shortcutThumbSide: ThumbWheelSide?
```

(2) Substitua o corpo de `actionMenu(for control:)` por uma chamada ao builder compartilhado:

```swift
    private func actionMenu(for control: ControlInfo) -> some View {
        let action = config.action(forCID: control.cid) ?? .disabled
        return actionMenu(title: ActionCatalog.title(for: action),
                          icon: ActionCatalog.icon(for: action),
                          onSet: { setAction($0, for: control) },
                          onCustomShortcut: { shortcutControl = control },
                          extras: {
                              if control.cid == 0x00C3 {
                                  Button {
                                      gestureControl = control
                                  } label: {
                                      Label("Gesture…", systemImage: "hand.draw")
                                  }
                              }
                          })
    }
```

(3) Adicione o builder compartilhado, o `commonActionSections` e os itens genéricos (substituindo as versões atuais `systemItem`/`shortcutItem`/`clickItem` que recebiam `ControlInfo`):

```swift
    private func actionMenu(title: String, icon: String,
                            onSet: @escaping (ButtonAction) -> Void,
                            onCustomShortcut: @escaping () -> Void,
                            @ViewBuilder extras: () -> some View) -> some View {
        Menu {
            commonActionSections(onSet: onSet)
            Divider()
            Button {
                onCustomShortcut()
            } label: {
                Label("Custom Shortcut…", systemImage: "keyboard")
            }
            extras()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func commonActionSections(onSet: @escaping (ButtonAction) -> Void) -> some View {
        Section("None") {
            Button {
                onSet(.disabled)
            } label: {
                Label("Native (default)", systemImage: "circle.slash")
            }
        }
        Section("Desktop & System") {
            systemItem("missionControl", onSet)
            systemItem("appExpose", onSet)
            systemItem("showDesktop", onSet)
            systemItem("launchpad", onSet)
            systemItem("previousSpace", onSet)
            systemItem("nextSpace", onSet)
            systemItem("spotlight", onSet)
            systemItem("lockScreen", onSet)
        }
        Section("Navigation") {
            shortcutItem("Back", key: "[", modifiers: ["command"], onSet)
            shortcutItem("Forward", key: "]", modifiers: ["command"], onSet)
            shortcutItem("New Tab", key: "t", modifiers: ["command"], onSet)
            shortcutItem("Close Tab", key: "w", modifiers: ["command"], onSet)
            shortcutItem("New Window", key: "n", modifiers: ["command"], onSet)
        }
        Section("Editing") {
            shortcutItem("Copy", key: "c", modifiers: ["command"], onSet)
            shortcutItem("Paste", key: "v", modifiers: ["command"], onSet)
            shortcutItem("Undo", key: "z", modifiers: ["command"], onSet)
            shortcutItem("Select All", key: "a", modifiers: ["command"], onSet)
            shortcutItem("Find", key: "f", modifiers: ["command"], onSet)
        }
        Section("Volume") {
            systemItem("volumeUp", onSet)
            systemItem("volumeDown", onSet)
            systemItem("volumeUpSmall", onSet)
            systemItem("volumeDownSmall", onSet)
            systemItem("volumeMute", onSet)
        }
        Section("Screenshot") {
            shortcutItem("Full Screen", key: "3", modifiers: ["command", "shift"], onSet)
            shortcutItem("Selection", key: "4", modifiers: ["command", "shift"], onSet)
            shortcutItem("Recording", key: "5", modifiers: ["command", "shift"], onSet)
        }
        Section("Click") {
            clickItem(button: 3, onSet)
            clickItem(button: 4, onSet)
        }
    }

    private func systemItem(_ name: String, _ onSet: @escaping (ButtonAction) -> Void) -> some View {
        Button {
            onSet(.system(name))
        } label: {
            Label(ActionCatalog.systemTitle(name), systemImage: ActionCatalog.systemIcon(name))
        }
    }

    private func shortcutItem(_ title: String, key: String, modifiers: [String], _ onSet: @escaping (ButtonAction) -> Void) -> some View {
        Button {
            onSet(.shortcut(key: key, modifiers: modifiers))
        } label: {
            Label(title, systemImage: "keyboard")
        }
    }

    private func clickItem(button: UInt8, _ onSet: @escaping (ButtonAction) -> Void) -> some View {
        Button {
            onSet(.click(button: button))
        } label: {
            Label(button == 3 ? "Back Click" : "Forward Click", systemImage: "hand.point.up")
        }
    }
```

(4) No `body`, dentro do `ScrollView` > `VStack(spacing: 6)`, adicione a seção **antes** do `ForEach(model.controls)`:

```swift
                VStack(alignment: .leading, spacing: 6) {
                    Text("Thumb Wheel")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    thumbWheelRow(side: .left)
                    thumbWheelRow(side: .right)
                    Text("Ações para o scroll horizontal. Se a direção parecer invertida, troque Esquerda/Direita.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 44)
                    Divider().padding(.vertical, 4)
                }
                VStack(spacing: 6) {
                    ForEach(model.controls, id: \.cid) { control in
                        row(for: control)
                    }
                }
```

> Substitua o `VStack` atual que contém apenas o `ForEach(model.controls)` pelos dois `VStack` acima.

(5) Adicione os helpers do thumb wheel (perto de `actionMenu`):

```swift
    private func thumbWheelRow(side: ThumbWheelSide) -> some View {
        let action = config.thumbWheelAction(for: side) ?? .disabled
        return HStack(spacing: 12) {
            Image(systemName: side == .right ? "arrow.right.to.line" : "arrow.left.to.line")
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(side == .right ? "Thumb Wheel Right" : "Thumb Wheel Left")
                .frame(width: 170, alignment: .leading)
            Spacer()
            actionMenu(title: ActionCatalog.title(for: action),
                       icon: ActionCatalog.icon(for: action),
                       onSet: { setThumbWheelAction($0, side: side) },
                       onCustomShortcut: { shortcutThumbSide = side },
                       extras: { EmptyView() })
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private func setThumbWheelAction(_ action: ButtonAction, side: ThumbWheelSide) {
        config.setThumbWheelAction(action, for: side)
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }
```

(6) Adicione o sheet do shortcut do thumb wheel, após o `.sheet(item: $gestureControl)` existente:

```swift
        .sheet(item: $shortcutThumbSide) { side in
            ShortcutRecorderView { key, modifiers in
                setThumbWheelAction(.shortcut(key: key, modifiers: modifiers), side: side)
                shortcutThumbSide = nil
            } onCancel: {
                shortcutThumbSide = nil
            }
        }
```

> A refatoração de `actionMenu` deve manter o comportamento atual dos botões; a única mudança visível é a adição dos itens "Volume Up (small)"/"Volume Down (small)" na seção Volume e a nova seção "Thumb Wheel".

- [ ] **Step 3: Build e testes**

Run: `swift build` e depois `swift test`
Expected: build sem erros; testes PASS.

- [ ] **Step 4: Commit (checkpoint)**

```bash
git add Sources/RatTamerApp/ActionCatalog.swift Sources/RatTamerApp/Views/ButtonsTabView.swift
git commit -m "feat: add thumb wheel configuration UI"
```

---

### Task 7: Housekeeping do `RatDiagnose` — remover enumeração de features

**Files:**
- Modify: `Sources/RatDiagnose/main.swift`

**Interfaces:**
- Consumes: (nada)
- Produces: diagnostico mais limpo; mantém checagem de presença da 0x2150 e modo `--raw`.

- [ ] **Step 1: Remover o bloco de enumeração de features**

Em `Sources/RatDiagnose/main.swift`, remova o bloco `if let featureSetIndex = try session.getFeatureIndex(featureID: 0x0003, ...)` (linhas ~30–45), que faz a enumeração completa de features. Ele retornou dados inválidos (0x0142/0x004D×2/0x0500). Mantenha a checagem de presença da 0x2150 e o modo `--raw`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: sucesso.

- [ ] **Step 3: Commit (checkpoint)**

```bash
git add Sources/RatDiagnose/main.swift
git commit -m "chore: drop invalid feature enumeration from diagnostics"
```

---

## Validação final

- [ ] Run: `swift test` — todos os testes PASS (suíte original atualizada + `ThumbWheelClassifierTests` + `ScrollWheelTapTests` + novos casos).
- [ ] Run: `swift build -c release` — build limpo.
- [ ] Manual (usuário): com o mouse conectado e o app habilitado, girar o thumb wheel:
  - sem ações configuradas → scroll horizontal nativo intacto;
  - com volume configurado → volume muda ±3 por notch e o scroll nativo some;
  - se a direção parecer invertida → trocar Esquerda/Direita na UI.
- [ ] Restaurar `autoDisengage` do mouse se os testes com RatDiagnose o tiverem alterado (valor padrão 255 no modo ratcheted).
