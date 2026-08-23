# RatTamer Níveis de Smoothness — slider no app + painel de tuning no RatTest

Data: 2026-08-09

## Objetivo

Permitir ajustar o **feel** do smooth scroll vertical. Duas superfícies:

1. **App principal**: um controle só — slider contínuo 0–100 com presets
   (Discreta / Média / Fluida). Quanto maior o nível, mais **amplificação**
   (pixels por detente) e mais **inércia** (glide). Substitui o toggle
   "Momentum".
2. **RatTest (app de debug)**: painel "Smooth Scroll" que expõe **todas** as
   opções de tuning ao vivo (amplificação, inércia, momentum, pixels/notch,
   bounce, etc.), para experimentar combinações durante o desenvolvimento.

## Contexto e motivação

- `ScrollSmoother` hoje tem parâmetros estáticos (`pixelsPerNotch = 10`,
  `maxBoost = 3.0`, `momentumDecay = 0.85`, `accelerationWindow = 0.05`,
  `feedGapTimeout = 0.08`, `momentumStopThreshold = 0.1`, bounce
  window/ratio/damping, `reversalConfirmation`, `directionThreshold`) e
  `Parameters` com apenas `multiplier`/`momentumEnabled`/`invert`.
- Teste no hardware mostrou que o feel não agrada em todos os modos
  ("ficou mais ou menos"). O usuário quer calibrar e, para isso, quer
  experimentar todas as combinações de parâmetros ao vivo no RatTest.
- Decisões de produto (brainstorming): nível **único** que combina velocidade
  e inércia; formato slider + presets; e **todas as opções expostas no RatTest**
  (pedido explícito do usuário).

## Decisões de design

1. **`SmoothnessLevel` (RatTamerCore, puro e testável)** — converte um nível
   0–100 nos parâmetros principais:
   - Clamp do valor em 0–100.
   - Âncoras de interpolação linear por partes:

     | nível | `maxBoost` | inércia (`momentumEnabled`) | `momentumDecay` |
     |-------|-----------|-----------------------------|-----------------|
     | 0 (Discreta) | 1.5 | off | — |
     | 20 | — | on (liga aqui) | 0.75 |
     | 50 (Média) | 3.0 | on | 0.85 |
     | 100 (Fluida) | 5.0 | on | 0.92 |

   - `momentumEnabled = nível >= 20` (abaixo disso: resposta seca, sem glide).
   - `maxBoost` interpola 0→1.5, 50→3.0, 100→5.0 (por partes).
   - `momentumDecay` interpola 20→0.75, 50→0.85, 100→0.92 (por partes).
   - `SmoothnessLevel.parameters(level:multiplier:invert:)` produz um
     `ScrollSmoother.Parameters` completo: aplica o nível sobre os defaults.
2. **`ScrollSmoother.Parameters` vira a superfície completa de tuning** — todos
   os knobs hoje estáticos passam a ser campos de `Parameters`, com `init`
   default reproduzindo os valores atuais:
   `multiplier`, `momentumEnabled`, `invert`, `maxBoost`, `momentumDecay`,
   `pixelsPerNotch`, `accelerationWindow`, `feedGapTimeout`,
   `momentumStopThreshold`, `bounceWindow`, `bounceRatio`, `bounceDamping`,
   `reversalConfirmation`, `directionThreshold`.
   - As constantes estáticas atuais permanecem como valores default do `init`
     (ex. `static let defaultMaxBoost = 3.0`), então testes existentes que só
     setam `multiplier`/`momentumEnabled`/`invert` continuam passando.
   - `feed`/`tick`/`stabilized` passam a ler de `parameters` (nunca de estático
     mutável).
3. **Config**: `smoothScrollMomentum: Bool?` é removido e substituído por
   `smoothScrollLevel: Double?` (0–100, `decodeIfPresent`, default 50). Configs
   antigas com momentum ficam sem nível → default 50 (decode não quebra: chave
   desconhecida é ignorada). `ConfigEntitlement.filteringProFeatures` passa a
   limpar `smoothScrollLevel`.
4. **EngineController** (app principal): `applySmoothScrollIfNeeded` monta os
   `Parameters` via `SmoothnessLevel.parameters(level:multiplier:invert:)`
   (fallback 50).
