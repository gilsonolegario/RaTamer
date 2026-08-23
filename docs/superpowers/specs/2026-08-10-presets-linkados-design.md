# RatTamer Presets ligados — level ⇄ momentum/smoothing + presets no app

Data: 2026-08-10

## Objetivo

Fazer o **nível de smoothness ser a fonte única** que deriva **todas** as
configurações de scroll (momentum, smoothing/glide, feed), e reunir **todos os
presets no RatTamer** — eliminando a dependência do MOS e o estado "advanced"
desconexo do nível. O usuário navega por presets nomeados, refina com o slider
e entende cada controle com ajuda `(?)` estilo macOS.

Presets (nomes em inglês): **Subtle, Medium, Personal, Glide, MOS, Fluid**.
Default de instalação nova e do "Reset to default" = **Glide (nível 70)**.

## Contexto e motivação

- `SmoothnessLevel.parameters` (SmoothnessLevel.swift:38) deriva hoje apenas
  3 campos de momentum (`momentumEnabled`, `maxBoost`, `momentumDecay`).
  Glide/smoothing e feed vivem 100% no `smoothScrollAdvanced` (custom), sem
  vínculo com o nível.
- `SmoothScrollSettings.isCustom` (SmoothScrollSettings.swift:25) compara só
  `maxBoost`/`momentumDecay`/`momentumEnabled` — **bug**: divergir glide
  (`smoothingEnabled`, `pixelsPerNotch`, `smoothFraction`, `glideStopThreshold`)
  não marca custom.
- Aba Advanced tem botões hardcoded "Glide"/"Mos-like" que setam `level = nil`
  + params (AdvancedTabView.swift:174-196), duplicando a semântica de preset
  sem nível.
- O usuário usa MOS como referência de feel; seu "personal-like" (screenshot)
  tem **Momentum ON + Smoothing ON** simultâneos — no motor o glide tem
  prioridade (ScrollSmoother.swift:202), então momentum fica inerte, mas o
  preset deve preservar os valores exatos.
- Flicker pendente: `setLevel` na aba Advanced chama `apply()` por tick do
  slider (destrói/recria o coordinator) — precisa migrar para o caminho leve.
- Direção aprovada em brainstorm: nível = fonte única; mexer no avançado →
  "Custom"; seletor de presets + slider; ajuda `(?)`; reset para o padrão.

## Decisões de design

### 1. Presets = âncoras da curva (`SmoothnessLevel`)

`SmoothnessLevel` passa a ter uma tabela de **6 presets-âncora**. Cada preset
define um conjunto completo dos campos "sensíveis". A curva interpola entre
presets adjacentes:

| Preset | nível | momentum | smoothing | pixels/notch | maxBoost | decay | smoothFraction | glideStop |
|--------|-------|----------|-----------|--------------|----------|-------|----------------|-----------|
| Subtle | 0 | off | off | 10 | 1.5 | 0.70 | 0.13 | 0.5 |
| Medium | 50 | on | off | 12 | 3.0 | 0.85 | 0.13 | 0.5 |
| Personal | 60 | on | on | 120 | 1.8 | 0.92 | 0.13 | 0.5 |
| Glide | 70 | off | on | 100 | 1.5 | 0.85 | 0.13 | 0.5 |
| MOS | 78 | off | on | 132 | 1.0 | 0.85 | 0.13 | 0.5 |
| Fluid | 100 | off | on | 160 | 1.0 | 0.85 | 0.15 | 0.5 |

- **Contínuos** (maxBoost, momentumDecay, pixelsPerNotch, smoothFraction,
  glideStop): interpolação linear por partes entre presets adjacentes.
- **Booleanos** (momentumEnabled, smoothingEnabled): valor da âncora mais
  próxima (empate no ponto médio → âncora de maior nível).
- Demais campos (feedGapTimeout 0.08, accelWindow 0.05, momentumStop 0.1,
  bounce 0.04/0.5/0.15, reversalConfirmation 2, directionThreshold 1.0):
  constantes de preset = defaults atuais (o Personal coincide com os defaults,
  então preserva os valores exatos do screenshot sem estado extra).
- `SmoothnessLevel.defaultValue` muda de 50 → **70 (Glide)**.
- Nova API: `SmoothnessLevel.preset(at level:) -> SmoothnessPreset?` e
  `SmoothnessPreset.level`; `momentumOnThreshold` (20) é removido (o flip agora
  vem da curva).
- `SmoothnessLevel.parameters(level:multiplier:invert:)` deriva **todos** os 17
  campos; `multiplier`/`invert` continuam vindos do chamador.

