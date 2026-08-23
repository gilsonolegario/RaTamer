# Otimização de código (hot path + robustez + qualidade) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminar custo por frame desnecessário no smooth scroll (120 Hz), eliminar o risco de congelamento da UI por I/O HID síncrono na main thread, limitar o wait de ownership do mailbox, e limpar warnings/re-leitura de config.

**Architecture:** Quatro frentes independentes entre si, na ordem certa para dependências: (1) hot path — remover log por frame, cachear `AXIsProcessTrusted()` com TTL e subir o TTL do `FrontmostAppGuard`; (2) mailbox — `beginRequest(timeout:) -> Bool` com wait limitado, exposto no protocolo `HIDDevice`; (3) session — `request()`/`ping()` usam o wait limitado e lançam `noResponse`; (4) `ConfigStore` — cache mtime-guardado e thread-safe, que habilita (5) mover os loads de device I/O dos views para fora da main thread seguindo o padrão de `AppModel.preloadDPI`; (6) CrashReporter — remover `try?` em chamadas non-throwing.

**Tech Stack:** Swift 5 (tools 5.9), SwiftPM, macOS 14+. Testes: XCTest (`RatTamerCoreTests`).

## Global Constraints

- `beginRequest()` sem argumentos é preservado — os testes existentes (`HIDReportMailboxTests.swift:83`) o usam.
- `ConfigStore.loadStrict()` continua lendo do disco sempre (sem cache).
- Nenhuma mudança no teardown do mailbox (`wake`) nem no caminho de reconexão/watchdog.
- `EngineController.controls` **não** é alterado (o data race foi refutado — toda leitura/escrita é na main thread).
- Loads async dos views seguem exatamente o padrão de `AppModel.preloadDPI` (`DispatchQueue.global(qos: .utility).async` + hop para main).
- Escritas de device I/O (apply/applyConfig) já são off-main via `ioQueue` — não alterar.
- Não introduzir novos warnings de build; os 345 testes existentes devem continuar passando.
- Sem comentários novos no código além dos que já existem (manter docstrings do estilo do arquivo).

---

### Task 1: Hot path — remover custos por frame no smooth scroll

Remove os dois custos não-essenciais que rodam a cada evento postado (até 120 Hz):
o `os_log` por amostra no coordinator e o `AXIsProcessTrusted()` sem cache por
evento. O terceiro ajuste reduz a frequência do lookup caro de `NSWorkspace`.

**Files:**
- Modify: `Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift:108-114`
- Modify: `Sources/RatTamerApp/Permissions.swift`
- Modify: `Sources/RatTamerApp/FrontmostAppGuard.swift:10`

**Interfaces:**
- Consumes: nada de tasks anteriores.
- Produces: `Permissions.isAccessibilityTrusted() -> Bool` e `Permissions.requestAccessibility()` com a MESMA assinatura de hoje (cache interno). `FrontmostAppGuard.isFrontmostTerminal()` inalterado na API.

- [x] **Step 1: Remover o log por frame no coordinator**

Em `Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift`, dentro de `private func post(_ value: Double)` (linhas 108-114), remover a linha:

```swift
Self.log.info("OUT \(value, format: .fixed(precision: 2))")
```

O método `post` fica:

```swift
private func post(_ value: Double) {
    if let onSample = onSample {
        onSample(ScrollSample(time: now(), kind: .output, value: value))
    }
    poster(value)
}
```

`Self.log` continua sendo usado em `start()`/`stop()` — o import de `os` fica.

- [x] **Step 2: Cache de `AXIsProcessTrusted()` com TTL no `Permissions`**

Substituir o conteúdo de `Sources/RatTamerApp/Permissions.swift` por:

```swift
import ApplicationServices
import Foundation

enum Permissions {
    private static let lock = NSLock()
    private static let cacheTTL: TimeInterval = 0.5
    private static var cachedTrusted = false
    private static var cachedAt = Date.distantPast

    static func isAccessibilityTrusted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(cachedAt) < cacheTTL else {
            let value = AXIsProcessTrusted()
            cachedTrusted = value
            cachedAt = now
            return value
        }
        return cachedTrusted
    }

    static func requestAccessibility() {
        lock.lock()
        cachedAt = .distantPast
        lock.unlock()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
```

- [x] **Step 3: Subir o TTL do `FrontmostAppGuard`**