5. **UI app** (`SmoothScrollRow`): remove o toggle "Momentum". Com o smooth
   habilitado, exibe slider "Smoothness" 0–100 (inteiro, default 50) com
   marcadores clicáveis **Discreta · Média · Fluida** (0/50/100). Pro gating
   inalterado.
6. **RatTest** — painel "Smooth Scroll":
   - `RatTestEngine` passa a abrir o serviço `HiResWheel` (0x2121), fazer
     `setWheelMode(highResolution: true, target: true)` quando o painel está
     ativo, criar `ScrollSmoother` + `ScrollSmootherCoordinator` e rotear os
     reports de wheel do `DivertedButtonMonitor` para o smoother (mesmo padrão
     do `EngineController` do app).
   - `RatTestView` ganha uma seção "Smooth Scroll" com controles ao vivo:
     toggle master (liga/desliga o divert), e sliders/toggles para **todos** os
     campos de `Parameters` (multiplier read-only exibido, `maxBoost`,
     `momentumDecay`, `momentumEnabled`, `pixelsPerNotch`, `accelerationWindow`,
     `feedGapTimeout`, `momentumStopThreshold`, bounce window/ratio/damping,
     `reversalConfirmation`, `directionThreshold`).
   - Cada mudança reconstroi os `Parameters` e aplica no smoother em execução
     (método `setParameters` no coordinator/smoother) sem reiniciar o loop.
   - O painel funciona com licença livre (debug), sem Pro gating.
7. **Escopo**: sem novos sliders de velocidade/inércia no app principal (o
   nível único cobre); o tuning fino fica no RatTest. Apenas o wheel vertical
   principal. Thumb wheel e SmartShift intactos.

## Estrutura de arquivos

- **Criar** `Sources/RatTamerCore/Core/SmoothnessLevel.swift`
- **Criar** `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`
- **Editar** `Sources/RatTamerCore/Core/ScrollSmoother.swift`
  (`Parameters` completo + leitura em `feed`/`tick`/`stabilized`)
- **Editar** `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`
  (helper `make()`; semântica inalterada por causa dos defaults)
- **Editar** `Sources/RatTamerCore/Core/ConfigStore.swift`
  (campo + CodingKeys + default reset)
- **Editar** `Sources/RatTamerCore/Core/ConfigEntitlement.swift`
  (strip `smoothScrollLevel`)
- **Editar** `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`
  e `ConfigEntitlementTests.swift`
- **Editar** `Sources/RatTamerApp/EngineController.swift`
- **Editar** `Sources/RatTamerApp/Views/GeneralTabView.swift`
  (`SmoothScrollRow`)
- **Editar** `Sources/RatTest/RatTestEngine.swift` (HiResWheel + smoother)
- **Editar** `Sources/RatTest/RatTestView.swift` (painel "Smooth Scroll")
- **Editar** `README.md` (seção smooth scroll)

## Testes

- `SmoothnessLevelTests`: âncoras exatas (0/20/50/100) para `maxBoost`,
  `momentumDecay`, `momentumEnabled`; interpolação monotônica crescente; clamp
  de valores fora da faixa (ex. -10 → 0, 150 → 100); `default == 50`;
  `parameters(level:multiplier:invert:)` produz `Parameters` coerente.
- `ScrollSmootherTests`: helper `make()` atualizado; comportamento de feed/tick
  idêntico ao atual quando os campos default são usados (regressão);
  parâmetros customizados de `feed`/`tick` (ex. `maxBoost`/`momentumDecay`
  alterados) respeitam o valor de `parameters`.
- `ConfigStoreTests`: round-trip do novo campo `smoothScrollLevel`; default
  reset; config antiga com `smoothScrollMomentum` decodifica sem quebrar.
- `ConfigEntitlementTests`: `smoothScrollLevel` é limpo sem licença e mantido
  com licença.
- RatTest compila e o painel aplica mudanças ao vivo (verificação manual no
  hardware: `swift run RatTest`).

## Verificação

- `swift test` 100% verde.
- `swift build` sem warnings novos.
- App: slider + marcadores apenas com smooth habilitado; Discreta/Média/Fluida
  setam 0/50/100.
- RatTest: painel "Smooth Scroll" com todos os knobs; mudanças aplicam sem
  reiniciar o app; scroll suave responde aos valores alterados.
