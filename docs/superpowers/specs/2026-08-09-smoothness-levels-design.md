# RatTamer Níveis de Smoothness — slider único com presets

Data: 2026-08-09

## Objetivo

Permitir ajustar o **feel** do smooth scroll vertical com um controle só:
um slider contínuo 0–100 com marcadores de preset (Discreta / Média / Fluida).
Quanto maior o nível, mais **amplificação** (pixels por detente) e mais
**inércia** (glide depois de soltar a roda). O nível substitui o toggle
"Momentum" atual, passando a governar velocidade + inércia juntos.

## Contexto e motivação

- O `ScrollSmoother` hoje tem os parâmetros fixos `maxBoost = 3.0` e
  `momentumDecay = 0.85`, com toggle binário `momentumEnabled` exposto na UI
  como "Momentum". Teste no hardware mostrou que o feel não agrada em todos os
  modos de uso ("ficou mais ou menos") — o usuário quer calibrar.
- Decisão de produto (brainstorming): um **nível único** que combina velocidade
  e inércia (não sliders separados). Formato: slider contínuo + presets, em vez
  de presets discretos.
- O nível default **50 (Média)** reproduz o parâmetros atuais, então quem já
  usa não sente diferença ao atualizar.

## Decisões de design

1. **`SmoothnessLevel` (RatTamerCore, puro e testável)** — converte um nível
   0–100 nos parâmetros do `ScrollSmoother`:
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
   - Constantes públicas para testes/tuning: `min`, `max`, `default`, âncoras.
2. **`ScrollSmoother.Parameters` ganha `maxBoost` e `momentumDecay`** — saem do
   escopo estático; `feed` e `tick` passam a ler de `parameters`. O resto
   (`pixelsPerNotch`, `accelerationWindow`, `feedGapTimeout`,
   `momentumStopThreshold`, bounce window/ratio/damping, reversal confirmation)
   permanece estático.
3. **Config**: `smoothScrollMomentum: Bool?` é removido e substituído por
   `smoothScrollLevel: Double?` (0–100, `decodeIfPresent`, default 50). Configs
   antigas com momentum simplesmente ficam sem nível → default 50.
   `ConfigEntitlement.filteringProFeatures` passa a limpar `smoothScrollLevel`.
4. **EngineController**: `applySmoothScrollIfNeeded` monta os `Parameters` a
   partir de `config.smoothScrollLevel` via `SmoothnessLevel` (fallback 50).
5. **UI** (`SmoothScrollRow`): remove o toggle "Momentum". Com o smooth
   habilitado, exibe:
   - Slider "Smoothness" 0–100 (valor inteiro, default 50).
   - Marcadores clicáveis **Discreta · Média · Fluida** alinhados sob o slider
     (0 / 50 / 100) — clicar define o nível; arrastar faz ajuste fino.
   - Pro gating inalterado: o toggle mestre continua bloqueado sem licença.
6. **Escopo**: sem novos sliders (velocidade/inércia separados ficam fora).
   Apenas o wheel vertical principal, como hoje. Thumb wheel e SmartShift
   intactos.

## Estrutura de arquivos

- **Criar** `Sources/RatTamerCore/Core/SmoothnessLevel.swift`
- **Criar** `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift`
- **Editar** `Sources/RatTamerCore/Core/ScrollSmoother.swift`
  (`Parameters` + uso em `feed`/`tick`)
- **Editar** `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`
  (helper `make()` com os novos campos)
- **Editar** `Sources/RatTamerCore/Core/ConfigStore.swift`
  (campo + CodingKeys + default reset)
- **Editar** `Sources/RatTamerCore/Core/ConfigEntitlement.swift`
  (strip `smoothScrollLevel`)
- **Editar** `Tests/RatTamerCoreTests/Core/ConfigStoreTests.swift`
  e `ConfigEntitlementTests.swift`
- **Editar** `Sources/RatTamerApp/EngineController.swift`
- **Editar** `Sources/RatTamerApp/Views/GeneralTabView.swift`
  (`SmoothScrollRow`)
- **Editar** `README.md` (seção smooth scroll)

## Testes

- `SmoothnessLevelTests`: âncoras exatas (0/20/50/100) para `maxBoost`,
  `momentumDecay`, `momentumEnabled`; interpolação monotônica crescente; clamp
  de valores fora da faixa (ex. -10 → 0, 150 → 100); `default == 50`.
- `ScrollSmootherTests`: helper `make()` atualizado; comportamento de feed/tick
  idêntico com `maxBoost = 3.0` / `momentumDecay = 0.85` (regressão).
- `ConfigStoreTests`: round-trip do novo campo `smoothScrollLevel`; default
  reset; config antiga com `smoothScrollMomentum` não quebra decode.
- `ConfigEntitlementTests`: `smoothScrollLevel` é limpo sem licença e mantido
  com licença.
- Verificação manual (hardware): `swift run RatTamer`, variar o slider e
  conferir amplificação/glide em cada extremo.

## Verificação

- `swift test` 100% verde.
- `swift build` sem warnings novos.
- UI mostra slider + marcadores apenas com smooth habilitado; clicar em
  Discreta/Média/Fluida seta 0/50/100.
