# Presets: Curva Coerente de Âncoras (somente valores)

**Data:** 2026-08-10
**Status:** aprovado (brainstorming)
**Escopo:** corrigir apenas os VALORES das âncoras de `SmoothnessLevel` para uma progressão monotônica e coerente. Nomes, estrutura, default (Mos 80), UI, engine e testes de comportamento permanecem intactos.

## Problema

As âncoras atuais violam a coerência:

- `pixelsPerNotch` **não é monotônico**: Native(0)=48 → Smooth(35)=45 (dip abaixo do nativo) → Glide(60)=110.
- `smoothFraction` está **invertido** na progressão: Fluid(100)=0.15 é o *mais rápido* (fração maior = ease-out mais curto), contrariando "Fluid = o mais fluido". Fluxo coerente exige fração **decrescente** com o nível.
- `maxBoost` não segue uma rampa clara de compensação (baians/altos arbitrários).

## Dados observados (gráfico Scroll Thermograph)

O gráfico mede `raw = notches × pixelsPerNotch` (px, já multiplicado) e `output` (px suavizados). Capturas ao vivo mostraram notches por evento de ~0,1–1,5 — valores típicos de roda de detente. Esse range calibra o intervalo de `pixelsPerNotch` (48–165) como fisicamente sensato.

## Novas âncoras

| Preset | Nível | momentum | smoothing | px/notch | maxBoost | decay | smoothFraction |
|---|---|---|---|---|---|---|---|
| Native | 0 | off | off | 48 | 1.0 | 0.70 | 0.13 |
| Smooth | 35 | on | off | 55 | 2.5 | 0.88 | 0.13 |
| Glide | 60 | off | on | 90 | 1.6 | 0.85 | 0.14 |
| Mos | 80 | off | on | 115 | 1.2 | 0.85 | 0.13 |
| Flow | 90 | off | on | 140 | 1.1 | 0.85 | 0.12 |
| Fluid | 100 | off | on | 165 | 1.0 | 0.85 | 0.11 |

`glideStopThreshold` permanece 0.5 em todas. Booleanos de momentum/smoothing não mudam (momentum só em Smooth; glide a partir de Glide).

## Princípios de coerência

1. **px/notch estritamente crescente** 48 < 55 < 90 < 115 < 140 < 165. Native ≈ macOS nativo (~50px); Smooth levemente acima (momentum ganha distância); rampa mais íngreme quando o glide assume.
2. **maxBoost decrescente** de Smooth em diante: 2.5 → 1.6 → 1.2 → 1.1 → 1.0. Native não aplica boost (passthrough puro), então 1.0 ali é inerte.
3. **smoothFraction decrescente** nos presets de glide: 0.14 → 0.13 → 0.12 → 0.11 (nível maior = glide mais longo/suave). Âncoras sem glide (0 e 35) ficam em 0.13, inerte.
4. **Propriedade-chave (pico de flick consistente):** `maxBoost × pixelsPerNotch` no fluxo rápido fica ~135–165px em TODOS os níveis (2.5×55≈138, 1.6×90≈144, 1.2×115≈138, 1.1×140≈154, 1.0×165=165). Rolagem rápida = magnitude parecida em qualquer preset; rolagem calma = escala com a fluidez. É isso que define a "progressão clara".
5. `momentumDecay`: só é aplicado em Smooth (0.88). Demais âncoras ficam em 0.85, inertes.

## Mudanças

- **Modificar** `Sources/RatTamerCore/Core/SmoothnessLevel.swift` — apenas o array `anchors` (6 linhas).
- **Modificar** `Tests/RatTamerCoreTests/Core/SmoothnessLevelTests.swift` — atualizar `testAnchorValues`, `testInterpolationBetweenAnchors` e `testParametersDerivesFullSet` para os novos valores:
  - `maxBoost(17.5)` = 1.75; `pixelsPerNotch(70)` = 102.5; `smoothFraction(85)` = 0.125; `pixelsPerNotch(95)` = 152.5; `momentumDecay(17.5)` = 0.79 (mantém).
  - Parâmetros em nível 80: ppn = 115, maxBoost = 1.0, smoothFraction = 0.13.

Valores propagam automaticamente para General/Advanced/RatTest (todos usam `SmoothnessLevel.*`).

## Não muda

- Nomes de presets (Native/Smooth/Glide/Mos/Flow/Fluid), níveis (0/35/60/80/90/100), default (Mos=80), UI, `ScrollSmoother`, booleans, `glideStopThreshold`.

## Verificação

1. `swift test` — todos verdes (inclui `SmoothnessLevelTests` atualizado).
2. `swift build` — sem warnings.
3. Checagem ao vivo opcional: rolar em 2-3 níveis (ex. Smooth e Fluid) e conferir no Scroll Thermograph que `raw` escala com o nível e o `output` responde sem cortes.
