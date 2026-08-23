# Menu bar: toggle de enable e bateria no popover

Data: 2026-08-08

## Objetivo

Completar o popover do menu bar com o que falta em relação à feature escolhida pelo
usuário: o **toggle Enable/Disable de remapping** e a **linha de bateria** com
atualização periódica. O resto (ícone na menu bar, status da conexão, Settings…,
Reconnect, Quit) já existe.

## Contexto e achados da investigação

- O app já roda como menu bar app: `main.swift` usa `setActivationPolicy(.accessory)`
  (sem dock icon) e `AppDelegate` constrói um `MenuBarController` com `NSStatusItem`
  e popover.
- `MenuBarPopoverView` atual: status (dot + `statusText`), Settings…, Reconnect, Quit.
  `AppModel.statusText` já publica o status da conexão ("Connected — N controls").
- `AppModel.remappingEnabled` (`@Published`, default true) já é a fonte da verdade do
  toggle e, no `didSet`, já sincroniza com `engine.enabled` (async via `ioQueue`).
  Existe toggle equivalente na General tab.
- A bateria hoje é lida **sob demanda** na `BatteryStatusRow` da General tab via
  `engine.batteryStatusService?.getBatteryInfo()`. Não há polling periódico.
- `BatteryInfo` (core) expõe `capacity`, `state` (`.full/.charging/.recharging/
  .notCharging/.discharging/.unknown`) e `level` (`.full/.good/.low/.critical/
  .unknown`).
- App target não tem test target; core (`RatTamerCore`) não precisa mudar.

## Decisões de design

1. **Toggle ligado direto ao `AppModel`**: `Toggle("Enable remapping", isOn:
   Binding(AppModel.shared.remappingEnabled))` no popover — zero estado novo; o
   `didSet` existente já despacha `applyAll`/`restoreNativeDiverts` no engine.
2. **Novo `BatteryMonitor` (app target, `ObservableObject`)**: polling periódico
   (60 s) de `getBatteryInfo()`, publicado como `@Published var info: BatteryInfo?`.
   - `start()` idempotente (um único `Timer`); faz refresh imediato + timer no main.
   - `refresh()` roda o read HIDPP (bloqueante) numa queue `.utility` e publica no main.
   - Device desconectado ou `batteryStatusService == nil` → `info = nil`.
   - Ciclo de vida ligado ao popover: `.onAppear` → start, `.onDisappear` → stop.
3. **`BatteryDisplay` (app target)**: helper de formatação (título + SF Symbol) usado
   pelo popover; a `BatteryStatusRow` da General tab passa a usar o mesmo título
   (evita drift de string entre as duas superfícies).
4. **Layout do popover**: status → linha de bateria (só quando `info != nil`) →
   separador → toggle → separador → Settings…/Reconnect/Quit. Ajuste do
   `contentSize` para acomodar as linhas novas.
5. **Sem mudanças no `RatTamerCore`**: bateria e toggle são só camada de app.

## Componentes

### Novo `Sources/RatTamerApp/BatteryMonitor.swift`

```swift
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()
    @Published var info: BatteryInfo?
    private var timer: Timer?
    private static let interval: TimeInterval = 60
    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) {
            [weak self] _ in self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let service = AppModel.shared.engine?.batteryStatusService else {
                DispatchQueue.main.async { self?.info = nil }
                return
            }
            if let info = try? service.getBatteryInfo() {
                DispatchQueue.main.async { self?.info = info }
            }
        }
    }
}

enum BatteryDisplay {
    static func title(for info: BatteryInfo) -> String { /* Full / Charging / Not charging / capacity% */ }
    static func symbol(for info: BatteryInfo) -> String { /* bolt.fill ou battery.NNpercent */ }
}
```

### `Sources/RatTamerApp/Views/MenuBarPopoverView.swift`

- `@ObservedObject private var battery = BatteryMonitor.shared`.
- Linha de bateria (ícone + título) quando `battery.info != nil`.
- `Toggle("Enable remapping", isOn: ...)` no estilo do popover (row com ícone e switch).
- `.onAppear { BatteryMonitor.shared.start() }` / `.onDisappear { BatteryMonitor.shared.stop() }`.

### `Sources/RatTamerApp/MenuBarController.swift`

- `popover.contentSize` de `(260, 190)` para ~`(260, 250)`.

### `Sources/RatTamerApp/Views/GeneralTabView.swift`

- `BatteryStatusRow.title(for:)` delega para `BatteryDisplay.title`; `color(for:)`
  permanece local.

## Fluxo de dados

```
popover abre → BatteryMonitor.start() → refresh() imediato + Timer 60s
  → ioQueue? não: utility queue → getBatteryInfo() (feature 0x1000)
  → main → @Published info → row renderiza

Toggle → Binding AppModel.remappingEnabled → didSet → engine.enabled (já existente,
async via ioQueue: applyAll / restoreNativeDiverts)
```

## Tratamento de erro e casos de borda

- **Device desconectado / sem battery service**: `refresh()` seta `info = nil`; a
  linha some (não mostra placeholder no popover compacto).
- **Read falha intermitente**: `try?` ignora; o próximo tick (60 s) tenta de novo.
- **Toggle com device desconectado**: comportamento já existente da General tab —
  guard `!stopped` no engine faz a mudança ser aplicada na próxima conexão.
- **Timer duplicado**: `start()` idempotente (`guard timer == nil`).

## Testes

Sem test target no `RatTamerApp`; o polling depende de IOKit (`session.request`), não
unitarizável sem sessão fake. Verificação manual com o device físico (padrão do
projeto). `swift build` e `swift test` (core) devem continuar verdes.

## Fora de escopo

- Trocar o popover por `NSMenu` nativo (opção descartada pelo usuário).
- Toggle de "Start at login" no popover (não escolhido).
- Notificação quando a bateria muda de nível.
- Polling quando o popover está fechado.

## Critérios de sucesso

- Popover mostra a bateria (ícone + estado/%) e atualiza periodicamente.
- Toggle Enable/Disable liga/desliga o remapping no device (diverts restaurados ao
  desligar, reaplicados ao ligar).
- Popover abre/fecha sem travar a UI e com tamanho adequado.
- `swift build` e `swift test` verdes.

## Stack de verificação

**v1 (automatizado)**: `swift build` e `swift test` (140 testes) verdes.

**v2 (manual)**: relançar o app (matar instância antiga antes), abrir o popover na
menu bar: conferir status + bateria; alternar o toggle Enable/Disable e confirmar via
log do engine (`/usr/bin/log show --predicate 'subsystem == "com.rattamer"'`) que
aplicou/restaurou os diverts; reabrir o popover depois de ~60 s e ver a bateria
atualizada.