Em `Sources/RatTamerApp/FrontmostAppGuard.swift:10`, trocar:

```swift
private static let cacheTTL: TimeInterval = 0.1
```

por:

```swift
private static let cacheTTL: TimeInterval = 0.25
```

- [x] **Step 4: Build e testes de regressão**

Run: `swift test`
Expected: todos os testes passam (nenhuma mudança de comportamento; `ScrollSmootherCoordinatorTests` e demais intactos). `swift build` não pode gerar warnings novos.

- [x] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift Sources/RatTamerApp/Permissions.swift Sources/RatTamerApp/FrontmostAppGuard.swift
git commit -m "perf: remove custos por frame no smooth scroll (os_log e AXIsProcessTrusted)"
```

---

### Task 2: Mailbox — `beginRequest(timeout:)` com wait limitado

Adiciona aquisição de ownership com timeout ao `HIDReportMailbox`, expõe no
protocolo `HIDDevice` (com default no-op) e implementa no wrapper real e no mock.
Um device travado não pode mais bloquear um chamador indefinidamente.

**Files:**
- Modify: `Sources/RatTamerCore/HIDPP/HIDReportMailbox.swift:108-123`
- Modify: `Sources/RatTamerCore/HIDPP/HIDDevice.swift:15-30`
- Modify: `Sources/RatTamerCore/HIDPP/IOHIDDeviceWrapper.swift:79-85`
- Test: `Tests/RatTamerCoreTests/HIDPP/HIDReportMailboxTests.swift`
- Modify: `Tests/RatTamerCoreTests/Support/MockHIDDevice.swift:40-46`

**Interfaces:**
- Consumes: nada de tasks anteriores.
- Produces: `HIDReportMailbox.beginRequest(timeout: TimeInterval) -> Bool`
  (true = ownership adquirido; false = timeout sem adquirir, sem mudar estado);
  `HIDDevice.beginRequest(timeout: TimeInterval) -> Bool` no protocolo, default
  na extension = `true`; `IOHIDDeviceWrapper.beginRequest(timeout:)` delegando ao
  mailbox; `MockHIDDevice.beginRequest(timeout:)` delegando ao seu mailbox.
  A Task 3 consome `device.beginRequest(timeout:)`.

- [x] **Step 1: Escrever o teste que falha**

Em `Tests/RatTamerCoreTests/HIDPP/HIDReportMailboxTests.swift`, adicionar:

```swift
func testBeginRequestTimesOutWhenOwnershipHeld() {
    let mailbox = HIDReportMailbox(capacity: 16)
    mailbox.beginRequest()
    XCTAssertFalse(mailbox.beginRequest(timeout: 0.1))
    XCTAssertNil(mailbox.read(timeout: 0), "gate must still be held by the first request")
    mailbox.endRequest()
    XCTAssertTrue(mailbox.beginRequest(timeout: 0.1))
    mailbox.endRequest()
}
```

- [x] **Step 2: Rodar o teste para verificar que falha**

Run: `swift test --filter HIDReportMailboxTests/testBeginRequestTimesOutWhenOwnershipHeld`
Expected: FAIL — `beginRequest(timeout:)` não existe (erro de compilação do teste).

- [x] **Step 3: Implementar `beginRequest(timeout:)` no mailbox**

Em `Sources/RatTamerCore/HIDPP/HIDReportMailbox.swift`, substituir o corpo de
`beginRequest()` (linhas 108-116) por:

```swift
func beginRequest(timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    condition.lock()
    defer { condition.unlock() }
    while activeRequests > 0 {
        if !condition.wait(until: deadline) {
            return false
        }
    }
    activeRequests = 1
    condition.broadcast()
    return true
}

