# Relatório de Reuso — Smooth Glide no ScrollSmoother + Paridade do RatTest

**Tarefa:** `smooth-glide-and-ratest-parity` (spec `2026-08-09-smooth-glide-and-ratest-parity-design.md`)
**Data:** 2026-08-09
**Atualização (rodada 2, 2026-08-09):** defaults sãos do glide validados **no código-fonte** de Mos, SmoothScroll e LinearMouse + calibração real da comunidade (Reddit, blogs) para roda ratcheted em tela 4K — ver seção "Defaults sãs para o glide (traduzidos para 120 Hz)".
**Escopo da pesquisa:** (A) algoritmos OSS de "smooth scrolling" de roda de mouse no macOS (Swift/ObjC) com glide por alvo + ease-out; (B) scroll inercial/kinetic como referência de curva; (C) padrões de interceptação/reescrita de CGEvent scrollWheel; (D) leitura HID++ HiResWheel/SmartShift/AdjustableDPI fora do RatTamer.
**Vínculo do projeto:** Swift 6, SwiftPM puro, **sem novas dependências** (sem Cocoapods/Carthage, sem binários). `ScrollSmoother` é puro e clock-injected (sem timers/IO; o caller injeta `Date`). macOS 13+.

---

## Resumo executivo

**Não existe biblioteca Swift pronta para integrar** que resolva a feature sem violar o vínculo "sem novas dependências". O algoritmo de glide por alvo com ease-out é **trivial** (lerp exponencial: `step = remaining * fraction` por tick) e já está totalmente especificado na spec. As implementações OSS existentes — **Mos** (Caldis/Mos), **SmoothScroll** (negativepl), **Mac Mouse Fix** — são **apps completos**, não bibliotecas, e servem como **referência de comportamento e de parâmetros**, não como código a importar.

**Recomendação: implementar do zero no `ScrollSmoother`** (a spec já descreve o algoritmo com precisão), usando as referências abaixo para **validar a matemática e calibrar os parâmetros** (`smoothFraction`, epsilon de parada, mínimo de 1px). Para a **Parte B (RatTest)**, todo o maquinário já existe no RatTamer (verificado no código-fonte): é trabalho de **UI wiring**, sem dependência externa.

---

## Parte A — Glide por alvo: candidatos avaliados

### A.1 Caldis/Mos — `Caldis/Mos` ⭐ REFERÊNCIA PRINCIPAL DE COMPORTAMENTO

- **URL:** https://github.com/Caldis/Mos
- **Licença:** **CC BY-NC 4.0** (confirmado no `LICENSE` do repo — **não permissiva**; proíbe uso comercial. Não copiar código).
- **Stars/atividade:** ~21,1k stars, 1.190 commits, ativo (v4.2.1, maio/2026; PRs abertos em jun/2026).
- **O que faz:** app de menu bar que intercepta scrollWheel via CGEventTap e re-emite eventos suavizados via CVDisplayLink. O núcleo está em `Mos/ScrollCore/ScrollPoster.swift` + `Interpolator.swift` (lidos na íntegra).
- **Por que serve:** é a **implementação de referência exata do padrão glide da spec**:
  - Estado: `buffer` (alvo acumulado) + `current` (posição emitida) — idêntico a `target`/`current` da spec.
  - `processing()` por frame: `frame = Interpolator.lerp(src: current, dest: buffer, trans: duration)` onde `lerp = (dest - src) * trans` → **exatamente `remaining * smoothFraction`** da spec.
  - Reversal: `if y*delta.y > 0 { buffer += ... } else { buffer = ...; current = 0 }` → **reset de current/target em reversal real**, igual à spec.
  - Dead zone: só posta quando `outputMagnitude > deadZone` (default 1.0) → equivalente ao epsilon de parada da spec (`momentumStopThreshold` 0.1).
  - Momentum phases (ScrollPhase) só para simulação de trackpad — o modo "não-trackpad" é o glide puro.
  - `post` usa `CGEventPostToPid` (via `ScrollDispatchContext`) — não re-roteia pelo tap.
- **Parâmetro validado:** a spec calcula `smoothFraction 0.13 @ 120 Hz ≈ Duration 3.0 do Mos` (que produz `1 - sqrt(3/5.2) ≈ 0.24`/frame @ 60 Hz). O código do Mos confirma a mecânica (trans = fração do restante por frame), validando a matemática da spec.
- **Esforço de integração:** zero (referência de leitura). Não usar como dependência (licença NC + app completo).
- **Recomendação:** **USAR COMO REFERÊNCIA** — valida a matemática e o comportamento do glide. Não copiar código.

