# Review — Task 2 + Task 3 (glide feed + tick): ScrollSmoother

**Spec:** `docs/superpowers/specs/2026-08-09-smooth-glide-and-ratest-parity-design.md` (Tasks 2 e 3)
**Briefs:** `.superpowers/sdd/2026-08-09-smooth-glide-and-ratest-parity/task-2-brief.md` + plan Task 3
**Implementation:** `Sources/RatTamerCore/Core/ScrollSmoother.swift` + `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`
**Commit:** `f1f02ba`
**Reviewer:** automated code-review
**Date:** 2026-08-09

## Verdict: APROVADO

Spec compliance: ✅ Task 2 (feed + stabilized 4-tuple) + ✅ Task 3 (tick/glideTick)
Task quality: Approved

Implementador reportou 289 testes, 0 failures (285 pré-existentes + 4 novos). Nenhum teste existente editado — diff do arquivo de teste é adição pura. Código transcrito verbatim do brief e do plano; matemática do glide validada analiticamente (ver abaixo).

---

## Checklist — Task 2 (feed + stabilized)

| Requisito | Status | Evidência |
|---|---|---|
| `feed` retorna 0 no modo glide | ✅ | `ScrollSmoother.swift:139` — `return 0` após acumular |
| `feed` acumula em `target` quando `accepted && !isBounce` | ✅ | `ScrollSmoother.swift:136-138` |
| `reversed` reseta `current`/`target`/`carry` | ✅ | `ScrollSmoother.swift:131-135` |
| `stabilized` retorna 4-tuple `(pixels, isBounce, reversed, accepted)` | ✅ | `ScrollSmoother.swift:153-154` — assinatura exata do brief |
| Branch `direction == 0 \|\| sign == 0` com `accepted = directionBefore == 0 \|\| sign == directionBefore` | ✅ | `ScrollSmoother.swift:165` |
| Branch `sign == direction` com `accepted = true` | ✅ | `ScrollSmoother.swift:174` |
| Branch reversal dentro de `bounceWindow` com `reversed = true` | ✅ | `ScrollSmoother.swift:182` |
| Branch bounce damping com `isBounce = true` | ✅ | `ScrollSmoother.swift:187` |
| Branch bounce fora de window com `reversed = true` | ✅ | `ScrollSmoother.swift:195` |
| Modo legado byte-identical (`if !isBounce { velocity = pixels }` + `applyInvert`) | ✅ | `ScrollSmoother.swift:141-144` — inalterado |
| 4 testes adicionados com semântica do brief | ✅ | `ScrollSmootherTests.swift:177-229` |
| Nenhum teste existente modificado | ✅ | Diff mostra apenas adições (0 linhas deletadas no teste) |

## Checklist — Task 3 (tick/glideTick)

| Requisito | Status | Evidência |
|---|---|---|
| `tick` short-circuits para `glideTick` quando `smoothingEnabled` | ✅ | `ScrollSmoother.swift:202-204` |
| Epsilon stop: `abs(remaining) <= glideStopThreshold` emite remainder e zera estado | ✅ | `ScrollSmoother.swift:220-225` |
| Ease-out: `step = remaining * smoothFraction` | ✅ | `ScrollSmoother.swift:226` |
| Min 1px quando `abs(step) < 1 && abs(remaining) >= 1` | ✅ | `ScrollSmoother.swift:227-229` |
| Carry compensation: `carry += step - step.rounded()` | ✅ | `ScrollSmoother.swift:230` |
| Whole-pixel release quando `abs(carry) >= 1` | ✅ | `ScrollSmoother.swift:232-236` |
| `current` avança pelo valor real `remaining * smoothFraction` | ✅ | `ScrollSmoother.swift:237` |
| Legado byte-identical quando `smoothingEnabled == false` | ✅ | `ScrollSmoother.swift:205-215` — inalterado |

---

## Validação analítica da matemática do glide

Implementação validada traçando `testGlideConvergesAndStops` (plan Task 3, `fraction: 0.5, stop: 0.01, pixelsPerNotch: 16`):