func beginRequest() {
    _ = beginRequest(timeout: .greatestFiniteMagnitude)
}
```

Mantém o docstring existente da semântica de exclusividade acima de
`beginRequest(timeout:)`.

- [x] **Step 4: Expor no protocolo `HIDDevice`**

Em `Sources/RatTamerCore/HIDPP/HIDDevice.swift`, adicionar após o
`func beginRequest()` (linha 15):

```swift
/// Marks the start of a synchronous feature request with a bounded wait.
/// Returns false if ownership could not be acquired before `timeout` elapses,
/// without changing state (the caller should treat it as a failed request).
func beginRequest(timeout: TimeInterval) -> Bool
```

E na extension (após `func beginRequest() {}`, linha 39):

```swift
func beginRequest(timeout: TimeInterval) -> Bool { true }
```

- [x] **Step 5: Implementar no wrapper real**

Em `Sources/RatTamerCore/HIDPP/IOHIDDeviceWrapper.swift`, após
`mailbox.beginRequest()` (linha 80):

```swift
public func beginRequest(timeout: TimeInterval) -> Bool {
    mailbox.beginRequest(timeout: timeout)
}
```

- [x] **Step 6: Implementar no mock**

Em `Tests/RatTamerCoreTests/Support/MockHIDDevice.swift`, após
`mailbox.beginRequest()` (linha 41):

```swift
func beginRequest(timeout: TimeInterval) -> Bool {
    mailbox.beginRequest(timeout: timeout)
}
```

- [x] **Step 7: Rodar o teste para verificar que passa**

Run: `swift test --filter HIDReportMailboxTests`
Expected: PASS — o novo teste passa e os existentes continuam passando (o
`beginRequest()` no-arg foi preservado e delega).

- [x] **Step 8: Commit**

```bash
git add Sources/RatTamerCore/HIDPP/HIDReportMailbox.swift Sources/RatTamerCore/HIDPP/HIDDevice.swift Sources/RatTamerCore/HIDPP/IOHIDDeviceWrapper.swift Tests/RatTamerCoreTests/Support/MockHIDDevice.swift Tests/RatTamerCoreTests/HIDPP/HIDReportMailboxTests.swift
git commit -m "feat(core): beginRequest com timeout no mailbox (falha rápida em vez de bloquear)"
```

---

### Task 3: Session — `request()`/`ping()` usam ownership limitado

`HIDPPSession.request` e `ping` adquirem o ownership com o wait limitado; se não
conseguirem no prazo dos seus timeouts, lançam `HIDPPSessionError.noResponse` em
vez de bloquear para sempre.

**Files:**
- Modify: `Sources/RatTamerCore/HIDPP/HIDPPSession.swift:71-95` (request) e `:111-135` (ping)
- Test: `Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift`

**Interfaces:**
- Consumes: `HIDDevice.beginRequest(timeout:) -> Bool` (Task 2).
- Produces: `request(...)` e `ping(...)` com a MESMA assinatura pública de hoje,
  mas com o novo comportamento de lançar `HIDPPSessionError.noResponse` se o
  ownership não for adquirido no prazo. A Task 4 em diante não depende disso.

- [x] **Step 1: Escrever o teste que falha**

Em `Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift`, adicionar:

```swift
func testRequestThrowsWhenRequestOwnershipHeld() throws {
    let mock = MockHIDDevice()
    let session = HIDPPSession(device: mock)
    mock.beginRequest()
    XCTAssertThrowsError(try session.request(deviceIndex: 1, featureIndex: 2, functionID: 3, timeout: 0.05)) { error in
        XCTAssertEqual(error as? HIDPPSessionError, .noResponse)
    }
    mock.endRequest()
}
```

- [x] **Step 2: Rodar o teste para verificar que falha**

Run: `swift test --filter HIDPPSessionTests/testRequestThrowsWhenRequestOwnershipHeld`
Expected: no estado pré-mudança o teste **trava/deadlocka** — `request` chama o
`beginRequest()` unbounded na mesma thread que já detém o ownership
(NSCondition não é reentrante), e o XCTest fica preso. Esse travamento é
exatamente o bug que a Task 3 corrige; ao implementar, o teste passa. Para não
travar a suíte, rodar com timeout externo: `timeout 30 swift test --filter
HIDPPSessionTests/testRequestThrowsWhenRequestOwnershipHeld` (retorna 124 = hang
esperado).

- [x] **Step 3: Implementar no `request`**

Em `Sources/RatTamerCore/HIDPP/HIDPPSession.swift`, dentro de `request(...)`
(linha 78), substituir:

```swift
device.beginRequest()
defer { device.endRequest() }
```

por:

```swift
guard device.beginRequest(timeout: timeout) else {
    throw HIDPPSessionError.noResponse
}
defer { device.endRequest() }
```

- [x] **Step 4: Implementar no `ping`**

Em `Sources/RatTamerCore/HIDPP/HIDPPSession.swift`, dentro de `ping(...)`
(linha 117), substituir:

```swift
device.beginRequest()
defer { device.endRequest() }
```

por:

```swift
guard device.beginRequest(timeout: 0.4) else {
    throw HIDPPSessionError.noResponse
}
defer { device.endRequest() }
```

- [x] **Step 5: Rodar o teste para verificar que passa**

Run: `swift test --filter HIDPPSessionTests`
Expected: PASS — o novo teste passa; todos os existentes de `HIDPPSessionTests`
continuam passando (o mock adquire ownership imediatamente em
`beginRequest(timeout:)` quando ninguém detém).

- [x] **Step 6: Commit**

```bash
git add Sources/RatTamerCore/HIDPP/HIDPPSession.swift Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift
git commit -m "feat(core): request/ping lançam noResponse quando o ownership não é adquirido a tempo"
```

---

### Task 4: ConfigStore — cache mtime-guardado e thread-safe

`ConfigStore.load()` memoiza o config após a primeira leitura do disco, invalida
no `save()` ou se o mtime do arquivo mudar (preserva edição externa). O cache é
protegido por NSLock para `load()` poder rodar de qualquer thread (a Task 5 o
chama de uma queue de utility).

**Files:**
- Modify: `Sources/RatTamerCore/Core/ConfigStore.swift:302-342`
- Test: `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: nada de tasks anteriores.
- Produces: `ConfigStore.load() -> Config` com a MESMA assinatura (agora com
  cache interno thread-safe); `save(_:)` inaltera na API e também atualiza o
  cache. `loadStrict()` permanece lendo o disco. A Task 5 consome `load()` de
  uma queue de utility.

