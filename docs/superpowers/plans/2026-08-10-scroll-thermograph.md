# Scroll Thermograph (RAT.ENERGY) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrar ao vivo um gráfico térmico de rolagem (entrada crua → flares, saída domada → onda térmica), com visual de câmera de infravermelho e personalidade própria — não cópia do Mos. **Rev 2 (aprovada):** o gráfico vive numa **janela externa** (fechada por padrão → zero RAM/CPU quando fechada), acessível por botão no tab Advanced e item de menu, e é **descritivo** (eixos com escala, leituras ao vivo, legenda raw/smoothed, aviso quando smooth desligado).

**Architecture:** Captura de amostras no `ScrollSmootherCoordinator` (Core) via callback `onSample`; buffer anelar puro e testável `ScrollSampleBuffer`; store `ObservableObject` no App que publica snapshots a 30 Hz apenas enquanto a view está visível; render custom em `Canvas` (termografia), sem Swift Charts e sem dependências novas.

**Tech Stack:** Swift 6.2, SwiftUI (Canvas/GraphicsContext), macOS 14+, DispatchSourceTimer, XCTest.

## Global Constraints

- **Sem dependências novas** — `Package.swift` não muda; **não usar Swift Charts**.
- **Zero wakeups/consumo com a janela do gráfico fechada** — o timer de 30 Hz e o sink existem somente enquanto a `ScrollGraphWindow` está aberta (start em `show()`, stop em `windowWillClose`). A janela é criada fechada, sob demanda.
- **UI do app em inglês**; docs/specs/planos em pt-BR; textos do gráfico ("quente/frio", aviso) em pt-BR.
- **Paleta térmica** (cores exatas da spec): linha incandescente `#FFFCE8`; gradiente vertical da área: `#FFFCE8 → #FFE066 → #FFB454 → #FF5E3A → #C2252F → #6D0F2A → #2D0B3D → #0A0413`; grid `#2B1522`; brasa `#FFCF7D`; fundo ink `#0A0413`.
- Janela rolante de **5s**; Y simétrico `±max(abs)` da janela com piso `±60`; 0 = baseline.
- Verificação: `swift test` (suite existente: 328 testes, não pode quebrar), `swift build`, `./build-app.sh`, relançar `open build/RatTamer.app`.

---

## File Structure

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `Sources/RatTamerCore/Core/ScrollSample.swift` | criar | Tipo `ScrollSample` (time/kind/value) |
| `Sources/RatTamerCore/Core/ScrollSampleBuffer.swift` | criar | Ring buffer thread-safe, janela 5s |
| `Sources/RatTamerCore/Core/ScrollSmoother.swift` | modificar | Novo `rawPixels(for:)`; `feed` reutiliza |
| `Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift` | modificar | `onSample` emitindo `.raw`/`.output` |
| `Sources/RatTamerApp/ScrollGraphStore.swift` | criar | `ObservableObject`, flush 30 Hz |
| `Sources/RatTamerApp/ScrollGraphWindow.swift` | criar (Rev 2) | Janela externa; dono do store e do lifecycle |
| `Sources/RatTamerApp/EngineController.swift` | modificar | `scrollSampleSink` + roteio `onSample` |
| `Sources/RatTamerApp/Views/ScrollGraphView.swift` | criar (Rev 2) | View + painter Canvas + paleta (descritivo) |
| `Sources/RatTamerApp/Views/AdvancedTabView.swift` | modificar | Botão "Open Scroll Thermograph…" (Rev 2) |
| `Sources/RatTamerApp/AppDelegate.swift` | modificar (Rev 2) | Main menu com "Scroll Thermograph…" |
| `Tests/RatTamerCoreTests/Core/ScrollSampleTests.swift` | criar | Testes `rawPixels` + `ScrollSample` |
| `Tests/RatTamerCoreTests/Core/ScrollSampleBufferTests.swift` | criar | Testes do buffer |
| `Tests/RatTamerCoreTests/Core/ScrollSmootherCoordinatorTests.swift` | modificar | Testes `onSample` |

---

### Task 1: `ScrollSample` + `ScrollSmoother.rawPixels(for:)`

**Files:**
- Create: `Sources/RatTamerCore/Core/ScrollSample.swift`
- Modify: `Sources/RatTamerCore/Core/ScrollSmoother.swift:118-124` (feed usa `rawPixels`)
- Test: `Tests/RatTamerCoreTests/Core/ScrollSampleTests.swift`

**Interfaces:**
- Consumes: `WheelMovement(deltaV:periods:resolution:)` (já existe), `ScrollSmoother.Parameters` (já existe).
- Produces:
  - `public struct ScrollSample: Equatable { public enum Kind { case raw, output } public let time: Date; public let kind: Kind; public let value: Double }`
  - `public func rawPixels(for movement: WheelMovement) -> Double` em `ScrollSmoother`.

- [ ] **Step 1: Escrever o teste que falha**

`Tests/RatTamerCoreTests/Core/ScrollSampleTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class ScrollSampleTests: XCTestCase {
    func testRawPixelsMatchesFeedNativeOutput() {
        let smoother = ScrollSmoother(parameters: .init(multiplier: 8,
                                                        momentumEnabled: false,
                                                        invert: false,
                                                        pixelsPerNotch: 10))
        let movement = WheelMovement(deltaV: 80, periods: 1, resolution: true)
        XCTAssertEqual(smoother.rawPixels(for: movement), 100, accuracy: 0.0001)
        XCTAssertEqual(smoother.feed(movement, at: Date()), 100, accuracy: 0.0001)
    }

    func testRawPixelsComputesNotchesFromDeltaV() {
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: false,
                                                        invert: false,
                                                        pixelsPerNotch: 20))
        let movement = WheelMovement(deltaV: 45, periods: 1, resolution: true)
        XCTAssertEqual(smoother.rawPixels(for: movement), 60, accuracy: 0.0001)
    }

    func testScrollSampleEquality() {
        let a = ScrollSample(time: Date(timeIntervalSince1970: 1000), kind: .raw, value: 5)
        let b = ScrollSample(time: Date(timeIntervalSince1970: 1000), kind: .raw, value: 5)
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter ScrollSampleTests`
Expected: FAIL — "value of type 'ScrollSmoother' has no member 'rawPixels'" (não compila).

- [ ] **Step 3: Implementação mínima**

Create `Sources/RatTamerCore/Core/ScrollSample.swift`:

```swift
import Foundation

/// One timestamped point of the live scroll waveform: either the raw wheel
/// input (`raw`) or the tamed output that was actually posted (`output`).
public struct ScrollSample: Equatable {
    public enum Kind {
        case raw
        case output
    }

    public let time: Date
    public let kind: Kind
    public let value: Double

    public init(time: Date, kind: Kind, value: Double) {
        self.time = time
        self.kind = kind
        self.value = value
    }
}
```

