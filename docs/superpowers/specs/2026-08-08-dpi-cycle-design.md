# Cycle DPI como ação atribuível

Data: 2026-08-08

## Objetivo

Permitir trocar a resolução do sensor (DPI) com um clique do mouse: uma nova ação
**"Cycle DPI"** entra no catálogo e pode ser atribuída a qualquer botão remapeável
(Gesture, Back, Forward, Middle…). Cada pressão avança para o próximo preset de uma
lista configurável, salvando o valor no config e aplicando no device.

## Contexto e achados da investigação

- **O MX Master 2S não tem botão físico de DPI**: a enumeração 0x1B04 lista 8
  controles (Left, Right, Middle, Back, Forward, Thumb/Gesture, Scroll Mode/SmartShift,
  Virtual Gesture) e nenhum é de DPI. O botão "embaixo da roda" é o Scroll Mode
  (0x00C4). A decisão (com o usuário) foi implementar como **ação atribuível**.
- DPI é ajustado via feature 0x2201: `AdjustableDPI.setSensorDpi(sensor: 0, dpi:)`
  (escrita HIDPP). O device suporta 200–4000 (lista expandida em passos de 50).
- `Config` já tem `dpiValue: UInt16?` (DPI atual salvo), usado por
  `applyDPIIfNeeded` e pelo slider da General tab.
- `ButtonAction` é um enum Codable com `case gesture(GestureConfig)` e
  `case disabled`; `ActionEngine.execute` tem `case .gesture, .disabled: break`
  (ações tratadas fora do engine). `EngineController.handlePress` já trata
  `.gesture` antes de executar no `ActionEngine` — padrão a replicar para
  `.cycleDPI`.
- Testes: target `RatTamerCoreTests` (140 verdes); lógica pura de ciclo deve viver
  no core para ser testada.

## Decisões de design

1. **Nova case `ButtonAction.cycleDPI`** (sem payload): Codable com `action =
   "cycleDPI"`. `requiresDivert` já cobre (`self != .disabled` → true), então o
   botão é desviado automaticamente.
2. **Lógica pura no core**: `DPICycle.next(current:presets:) -> UInt16?` — retorna o
   próximo preset (wrap-around); se o DPI atual não está na lista, volta ao primeiro;
   lista vazia → `nil`. Constante `DPICycle.defaultPresets = [1000, 1600, 2000,
   4000]` (dentro do range 200–4000 do device). Testável sem device.
3. **Config**: novo campo opcional `dpiCycleValues: [UInt16]?`. Se ausente, o engine
   usa `DPICycle.defaultPresets`. Sem bump de versão (decodeIfPresent).
4. **`ActionEngine.execute(.cycleDPI)` faz nada** (break junto de `.gesture`/
   `.disabled`): quem executa o ciclo é o `EngineController`, que tem acesso ao
   `_dpiService` (o core não sabe de HIDPP de app).
5. **`EngineController.handlePress`**: após o bloco do gesture, se a ação for
   `.cycleDPI`, chama `cycleDPI()` (publica `onButtonEvent` para o highlight) e
   retorna — não passa pelo `actionEngine`.
6. **`cycleDPI()` roda na `ioQueue`** (escrita HIDPP bloqueante, padrão das demais
   configs):
   - lê `currentConfig().dpiValue` (fallback: `getSensorDpi` do device);
   - presets = `config.dpiCycleValues ?? DPICycle.defaultPresets`;
   - `next = DPICycle.next(current:presets:)`; guard se `nil`;
   - salva `config.dpiValue = next` no `ConfigStore`, `refreshConfig()`;
   - `setSensorDpi(sensor: 0, dpi: next)` + log `dpi cycle: X → Y`.
   - Na próxima pressão, `dpiValue` salvo já é o novo DPI → ciclo continua.
7. **Catálogo e menu**: `ActionCatalog` ganha título "Cycle DPI" e ícone
   "speedometer"; `commonActionSections` do `ButtonsTabView` ganha uma Section
   "Pointer" com o item. Funciona para qualquer botão remapeável.
8. **UI dos presets**: na General tab, junto ao slider de DPI, um campo de texto
   com a lista de presets separada por vírgula (ex.: "1000, 1600, 2000, 4000") +
   botão "Reset" (volta ao default). Salva em `dpiCycleValues`.