- [x] **Step 1: Escrever os testes que falham**

Em `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`, adicionar:

```swift
func testLoadReloadsWhenFileChangesExternally() throws {
    let url = tempDir.appendingPathComponent("config.json")
    let store = ConfigStore(fileURL: url)
    var config = Config.empty()
    config.dpiValue = 1000
    try store.save(config)
    XCTAssertEqual(store.load().dpiValue, 1000)
    var edited = Config.empty()
    edited.dpiValue = 4000
    let editedData = try JSONEncoder().encode(edited)
    try editedData.write(to: url, options: .atomic)
    XCTAssertEqual(store.load().dpiValue, 4000)
}

func testLoadReturnsEmptyAfterFileDeleted() throws {
    let url = tempDir.appendingPathComponent("config.json")
    let store = ConfigStore(fileURL: url)
    var config = Config.empty()
    config.dpiValue = 1000
    try store.save(config)
    XCTAssertEqual(store.load().dpiValue, 1000)
    try FileManager.default.removeItem(at: url)
    XCTAssertEqual(store.load(), Config.empty())
}
```

- [x] **Step 2: Rodar os testes para verificar que falham**

Run: `swift test --filter ConfigStoreTests/testLoadReloadsWhenFileChangesExternally`
e `swift test --filter ConfigStoreTests/testLoadReturnsEmptyAfterFileDeleted`
Expected: FAIL — sem cache, ambos já passam hoje (leitura direta do disco). O
primeiro é o comportamento que o cache **não** pode quebrar; o segundo prova que
arquivo deletado ⇒ `Config.empty()`. Após a implementação eles devem continuar
passando; a falha esperada só existe em conjunto com um teste de cache positivo.

> Nota: o teste positivo de "usa o cache" não é assertável de forma confiável
> (não dá para provar que o disco não foi lido sem instrumentação). Os dois
> testes acima travam o comportamento correto do cache: reload em mudança
> externa e recarga de `Config.empty()` com arquivo removido.

- [x] **Step 3: Implementar o cache em `ConfigStore`**

Em `Sources/RatTamerCore/Core/ConfigStore.swift`, substituir as propriedades e
os métodos `load()`/`save()` (linhas 302-341) por:

```swift
public final class ConfigStore {
    private let fileURL: URL
    private let lock = NSLock()
    private var cached: Config?
    private var cachedMtime: Date?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("RatTamer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }

    public func load() -> Config {
        let mtime = fileModificationDate()
        if let cached = cachedValue(matching: mtime) {
            return cached
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            let empty = Config.empty()
            store(cached: empty, mtime: mtime)
            return empty
        }
        let config = (try? JSONDecoder().decode(Config.self, from: data)) ?? Config.empty()
        if config.migrateLegacy() {
            try? save(config)
        } else {
            store(cached: config, mtime: mtime)
        }
        return config
    }

    public func loadStrict() throws -> Config {
        guard let data = try? Data(contentsOf: fileURL) else {
            return Config.empty()
        }
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public func save(_ config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
        store(cached: config, mtime: fileModificationDate())
    }

    private func fileModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    private func cachedValue(matching mtime: Date?) -> Config? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached, cachedMtime == mtime else { return nil }
        return cached
    }

    private func store(cached config: Config, mtime: Date?) {
        lock.lock()
        cached = config
        cachedMtime = mtime
        lock.unlock()
    }
}
```

> Nota de implementação: o lock é usado **apenas** ao redor das leituras/escritas
> das variáveis `cached`/`cachedMtime` (via `cachedValue(matching:)` e
> `store(cached:mtime:)`), nunca ao redor de `save()` interno — evita deadlock de
> NSLock não-reentrante quando `load()` chama `save()` no caminho de migração.

- [x] **Step 4: Rodar os testes para verificar que passam**

Run: `swift test --filter ConfigStoreTests`
Expected: PASS — os dois novos testes passam e os ~40 existentes continuam
passando (eles criam `ConfigStore` novos por teste, sem estado de cache
compartilhado).