In `Sources/RatTamerCore/Core/ScrollSmoother.swift`, replace the two lines inside `feed` that compute `notches`/`raw` (currently `let notches = ...; let raw = notches * parameters.pixelsPerNotch`) with `let raw = rawPixels(for: movement)`, and add the new public method above `parameters`:

```swift
    /// The pixels this wheel movement would produce natively, before any
    /// smoothing, boost or stabilization: notches × pixels per notch.
    public func rawPixels(for movement: WheelMovement) -> Double {
        let notches = Double(movement.deltaV) / Double(max(1, parameters.multiplier))
        return notches * parameters.pixelsPerNotch
    }
```

- [ ] **Step 4: Rodar para ver passar**

Run: `swift test --filter ScrollSampleTests`
Expected: PASS (3 testes).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSample.swift Sources/RatTamerCore/Core/ScrollSmoother.swift Tests/RatTamerCoreTests/Core/ScrollSampleTests.swift
git commit -m "feat(core): ScrollSample e ScrollSmoother.rawPixels(for:)"
```

---

### Task 2: `ScrollSampleBuffer` (ring buffer 5s)

**Files:**
- Create: `Sources/RatTamerCore/Core/ScrollSampleBuffer.swift`
- Test: `Tests/RatTamerCoreTests/Core/ScrollSampleBufferTests.swift`

**Interfaces:**
- Consumes: `ScrollSample` (Task 1).
- Produces:
  - `public final class ScrollSampleBuffer`
  - `public init(capacity: Int = 900)`
  - `public func append(_ sample: ScrollSample)`
  - `public func samples(in window: TimeInterval, before now: Date) -> [ScrollSample]` — trunca aos `capacity` mais recentes, filtra `time >= now - window && time <= now`, devolve ordenado por `time` (mais antigo primeiro).

- [ ] **Step 1: Escrever o teste que falha**

`Tests/RatTamerCoreTests/Core/ScrollSampleBufferTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class ScrollSampleBufferTests: XCTestCase {
    private func sample(_ offset: TimeInterval, value: Double, kind: ScrollSample.Kind = .raw) -> ScrollSample {
        ScrollSample(time: Date(timeIntervalSince1970: 1000 + offset), kind: kind, value: value)
    }

    func testWindowOrdersByTime() {
        let buffer = ScrollSampleBuffer()
        buffer.append(sample(0.3, value: 10))
        buffer.append(sample(0.1, value: 5))
        buffer.append(sample(0.2, value: 7, kind: .output))
        let got = buffer.samples(in: 5, before: Date(timeIntervalSince1970: 1000.5))
        XCTAssertEqual(got.map { $0.value }, [5, 7, 10])
        XCTAssertEqual(got.map { $0.kind }, [.raw, .output, .raw])
    }

    func testExcludesOutOfWindowAndFuture() {
        let buffer = ScrollSampleBuffer()
        buffer.append(sample(-10, value: 1))       // mais antiga que a janela
        buffer.append(sample(-4.9, value: 2))      // dentro
        buffer.append(sample(6.0, value: 3))       // no futuro
        let got = buffer.samples(in: 5, before: Date(timeIntervalSince1970: 1005))
        XCTAssertEqual(got.map { $0.value }, [2])
    }

    func testCapacityTrimsOldest() {
        let buffer = ScrollSampleBuffer(capacity: 3)
        for i in 0..<5 {
            buffer.append(sample(Double(i), value: Double(i)))
        }
        let got = buffer.samples(in: 100, before: Date(timeIntervalSince1970: 1100))
        XCTAssertEqual(got.map { $0.value }, [2, 3, 4])
    }

    func testAppendAndSnapshotFromDifferentThreads() {
        let buffer = ScrollSampleBuffer()
        let group = DispatchGroup()
        for thread in 0..<4 {
            group.enter()
            DispatchQueue.global().async {
                for i in 0..<50 {
                    buffer.append(self.sample(Double(thread * 1000 + i), value: Double(i)))
                }
                group.leave()
            }
        }
        group.wait()
        let got = buffer.samples(in: 100000, before: Date(timeIntervalSince1970: 100000))
        XCTAssertEqual(got.count, 200)
    }
}
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter ScrollSampleBufferTests`
Expected: FAIL — "cannot find 'ScrollSampleBuffer' in scope".

- [ ] **Step 3: Implementação mínima**

Create `Sources/RatTamerCore/Core/ScrollSampleBuffer.swift`:

```swift
import Foundation

/// Thread-safe ring buffer of `ScrollSample`s. The HID++/smoothscroll queue
/// appends while the UI thread snapshots; the lock keeps both ordered and
/// race-free. Oldest samples fall off when the capacity is exceeded.
public final class ScrollSampleBuffer {
    private let lock = NSLock()
    private var samples: [ScrollSample]
    private let capacity: Int

    public init(capacity: Int = 900) {
        self.capacity = max(1, capacity)
        self.samples = []
    }

    public func append(_ sample: ScrollSample) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    /// Samples inside `[now - window, now]`, oldest first, capped at capacity.
    public func samples(in window: TimeInterval, before now: Date) -> [ScrollSample] {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = now.addingTimeInterval(-window)
        return samples.filter { $0.time >= cutoff && $0.time <= now }
    }
}
```

- [ ] **Step 4: Rodar para ver passar**

Run: `swift test --filter ScrollSampleBufferTests`
Expected: PASS (4 testes).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSampleBuffer.swift Tests/RatTamerCoreTests/Core/ScrollSampleBufferTests.swift
git commit -m "feat(core): ScrollSampleBuffer (ring buffer thread-safe)"
```

---

### Task 3: `ScrollSmootherCoordinator.onSample`

**Files:**
- Modify: `Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift`
- Test: `Tests/RatTamerCoreTests/Core/ScrollSmootherCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ScrollSample`, `ScrollSmoother.rawPixels(for:)` (Task 1).
- Produces:
  - `public var onSample: ((ScrollSample) -> Void)?` no coordinator.
  - Comportamento: em `onWheelMovement`, emite `.raw` (via `smoother.rawPixels(for:)`) e depois o `.output` do valor postado. Em cada tick do timer, emite `.output`. Todas as amostras `.output` passam por um helper privado `post(_:)` que emite a amostra **antes** de chamar o `poster`.

- [ ] **Step 1: Escrever o teste que falha**

Append a `Tests/RatTamerCoreTests/Core/ScrollSmootherCoordinatorTests.swift`:

```swift
    func testOnSampleEmitsRawThenOutputPerFeed() {
        let now = Date()
        var samples: [ScrollSample] = []
        let lock = NSLock()
        let exp = expectation(description: "samples")
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: false,
                                                        invert: false,
                                                        pixelsPerNotch: 20))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother,
                                                    now: { now },
                                                    poster: { _ in })
        coordinator.onSample = { sample in
            lock.lock()
            samples.append(sample)
            lock.unlock()
            if samples.count == 2 { exp.fulfill() }
        }
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        wait(for: [exp], timeout: 1)
        lock.lock()
        let got = samples
        lock.unlock()
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got[0].kind, .raw)
        XCTAssertEqual(got[0].value, 20, accuracy: 0.0001)
        XCTAssertEqual(got[1].kind, .output)
        XCTAssertEqual(got[1].value, 20, accuracy: 0.0001)
    }

    func testOnSampleEmitsOutputOnEveryTick() {
        var samples: [ScrollSample] = []
        let lock = NSLock()
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: true,
                                                        invert: false,
                                                        momentumDecay: 0.5,
                                                        pixelsPerNotch: 20))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother, poster: { _ in })
        coordinator.onSample = { sample in
            lock.lock()
            samples.append(sample)
            lock.unlock()
        }
        coordinator.start()
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        let gotEnough = waitUntil({
            lock.lock()
            let n = samples.count
            lock.unlock()
            return n >= 4
        }, timeout: 2.0)
        coordinator.stop()
        XCTAssertTrue(gotEnough)
        lock.lock()
        let got = samples
        lock.unlock()
        XCTAssertEqual(got.first?.kind, .raw)
        XCTAssertTrue(got.dropFirst().allSatisfy { $0.kind == .output })
    }
```

- [ ] **Step 2: Rodar para ver falhar**

Run: `swift test --filter ScrollSmootherCoordinatorTests`
Expected: FAIL — "value of type 'ScrollSmootherCoordinator' has no member 'onSample'".

- [ ] **Step 3: Implementação mínima**

In `Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift`:

Add the stored property near the others:

```swift
    /// Called on the coordinator's queue with one sample per raw wheel
    /// movement (`.raw`) and per posted value (`.output`), always before the
    /// corresponding `poster` call.
    public var onSample: ((ScrollSample) -> Void)?
```

Replace `onWheelMovement` (lines 28-37) with:

```swift
    public func onWheelMovement(_ movement: WheelMovement) {
        queue.async { [weak self] in
            guard let self else { return }
            let now = self.now()
            if let onSample = self.onSample {
                onSample(ScrollSample(time: now, kind: .raw, value: self.smoother.rawPixels(for: movement)))
            }
            self.post(self.smoother.feed(movement, at: now))
            if self.smoother.hasPendingWork(at: now) {
                self.startTimerIfNeeded()
            }
        }
    }
```

Replace the two direct `self.poster(...)` calls (one in `onWheelMovement`, one in the timer handler at line 84) with `self.post(...)`, and add the helper:

```swift
    /// Emits the `.output` sample for a value (including 0, which the feed
    /// returns while smoothing accumulates) and then forwards it to the poster.
    private func post(_ value: Double) {
        if let onSample = onSample {
            onSample(ScrollSample(time: now(), kind: .output, value: value))
        }
        poster(value)
    }
```

- [ ] **Step 4: Rodar para ver passar**

Run: `swift test --filter ScrollSmootherCoordinatorTests`
Expected: PASS (todos, incluindo os 2 novos).

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift Tests/RatTamerCoreTests/Core/ScrollSmootherCoordinatorTests.swift
git commit -m "feat(core): ScrollSmootherCoordinator.onSample (raw + output)"
```

---

### Task 4: `ScrollGraphStore` (App)

**Files:**
- Create: `Sources/RatTamerApp/ScrollGraphStore.swift`

**Interfaces:**
- Consumes: `ScrollSampleBuffer`, `ScrollSample` (Core).
- Produces:
  - `final class ScrollGraphStore: ObservableObject`
  - `@Published private(set) var samples: [ScrollSample]`
  - `func add(_ sample: ScrollSample)` (chamado na queue do coordinator)
  - `func start()` (cria o timer de flush 30 Hz na main)
  - `func stop()` (invalida o timer)

- [ ] **Step 1: Implementação**

Create `Sources/RatTamerApp/ScrollGraphStore.swift`:

```swift
import Foundation
import RatTamerCore

/// Holds the live scroll samples produced by the smooth-scroll coordinator
/// and publishes a 5-second snapshot to the UI at 30 Hz. The timer only runs
/// while the graph view is visible, so an idle/hidden graph adds no wakeups.
final class ScrollGraphStore: ObservableObject {
    @Published private(set) var samples: [ScrollSample] = []

    private let buffer = ScrollSampleBuffer(capacity: 900)
    private let window: TimeInterval = 5
    private var timer: DispatchSourceTimer?

    func add(_ sample: ScrollSample) {
        buffer.append(sample)
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0 / 30.0,
                       repeating: 1.0 / 30.0,
                       leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.flush()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func flush() {
        samples = buffer.samples(in: window, before: Date())
    }
}
```

- [ ] **Step 2: Verificar build**

Run: `swift build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/ScrollGraphStore.swift
git commit -m "feat(app): ScrollGraphStore com flush 30 Hz"
```

---

### Task 5: `EngineController.scrollSampleSink`

**Files:**
- Modify: `Sources/RatTamerApp/EngineController.swift:398-416`

**Interfaces:**
- Consumes: `ScrollSample`, `ScrollSmootherCoordinator.onSample` (Task 3).
- Produces:
  - `var scrollSampleSink: ((ScrollSample) -> Void)?` no `EngineController` (default nil; a view liga no `.onAppear` e desliga no `.onDisappear`).

- [ ] **Step 1: Implementação**

In `Sources/RatTamerApp/EngineController.swift`:

Add the stored property next to `smoothCoordinator` (line 31):

```swift
    /// Where live scroll samples (raw + output) are forwarded while the
    /// scroll graph is visible. Wired by ScrollGraphView on appear/disappear.
    var scrollSampleSink: ((ScrollSample) -> Void)?
```

In `applySmoothScrollIfNeeded` (lines 411-413), build the coordinator as:

```swift
        let coordinator = ScrollSmootherCoordinator(smoother: ScrollSmoother(parameters: settings.parameters)) { [weak self] pixels in
            self?.postSmoothScroll(pixels)
        }
        coordinator.onSample = { [weak self] sample in
            self?.scrollSampleSink?(sample)
        }
```

- [ ] **Step 2: Verificar build**

Run: `swift build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/EngineController.swift
git commit -m "feat(app): EngineController.scrollSampleSink roteia onSample"
```

---

### Task 6: `ScrollGraphView` (Canvas termográfico)

**Files:**
- Create: `Sources/RatTamerApp/Views/ScrollGraphView.swift`

**Interfaces:**
- Consumes: `ScrollGraphStore` (Task 4), `EngineController.scrollSampleSink` (Task 5), `ScrollSample` (Core).
- Produces:
  - `struct ScrollGraphView: View` — usa `@StateObject var store = ScrollGraphStore()`; no `.onAppear` liga `AppModel.shared.engine?.scrollSampleSink = { [weak store] in store?.add($0) }` e chama `store.start()`; no `.onDisappear` zera o sink e chama `store.stop()`.

- [ ] **Step 1: Implementação**

Create `Sources/RatTamerApp/Views/ScrollGraphView.swift`:

```swift
import AppKit
import RatTamerCore
import SwiftUI

/// Live thermal scroll graph (RAT.ENERGY · TERMO): the raw wheel input shows
/// as ignition flares and the tamed output as an incandescent thermal wave
/// over a 5 s rolling window. Drawn in Canvas with an infrared palette.
struct ScrollGraphView: View {
    @StateObject private var store = ScrollGraphStore()