### A.2 negativepl/SmoothScroll — `negativepl/SmoothScroll` ⭐ MELHOR REFERÊNCIA DE CÓDIGO (MIT)

- **URL:** https://github.com/negativepl/SmoothScroll
- **Licença:** **MIT** (confirmado no `LICENSE` — permissiva, copiável).
- **Stars/atividade:** 0 stars, 8 commits, criado 2026-02-26 (novo, sem tração — mas o código é pequeno e legível).
- **O que faz:** app de menu bar (~200 linhas Swift, arquivo único `Sources/main.swift`, lido na íntegra) que implementa **exatamente o padrão glide da spec**:
  - `accY/accX` = alvo acumulado; `errY/errX` = compensação de arredondamento fracionário (evita perda de sub-pixel).
  - `DispatchSourceTimer` a **120 Hz**; `tick()`: `step = acc * d` (d = `damping`, default 0.02) → `acc -= step` → posta evento pixel contínuo.
  - Reversal: `if (dy > 0 && accY < 0) || (dy < 0 && accY > 0) { accY = 0; errY = 0 }` → reset em reversal.
  - Epsilon de parada: `if abs(accY) < 0.5 && abs(accX) < 0.5` → zera e para (sem cauda longa).
  - **Mínimo de 1px no fim:** `if abs(stepY) < 1.0 && abs(accY) >= 1.0 { stepY = copysign(1.0, accY) }` — detalhe que a spec não menciona e vale considerar.
  - Idle 100 ms → "Instant Stop" ou "Momentum" (friction) — toggle equivalente ao `smoothingEnabled` + comportamento pós-parada.
  - Presets (Silky/Balanced/Fast/Precise) com speed+damping e slider log-scale — padrão de UI análogo aos presets do RatTest.
- **Por que serve:** é a **única implementação MIT completa do mesmo algoritmo** — serve para validar parâmetros (damping 0.02 ≈ smoothFraction; epsilon 0.5; mínimo 1px) e como referência de código copiável se algum detalhe (ex.: compensação de arredondamento) for adotado.
- **Contras:** app completo (CGEventTap + SwiftUI), não é biblioteca; 0 stars (sem validação da comunidade); o núcleo do algoritmo são ~30 linhas — não justifica dependência.
- **Esforço de integração:** zero (referência). O `ScrollSmoother` do RatTamer é puro/clock-injected; o SmoothScroll mistura tap+timer+UI no mesmo arquivo.
- **Recomendação:** **USAR COMO REFERÊNCIA DE CÓDIGO** (MIT) — validar parâmetros e o detalhe do mínimo de 1px / compensação de erro fracionário.

### A.3 noah-nuebling/mac-mouse-fix — `noah-nuebling/mac-mouse-fix` (referência de UX)

- **URL:** https://github.com/noah-nuebling/mac-mouse-fix
- **Licença:** **MMF License** (custom, baseada em MIT+DBAD; restringe monetização de derivados — **não permissiva padrão**).
- **Stars/atividade:** ~10,6k stars, ObjC, ativo (v3.0.6, 2025; v2.2.5 free no Homebrew).
- **O que faz:** app de "momentum-based scrolling algorithm" com níveis de suavidade (**High / Regular / Off**) — exatamente o conceito de "níveis de suavidade" que a Parte B do RatTest pede (Discreta/Média/Fluida).
- **Por que serve:** referência de **UX de níveis de suavidade** (como o usuário percebe High vs Regular vs Off) e de comportamento de free-spin (v3.0.6: "no longer speed-up scrolling when the wheel spins freely on MX Master" — relevante para o modo free-spin do RatTest).
- **Contras:** ObjC, licença custom, app completo; o algoritmo de momentum não é extraível sem contaminação de licença.
- **Recomendação:** **USAR COMO REFERÊNCIA DE UX** (níveis de suavidade + comportamento free-spin). Não copiar código.

### A.4 pilotmoon/Scroll-Reverser — `pilotmoon/Scroll-Reverser` (referência de CGEventTap)

