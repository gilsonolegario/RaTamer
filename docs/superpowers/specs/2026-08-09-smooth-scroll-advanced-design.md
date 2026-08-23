# Design — Smooth Scroll Avançado no app principal

Data: 2026-08-09
Status: Aprovado (brainstorming)

## Contexto

O RatTest expõe um painel completo de parâmetros avançados de smooth scroll
(18 controles + 5 presets), aplicados ao vivo no `ScrollSmoother` sem persistência.
O app principal (RaTamer) hoje oferece apenas um toggle + slider de nível (0-100)
que deriva somente 3 parâmetros via `SmoothnessLevel.parameters()`; todos os demais
parâmetros usam os defaults do `ScrollSmoother` e não são persistidos nem expostos
na UI.

Objetivo: portar o painel avançado de smooth scroll do RatTest para o app
principal, com persistência no `Config`, mantendo o modelo de interação
"nível sincroniza; custom desacopla" e a arquitetura atual de apply.

Escopo: **somente** o painel avançado de smooth scroll. Botões, DPI, wheel mode e
thumb wheel já têm UI/config no app principal e não serão alterados.

## 1. Modelo de dados (RatTamerCore)

### 1.1 `ScrollSmoother.Parameters` → `Codable`

`ScrollSmoother.Parameters` (arquivo `ScrollSmoother.swift`) ganha conformidade
`Codable`. Todos os campos são primitivos (UInt8, Bool, Double, TimeInterval, Int),
logo a síntese automática é suficiente. A conformidade é `public` e não altera o
comportamento existente (`Equatable` já existe).

### 1.2 Chave nova no `ConfigStore`

- `smoothScrollAdvanced: ScrollSmoother.Parameters?` — novo, opcional.
- `smoothScrollEnabled: Bool?` e `smoothScrollLevel: Double?` permanecem.
- Semântica de `smoothScrollLevel`: **nil = custom** (espelha o `syncedLevel` do
  RatTest). Valor não-nil = "sincronizado nesse nível".
- Decode retrocompatível: `smoothScrollAdvanced` ausente + `smoothScrollLevel`
  não-nil (instalações atuais) → comportamento idêntico ao atual (deriva os 3
  parâmetros do nível, restante em defaults), tratado como "sincronizado".
- `multiplier` e `invert` persistidos no struct são **sobrescritos** no apply
  (derivados do device e do `config.invertScrollDirection`, nunca da UI).

### 1.3 Helper `SmoothScrollSettings` (testável)

Novo tipo no Core com uma responsabilidade única: resolver `smoothScrollLevel` +
`smoothScrollAdvanced` em `ScrollSmoother.Parameters` finais.

- Input: `level: Double?`, `advanced: Parameters?`, `multiplier: UInt8`, `invert: Bool`.
- Regra:
  - Se `advanced` não-nil → usa-o como base.
  - Senão → deriva de `SmoothnessLevel.parameters(level: level ?? defaultValue, ...)`.
  - Em qualquer caso, sobrescreve `multiplier` e `invert` com os argumentos.
- Expõe também:
  - `isCustom` — `advanced` diverge da derivação de nível (os 3 parâmetros ligados
    não batem com `SmoothnessLevel.parameters(level:)`).
  - `synced(level:multiplier:invert:)` — produz um `Parameters` derivado do nível
    (usado ao tocar num preset ou mover o slider).
- Decode defensivo: valores inválidos/ausentes caem em defaults/derivação. Sem crash.

## 2. Motor (EngineController)

- `applySmoothScrollIfNeeded` (EngineController.swift) passa a montar os parâmetros
  via `SmoothScrollSettings` em vez de `SmoothnessLevel.parameters(...)` direto.
  O fluxo atual (enabled → setWheelMode → parar/recriar coordinator → iniciar) não muda.
- Novo método `updateSmoothParameters(_:)`: quando o smooth scroll está ativo, chama
  `smoothCoordinator?.setParameters(...)` — update ao vivo na fila privada do
  coordinator (troca `smoother.parameters` + reset), sem rebuild. Paridade com o
  `engine.setSmoothParameters` do RatTest. Se o smooth scroll estiver desativado,
  não faz nada.

## 3. UI (GeneralTabView → SmoothScrollRow)

- Mantém: toggle "Smooth scrolling", slider de nível (0-100), presets Discreta/
  Média/Fluida, gate Pro no toggle.
- Presets ganham **"Glide sã"** e **"Mos-like"** (do RatTest), com os mesmos valores:
  - Glide sã: smoothing on, pixelsPerNotch 120, maxBoost 1.5, smoothFraction 0.13,
    glideStopThreshold 0.5, accelerationWindow 0.05.
  - Mos-like: smoothing on, pixelsPerNotch 132, maxBoost 1.0, smoothFraction 0.13,
    glideStopThreshold 0.5, accelerationWindow 0.05.
- Novo `DisclosureGroup("Avançado")`, colapsado por padrão, com os 18 controles do
  RatTest organizados em grupos:
  - **Momentum:** toggle, Max boost (1.0-6.0), Momentum decay (0.5-0.98),
    Momentum stop (0.0-1.0)
  - **Glide:** toggle Smoothing, Smooth fraction (0.02-0.15), Glide stop (0.0-2.0)
  - **Feed:** Pixels per notch (1-40), Accel window (0.01-0.20), Feed gap timeout
    (0.02-0.30)
  - **Bounce:** Bounce window (0.0-0.20), Bounce ratio (0.1-1.0), Bounce damping
    (0.0-1.0)
  - **Direção:** Reversal confirmation (stepper 1-5), Direction threshold (0.0-5.0)
- Comportamento "custom": tocar em qualquer controle avançado desacopla o nível
  (marca custom); tocar num preset ou mover o slider re-sincroniza os 3 parâmetros
  ligados. (Mesmo modelo do RatTest.)
- Persistência + apply: toda mudança salva o `Config` e chama
  `updateSmoothParameters` (ao vivo) quando o toggle está ativo; mudanças de
  enabled/nível/presets seguem o fluxo atual (`applyConfig`).

## 4. Testes

- ConfigStore: round-trip encode/decode de `smoothScrollAdvanced` + combinações
  nível synced/custom; decode retrocompatível (JSON antigo sem a chave → deriva do
  nível, não-custom).
- `SmoothScrollSettings`: mapeamento nível→params; detecção de `isCustom`;
  sobreposição de `multiplier`/`invert`; fallback para defaults.
- Sem regressão esperada nos 304 testes existentes (chave nova é opcional; o
  comportamento default do apply não muda quando a chave está ausente).

## 5. Erros e compatibilidade

- Decode defensivo em `ConfigStore`: chave ausente ou valores inválidos → defaults/
  derivação do nível. Nunca crasha.
- `multiplier`/`invert` persistidos nunca chegam ao motor como-is; são sempre
  derivados do device/config no apply.
- Instalações existentes (sem `smoothScrollAdvanced`) mantêm exatamente o
  comportamento atual até o usuário tocar no painel avançado.

## Fora de escopo

- Não alterar o RatTest.
- Não tocar em botões, DPI, wheel mode, thumb wheel (já cobertos no app principal).
- Sem mudanças no gate Pro (toggle continua Pro; o painel avançado herda o estado).