    var body: some View {
        Canvas { context, size in
            ScrollGraphPainter.draw(samples: store.samples, size: size, in: &context)
        }
        .frame(height: 210)
        .background(ScrollGraphPalette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.08)))
        .onAppear {
            AppModel.shared.engine?.scrollSampleSink = { [weak store] sample in
                store?.add(sample)
            }
            store.start()
        }
        .onDisappear {
            AppModel.shared.engine?.scrollSampleSink = nil
            store.stop()
        }
    }
}

/// Infrared camera palette used by the scroll graph.
enum ScrollGraphPalette {
    static let ink = Color(red: 0.039, green: 0.016, blue: 0.075)   // #0A0413
    static let grid = Color(red: 0.169, green: 0.082, blue: 0.133)  // #2B1522
    static let incandescent = Color(red: 1.0, green: 0.988, blue: 0.91)  // #FFFCE8
    static let ember = Color(red: 1.0, green: 0.812, blue: 0.49)    // #FFCF7D
    static let flare = Color(red: 1.0, green: 0.878, blue: 0.4)     // #FFE066

    /// Vertical thermal gradient: hot at the top of the wave, dark at rest.
    static let thermal: [Color] = [
        .init(red: 1.0, green: 0.988, blue: 0.91),   // #FFFCE8
        .init(red: 1.0, green: 0.878, blue: 0.4),    // #FFE066
        .init(red: 1.0, green: 0.706, blue: 0.33),   // #FFB454
        .init(red: 1.0, green: 0.369, blue: 0.227),  // #FF5E3A
        .init(red: 0.761, green: 0.145, blue: 0.184),// #C2252F
        .init(red: 0.427, green: 0.059, blue: 0.165),// #6D0F2A
        .init(red: 0.176, green: 0.043, blue: 0.239),// #2D0B3D
        .init(red: 0.039, green: 0.016, blue: 0.075),// #0A0413
    ]
}

/// Turns the sample array into the thermal waveform. Pure function of the
/// samples + canvas size; called once per 30 Hz frame.
enum ScrollGraphPainter {
    struct Plot {
        let left: CGFloat
        let right: CGFloat
        let bottom: CGFloat
        let top: CGFloat
        let window: TimeInterval = 5
        let yFloor: Double = 60

        func x(for time: Date, now: Date, width: CGFloat) -> CGFloat {
            let age = now.timeIntervalSince(time)
            let clamped = min(max(age, 0), window)
            let fraction = 1 - clamped / window
            return left + width * CGFloat(fraction)
        }

        func y(for value: Double, scale: CGFloat, midY: CGFloat) -> CGFloat {
            midY - CGFloat(value) * scale
        }
    }

    static func draw(samples: [ScrollSample], size: CGSize, in context: inout GraphicsContext) {
        let plot = Plot(left: 14, right: size.width - 34, bottom: size.height - 22, top: 8)
        let plotWidth = plot.right - plot.left
        let plotHeight = plot.bottom - plot.top
        let now = Date()
        let outputs = samples.filter { $0.kind == .output }
        let raws = samples.filter { $0.kind == .raw }

        // Y scale: symmetric ±max, with a floor so an idle graph does not zoom
        // into noise.
        let maxValue = max(
            outputs.map { abs($0.value) }.max() ?? 0,
            raws.map { abs($0.value) }.max() ?? 0
        )
        let halfRange = max(maxValue, plot.yFloor)
        let scale = (plotHeight / 2) / CGFloat(halfRange)
        let midY = plot.bottom - plotHeight / 2

        drawGrid(in: &context, plot: plot)

        if !outputs.isEmpty {
            drawThermalWave(outputs: outputs, in: &context, plot: plot, now: now, midY: midY, scale: scale)
            drawEmbers(outputs: outputs, in: &context, plot: plot, now: now, midY: midY, scale: scale)
        }
        for raw in raws {
            drawFlare(raw: raw, in: &context, plot: plot, now: now, midY: midY, scale: scale)
        }
        drawTemperatureBar(in: &context, plot: plot)
        drawHUD(in: &context, size: size, now: now, active: !outputs.isEmpty)
    }