- **URL:** https://github.com/pilotmoon/Scroll-Reverser
- **Licença:** **Apache 2.0** (permissiva).
- **Stars/atividade:** ativo (v1.9, jun/2024; mantido por Nick Moore).
- **O que faz:** reverte direção de scroll com detecção mouse vs trackpad via CGEventTap; inclui "step size" para roda discreta.
- **Por que serve:** **não faz smoothing** — mas é a referência canônica de **padrões de CGEventTap** (lifecycle, detecção de device, reescrita de campos do evento). O RatTamer já tem `ScrollWheelTap` com o mesmo padrão; útil apenas para conferir boas práticas (ex.: recuperação de `tapDisabledByTimeout`).
- **Recomendação:** **USAR COMO REFERÊNCIA** de CGEventTap (baixa prioridade — o RatTamer já implementa o padrão).

### A.5 linearmouse/linearmouse — ⭐ NOVO: modo "Smoothed" (MIT, dez/2025)

- **URL:** https://github.com/linearmouse/linearmouse
- **Licença:** MIT. Ativo (~1,5k stars).
- **O que faz:** desde dez/2025 o LinearMouse ganhou um modo **Smoothed** (PR #1108, refinado em #1157/#1224/#1228): engine de scroll suavizado com presets de curva (Ease In/Out/InOut, Quadratic, Cubic, Quartic, Smooth, Custom) e controles `response`/`speed`/`acceleration`/`inertia`. É **MIT** e publica valores reais de calibração (ver seção de defaults). O modelo é **velocity-based** (decay de velocidade + fases de momentum), não glide-por-alvo — serve para **calibrar**, não para copiar o algoritmo.
- **Recomendação:** **USAR COMO REFERÊNCIA DE CALIBRAÇÃO** (MIT) — `decay` 0.80–0.93/frame@60fps, `stopThreshold` 0.5, presets com números publicados.

### A.6 Outros — ❌

- **AirScroll** (airscroll.net): shareware fechado (trial 21 dias). **IGNORAR**.
- **quangtruong2003/SmoothScroll**: Windows/Rust, FSL-1.1-Apache-2.0 (fonte funcional, converte para Apache 2.0 só após 2 anos). Plataforma errada. **IGNORAR**.
- **Snippets de Stack Overflow** ("mimic inertial scrolling via CGEvent"): loops com `usleep` e ease-in/out manual — não são bibliotecas e são inferiores ao algoritmo da spec. **IGNORAR**.
- **galambalazs/smoothscroll-for-websites** (citado nos agradecimentos do Mos): JS para web, não roda no macOS. **IGNORAR**.

---

## Parte B — Paridade do RatTest: o que já existe no RatTamer (verificado no código)

A Parte B **não precisa de biblioteca externa** — todo o maquinário já está implementado e testado no RatTamer:

| Item da spec | Já existe no RatTamer | Arquivo |
|---|---|---|
| Níveis 0–100 + presets (Discreta/Média/Fluida) | `SmoothnessLevel` com âncoras (0/50/100) e `parameters(level:multiplier:invert:)` | `Sources/RatTamerCore/Core/SmoothnessLevel.swift` |
| Catálogo completo de ações | `ActionCatalog.systemTitle/systemIcon` cobre as 12 system actions + `.click` + `.gesture` + `.cycleDPI` + `.shortcut` | `Sources/RatTamerApp/ActionCatalog.swift` |
| DPI cycle | `DPICycle.next(current:presets:)` + `recommendedPresets(from:limit:)` + `AdjustableDPI` (0x2201: getSensorCount/getSensorDpiList/getSensorDpi/setSensorDpi) | `Sources/RatTamerCore/Core/DPICycle.swift`, `Sources/RatTamerCore/HIDPP/AdjustableDPI.swift` |
| Thumb wheel | `ScrollWheelTap` (CGEventTap) + `ThumbWheel.isThumbWheel` + `NotchAccumulator` | `Sources/RatTamerCore/Core/ScrollWheelTap.swift`, `ThumbWheelClassifier.swift` |
| Modo da roda ratchet/free-spin | `SmartShiftControls.getRatchetControlMode/setRatchetControlMode` + `HiResWheel.getInfo().hasSwitch` (0x2121) | `Sources/RatTamerCore/HIDPP/SmartShiftControls.swift`, `HiResWheel.swift` |
| RatTest posta via CGEvent + checa AXIsProcessTrusted | já presente | `Sources/RatTest/RatTestEngine.swift` |

O protocolo HID++ (0x2201, 0x2121, 0x2110/0x2111, 0x1000/0x1004, 0x1B04) foi validado contra **Solaar**, **OpenLogi docs** e **Mouser** no relatório de reuse anterior (`docs/superpowers/specs/2026-08-08-multi-device-support-v1.reuse.md`) — não há nada novo a pesquisar para a Parte B.

**O que falta na Parte B é exclusivamente UI wiring** no `RatTestView`/`RatTestEngine`: seções novas (Wheel Mode, DPI, Thumb Wheel), slider de nível + presets sincronizados com os sliders crus, toggle/slider de smoothing, e o picker de ações completo. Nenhuma dependência.

---

## Recomendação final

1. **REAPROVEITAR como referência de comportamento (não copiar):** **Caldis/Mos** — `Mos/ScrollCore/ScrollPoster.swift` + `Interpolator.swift` (https://github.com/Caldis/Mos, CC-BY-NC 4.0). Valida a matemática do glide: `lerp(current→buffer, trans)` = `remaining * smoothFraction`; reset em reversal; dead zone como epsilon de parada. **Confirmar a calibração:** `smoothFraction 0.13 @ 120 Hz` (spec) ≈ Duration 3.0 do Mos.
2. **REAPROVEITAR como referência de código MIT:** **negativepl/SmoothScroll** (https://github.com/negativepl/SmoothScroll, MIT) — implementação completa e copiável do mesmo algoritmo. **Adotar 2 detalhes que a spec não menciona:** (a) mínimo de 1px no fim do glide (`copysign(1.0, remaining)` quando `|remaining| >= 1`), evitando "derretimento" sub-pixel; (b) compensação de erro fracionário (`err += step - round(step)`) para não perder distância acumulada. Ambos são compatíveis com a arquitetura pura do `ScrollSmoother`.
3. **ADAPTAR (parâmetros, não código):** epsilon de parada — spec usa `momentumStopThreshold` (0.1); SmoothScroll usa 0.5; Mos usa deadZone 1.0. O valor 0.1 da spec é mais agressivo (para mais cedo); validar em teste real. `smoothFraction` default 0.13 @ 120 Hz está coerente com as duas referências.
4. **IGNORAR:** Mac Mouse Fix (licença custom — usar só como referência de UX de níveis), AirScroll (fechado), quangtruong2003/SmoothScroll (Windows), snippets de SO. **LinearMouse** deixou de ser "ignorar" — virou referência de calibração (modo Smoothed, MIT; ver A.5).
5. **Parte B:** **implementar do zero** (UI wiring) — todo o maquinário já existe no RatTamer; não há biblioteca Swift que entregue o painel do RatTest.
6. **CALIBRAR com os defaults sãos da seção abaixo:** modo glide `pixelsPerNotch 120 / maxBoost 1.5 / smoothFraction 0.13 / epsilon 0.5 / accelerationWindow 0.05`; preset Mos-like do RatTest `132 / 1.0 / 0.13 / 0.5 / 0.05` — **reconciliar com o design spec** (que usa 60/2.2; ver discrepância na seção).

**Justificativa do "do zero":** o algoritmo de glide é ~10 linhas de matemática (lerp exponencial) já especificadas na spec; as implementações OSS são apps completos (CGEventTap + timer + UI) incompatíveis com a arquitetura pura/clock-injected do `ScrollSmoother` (que não pode ter timers/IO internos — o caller injeta `Date`). Importar qualquer uma delas violaria o vínculo "sem novas dependências" e/ou a licença. O esforço de implementar é pequeno (2 parâmetros + 2 campos de estado + ramificação em `feed`/`tick`) e o risco de integrar dependência é maior que o benefício.

**Ações concretas para o `edit`:**
1. `ScrollSmoother.Parameters`: adicionar `smoothingEnabled: Bool = false` e `smoothFraction: Double = 0.13` (no Equatable, init e decode legado).
2. Estado: `target`/`current` zerados em `reset()`.
3. `feed` (glide ON): pipeline atual intacto (notches→raw→boost→bounce); bounce não acumula; reversal real zera `current`/`target`; `target += pixels`; retorna 0.
4. `tick` (glide ON): `remaining = target - current`; se `|remaining| <= momentumStopThreshold` emite o restante e zera; senão emite `remaining * smoothFraction` e avança `current`. Considerar mínimo de 1px e compensação de erro fracionário (referência SmoothScroll).
5. RatTest: seções Wheel Mode / DPI / Thumb Wheel + níveis/presets + toggle/slider de smoothing, usando as APIs já existentes listadas na tabela acima.

---

## Defaults sãs para o glide (traduzidos para 120 Hz)

> Rodada 2 da pesquisa (2026-08-09): valores validados **no código-fonte** de Mos, SmoothScroll e LinearMouse + calibração real da comunidade (Reddit, blogs) para roda ratcheted (MX Master) em tela 4K. Nenhum código copiado — apenas números.

### Fórmula de tradução 60 Hz → 120 Hz

O Mos roda a 60 fps (CVDisplayLink) e aplica `frame = (buffer − current) × transition` por frame. Para o **mesmo tempo de convergência** a 120 Hz:

```
smoothFraction@120Hz = 1 − sqrt(1 − transition@60Hz)
```

(derivado de `(1−s)¹²⁰ = (1−t)⁶⁰`). O SmoothScroll (negativepl) já roda a 120 Hz nativo — o `damping` dele **é** o `smoothFraction` direto, sem tradução.

### Tabela de fontes — valores brutos e tradução

| Fonte (URL / licença) | Valores brutos (verificados) | Tradução p/ nossos parâmetros |
|---|---|---|
| **Caldis/Mos** — github.com/Caldis/Mos (CC BY-NC 4.0) — `Utils/Constants.swift` + `Options/Options.swift` + `ScrollCore/ScrollPoster.swift` + `Interpolator.swift` | defaults master: `step 33.6, speed 2.70, duration 4.35, deadZone 1.00`; fórmula `transition = 1 − sqrt(duration/5.2)` (arred. 3 casas); `ANIMATION.duration 0.3`; thresholds continuation 0.18 s / separation 0.45 s / momentumEnd 0.13 s / trackingEndAdvance 0.04 s; CVDisplayLink 60 fps; `lerp = (dest−src) × trans` | `pixelsPerNotch = step × speed` = **90.7 px/notch** (master) / **132 px/notch** (config do usuário: 60 × 2.2); `smoothFraction@120Hz`: duration 3.0 → **0.128**, 3.75 → **0.079**, 4.35 → **0.044**; epsilon ≈ deadZone **1.0** |
| **Mos site demo** — mos.caldis.me | step 10, speed ×1.0, duration 3.75 → transition **0.151** | **confirma a fórmula** (1 − sqrt(3.75/5.2) = 0.1508); 10 px/notch (piso); sf@120Hz 0.079 |
| **negativepl/SmoothScroll** — github.com/negativepl/SmoothScroll (MIT) — `Sources/main.swift` (lido na íntegra) | 120 Hz nativo; `damping` default **0.02** (presets Silky 0.008 / Balanced 0.02 / Fast 0.06 / Precise 0.012; slider log 0.005–0.20); `speed` default 0.6 (0.05–3.0); epsilon **0.5**; idle 0.1 s; momentumFriction 0.15; mínimo 1 px no fim; compensação de erro fracionário | `smoothFraction` = damping direto: **0.02** (Balanced) / 0.008–0.06 (presets); `epsilon` = **0.5**; `pixelsPerNotch` ≈ raw (~10 px) × speed ≈ **6 px/notch** (piso — lento demais p/ 4K); `feedGapTimeout` ≈ 0.1 s |
| **noah-nuebling/mac-mouse-fix** — github.com/noah-nuebling/mac-mouse-fix (MMF License, custom) | presets **Off / Regular / High**; `animationDuration = msPerStep/2000` (≈0.15–0.3 s); curva cubic-bezier + momentum por drag de velocidade; free-spin **sem** speed-up desde 3.0.6 | sem números publicados (licença custom) — referência de **UX de níveis** (Regular = cauda curta/direto; High = trackpad-like com bounce) e de comportamento free-spin |
| **LinearMouse** — github.com/linearmouse/linearmouse (MIT) — `EventTransformer/SmoothedScrollingEngine.swift` + `Model/Configuration/Scheme/Scrolling/Smoothed.swift` (PR #1108, dez/2025) | defaults: `response 0.45` (0–2), `speed 1` (0–8), `acceleration 1.2` (0–8), `inertia 0.65` (0–8); preset default easeInOut: `decay 0.89`/frame@60fps; presets decay 0.80–0.93; `stopThreshold 0.5`; `inputGrace 1/25 s` | `smoothFraction@120Hz = 1 − sqrt(decay)`: easeInOut → **0.057**; faixa 0.036–0.106; `epsilon` = **0.5**; boost por taxa ≈ +10–16% (accelerationGain) → teto modesto |
| **Comunidade** — Reddit r/logitech, baty.net, Mos discussions | Reddit (MX Master 3S, 4K): Step 35 / Speed 3.5 → **122.5 px/notch**; Jack Baty (MX Master, 4K): Step 75 / Speed 3.5 → **262.5 px/notch**, Duration 3.90; Mos #446: Step 54.72 / Speed 3.09 → **169 px/notch**, Duration 3.90 | 4K converge em **120–170 px/notch** (Baty 262 é o extremo "muito rápido"); sf@120Hz p/ Duration 3.90 → **0.069** |

### Recomendação — UM conjunto de defaults sãos (modo glide)

| Parâmetro | **Default glide** | **Preset Mos-like (RatTest)** | Justificativa |
|---|---|---|---|
| `pixelsPerNotch` | **120** | **132** | 4K "More Space" (2304×1296 pt): comunidade converge em 120–170 px/notch (Reddit 122.5, #446 169, usuário 132). 120 é redondo e no meio do intervalo sano; Mos master (90.7) é o piso. Mos-like = **Step 60 × Speed 2.2 = 132** (distância real por notch no Mos — ver discrepância abaixo). |
| `maxBoost` | **1.5** | **1.0** | Boost por taxa de chegada é a única diferença do nosso modelo vs Mos (que aplica `speed` em **todo** evento). Teto modesto evita o runaway do free-spin que o usuário relatou (Step 30/45 "rápidos demais"). LinearMouse acelera ~1.1–1.2×; legado usa 3.0. Mos-like = **1.0** (sem boost — Mos não tem; `boost = 1 + (maxBoost−1)·…` fica 1). |
| `smoothFraction` | **0.13** | **0.13** | = Duration 3.0 do Mos → 0.128 @120 Hz, config **validada pelo usuário** ("mais controlado, sem inércia longa"). Cauda ~0.28 s até 1% do restante. Faixa sã: 0.02 (SmoothScroll Balanced, cauda 1.9 s — flutuante) a 0.13 (Mos Dur 3.0). |
| `epsilon` | **0.5** | **0.5** | Consenso SmoothScroll (0.5) + LinearMouse (stopThreshold 0.5); Mos usa deadZone 1.0. Com semântica "emite o restante e para", não perde distância. (Spec reusa `momentumStopThreshold` 0.1 — aceitável, porém menos suportado.) |
| `accelerationWindow` | **0.05** | **0.05** | Mantém o default existente: separa cadência normal ratcheted (100–200 ms/notch) de spin rápido (<50 ms). Referências de 0.1–0.18 s (Mos continuation 0.18, SmoothScroll idle 0.1) são para transição de fase/momentum, não para boost. |

**Discrepância com o design spec (reconciliar no edit):** a spec (linha 98) define o preset Mos-like como `pixelsPerNotch = 60, maxBoost = 2.2` (mapeando Step→pixelsPerNotch e Speed→maxBoost). O código do Mos mostra que `speed` multiplica **todos** os eventos (`buffer += y × speed`), então a distância real por notch é `step × speed = 132 px`. Com 60 px/notch o scroll lento ficaria com **metade** da distância do Mos real do usuário. **Recomendação: 132 / 1.0** (ou 132 / 1.5 se quiser um boost leve no spin).

**Notas de implementação:**
- `feedGapTimeout` (legado, default 0.08 s): referências — SmoothScroll idle 0.1 s, Mos separation 0.45 s / continuation 0.18 s. Manter legado intacto.
- Mínimo de 1 px no fim do glide (`copysign(1.0, remaining)` quando `|remaining| ≥ 1`) e compensação de erro fracionário (SmoothScroll) — já recomendados na rodada 1; compatíveis com epsilon 0.5.
- Slider do RatTest para `smoothFraction`: faixa sã **0.02–0.15** (a spec usa 0.02–0.50; acima de ~0.2 o glide vira "quase instantâneo").