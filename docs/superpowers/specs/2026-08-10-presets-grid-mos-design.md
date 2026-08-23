# RatTamer Presets com referências reais — Native/Smooth/Glide/Mos/Flow/Fluid

Data: 2026-08-10

## Objetivo

Substituir a grade de presets por um conjunto com **referências reais de feel**:
macOS de fábrica, momentum clássico, quase-trackpad, defaults do Mos. O preset
Native é um **pass-through real** (roda como se o RatTamer não existisse, mas
na velocidade nativa do macOS). Default da app = Mos.

## Contexto e motivação

- Setup real do usuário (MX Master 2S, Dell U2718Q 4K "More Space",
  Logi Options+, Mos): Mos Step 60 / Speed 2.2 / Duration 3.0; Logi Options+
  pointer speed 48% e `com.apple.mouse.scaling` 1.49 são **velocidade do
  cursor** (fora do escopo do RatTamer).
- O RatTamer trava a roda em modo hi-res **diverted** — o macOS não recebe
  scroll direto; tudo é re-postado sinteticamente em eventos de *pixel*.
  Por isso o "scaling de linhas" do macOS nunca acontece: o Native atual
  (ppn 10) rola ~5× mais devagar que o macOS de fábrica.
- Dados reais do device (RatDiagnose): `multiplier=8` → 1 detente = `deltaV 8`.
- Decisões aprovadas em brainstorm:
  - Roster: **4 presets + extremos (6)**: Native · Smooth · Glide · Mos · Flow · Fluid.
  - Smooth = **momentum clássico**.
  - Glide = **quase trackpad**.
  - Mos = **defaults do Mos** (Step 60 × Speed 2.2 = 132 px; Duration 3.0 = sf 0.13).
  - Native = **pass-through com escala nativa**: quando momentum E smoothing
    estão off, o `feed` re-posta `notches × ppn` **sem boost, sem filtro de
    bounce, sem invert** (ppn em Native = 48 ≈ 3 linhas do macOS de fábrica).
  - Nome: **Mos** (não "MOS").

## Decisões de design

### 1. Tabela de presets-âncora

| Preset | nível | momentum | smoothing | pixels/notch | maxBoost | decay | smoothFraction | glideStop |
|--------|-------|----------|-----------|--------------|----------|-------|----------------|-----------|
| Native | 0 | off | off | 48 | 1.0 | 0.70 | 0.13 | 0.5 |
| Smooth | 35 | on | off | 45 | 2.2 | 0.88 | 0.13 | 0.5 |
| Glide | 60 | off | on | 110 | 1.2 | 0.85 | 0.14 | 0.5 |
| Mos | 80 | off | on | 132 | 1.0 | 0.85 | 0.13 | 0.5 |
| Flow | 90 | off | on | 145 | 1.0 | 0.85 | 0.14 | 0.5 |
| Fluid | 100 | off | on | 170 | 1.0 | 0.85 | 0.15 | 0.5 |

- **Native (0)** = pass-through: `feed` retorna `notches × pixelsPerNotch` (48)
  direto, sem passar por `stabilized()` (bounce), sem boost de aceleração, sem
  `applyInvert`. Sem momentum (tick retorna 0). Aplica-se a toda a zona em que
  momentum E smoothing estão off (níveis 0 até o meio entre Native e Smooth = 17.5).
- **Smooth (35)** = momentum clássico: momentum on, smoothing off, boost 2.2,
  decay 0.88 (rolagem continua após parar).
- **Glide (60)** = quase trackpad: smoothing on, ppn alto, glide suave.
- **Mos (80)** = defaults do Mos: ppn 132 (= 60 × 2.2), sf 0.13 (≈ Duration
  3.0), boost 1.0 (Speed do Mos é constante), smoothing on, momentum off.
- Regras da curva inalteradas: contínuos interpolam linearmente; booleanos =
  âncora mais próxima (empate → maior nível).
- `smoothingStartLevel` derivado = meio entre Smooth(35 off) e Glide(60 on) = **47.5**.
- `SmoothnessPreset`: `native, smooth, glide, mos, flow, fluid`, com `Mos`
  como display name.
- **Default da app** (instalação nova + Reset) = **Mos (80)**.

### 2. Pass-through nativo no `ScrollSmoother.feed`

`feed` ganha um early-return quando `!momentumEnabled && !smoothingEnabled`:

```swift
let notches = Double(movement.deltaV) / Double(max(1, parameters.multiplier))
let raw = notches * parameters.pixelsPerNotch
if !parameters.momentumEnabled && !parameters.smoothingEnabled {
    return raw
}
// ... resto inalterado (stabilized, boost, smoothing, momentum)
```

Isso muda o comportamento dos parâmetros padrão (ambos off) — antes havia
boost/bounce/invert mesmo com os dois off; agora é pass-through puro. Testes
do `ScrollSmoother` que exercitam boost/bounce/invert passam a usar
`momentumEnabled: true`.

### 3. Migração de config

- Nível salvo (ex. 70/78) **não é remapeado**: continua como nível contínuo na
  nova curva. O Picker mostra "Custom" para níveis que não batem com âncora.
- Instalação nova / Reset → `smoothScrollLevel = 80` (Mos).
- `smoothScrollAdvanced` existente → continua como Custom (`level = nil`).

## Estrutura de arquivos

- **Editar** `Sources/RatTamerCore/Core/SmoothnessLevel.swift` (casos do enum,
  âncoras, `defaultValue = 80`)
- **Editar** `Sources/RatTamerCore/Core/ScrollSmoother.swift` (pass-through no
  `feed`)
- **Editar** `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`
- **Editar** `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift` (bypass +
  config momentum nos testes de boost/bounce/invert)

## Testes

- `SmoothnessLevelTests`: valores exatos nos 6 níveis; booleanos flipam no
  ponto médio (momentum on em [17.5, 47.5); smoothing on a partir de 47.5);
  interpolação (ex. `maxBoost(17.5) = 1.6`, `pixelsPerNotch(70) = 121`,
  `smoothFraction(85) = 0.135`); clamp; `defaultValue == 80`; `preset(at:)`
  resolve cada âncora; `smoothingStartLevel == 47.5`.
- `ScrollSmootherTests`: bypass sem boost, sem invert, sem damping de bounce,
  sem momentum; testes existentes de boost/bounce/invert migrados para
  `momentumEnabled: true`.
- RatTest compila e aplica os 6 presets.

## Verificação

- `swift test` 100% verde.
- `swift build` sem warnings novos.
- App: Picker mostra Native/Smooth/Glide/Mos/Flow/Fluid; selecionar **Mos**
  aplica ppn 132/boost 1.0/sf 0.13 (momentum off, smoothing on); **Native**
  rola ~48px/detente sem moldar (sem boost/bounce/invert); Reset restaura 80;
  marcadores na barra nas 6 posições, smoothing start em 47.5.
- RatTest: 6 botões aplicando ao vivo.