    private static func outputPath(_ outputs: [ScrollSample], plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) -> Path {
        var path = Path()
        for (index, sample) in outputs.enumerated() {
            let x = plot.x(for: sample.time, now: now, width: plot.right - plot.left)
            let y = plot.y(for: sample.value, scale: scale, midY: midY)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private static func drawGrid(in context: inout GraphicsContext, plot: Plot) {
        var path = Path()
        for i in 0...4 {
            let y = plot.bottom - CGFloat(i) * (plot.bottom - plot.top) / 4
            path.move(to: CGPoint(x: plot.left, y: y))
            path.addLine(to: CGPoint(x: plot.right, y: y))
        }
        for i in 0...4 {
            let x = plot.left + CGFloat(i) * (plot.right - plot.left) / 4
            path.move(to: CGPoint(x: x, y: plot.top))
            path.addLine(to: CGPoint(x: x, y: plot.bottom))
        }
        context.stroke(path, with: .color(ScrollGraphPalette.grid), lineWidth: 1)
    }

    /// Glowing embers along the recent output curve, fading with age — the
    /// heat that is still dissipating after the wheel stops.
    private static func drawEmbers(outputs: [ScrollSample], in context: inout GraphicsContext,
                                   plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        for sample in outputs.suffix(10) {
            let age = now.timeIntervalSince(sample.time)
            guard age >= 0, age < 2 else { continue }
            let x = plot.x(for: sample.time, now: now, width: plot.right - plot.left)
            let y = plot.y(for: sample.value, scale: scale, midY: midY)
            let alpha = 1 - age / 2
            let dot = Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
            context.fill(dot, with: .color(ScrollGraphPalette.ember.opacity(alpha)))
        }
    }

    private static func drawThermalWave(outputs: [ScrollSample], in context: inout GraphicsContext,
                                        plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        let line = outputPath(outputs, plot: plot, now: now, midY: midY, scale: scale)

        // Area under the wave, filled with the vertical thermal gradient.
        var area = line
        if let last = outputs.last {
            let lastX = plot.x(for: last.time, now: now, width: plot.right - plot.left)
            area.addLine(to: CGPoint(x: lastX, y: plot.bottom))
        }
        if let first = outputs.first {
            let firstX = plot.x(for: first.time, now: now, width: plot.right - plot.left)
            area.addLine(to: CGPoint(x: firstX, y: plot.bottom))
        }
        area.closeSubpath()
        let gradient = Gradient(colors: ScrollGraphPalette.thermal)
        context.fill(area, with: .linearGradient(gradient,
                                                 startPoint: CGPoint(x: 0, y: plot.top),
                                                 endPoint: CGPoint(x: 0, y: plot.bottom)))

        // Incandescent line with a soft glow (double pass via a filtered layer).
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .white.opacity(0.55), radius: 5, x: 0, y: 0))
            layer.stroke(line, with: .color(ScrollGraphPalette.incandescent), lineWidth: 2.5)
        }
    }

    private static func drawFlare(raw: ScrollSample, in context: inout GraphicsContext,
                                  plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        let x = plot.x(for: raw.time, now: now, width: plot.right - plot.left)
        guard x >= plot.left else { return }
        let y = plot.y(for: raw.value, scale: scale, midY: midY)
        var halo = Path()
        halo.move(to: CGPoint(x: x, y: plot.bottom))
        halo.addLine(to: CGPoint(x: x, y: y - 10))
        context.stroke(halo, with: .color(ScrollGraphPalette.flare.opacity(0.35)), lineWidth: 6, lineCap: .round)

        var core = Path()
        core.move(to: CGPoint(x: x, y: plot.bottom))
        core.addLine(to: CGPoint(x: x, y: y))
        context.stroke(core, with: .color(ScrollGraphPalette.incandescent), lineWidth: 2, lineCap: .round)
    }

    private static func drawTemperatureBar(in context: inout GraphicsContext, plot: Plot) {
        let barX = plot.right + 10
        let bar = Path(roundedRect: CGRect(x: barX, y: plot.top, width: 12, height: plot.bottom - plot.top),
                       cornerRadius: 3)
        let gradient = Gradient(colors: ScrollGraphPalette.thermal)
        context.fill(bar, with: .linearGradient(gradient,
                                                startPoint: CGPoint(x: 0, y: plot.top),
                                                endPoint: CGPoint(x: 0, y: plot.bottom)))
        context.draw(Text("quente").font(.system(size: 9, design: .monospaced)),
                     at: CGPoint(x: barX + 6, y: plot.top - 6))
        context.draw(Text("frio").font(.system(size: 9, design: .monospaced)),
                     at: CGPoint(x: barX + 6, y: plot.bottom + 12))
    }

    private static func drawHUD(in context: inout GraphicsContext, size: CGSize, now: Date, active: Bool) {
        let status = active ? "● LIVE" : "○ IDLE"
        let text = Text("RAT.ENERGY · TERMO   5s   \(status)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(active ? ScrollGraphPalette.flare : Color.gray)
        context.draw(text, at: CGPoint(x: 14, y: size.height - 4))
    }
}
```

- [ ] **Step 2: Verificar build**

Run: `swift build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/Views/ScrollGraphView.swift
git commit -m "feat(app): ScrollGraphView (Canvas termográfico)"
```

---

### Task 7: Integrar no `AdvancedTabView`

**Files:**
- Modify: `Sources/RatTamerApp/Views/AdvancedTabView.swift:84-90`

- [ ] **Step 1: Implementação**

In `Sources/RatTamerApp/Views/AdvancedTabView.swift`, inside `tuningPanel`'s `VStack` (after `advancedPanel`, before the closing `}` of the VStack at line 86), add:

```swift
                advancedPanel
                    .disabled(!enabled)
                if enabled {
                    ScrollGraphView()
                }
```

- [ ] **Step 2: Verificar build**

Run: `swift build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/Views/AdvancedTabView.swift
git commit -m "feat(app): gráfico térmico no tab Advanced"
```

---

### Task 8: Verificação completa e revisão

**Files:** nenhum (verificação).

- [ ] **Step 1: Suíte completa**

Run: `swift test`
Expected: PASS — suíte existente (328 + novos) sem quebrar.

- [ ] **Step 2: Build da app assinada**

Run: `./build-app.sh`
Expected: app assinada em `build/RatTamer.app`.

- [ ] **Step 3: Relançar e verificar visualmente**

Run: `open build/RatTamer.app`
- Abrir Settings → Advanced, ligar "Smooth scrolling", rolar o mouse e confirmar: onda térmica flui, flares de ignição nos entalhes, barra de temperatura à direita, HUD `RAT.ENERGY · TERMO`.
- Desligar o smooth scroll → gráfico some.
- Fechar o tab Advanced → nenhum timer ativo (zero wakeups extra; conferir no Monitor de Atividade).

- [ ] **Step 4: Veredito**

Reportar resultado (aprovado/ok ou achados) no `docs/superpowers/specs/2026-08-10-scroll-thermograph-design.md` (seção Veredito) e commitar.

---

# Rev 2 — Janela externa + gráfico descritivo

Aprovação: usuário (2026-08-10). Spec Rev 2 commitada (`81812e3`).
Reescreve a "camada App" das tasks 4-7: o gráfico sai do tab Advanced e vai
para uma janela externa, com descritividade (eixos, leituras, legenda) e aviso
de smooth desligado. Tasks 9-11 implementam; Task 12 verifica. O Core
(tasks 1-3) não muda.

### Task 9: `ScrollGraphWindow` (janela externa)

**Files:** criar `Sources/RatTamerApp/ScrollGraphWindow.swift`.

Singleton no padrão de `SettingsWindow` (SettingsWindow.swift:10-41). É o dono
do `ScrollGraphStore` e do lifecycle: conectar/desconectar o sink e
start/stop do flush. **A janela nasce fechada** (`makeWindowIfNeeded` só roda
no primeiro `show()`), então app sem o gráfico aberto custa zero.

```swift
import AppKit
import SwiftUI