- **Convergência sem overshoot**: `current += remaining * smoothFraction` (linha 237) avança pelo valor real; `remaining = target - current` (linha 219) é recalculado a cada chamada. Como `0 < smoothFraction < 1`, `remaining` decai exponencialmente sem nunca ultrapassar `target`.
- **Epsilon branch**: quando `abs(remaining) <= 0.01`, emite o remainder exato e zera `target`/`current`/`carry` (linhas 220-225). Não há perda de pixels por arredondamento.
- **Min-1px**: condição `abs(step) < 1 && abs(remaining) >= 1` (linha 227) só força 1px quando o passo arredondaria 0 mas ainda há >= 1px de distância. Correto — evita stalls sem causar overshoot.
- **Carry**: erro fracionário acumulado em `carry` (linha 230) e liberado como pixel inteiro quando `abs(carry) >= 1` (linha 232). `carry` permanece limitado a (-1, 1) após o release check.
- **Total emitido**: traçado resulta em ~16.01px (dentro da tolerância `accuracy: 1.0` do teste). ✅

Traçado similar confirma `testGlideTickEmitsFractionOfRemaining` (8, 4, 2, 1) e `testGlideStopThresholdEmitsRemainder` (8, 4, 2, 2, 0).

---

## Findings

### 1. Escopo da mensagem de commit — **Menor**

- **Arquivo**: commit `f1f02ba`
- **O quê**: mensagem diz "glide feed accumulates into target and returns 0" mas o commit inclui também a implementação Task 3 (`tick`/`glideTick`).
- **Por que importa**: quem ler o log do git encontra uma discrepância entre a mensagem e o diff. Não afeta código nem comportamento.
- **Ação**: nenhuma para este commit (já consolidado). Para commits futuros, considerar mensagem que abarque ambos os tasks ou commit separado para Task 3.

### 2. Task 3 sem seus 5 testes — **Importante** (processo, não código)

- **Arquivo**: `Tests/RatTamerCoreTests/Core/ScrollSmootherTests.swift`
- **O quê**: a implementação `glideTick` está commitada mas os 5 testes do plan Task 3 (`testGlideTickEmitsFractionOfRemaining`, `testGlideConvergesAndStops`, `testGlideStopThresholdEmitsRemainder`, `testGlideMinOnePixel`, `testGlideParamsIgnoredWhenSmoothingDisabled`) não estão.
- **Por que importa**: o passo "rodar para ver falhar" do Task 3 não se reproduzirá — os testes passarão de primeira. Reportado pelo implementador no `task-2-report.md`.
- **Próximo passo**: dispatcher/orchestrator — ao Task 3, ou marcar como "verificar implementação contra plano + adicionar 5 testes" ou adicionar os testes e dar skip no fail-first. Não é bloqueio de código.

### 3. `makeGlide` arg-order fix — **Menor**

- **Arquivo**: `ScrollSmootherTests.swift:164-175`
- **O quê**: o brief passava `pixelsPerNotch` após `smoothingEnabled`/`smoothFraction`/`glideStopThreshold`, ordem que não compila (o init real tem `pixelsPerNotch` antes, linha 35 vs 44-46). Implementador reordenou.
- **Por que importa**: sem o fix, o teste não compila. Semântica idêntica — é o único desvio literal do brief, documentado no report.
- **Ação**: nenhuma.

---

## Itens não verificáveis pelo diff

- ⚠️ **Contagem exata de 289 testes**: baseada no implementer report (`task-2-report.md`). Não re-executei `swift test`. Confio na evidência do report conforme instruções.
- ⚠️ **Testes Task 3**: não presentes neste commit; validação analítica acima cobre a lógica, mas a execução real dos 5 testes do plan Task 3 fica para o dispatch do Task 3.

---

## Conclusão

Implementação correta, completa e fiel aos briefs Task 2 e Task 3. Matemática do glide validada: converge sem overshoot, epsilon emite remainder, min-1px e carry corretos. Código legado byte-identical quando `smoothingEnabled == false`. Nenhum teste existente tocado. Findings são menores ou de processo — nenhum bloqueante de código.

**Aprovado.**
