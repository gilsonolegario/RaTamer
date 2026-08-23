# Sensibilidade do SmartShift (limiar de auto-disengage configurável)

Data: 2026-08-08

## Objetivo

Adicionar o critério "smart" ao modo SmartShift do RatTamer: um limiar de
velocidade configurável (sensibilidade 1–100) que define em que velocidade a
roda solta o ratchet e engata o free-spin — equivalente ao slider de sensibilidade
do Logitech Options/Options+.

## Contexto e achados da investigação

- Feature HID++ **0x2110** (SmartShift / ratchet control), documentada em
  lekensteyn.nl/files/logitech/x2110_smartshift.html e OpenLogi:
  - `wheelMode`: `1` = freespin, `2` = ratchet.
  - `autoDisengage`: `0x01`–`0xFE` = limiar de velocidade (em passos de ¼ volta/seg)
    acima do qual o ratchet solta para free-spin (maior = mais difícil soltar);
    `0xFF` = ratchet sempre engatado; `0x00` = "não alterar".
  - `autoDisengageDefault`: default persistido na NVM do device, usado após HID
    reset; `0x00` = "não alterar".
  - Default de fábrica Logitech: `wheelMode = ratchet`, `autoDisengage = 16`
    (~4 voltas/seg), `autoDisengageDefault = 16`.
- **Bug atual:** `SmartShiftMode.smartshift.autoDisengage = 0x00` — o modo smartshift
  é apresentado na UI mas nunca aplica um limiar real; o device mantém o valor que já
  tinha.
- Config já possui `smartShiftMode`; falta o limiar.

## Decisões de design

1. **Campo de config:** novo campo opcional `smartShiftSensitivity: Int?` (1–100) no
   `Config`. `nil` → usa o default Logitech `16`. Escala 1–100 mapeada 1:1 ao byte
   `autoDisengage` (100 < 254, não há necessidade de remapear).
2. **Mapeamento modo + sensibilidade → `SmartShiftStatus`** em um helper puro e
   testável no `RatTamerCore`:
   - `.freespin` → `(wheelMode: 1, autoDisengage: 0x00)`
   - `.ratcheted` → `(wheelMode: 2, autoDisengage: 0xFF)`
   - `.smartshift` → `(wheelMode: 2, autoDisengage: sensibilidade clampada 1–254)`
   - `autoDisengageDefault` sempre `0` (não persiste na NVM; decisão do usuário).
3. **Aplicação:** `EngineController.applySmartShiftIfNeeded` passa a usar o helper
   (modo + sensibilidade do config) em vez de `mode.autoDisengage`.
4. **UI:** na linha do botão `0x00C4`, quando o modo selecionado for `.smartshift`,
   exibir um slider **"Sensitivity"** (1–100, stepper numérico ao lado) indentado abaixo
   da linha. Mudar o slider salva no config e re-aplica no device imediatamente
   (mesmo padrão do menu de modo). Selecionar smartshift sem sensibilidade configurada
   aplica o default 16.
5. **Migração:** campo opcional via `decodeIfPresent` — configs existentes sem o campo
   decodificam `nil` e usam 16. Sem bump de `version`.

## Componentes

### `SmartShiftStatus` — `Sources/RatTamerCore/HIDPP/SmartShiftControls.swift`

- Novo static helper:
  `static func status(for mode: SmartShiftMode, sensitivity: Int) -> SmartShiftStatus`
  com o mapeamento da seção "Decisões de design" (item 2). Clamp da sensibilidade:
  `UInt8(min(max(sensitivity, 1), 254))`.

### `Config` — `Sources/RatTamerCore/Core/ConfigStore.swift`

- Campo novo `smartShiftSensitivity: Int?` (Codable, opcional).
- `SmartShiftMode.smartshift.autoDisengage` deixa de ser usado pelo fluxo de apply
  (mantém-se `0x00`, inerte); a fonte do limiar passa a ser o helper.

### `EngineController` — `Sources/RatTamerApp/EngineController.swift`

- `applySmartShiftIfNeeded`: monta o status via
  `SmartShiftStatus.status(for: mode, sensitivity: config.smartShiftSensitivity ?? 16)`.

### UI — `Sources/RatTamerApp/Views/ButtonsTabView.swift`

- Estado local `sensitivity` para o slider (inicializado do config).
- Quando `config.smartShiftMode == .smartshift`, renderizar abaixo da linha do `0x00C4`:
  `Slider(value:)` 1–100 + `Text("\(value)")`.
- `onChange` → `config.smartShiftSensitivity = value` → `ConfigStore.save` →
  `engine?.applyConfig()` (mesmo fluxo de `setSmartShiftMode`).

## Fluxo de dados

```
Slider Sensitivity (UI, modo SmartShift)
  → config.smartShiftSensitivity → ConfigStore.save
  → EngineController.applyConfig → applySmartShiftIfNeeded
    → SmartShiftStatus.status(for: mode, sensitivity:)  (limiar real, não 0x00)
    → SmartShiftControls.setRatchetControlMode
```

## Tratamento de erro e casos de borda

- **Sensibilidade fora de 1–100:** clamp no helper (`1...254` no byte).
- **Modo diferente de smartshift:** o slider não é exibido; `ratcheted` continua `0xFF`
  (ratchet permanente) e `freespin` `0x00`.
- **`setRatchetControlMode` falha:** `try?` + log (padrão existente).
- **Config antiga sem o campo:** `nil` → 16 (default Logitech).

## Testes

- `Tests/RatTamerCoreTests/HIDPP/SmartShiftControlsTests.swift`:
  - `.freespin` → `(1, 0x00)`; `.ratcheted` → `(2, 0xFF)`.
  - `.smartshift` sens 16 → `(2, 16)`; sens 1 → `(2, 1)`; sens 100 → `(2, 100)`.
  - Clamp: sens 0 → 1; sens 999 → 254.
  - `autoDisengageDefault` sempre 0.
- `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`:
  - Round-trip do campo `smartShiftSensitivity` através do store.
  - Ausência do campo decodifica `nil`.

## Fora de escopo

- Persistir `autoDisengageDefault` na NVM (decisão do usuário: não persistir).
- Feature 0x2111 (tunable torque / MX Master 3+) e torque da roda.
- Ação por botão "toggle SmartShift" (pode vir em outra spec).

## Critérios de sucesso

- Slider de sensibilidade aparece quando o modo é SmartShift e some nos demais.
- Mudar o slider aplica o limiar no device imediatamente (verificável via
  `getRatchetControlMode`).
- Modo smartshift envia limiar real (não `0x00`).
- `swift build` e `swift test` verdes.

## Stack de verificação

**v1 (automatizado, concluído)**: testes unitários do mapeamento e do round-trip
(6 novos testes; 140 no total, todos verdes).

**v2 (manual, pendente)**: com o MX Master 2S conectado, selecionar SmartShift,
arrastar a sensibilidade e conferir o comportamento da roda e o log do engine
(`smartshift mode: smartshift sens: N`).