/// External window hosting the live thermal scroll graph. Closed by default
/// at launch: opening it is the only thing that connects the sample sink and
/// starts the 30 Hz flush, so a closed window costs nothing.
final class ScrollGraphWindow: NSObject, NSWindowDelegate {
    static let shared = ScrollGraphWindow()
    private var window: NSWindow?
    private let store = ScrollGraphStore()

    private override init() {}

    func show() {
        makeWindowIfNeeded()
        AppModel.shared.engine?.scrollSampleSink = { [weak store] sample in
            store?.add(sample)
        }
        store.start()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        AppModel.shared.engine?.scrollSampleSink = nil
        store.stop()
    }

    private func makeWindowIfNeeded() {
        guard window == nil else { return }
        let view = ScrollGraphView(store: store)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        let window = SettingsNSWindow(contentViewController: hosting)
        window.title = "RatTamer — Scroll Thermograph"
        window.setContentSize(NSSize(width: 640, height: 400))
        window.contentMinSize = NSSize(width: 480, height: 280)
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("RatTamerScrollThermograph")
        self.window = window
    }
}
```

Steps (TDD é do Core; esta é camada App → build-verified):
1. Criar o arquivo verbatim acima. `SettingsNSWindow` já existe
   (SettingsWindow.swift:4-8) e dá o `Esc` → close.
2. Build: `swift build` (BUILD SUCCESSFUL). `swift test` continua verde.
3. Commit: `git add Sources/RatTamerApp/ScrollGraphWindow.swift` →
   `git commit -m "feat(app): ScrollGraphWindow - janela externa do termógrafo"`.

### Task 10: `ScrollGraphView` descritivo (Rev 2)

**Files:** reescrever `Sources/RatTamerApp/Views/ScrollGraphView.swift`.

A view perde o `@StateObject` e o lifecycle (agora do `ScrollGraphWindow`) e
ganha: `@ObservedObject var store`, eixo Y com rótulos de pixels, eixo X com
rótulos de tempo, leituras ao vivo, legenda e estado vazio (smooth desligado).
Paleta térmica **inalterada** (`ScrollGraphPalette`). Todo o conteúdo novo é
do painter; a view só passa `smoothEnabled` lido do config a cada frame.

```swift
import AppKit
import RatTamerCore
import SwiftUI

/// Live thermal scroll graph (RAT.ENERGY · TERMO) hosted in its own window.
/// Descriptive: time/pixel axes, live readouts and a raw/smoothed legend over
/// the thermal canvas. The store lifecycle is owned by `ScrollGraphWindow`.
struct ScrollGraphView: View {
    @ObservedObject var store: ScrollGraphStore

    var body: some View {
        let smoothEnabled = AppModel.shared.configStore.load().smoothScrollEnabled == true
        Canvas { context, size in
            ScrollGraphPainter.draw(samples: store.samples,
                                    smoothEnabled: smoothEnabled,
                                    size: size,
                                    in: &context)
        }
        .frame(height: 320)
        .background(ScrollGraphPalette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.08)))
        .padding()
    }
}

/// Infrared camera palette used by the scroll graph.
enum ScrollGraphPalette {
    static let ink = Color(red: 0.039, green: 0.016, blue: 0.075)   // #0A0413
    static let grid = Color(red: 0.169, green: 0.082, blue: 0.133)  // #2B1522
    static let incandescent = Color(red: 1.0, green: 0.988, blue: 0.91)  // #FFFCE8
    static let ember = Color(red: 1.0, green: 0.812, blue: 0.49)    // #FFCF7D
    static let flare = Color(red: 1.0, green: 0.878, blue: 0.4)     // #FFE066
    static let dimText = Color(red: 0.55, green: 0.45, blue: 0.55)

    /// Vertical thermal gradient: hot at the top of the wave, dark at rest.
    static let thermal: [Color] = [
        .init(red: 1.0, green: 0.988, blue: 0.91),   // #FFFCE8
        .init(red: 1.0, green: 0.878, blue: 0.4),    // #FFE066
        .init(red: 1.0, green: 0.706, blue: 0.33),   // #FFB454
        .init(red: 1.0, green: 0.369, blue: 0.227),  // #FF5E3A
        .init(red: 0.761, green: 0.145, blue: 0.184),// #C2252F
        .init(red: 0.427, green: 0.059, blue: 0.165),// #6D0F2A
        .init(red: 0.176, green: 0.043, blue: 0.239),// #2D0B3D
        .init(red: 0.039, green: 0.016, blue: 0.075),// #0A0413
    ]
}

/// Turns the sample array into the thermal waveform. Pure function of the
/// samples + canvas size; called once per 30 Hz frame.
enum ScrollGraphPainter {
    struct Plot {
        let left: CGFloat
        let right: CGFloat
        let bottom: CGFloat
        let top: CGFloat
        let window: TimeInterval = 5
        let yFloor: Double = 60

        func x(for time: Date, now: Date, width: CGFloat) -> CGFloat {
            let age = now.timeIntervalSince(time)
            let clamped = min(max(age, 0), window)
            let fraction = 1 - clamped / window
            return left + width * CGFloat(fraction)
        }

        func y(for value: Double, scale: CGFloat, midY: CGFloat) -> CGFloat {
            midY - CGFloat(value) * scale
        }
    }

    static func draw(samples: [ScrollSample], smoothEnabled: Bool,
                     size: CGSize, in context: inout GraphicsContext) {
        let plot = Plot(left: 42, right: size.width - 40, bottom: size.height - 22, top: 10)
        let plotHeight = plot.bottom - plot.top
        let now = Date()
        let outputs = samples.filter { $0.kind == .output }
        let raws = samples.filter { $0.kind == .raw }

        let maxValue = max(
            outputs.map { abs($0.value) }.max() ?? 0,
            raws.map { abs($0.value) }.max() ?? 0
        )
        let range = roundedRange(max(maxValue, plot.yFloor))
        let scale = (plotHeight / 2) / CGFloat(range)
        let midY = plot.bottom - plotHeight / 2

        drawGridAndAxes(in: &context, plot: plot, now: now, range: range)

        if smoothEnabled {
            if !outputs.isEmpty {
                drawThermalWave(outputs: outputs, in: &context, plot: plot, now: now, midY: midY, scale: scale)
                drawEmbers(outputs: outputs, in: &context, plot: plot, now: now, midY: midY, scale: scale)
            }
            for raw in raws {
                drawFlare(raw: raw, in: &context, plot: plot, now: now, midY: midY, scale: scale)
            }
        } else {
            drawEmptyState(in: &context, plot: plot)
        }
        drawTemperatureBar(in: &context, plot: plot)
        drawHUD(in: &context, size: size, active: smoothEnabled && !outputs.isEmpty)
        drawReadouts(outputs: outputs, raws: raws, in: &context, size: size)
        drawLegend(in: &context, size: size)
    }