## Componentes

### `Sources/RatTamerCore/Core/ConfigStore.swift`

- `ButtonAction`: nova case `cycleDPI`; decode `case "cycleDPI": self = .cycleDPI`;
  encode `case .cycleDPI: try c.encode("cycleDPI", forKey: .action)`.
- `Config`: novo campo `dpiCycleValues: [UInt16]?` + CodingKey + decodeIfPresent +
  init param.

### Novo `Sources/RatTamerCore/Core/DPICycle.swift`

```swift
public enum DPICycle {
    public static let defaultPresets: [UInt16] = [1000, 1600, 2000, 4000]

    public static func next(current: UInt16, presets: [UInt16]) -> UInt16? {
        guard !presets.isEmpty else { return nil }
        if let index = presets.firstIndex(of: current) {
            return presets[(index + 1) % presets.count]
        }
        return presets[0]
    }
}
```

### `Sources/RatTamerCore/Core/ActionEngine.swift`

- `case .gesture, .disabled, .cycleDPI: break` em `execute`.

### `Sources/RatTamerApp/EngineController.swift`

- `handlePress`: antes de `onButtonEvent`/`actionEngine`:
  ```swift
  if action == .cycleDPI {
      onButtonEvent?(cid)
      cycleDPI()
      return
  }
  ```
- Novo `private func cycleDPI()` (descrito na decisão 6).

### `Sources/RatTamerApp/ActionCatalog.swift`

- `case .cycleDPI: return "Cycle DPI"` (title) e `"speedometer"` (icon).

### `Sources/RatTamerApp/Views/ButtonsTabView.swift`

- Section "Pointer" em `commonActionSections` com item "Cycle DPI".

### `Sources/RatTamerApp/Views/GeneralTabView.swift`

- Seção DPI: campo de texto de presets + Reset (salva `dpiCycleValues`).

## Fluxo de dados

```
press no botão com action .cycleDPI
  → monitor (loop thread) → handlePress
  → onButtonEvent?(cid) (highlight da linha)
  → cycleDPI() → ioQueue.async
      → currentConfig().dpiValue ?? getSensorDpi
      → DPICycle.next(current:presets:)
      → save config.dpiValue = next → refreshConfig()
      → setSensorDpi(sensor: 0, dpi: next)  (0x2201)
```

## Tratamento de erro e casos de borda

- **Lista de presets vazia/inválida no config**: cai no default (`defaultPresets`).
- **`_dpiService` ausente** (device sem 0x2201): `cycleDPI` sai silenciosamente
  (guard).
- **DPI atual fora da lista** (ex.: 1200 e presets [1000, 2000]): pula para o
  primeiro preset.
- **Escrita HIDPP falha**: `try?`; o config já foi salvo, então a próxima pressão
  avança a partir do valor salvo (sem loop infinito de falha).
- **Device desconectado durante o ciclo**: guards `!stopped`/`self` existentes.

## Testes

- `DPICycleTests`: wrap-around; DPI fora da lista → primeiro preset; lista com 1
  elemento; lista vazia → nil; defaultPresets dentro do range do device.
- `ConfigStoreTests`: round-trip de `.cycleDPI`; decode de `dpiCycleValues`.
- `ActionEngineTests`: `execute(.cycleDPI)` não lança (no-op).
- Verificação manual: atribuir Cycle DPI a um botão, pressionar e confirmar DPI
  mudando (slider da General tab / `RatDiagnose dpi=` read-back via 0x2201).

## Fora de escopo

- Hook direto do botão DPI físico (inexistente no MX Master 2S).
- DPI por app (perfis por app ficam para feature futura).
- Debounce de cliques rápidos no cycle.

## Critérios de sucesso

- "Cycle DPI" aparece no catálogo e é atribuível a botões remapeáveis.
- Cada pressão cicla o DPI pelos presets configurados e persiste o valor.
- Presets editáveis na General tab (e reset para o default).
- `swift build` e `swift test` verdes.

## Stack de verificação

**v1 (automatizado)**: `swift build` e `swift test` (140 testes + novos).

**v2 (manual)**: relançar o app, atribuir "Cycle DPI" a um botão (ex.: Gesture),
pressionar várias vezes e conferir o DPI no slider da General tab e o read-back via
`RatDiagnose` (0x2201) batendo com o preset esperado.
