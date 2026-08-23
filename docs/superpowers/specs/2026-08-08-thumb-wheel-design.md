# Thumb Wheel configurável (scroll horizontal → volume)

Data: 2026-08-08

## Objetivo

Tornar o thumb wheel (scroll horizontal) do MX Master 2S um controle configurável no
RatTamer, como os demais botões, com volume como ação padrão em passos pequenos por
notch (estilo Logitech Options+). Ações configuráveis: esquerda e direita.

## Contexto e achados da investigação

- O thumb wheel **não** é visível via HID++ no MX Master 2S: a feature 0x2150
  (Thumbwheel) está ausente e um listener HID++ cru não recebeu nenhum report
  enquanto o usuário girava a rodinha.
- O thumb wheel produz **scroll horizontal nativo** no macOS (verificado em
  scrolltest.net).
- Um event tap CGEvent (probe `scroll_probe.swift`) consegue observar o thumb wheel:
  - Roda **discreta**: `scrollWheelEventIsContinuous == 0`, `scrollWheelEventScrollPhase == 0`.
  - Só horizontal: `dx != 0`, `dy == 0`.
  - Cada notch gera **2 eventos**: um de linha (`dx = ±1`) e um de pixels
    (`dx = ±10..20`).
  - Trackpad (deslizar dois dedos) é **contínuo** (`scrollWheelEventIsContinuous == 1`).
- Permissão de Accessibility já concedida (`axTrusted = true`); é a única necessária.

## Decisões de design

1. **Abordagem:** event tap CGEvent em `.scrollWheel`, instalado no nível do sistema
   (`.cgSessionEventTap`, `.headInsertEventTap`), filtrando scroll horizontal discreto.
   A interceptação é feita retornando `nil` do callback do tap (suprime o scroll nativo);
   caso contrário, o evento passa adiante intacto.
2. **Discriminação do thumb wheel** (condição para tratar o evento como thumb wheel):
   `deltaX != 0 && isContinuous == 0 && phase == 0` (campo Axis2 = horizontal).
3. **Direção:** `deltaX > 0` → ação "direita"; `deltaX < 0` → ação "esquerda". Se o
   ajuste "scroll natural" do usuário inverter a sensação, basta trocar as ações
   Esquerda/Direita na UI (sem toggle adicional).
4. **Acumulador de notches:** acumula `scrollWheelEventPointDeltaAxis2` (pixels) até o
   limiar constante `notchThreshold = 10`; a cada limiar atingido dispara **um** notch na
   direção do sinal e mantém o resto. Dois eventos por notch (linha + pixels) somam ≥ 10px
   e resultam em um único disparo.
5. **Supressão por direção:** uma direção só é interceptada (suprimida e convertida em
   ação) quando a configuração dela tiver uma ação válida (não `nil` e não `.disabled`).
   A direção não configurada passa o scroll nativo normalmente.
6. **Habilitação:** o tap só intercepta quando o app está **conectado e habilitado**
   (mesma semântica do `enabled` do EngineController). Fora disso, passa tudo adiante.
7. **Config:** novos campos opcionais `thumbWheelLeft`/`thumbWheelRight` (`ButtonAction?`).
   `nil` e `.disabled` significam scroll nativo. Migração: se ambos ausentes/nulos →
   `volumeDownSmall`/`volumeUpSmall` (volume padrão por notch).
8. **Execução assíncrona:** o disparo de ação roda na fila `ioQueue` (como o
   `handlePress`), para não bloquear o run loop do tap.

## Componentes

### `ThumbWheelClassifier` (novo, puro, testável) — `Sources/RatTamerCore/Core/ThumbWheelClassifier.swift`

- `static func isThumbWheel(deltaX: Int64, deltaY: Int64, isContinuous: Int64, phase: Int64) -> Bool`
  — `deltaX != 0 && isContinuous == 0 && phase == 0`.
- `enum Direction { case left, right }` e `static func direction(forDeltaX:)`.
- `struct NotchAccumulator`:
  - `mutating func push(pixels: Int64, direction: Direction) -> Int` — acumula o valor
    **com sinal** até `|total| >= notchThreshold`; a cada limiar devolve 1 notch na direção
    do sinal e desconta o limiar do total. Se o sinal do evento atual divergir do sinal do
    total pendente, zera o pendente antes de acumular (evita somar restos de direções
    opostas).
  - `reset()`.

### `ScrollWheelTap` (novo, I/O do CGEventTap) — `Sources/RatTamerCore/Core/ScrollWheelTap.swift`

- `init(shouldIntercept: @escaping (ThumbWheelClassifier.Direction) -> Bool,
        onNotch: @escaping (ThumbWheelClassifier.Direction) -> Void)`.
- `func start()` / `func stop()`: cria/remove o tap via `CGEvent.tapCreate`
  (`.cgSessionEventTap`, `.headInsertEventTap`, máscara `.scrollWheel`) e o agenda no
  main run loop. Se `tapCreate` falhar (Accessibility negada), loga e segue sem tap
  (comportamento nativo).
- Callback por evento:
  1. Lê `deltaX` (`.scrollWheelEventDeltaAxis2`), `deltaY` (`.scrollWheelEventDeltaAxis1`),
     `isContinuous`, `phase`, `pointDeltaX` (`.scrollWheelEventPointDeltaAxis2`).
  2. Se não for thumb wheel → passa adiante.
  3. Se `!shouldIntercept(direction)` → passa adiante (scroll nativo daquela direção).
  4. Alimenta o acumulador; para cada notch disparado → `onNotch(direction)`.
  5. Retorna `nil` (suprime).

### `Config` — `Sources/RatTamerCore/Core/ConfigStore.swift`