    /// Rounds the symmetric Y range up to the nearest multiple of 60 so axis
    /// labels are clean (120 / 60 / 0 / -60 / -120), never noisy.
    static func roundedRange(_ value: Double) -> Double {
        let step: Double = 60
        return max(step, (value / step).rounded(.up) * step)
    }

    private static func outputPath(_ outputs: [ScrollSample], plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) -> Path {
        var path = Path()
        for (index, sample) in outputs.enumerated() {
            let x = plot.x(for: sample.time, now: now, width: plot.right - plot.left)
            let y = plot.y(for: sample.value, scale: scale, midY: midY)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private static func drawGridAndAxes(in context: inout GraphicsContext, plot: Plot, now: Date, range: Double) {
        var grid = Path()
        for i in 0...4 {
            let y = plot.bottom - CGFloat(i) * (plot.bottom - plot.top) / 4
            grid.move(to: CGPoint(x: plot.left, y: y))
            grid.addLine(to: CGPoint(x: plot.right, y: y))
        }
        for age in 1...5 {
            let x = plot.left + (1 - CGFloat(age) / 5) * (plot.right - plot.left)
            grid.move(to: CGPoint(x: x, y: plot.top))
            grid.addLine(to: CGPoint(x: x, y: plot.bottom))
        }
        context.stroke(grid, with: .color(ScrollGraphPalette.grid), lineWidth: 1)

        // Y labels (pixels) aligned to the horizontal gridlines.
        let yLabelFont = Font.system(size: 9, design: .monospaced)
        for i in 0...4 {
            let value = range - Double(i) * (range / 2)
            let y = plot.bottom - CGFloat(i) * (plot.bottom - plot.top) / 4
            let label = Text(Int(value).description)
                .font(yLabelFont)
                .foregroundStyle(ScrollGraphPalette.dimText)
            context.draw(label, at: CGPoint(x: plot.left - 4, y: y - 4), anchor: .trailing)
        }

        // X labels (time) below the vertical 1 s gridlines.
        for age in 0...5 {
            let x = plot.left + (1 - CGFloat(age) / 5) * (plot.right - plot.left)
            let label = Text(age == 0 ? "0" : "-\(age)s")
                .font(yLabelFont)
                .foregroundStyle(ScrollGraphPalette.dimText)
            context.draw(label, at: CGPoint(x: x, y: plot.bottom + 12), anchor: .center)
        }
    }

    /// Glowing embers along the recent output curve, fading with age - the
    /// heat that is still dissipating after the wheel stops.
    private static func drawEmbers(outputs: [ScrollSample], in context: inout GraphicsContext,
                                   plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        for sample in outputs.suffix(10) {
            let age = now.timeIntervalSince(sample.time)
            guard age >= 0, age < 2 else { continue }
            let x = plot.x(for: sample.time, now: now, width: plot.right - plot.left)
            let y = plot.y(for: sample.value, scale: scale, midY: midY)
            let alpha = 1 - age / 2
            let dot = Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
            context.fill(dot, with: .color(ScrollGraphPalette.ember.opacity(alpha)))
        }
    }

    private static func drawThermalWave(outputs: [ScrollSample], in context: inout GraphicsContext,
                                        plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        let line = outputPath(outputs, plot: plot, now: now, midY: midY, scale: scale)

        var area = line
        if let last = outputs.last {
            let lastX = plot.x(for: last.time, now: now, width: plot.right - plot.left)
            area.addLine(to: CGPoint(x: lastX, y: plot.bottom))
        }
        if let first = outputs.first {
            let firstX = plot.x(for: first.time, now: now, width: plot.right - plot.left)
            area.addLine(to: CGPoint(x: firstX, y: plot.bottom))
        }
        area.closeSubpath()
        let gradient = Gradient(colors: ScrollGraphPalette.thermal)
        context.fill(area, with: .linearGradient(gradient,
                                                 startPoint: CGPoint(x: 0, y: plot.top),
                                                 endPoint: CGPoint(x: 0, y: plot.bottom)))

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .white.opacity(0.55), radius: 5, x: 0, y: 0))
            layer.stroke(line, with: .color(ScrollGraphPalette.incandescent), lineWidth: 2.5)
        }
    }

    private static func drawFlare(raw: ScrollSample, in context: inout GraphicsContext,
                                  plot: Plot, now: Date, midY: CGFloat, scale: CGFloat) {
        let x = plot.x(for: raw.time, now: now, width: plot.right - plot.left)
        guard x >= plot.left else { return }
        let y = plot.y(for: raw.value, scale: scale, midY: midY)
        var halo = Path()
        halo.move(to: CGPoint(x: x, y: plot.bottom))
        halo.addLine(to: CGPoint(x: x, y: y - 10))
        context.stroke(halo, with: .color(ScrollGraphPalette.flare.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))

        var core = Path()
        core.move(to: CGPoint(x: x, y: plot.bottom))
        core.addLine(to: CGPoint(x: x, y: y))
        context.stroke(core, with: .color(ScrollGraphPalette.incandescent),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private static func drawTemperatureBar(in context: inout GraphicsContext, plot: Plot) {
        let barX = plot.right + 6
        let bar = Path(roundedRect: CGRect(x: barX, y: plot.top, width: 12, height: plot.bottom - plot.top),
                       cornerRadius: 3)
        let gradient = Gradient(colors: ScrollGraphPalette.thermal)
        context.fill(bar, with: .linearGradient(gradient,
                                                startPoint: CGPoint(x: 0, y: plot.top),
                                                endPoint: CGPoint(x: 0, y: plot.bottom)))
        let font = Font.system(size: 9, design: .monospaced)
        context.draw(Text("quente").font(font).foregroundStyle(ScrollGraphPalette.dimText),
                     at: CGPoint(x: barX + 6, y: plot.top - 6))
        context.draw(Text("frio").font(font).foregroundStyle(ScrollGraphPalette.dimText),
                     at: CGPoint(x: barX + 6, y: plot.bottom + 12))
    }

    private static func drawHUD(in context: inout GraphicsContext, size: CGSize, active: Bool) {
        let status = active ? "● LIVE" : "○ IDLE"
        let text = Text("RAT.ENERGY · TERMO   5s   \(status)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(active ? ScrollGraphPalette.flare : Color.gray)
        context.draw(text, at: CGPoint(x: 14, y: size.height - 4))
    }

    /// Live numeric readouts of the 5 s window, right-aligned.
    private static func drawReadouts(outputs: [ScrollSample], raws: [ScrollSample],
                                     in context: inout GraphicsContext, size: CGSize) {
        let lastOut = outputs.last?.value
        let lastRaw = raws.last?.value
        let peak = outputs.map { abs($0.value) }.max() ?? 0
        let avg = outputs.isEmpty ? 0 : outputs.reduce(0) { $0 + abs($1.value) } / Double(outputs.count)
        let out = lastOut.map { String(format: "%6.1f", $0) } ?? "    —"
        let raw = lastRaw.map { String(format: "%6.0f", $0) } ?? "    —"
        let lines = [
            "out  \(out)",
            "raw  \(raw)",
            "peak \(String(format: "%6.0f", peak))",
            "avg  \(String(format: "%6.1f", avg))",
        ]
        let font = Font.system(size: 9, design: .monospaced)
        let color = outputs.isEmpty ? ScrollGraphPalette.dimText : ScrollGraphPalette.incandescent
        var y = size.height - 6
        for line in lines {
            context.draw(Text(line).font(font).foregroundStyle(color),
                         at: CGPoint(x: size.width - 6, y: y), anchor: .trailing)
            y -= 11
        }
    }

    /// Legend mapping the two visual languages to the two data series.
    private static func drawLegend(in context: inout GraphicsContext, size: CGSize) {
        let font = Font.system(size: 9, design: .monospaced)
        context.draw(Text("RAW entrada").font(font).foregroundStyle(ScrollGraphPalette.dimText),
                     at: CGPoint(x: size.width - 6, y: size.height - 52), anchor: .trailing)
        context.draw(Text("SMOOTHED saída").font(font).foregroundStyle(ScrollGraphPalette.dimText),
                     at: CGPoint(x: size.width - 6, y: size.height - 64), anchor: .trailing)
    }

    private static func drawEmptyState(in context: inout GraphicsContext, plot: Plot) {
        let rect = Path(CGRect(x: plot.left, y: plot.top,
                               width: plot.right - plot.left, height: plot.bottom - plot.top))
        context.fill(rect, with: .color(ScrollGraphPalette.ink.opacity(0.7)))
        let text = Text("Ligue o Smooth scrolling para capturar")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(ScrollGraphPalette.dimText)
        let center = CGPoint(x: (plot.left + plot.right) / 2, y: (plot.top + plot.bottom) / 2)
        context.draw(text, at: center)
    }
}
```

Notas para o implementador:
- `Path(CGRect)` e `Path(roundedRect:cornerRadius:)` são os inits públicos;
  `context.draw(_:at:anchor:)` e `context.stroke(_:style:)` existem em
  `GraphicsContext`.
- A view passa `smoothEnabled` lido do `AppModel.shared.configStore.load()` a
  cada frame; o body re-renderiza a 30 Hz por causa do `@Published` do store.
- Não esquecer: sem `.onAppear`/`.onDisappear` na view (lifecycle é da janela).

Steps:
1. Reescrever `ScrollGraphView.swift` verbatim.
2. `swift build` (BUILD SUCCESSFUL) - ajustes apenas de API/estilo exigidos
   pelo compilador, mantendo o visual. `swift test` continua verde (337).
3. Commit: `git add Sources/RatTamerApp/Views/ScrollGraphView.swift` →
   `git commit -m "feat(app): ScrollGraphView descritivo (eixos, leituras, legenda, aviso)"`.

### Task 11: Botão no Advanced + item de menu

**Files:** modificar `Sources/RatTamerApp/Views/AdvancedTabView.swift` e
`Sources/RatTamerApp/AppDelegate.swift`.

1. **AdvancedTabView** - substituir o bloco inline (linhas 86-88 atuais) por um
   botão sempre visível (não fica `disabled` quando `!enabled`; o aviso é da
   janela):

```swift
                advancedPanel
                    .disabled(!enabled)
                Button(action: { ScrollGraphWindow.shared.show() }) {
                    Label("Open Scroll Thermograph…", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.bordered)
                .help("Live thermal graph of raw vs smoothed scrolling in a separate window.")
```

2. **AppDelegate** - criar o main menu com o item "Scroll Thermograph…"
   (Cmd+Shift+T) chamando `ScrollGraphWindow.shared.show()`. Adicionar
   `buildMainMenu()` em `applicationDidFinishLaunching` (antes de
   `menuBar?.buildMenu()`) e o método `@objc`:

```swift
    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let graphItem = NSMenuItem(title: "Scroll Thermograph…",
                                   action: #selector(showScrollThermograph),
                                   keyEquivalent: "t")
        graphItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(NSMenuItem(title: "About RatTamer",
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(graphItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit RatTamer",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showScrollThermograph() {
        ScrollGraphWindow.shared.show()
    }
```

Steps:
1. Aplicar as duas mudanças.
2. `swift build` (BUILD SUCCESSFUL). `swift test` continua verde (337).
3. Commit: `git add Sources/RatTamerApp/Views/AdvancedTabView.swift Sources/RatTamerApp/AppDelegate.swift` →
   `git commit -m "feat(app): botão e item de menu para o Scroll Thermograph"`.

### Task 12: Verificação completa + veredito (Rev 2)

**Files:** nenhum (verificação).

- [ ] **Step 1: Suíte completa** - `swift test` (337, sem quebrar).
- [ ] **Step 2: Build assinado** - `bash scripts/build-app.sh` → app em
  `build/RatTamer.app`.
- [ ] **Step 3: App abre sem gráfico** - relançar `open build/RatTamer.app`;
  janela do gráfico NÃO abre sozinha (fechada por padrão).
- [ ] **Step 4: Abrir via menu** - `NSApp.mainMenu` tem "Scroll Thermograph…"
  (Cmd+Shift+T) e abre a janela.
- [ ] **Step 5: Abrir via botão** - tab Advanced tem "Open Scroll Thermograph…";
  abre a janela.
- [ ] **Step 6: Gráfico descritivo ao vivo** - com smooth ligado e rolando:
  eixos X (-5s..0) e Y (escala de pixels), leituras `out/raw/peak/avg`,
  legenda RAW/SMOOTHED, barra "quente/frio", HUD `RAT.ENERGY · TERMO`.
- [ ] **Step 7: Aviso smooth desligado** - desligar smooth → janela mostra
  "Ligue o Smooth scrolling para capturar".
- [ ] **Step 8: Zero consumo com janela fechada** - fechar a janela; conferir
  no Monitor de Atividade que não há timer/CPU ativo do gráfico.
- [ ] **Step 9: Veredito** - reportar resultado (aprovado/ok ou achados) na
  seção Veredito da spec e commitar.