- [x] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/Core/ConfigStore.swift Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift
git commit -m "feat(core): ConfigStore com cache mtime-guardado e thread-safe"
```

---

### Task 5: Views — device I/O fora da main thread

Move os loads de device I/O dos views para `DispatchQueue.global(qos:
.utility)` seguindo o padrão de `AppModel.preloadDPI`, com hop para a main
thread para atualizar os `@State`. Device lento/travado deixa de congelar a UI.

**Files:**
- Modify: `Sources/RatTamerApp/Views/GeneralTabView.swift:173-185` (load do DPI), `:277-286` (load da inversão), `:318-321` (load da bateria)
- Modify: `Sources/RatTamerApp/Views/MenuBarPopoverView.swift:141-153` (loadDPI)

**Interfaces:**
- Consumes: `ConfigStore.load()` thread-safe (Task 4) — chamado dentro da queue
  de utility nos loads.
- Produces: mesmo comportamento visível, com loads assíncronos. Sem nova API
  pública.

- [x] **Step 1: Converter o load do DPI no `GeneralTabView`**

Em `Sources/RatTamerApp/Views/GeneralTabView.swift`, substituir `load()`
(linhas 173-185) por:

```swift
private func load() {
    guard let service = AppModel.shared.engine?.dpiService else { return }
    let currentValue = current
    DispatchQueue.global(qos: .utility).async {
        let values = (try? service.getSensorDpiList(sensor: 0)) ?? []
        if values.count > 1 {
            let stored = AppModel.shared.configStore.load().dpiValue
            let selected: Double
            if let stored {
                selected = Double(stored)
            } else if let info = try? service.getSensorDpi(sensor: 0) {
                selected = Double(info.dpi)
            } else {
                selected = currentValue
            }
            let cache = DPICache(values: values, value: selected)
            DispatchQueue.main.async {
                self.values = values
                self.current = selected
                AppModel.shared.dpiCache = cache
            }
        } else {
            DispatchQueue.main.async { self.values = values }
        }
    }
}
```

- [x] **Step 2: Converter o load da inversão no `GeneralTabView`**

Em `Sources/RatTamerApp/Views/GeneralTabView.swift`, substituir o segundo
`load()` (linhas 277-286) por:

```swift
private func load() {
    guard let service = AppModel.shared.engine?.hiResWheelService else {
        unavailable = true
        return
    }
    DispatchQueue.global(qos: .utility).async {
        let hasInvert = (try? service.getInfo())?.hasInvert == true
        guard hasInvert else {
            DispatchQueue.main.async { self.unavailable = true }
            return
        }
        let stored = AppModel.shared.configStore.load().invertScrollDirection
        let inverted = stored ?? ((try? service.getWheelMode())?.inverted ?? false)
        DispatchQueue.main.async {
            self.inverted = inverted
            self.loaded = true
        }
    }
}
```

- [x] **Step 3: Converter o load da bateria no `GeneralTabView`**

Em `Sources/RatTamerApp/Views/GeneralTabView.swift`, substituir o `load()` do
`BatteryStatusRow` (linhas 318-321) por:

```swift
private func load() {
    guard let service = AppModel.shared.engine?.batteryStatusService else { return }
    DispatchQueue.global(qos: .utility).async {
        let info = try? service.getBatteryInfo()
        DispatchQueue.main.async { self.info = info }
    }
}
```

- [x] **Step 4: Converter o loadDPI no `MenuBarPopoverView`**

Em `Sources/RatTamerApp/Views/MenuBarPopoverView.swift`, substituir `loadDPI()`
(linhas 141-153) por:

```swift
private func loadDPI() {
    guard let service = AppModel.shared.engine?.dpiService else { return }
    let currentDPI = dpi
    DispatchQueue.global(qos: .utility).async {
        let values = (try? service.getSensorDpiList(sensor: 0)) ?? []
        guard values.count > 1 else {
            DispatchQueue.main.async { self.dpiValues = values }
            return
        }
        var selected = currentDPI
        if let stored = AppModel.shared.configStore.load().dpiValue {
            selected = Double(stored)
        } else if let info = try? service.getSensorDpi(sensor: 0) {
            selected = Double(info.dpi)
        }
        DispatchQueue.main.async {
            self.dpiValues = values
            self.dpi = selected
            self.dpiLoaded = true
        }
    }
}
```

- [x] **Step 5: Build de verificação**

Run: `swift build`
Expected: compila sem warnings. (Sem testes unitários — estes são arquivos do
target `RatTamerApp`, e o padrão já é validado por `AppModel.preloadDPI`.)

- [x] **Step 6: Commit**

```bash
git add Sources/RatTamerApp/Views/GeneralTabView.swift Sources/RatTamerApp/Views/MenuBarPopoverView.swift
git commit -m "feat(app): loads de device I/O dos views fora da main thread (sem congelamento de UI)"
```

---

### Task 6: CrashReporter — remover `try?` em chamadas non-throwing

`FileHandle.close()`, `seekToEnd()` e `seek(toFileOffset:)` são non-throwing no
SDK atual; o `try?` produz o warning "no calls to throwing functions occur
within 'try' expression".

**Files:**
- Modify: `Sources/RatTamerApp/CrashReporter.swift:128-141`

**Interfaces:**
- Consumes: nada de tasks anteriores.
- Produces: `warnIfPreviousCrash()` com o mesmo comportamento, sem warnings.

- [x] **Step 1: Remover os `try?`**

Em `Sources/RatTamerApp/CrashReporter.swift`, dentro de `warnIfPreviousCrash()`
(linhas 128-141), fazer exatamente estas duas trocas:

```swift
// ANTES
try? handle.seekToEnd()
...
try? handle.seek(toFileOffset: UInt64(start))
// DEPOIS
_ = try? handle.seekToEnd()
...
handle.seek(toFileOffset: UInt64(start))
```

> **Nota verificada empiricamente no SDK 26.2 (Xcode 26.2, target
> arm64-apple-macosx14.0):** `seek(toFileOffset:)` é non-throwing (remover o
> `try?` elimina o warning "no calls to throwing functions…"); `seekToEnd()`
> lança E retorna `UInt64` não usado (o `_ =` elimina o warning "result of
> 'try?' is unused"). `handle.close()` e `handle.readToEnd()` **lançam** neste
> SDK — manter `defer { try? handle.close() }` e `(try? handle.readToEnd()) ??
> Data()` como estão; remover o `try?` neles não compila.

- [x] **Step 2: Build de verificação**

Run: `swift build`
Expected: compila sem o warning de `try?`; nenhum warning novo.

- [x] **Step 3: Commit**

```bash
git add Sources/RatTamerApp/CrashReporter.swift
git commit -m "fix(app): remove try? em chamadas non-throwing no CrashReporter"
```

---

### Task 7: Regressão final

- [x] **Step 1: Suite completa**

Run: `swift test`
Expected: todos os testes passam (345 existentes + novos das Tasks 2, 3 e 4).

- [x] **Step 2: Build sem warnings**

Run: `swift build`
Expected: compila sem warnings novos.

- [x] **Step 3: Smoke test manual (se device conectado)**

Rodar o app (`swift run RatTamer` ou o .app assinado) e verificar: abrir o tab
General (DPI/inversão/bateria carregam), abrir o popover da menu bar (DPI
carrega), scroll suave funciona. Se não houver device, registrar que o smoke
test ficou pendente.
