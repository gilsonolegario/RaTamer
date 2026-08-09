# Design: Glide de suavização no ScrollSmoother + paridade do RatTest

Data: 2026-08-09
Status: aprovado em brainstorming

## Contexto

O `ScrollSmoother` atual emite a distância do feed **imediatamente** (passo +
boost de chegada + momentum com decaimento exponencial). Na prática, com um
mouse de roda ratcheted (MX Master 2S), cada detent vira um "pulo" instantâneo
seguido de um momentum curto que "quebra quase imediatamente". A experiência
é ruim comparada a ferramentas como Mos (Caldis/Mos) e ao scroll do Magic Mouse,
que **deslizam** o movimento ao longo do tempo com ease-out: o feed acumula num
alvo e o tick aproxima a saída do alvo progressivamente.

Paralelamente, o RatTest (ferramenta de validação do hardware) não está em
paridade com o app final: faltam níveis de suavidade/presets, o catálogo
completo de ações de botão, o teste de DPI cycle, do thumb wheel e dos modos
da roda (ratchet/free-spin).

## Decisões de design

1. Novo modo **glide por alvo com ease-out** no `ScrollSmoother`, ativado por
   um parâmetro novo. Quando desligado, o comportamento atual permanece
   byte-a-byte idêntico (compatibilidade com os 284 testes e com os níveis
   existentes).
2. O glide substitui o momentum quando ativo (o momentum/boost continua
   existindo para o modo legado).
3. RatTest ganha: níveis de suavidade + presets, controles de smoothing,
   catálogo completo de ações, DPI cycle, thumb wheel e modo da roda.

## Parte A — Glide por alvo no ScrollSmoother

### Novos parâmetros (em `ScrollSmoother.Parameters`)

- `smoothingEnabled: Bool` — default `false`. Quando `false`, todo o
  comportamento atual é preservado.
- `smoothFraction: Double` — fração da distância restante aproximada a cada
  tick (120 Hz). Default `0.13` (~equivalente ao Duration 3.0 do Mos, que
  produz `1 - sqrt(3/5.2) ≈ 0.24` por frame a 60 Hz; a 120 Hz o mesmo tempo de
  convergência dá `1 - sqrt(1 - 0.24) ≈ 0.128`).
- `glideStopThreshold: Double` — epsilon de parada do glide; default `0.5`
  (consenso SmoothScroll/LinearMouse). Ignorado no modo legado.

Novos parâmetros entram no `Equatable`, no init com default e no decode
legado (o decode atual já tolera campos ausentes — verificar `ConfigStore`).

### Novo estado interno

- `target: Double` — distância acumulada desejada (em pixels).
- `current: Double` — distância já emitida (posição da saída).
- Ambos zerados em `reset()`.

### `feed` — quando `smoothingEnabled == true`

1. Cálculo atual intacto: `notches = deltaV / multiplier`;
   `raw = notches * pixelsPerNotch`; boost por taxa de chegada; estabilização
   de bounce (retorna `(pixels, isBounce)`).
2. Se `isBounce` ou o pulso for atenuado: **não** acumula em `target`
   (mesma semântica de "não resemear momentum" do modo legado).
3. Em **reversal real** (direção aceita mudou): `current = 0` e `target = 0`
   antes de acumular.
4. `target += pixels` (com boost já aplicado).
5. Retorna `0` — o tick é quem emite.

### `tick` — quando `smoothingEnabled == true`

1. `remaining = target - current`.
2. Se `abs(remaining) <= glideStopThreshold` (epsilon de parada do glide;
   default **`0.5`** — consenso SmoothScroll + LinearMouse): emite `remaining`,
   faz `current = target; target = 0`, retorna `remaining`. Movimento
   terminou — **sem** momentum longo.
3. Senão: `step = remaining * smoothFraction`; **mínimo de 1px** quando
   `abs(step) < 1` (evita "derretimento" sub-pixel): `step = copysign(1.0, remaining)`
   se `abs(remaining) >= 1`; acumula o erro fracionário
   (`carry += step - step.rounded()`; soma `carry` quando `abs(carry) >= 1` —
   compensação da referência SmoothScroll). `current += step`; retorna `step`.
4. `applyInvert` aplicado ao valor emitido, como no legado.
5. Momentum/`momentumDecay`/`momentumStopThreshold` (velocidade) **não** são
   usados no modo glide — o epsilon do glide é um parâmetro dedicado.

### Parâmetro novo adicional: `glideStopThreshold`

- `glideStopThreshold: Double` — default `0.5`. Não afeta o modo legado (o
  legado continua usando `momentumStopThreshold`). Reconciliado com o reuse
  report (consenso SmoothScroll 0.5 / LinearMouse 0.5 / Mos deadZone 1.0).

### `feed`/`tick` — quando `smoothingEnabled == false`

Sem nenhuma alteração de comportamento (caminhos legados intactos).

### Testes novos (TDD)