- Campos novos: `thumbWheelLeft: ButtonAction?`, `thumbWheelRight: ButtonAction?`
  (Codable, opcionais — ausência decodifica como `nil`).
- `migrateLegacy()`: se `thumbWheelLeft == nil && thumbWheelRight == nil` →
  `thumbWheelLeft = .system("volumeDownSmall")`, `thumbWheelRight = .system("volumeUpSmall")`.

### `ActionEngine` — `Sources/RatTamerCore/Core/ActionEngine.swift`

- Novos system actions (constante `volumeSmallStep = 3`):
  - `"volumeUpSmall"` → `set volume output volume ((output volume of (get volume settings)) + 3)`
  - `"volumeDownSmall"` → `set volume output volume ((output volume of (get volume settings)) - 3)`

### `EngineController` — `Sources/RatTamerApp/EngineController.swift`

- Cria `ScrollWheelTap` (no `init`), liga em `start()` e desliga em `stop()`.
- `shouldIntercept(direction)`: retorna `enabled && isConnected && actionConfigurada(direction)`
  em que `actionConfigurada` é não `nil` e não `.disabled`.
- `onNotch(direction)`: lê a ação da direção em `currentConfig()`, executa via
  `actionEngine.execute` na `ioQueue`, logando erro (padrão do `handlePress`).
- Fecha o ciclo de vida: quando o app sai, o tap é removido e o scroll nativo volta
  automaticamente (não há divert residual).

### UI — `Sources/RatTamerApp/Views/ButtonsTabView.swift`

- Nova seção "Thumb Wheel" com duas linhas: "Thumb Wheel Left" e "Thumb Wheel Right",
  cada uma com um menu de ação.
- Reutilizar os itens existentes do menu (System, Volume, Navigation, Editing,
  Screenshot, Click, Custom Shortcut…) refatorando o construtor de menu atual
  (`actionMenu`) em um builder compartilhado que recebe a ação atual e um callback
  `onSet`; a parte específica de control (ex.: "Gesture…") continua anexada pelo
  chamador.
- Persistência: `config.thumbWheelLeft/Right` via `ConfigStore.save` + `applyConfig()`
  (sem `setDiverted`, pois o thumb wheel não é divertable — atualiza apenas o estado
  consultado pelo tap).

### `ActionCatalog` — `Sources/RatTamerApp/ActionCatalog.swift`

- `systemTitle`/`systemIcon` para `"volumeUpSmall"` ("Volume Up (small)") e
  `"volumeDownSmall"` ("Volume Down (small)"), mesmos ícones de volume.

### Housekeeping do RatDiagnose — `Sources/RatDiagnose/main.swift`

- Remover o bloco de enumeração completa de features (via 0x0003) que retornou dados
  inválidos (0x0142/0x004D×2/0x0500); manter a checagem de presença da 0x2150 e o modo
  `--raw`.

## Fluxo de dados

```
Thumb wheel (HID nativo) → CGEvent scrollWheel (discreto, horizontal)
  → ScrollWheelTap callback
    → ThumbWheelClassifier.isThumbWheel?  (não → passa adiante)
    → shouldIntercept(direção)?            (não → passa adiante)
    → acumulador (≥10px) → onNotch(direção)
      → EngineController → ActionEngine.execute(volumeUpSmall/DownSmall…) na ioQueue
    → retorna nil (suprime scroll nativo)
```

## Tratamento de erro e casos de borda

- **Accessibility negada:** `CGEvent.tapCreate` retorna `nil` → loga e segue em modo
  nativo (sem crash).
- **Notch parcial:** resto acumulado permanece para o próximo notch.
- **Giro rápido:** vários notches em sequência geram vários disparos; osascript serializa
  na `ioQueue`.
- **Limite de volume:** o próprio AppleScript já clampa em 0–100.
- **Falha do osascript:** exceção capturada e logada (padrão existente).
- **Outros dispositivos:** qualquer mouse com roda horizontal discreta será capturado da
  mesma forma (limitação documentada; trackpad não é afetado).
- **Direção invertida:** usuário troca Esquerda/Direita na UI.

## Testes

- `Tests/RatTamerCoreTests/Core/ThumbWheelClassifierTests.swift` (novo):
  - Matriz `isThumbWheel`: thumb wheel (discreto, horizontal) → `true`; trackpad
    (contínuo) → `false`; scroll vertical (`dy != 0`) → `false`.
  - Acumulador: +10 → 1 notch direita; +10 +10 → 2 notches; +15 → 1 notch e resto 5;
    -10 → 1 notch esquerda; resto persiste entre eventos; resto de +5 seguido de -10 →
    zera o pendente e dispara 1 notch esquerda.
- `Tests/RatTamerCoreTests/Core/ActionEngineTests.swift`: `volumeUpSmall`/`volumeDownSmall`
  executam script com `± 3` (injetando um `ScriptRunner` que grava o script).
- `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`: encode/decode dos campos novos;
  migração aplica defaults de volume quando ambos `nil`; `nil` preservado quando um dos
  lados já tem ação.

## Fora de escopo

- Detecção por dispositivo específico (não distingue de outros mouses com roda horizontal).
- Toggle de direção invertida na UI (resolvido trocando esquerda/direita).
- Reações visuais/toast por notch.
- Configuração do passo do volume (fixo ±3).

## Critérios de sucesso

- Esquerda/Direita do thumb wheel configuráveis na aba Buttons.
- Padrão: volume, um passo pequeno (±3) por notch, estilo Options+.
- Scroll nativo suprimido quando a direção tem ação configurada; restaurado quando não.
- `swift build` e `swift test` verdes.