### 2. `isCustom` corrigido (`SmoothScrollSettings`)

`isCustom` passa a comparar **todos** os campos que a curva deriva:
`momentumEnabled`, `maxBoost`, `momentumDecay`, `smoothingEnabled`,
`pixelsPerNotch`, `smoothFraction`, `glideStopThreshold`. Qualquer divergência
(na curva ou manual) → `true`.

### 3. UI — seletor de presets + slider + ajuda + reset

- **General tab (`SmoothScrollRow`)**: adiciona um `Picker` (menu) com os 6
  presets acima do slider "Smoothness". Selecionar preset → `level` =
  `preset.level`, `advanced = nil`, deriva tudo. Slider continua 0–100 para
  ajuste fino (arrastar → "Custom").
- **Advanced tab**: remove os botões "Glide"/"Mos-like" (vira o mesmo Picker de
  presets). O label "Custom" aparece quando `level == nil`.
- **Botão de ajuda `(?)`** (novo componente `HelpButton`): badge
  `questionmark.circle` estilo macOS ao lado de cada slider do painel avançado,
  do slider de Smoothness e do Picker de presets — popover com a explicação da
  função (ex.: "Max boost — multiplicador máximo aplicado à rolagem rápida",
  "Smooth fraction — fração da distância restante percorrida por tick do
  glide").
- **"Reset to default"**: botão ao lado do Picker → `smoothScrollLevel = 70`,
  `smoothScrollAdvanced = nil` (restaura Glide). Aplicado via caminho leve.

### 4. Caminho leve no slider + invariante do advanced (`AdvancedTabView`)

- `setLevel` usa `applyLive()` (→ `updateSmoothParameters`) por tick do slider,
  **não** `apply()` — corrige o flicker (não destrói o coordinator).
- Fix da invariante: `applyLive()` grava
  `smoothScrollAdvanced = level == nil ? currentParams() : nil` (hoje grava
  incondicionalmente, AdvancedTabView.swift:238).

### 5. Migração de config

- Config existente com `smoothScrollAdvanced` → carrega como **Custom**
  (`level = nil`), preservando o tuning.
- Config existente com `smoothScrollLevel` (ex. 50) → mantém o nível salvo.
- Instalação nova / reset → `smoothScrollLevel = 70` (Glide).
- Pro gating inalterado (`smoothScrollLevel`/`smoothScrollAdvanced` limpos sem
  licença via `filteringProFeatures`).

## Estrutura de arquivos

- **Editar** `Sources/RatTamerCore/Core/SmoothnessLevel.swift` (âncoras dos 6
  presets, curva completa, `SmoothnessPreset`, `defaultValue = 70`, remove
  `momentumOnThreshold`)
- **Editar** `Sources/RatTamerCore/Core/SmoothScrollSettings.swift` (`isCustom`
  completo)
- **Editar** `Sources/RatTamerApp/Views/GeneralTabView.swift`
  (`SmoothScrollRow`: Picker de presets + Reset + HelpButton)
- **Editar** `Sources/RatTamerApp/Views/AdvancedTabView.swift` (Picker de
  presets no lugar dos botões, `setLevel` → `applyLive`, invariante do
  `applyLive`, HelpButtons)
- **Criar** `Sources/RatTamerApp/Views/HelpButton.swift` (badge `(?)` + popover)
- **Editar** `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`
- **Editar** `Tests/RatTamerCoreTests/Core/SmoothScrollSettingsTests.swift`

## Testes

- `SmoothnessLevelTests`: valores exatos nos 6 níveis de preset (todos os
  campos sensíveis); booleanos flipam no ponto médio; interpolação monotônica
  entre presets (ex. 65 → valores entre Personal e Glide); clamp fora da faixa;
  `defaultValue == 70`; `preset(at:)` resolve cada âncora; `parameters` deriva
  todos os 17 campos.
- `SmoothScrollSettingsTests`: `isCustom == false` para advanced igual ao
  derivado do nível; `true` ao divergir `smoothingEnabled`/`pixelsPerNotch`/
  `smoothFraction`/`glideStopThreshold` (caso hoje quebrado).
- RatTest compila e o painel de tuning ao vivo continua aplicando sem reiniciar.

## Verificação

- `swift test` 100% verde.
- `swift build` sem warnings novos.
- App: seletor de presets seta o nível e os toggles avançados seguem;
  arrastar o slider vira "Custom"; Reset restaura Glide (70); `(?)` abre o
  popover em cada controle.
- Flicker: arrastar o slider de Smoothness na aba Advanced não treme mais a
  rolagem (com MOS fechado).