- `feed` no modo glide retorna 0 e acumula em `target`.
- `tick` emite `smoothFraction` do restante por tick.
- glide converge sem overshoot e para (alvo atingido, `target` zerado).
- `glideStopThreshold` encerra o glide emitindo o restante (sem perder distância).
- mínimo de 1px no fim do glide (`copysign(1.0, remaining)`).
- compensação de erro fracionário (`carry`) não perde distância acumulada.
- reversal real reseta o glide (`current`/`target` zerados).
- bounce não acumula no `target`.
- boost por taxa de chegada se aplica ao valor acumulado.
- `pixelsPerNotch` customizado é honrado no alvo.
- `smoothingEnabled == false`: `glideStopThreshold`/`smoothFraction` não têm
  efeito; suíte existente continua verde (backward compat).

## Parte B — Paridade do RatTest

### 1. Níveis de suavidade + presets

- Slider de nível `0...100` + botões **Discreta (0)** / **Média (50)** /
  **Fluida (100)** que aplicam `SmoothnessLevel.parameters(level:multiplier:invert:)`
  e sincronizam os sliders crus existentes.
- Preset **Glide (sã)** — conjunto validado pelo reuse report
  (`docs/superpowers/specs/2026-08-09-smooth-glide-and-ratest-parity-v1.reuse.md`):
  `smoothingEnabled = true`, `pixelsPerNotch = 120`, `maxBoost = 1.5`,
  `smoothFraction = 0.13`, `glideStopThreshold = 0.5`,
  `accelerationWindow = 0.05`. Comunidade 4K (Reddit/LinearMouse/Mos)
  converge em 120–170 px/notch; boost modesto evita o runaway do free-spin.
- Preset **Mos-like** — réplica exata da config real do usuário no Mos
  (Step 60 / Speed 2.2 / Duration 3.0). **Correção do reuse report:** o Mos
  multiplica **todo** evento por `speed` (`buffer += y × speed`), logo a
  distância real por notch é `step × speed = 132 px`. Preset:
  `smoothingEnabled = true`, `pixelsPerNotch = 132`, `maxBoost = 1.0`
  (sem boost — Mos não tem boost por taxa), `smoothFraction = 0.13`,
  `glideStopThreshold = 0.5`, `accelerationWindow = 0.05`.
- O slider de nível e os sliders crus devem se manter sincronizados
  (mover nível atualiza os crus; mover um cru desceleciona o nível).

### 2. Controles de smoothing

- Toggle **Smoothing (glide)** ligado a `smoothingEnabled`.
- Slider **Smooth fraction** (`0.02...0.15`, step `0.01` — faixa sã do reuse
  report; acima de ~0.2 o glide vira "quase instantâneo") ligado a
  `smoothFraction`.
- Slider **Glide stop** (`0.0...2.0`, step `0.1`) ligado a `glideStopThreshold`.
- Todos wired em `currentParams` (envio live via `setSmoothParameters`).

### 3. Catálogo completo de ações

O picker de ação por botão passa a oferecer:

- Todas as system actions do `ActionCatalog.systemTitle`/`systemIcon`
  (missionControl, appExpose, showDesktop, launchpad, previousSpace,
  nextSpace, spotlight, lockScreen, volumeUp, volumeDown, volumeUpSmall,
  volumeDownSmall, volumeMute).
- Click Forward (botão 4) / Back (botão 3).
- `cycleDPI` (executa o ciclo de DPI).
- `gesture` (GestureConfig default).
- Atalhos existentes (Cmd+W) — mantidos.
- `runShortcut`: **fora de escopo** nesta rodada (exige Shortcuts CLI + Pro;
  documentar como não testável no RatTest).

### 4. DPI cycle + thumb wheel

**DPI** — nova seção "DPI":
- `RatTestEngine` descobre o `AdjustableDPI` (como o `EngineController` faz).
- Botão **Cycle DPI** (usa `DPICycle.next` com `recommendedPresets` a partir
  da lista válida do device).
- Exibe o DPI atual (sensor 0) e o próximo.

**Thumb wheel** — nova seção "Thumb Wheel":
- `ScrollWheelTap` intercepta notches horizontais (`ThumbWheel.isThumbWheel`).
- Exibe ao vivo cada notch: "esquerda" / "direita".
- Requer Acessibilidade (RatTest já posta via CGEvent e checa `AXIsProcessTrusted`).

### 5. Modo da roda

- Nova seção "Wheel Mode", visível apenas se o device tem SmartShift
  (`hiResWheel.getInfo()?.hasSwitch == true`).
- Botões **Ratchet** / **Free-spin** via `SmartShiftControls.setRatchetControlMode`.
- Exibe o status atual (`getRatchetControlMode`).

### Layout do RatTestView (seções em ordem)

Buttons → Smooth Scroll (com níveis/presets/smoothing) → Wheel Mode → DPI →
Thumb Wheel.

## Fora de escopo (YAGNI)

- `runShortcut` no RatTest.
- Editor visual de `GestureConfig` no RatTest (usa-se default).
- Onboarding/permissões no RatTest.
- Persistência das configurações do painel do RatTest.
- Suavização em níveis do app (não muda `SmoothnessLevel` — o glide é opt-in).

## Riscos e mitigação

- **Regressão no modo legado**: mitigado por `smoothingEnabled` default
  `false` + suíte de 284 testes.
- **Glide "flutuante"**: mitigado pelo epsilon de parada
  (`momentumStopThreshold`) que encerra o movimento sem cauda.
- **Sincronização nível↔sliders**: manter os dois conjuntos de estado; nível é
  fonte quando movido, e sliders crus "destravam" do nível.
