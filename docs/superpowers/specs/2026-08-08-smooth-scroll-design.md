# RatTamer Smooth Scroll — scroll vertical suave estilo trackpad via HID++

Data: 2026-08-08

## Objetivo

Adicionar **smooth scrolling** ao scroll vertical do wheel principal (estilo
trackpad: contínuo, com curva de aceleração e momentum configurável), lendo os
deltas de alta resolução direto do HID++ (feature `0x2121`) e re-emitindo o
scroll como CGEvents sintéticos. Recurso **Pro** (pay-what-you-want).

## Contexto e achados da investigação

- O RatTamer fala HID++ 2.0 com o receiver Unifying/Bolt (interface D1) via
  `HIDPPSession`/`HIDLocator` — a infraestrutura de leitura de reports já existe
  (`DivertedButtonMonitor.feed` no loop thread de `EngineController`).
- Hoje o app **não** suaviza scroll: `ScrollWheelTap` só intercepta scroll
  **horizontal** para detectar o thumb wheel; o scroll vertical do wheel
  principal é 100% o pipeline nativo do macOS (notches discretos, sem
  aceleração/momentum).
- **macOS não implementa o HID Resolution Multiplier** — o scroll hi-res de um
  MX Master nunca chega com granularidade fina pelo caminho HID nativo. A
  resolução fina só existe via HID++ `0x2121`.
- **Formato confirmado** (spec x2121, OpenLogi, Solaar, kernel Linux, amostra
  real MARC):
  - `setWheelMode` (fn `0x02`, long): parâmetro `mode` — bit 0 `target` (0=HID,
    1=HID++ notification), bit 1 `resolution` (0=low, 1=high), bit 2 `invert`.
  - Evento `wheelMovement` (notification ID `0x00`): report
    `11 <dev> <feat> 00 <flags> <deltaV_hi> <deltaV_lo>` — `flags` bits 0-3
    `periods` (cap 15), bit 4 `resolution`; `deltaV` Int16 big-endian com sinal.
  - **`target=1` faz o device parar de emitir wheel HID nativo** — é o mecanismo
    de supressão do scroll duplo (confirmado no MARC). O `CGEventTap` é só rede
    de segurança para janelas de transição (reconexão/wake/low-power).
  - `invert` **só afeta o caminho HID nativo**; valores via HID++ não são
    invertidos — o app precisa inverter no poster se o usuário usar Natural
    Scrolling/invertido.
  - Multiplicadores: MX Anywhere 2 = 8, MX Master 2S = 8, MX Master 3 = 8/15
    (varia por firmware), MX Master 3S = 15 — ler `getWheelCapability` no device
    real; o acumulador do app precisa somar deltas fatiados (`periods` cap 15).
- Referências: `specs/research-hidd-logitech-hires-wheel.md` (relatório completo),
  x2121 PDF, OpenLogi, Solaar, MXControl (mesma estratégia, open source, macOS).

## Decisões de design

1. **Abordagem B — HID++ hi-res direto + CGEvents sintéticos** (escolhida pelo
   usuário sobre a A/CGEvent tap e a C/re-post pixels):
   - `setWheelMode(target: 1, resolution: 1)` quando ativo → device manda
     `wheelMovement` e para de gerar scroll HID nativo.
   - O app acumula `deltaV`/`periods`, aplica curva de aceleração própria e
     publica `CGEventCreateScrollWheelEvent` (scroll contínuo em pixels) —
     "skips the macOS scroll pipeline" (mesma estratégia do MXControl).
   - `CGEventTap` de segurança para suprimir scroll nativo residual em janelas
     de transição (opcional/defensivo).
2. **Escopo:** apenas o wheel vertical principal. Thumb wheel e SmartShift
   (features `0x2150`/`0x1B04`) ficam intactos. Sem slider de sensibilidade na
   v1 (aceleração por default).
3. **Configurável:** toggle mestre + toggle de momentum (o momentum é simulado
   por timer, pois o wheel físico não tem inércia).
4. **Pro gating:** novo `ProFeature.smoothScroll`; `filteringProFeatures` zera
   os campos de smooth scroll sem licença; UI mostra lock "Pro" e alerta de
   unlock (padrão do Buttons tab).
5. **Segurança de estado:** desativar smooth scroll, desconectar ou sair do app
   restaura `setWheelMode(target: 0, resolution: 0)` — o scroll nativo volta
   (espelha `restoreNativeDiverts`).

### Arquitetura

Componentes novos/alterados:

- **`Sources/RatTamerCore/HIDPP/HiResWheel.swift`** (modificar):
  - `setWheelMode(highResolution: Bool, target: Bool) throws` — fn `0x02`,
    monta o byte `mode` preservando o estado atual.
  - `parseWheelMovement(_:deviceIndex:featureIndex:) -> WheelMovement?` — parse
    do report `0x00`; `WheelMovement { deltaV: Int16, periods: UInt8,
    resolution: Bool }`. `ratchetSwitch` (`0x10`) fora de escopo por ora.
- **`Sources/RatTamerCore/Discovery/DivertedButtonMonitor.swift`** (modificar):
  - Novo init param `wheelFeatureIndex: UInt8?` (o `EngineController` já resolve
    o index da `0x2121` ao criar o `_hiResWheelService` e o repassa); `feed`
    roteia para `onWheelMovement` os reports cujo `resp[2] == wheelFeatureIndex`
    e `resp[3] >> 4 == 0x00`.
  - `onWheelMovement: ((WheelMovement) -> Void)?`.
- **`Sources/RatTamerCore/Core/ScrollSmoother.swift`** (novo, puro/testável):
  - **Sem timers e sem I/O** — é uma máquina de estados pura: `feed(_
    movement: WheelMovement, at now: Date)` acumula deltas em pixels (dividindo
    pelo multiplier do `getWheelCapability`), aplica curva de aceleração baseada
    na taxa de chegada e devolve os deltas a emitir; `tick(at now: Date)`
    devolve os deltas de momentum em decaimento exponencial (vazios se o
    momentum está off ou a velocidade zerou). O relógio é injetado (`now`) —
    testes usam tempo fictício.
  - Inversão de sinal quando config `invertScrollDirection`/Natural Scrolling.
  - O timer de ~120Hz e o `CGEventCreateScrollWheelEvent` ficam na camada App
    (`ScrollSmootherCoordinator`), que chama `feed`/`tick` e posta os eventos.
- **`Sources/RatTamerCore/Core/ConfigStore.swift`** (modificar):
  - `smoothScrollEnabled: Bool?`, `smoothScrollMomentum: Bool?` (decodificação
    `decodeIfPresent`, igual aos campos existentes).
- **`Sources/RatTamerCore/Core/LicenseKeyStore.swift`** (modificar):
  - `ProFeature.smoothScroll` (novo case).
- **`Sources/RatTamerCore/Core/ConfigEntitlement.swift`** (modificar):
  - sem `.smoothScroll`, `filteringProFeatures` zera `smoothScrollEnabled` e
    `smoothScrollMomentum`.
- **`Sources/RatTamerApp/EngineController.swift`** (modificar):
  - aplicar `setWheelMode` no connect/`applyAll` (via `_hiResWheelService`);
    restaurar no `stop()`; rotear `onWheelMovement` → `ScrollSmoother` → poster.
- **`Sources/RatTamerApp/Views/GeneralTabView.swift`** (modificar):
  - seção "Scrolling": toggles "Smooth scrolling" + "Momentum" com lock Pro
    (padrão do Buttons tab); unavailable se device sem feature `0x2121`.
- **`ScrollSmootherCoordinator`** (novo, camada App): dono do timer de ~120Hz;
  alimenta `ScrollSmoother` com `feed`/`tick` e posta os deltas como
  `CGEventCreateScrollWheelEvent` (unidade pixel, `isContinuous`), aplicando a
  inversão de Natural Scrolling lida do `Config`.

### UX (Settings → General → Scrolling)

- `Smooth scrolling` — toggle (recurso Pro, badge/lock se sem licença).
- `Momentum` — toggle visível só com smooth scroll ativo (sub-row).
- Sem licença: mostrar lock + alerta "Get RatTamer Pro" (padrão do Buttons tab).

### Testes

- `ScrollSmootherTests`: acumulação de deltas + multiplier, curva de aceleração
  (rápido acelera, lento é preciso), momentum decay para zero, parada sem
  momentum, inversão de sinal.
- `HiResWheelTests` (extender): parse `wheelMovement` (flags, periods, deltaV
  negativo), `setWheelMode` monta o byte `mode` correto preservando invert.
- `DivertedButtonMonitorTests` (extender): roteamento de report `0x2121` para
  `onWheelMovement`.
- `ConfigEntitlementTests` (extender): sem licença zera campos de smooth scroll.
- Manual no hardware: girar o wheel com smooth ativo → notif `0x00` + scroll
  contínuo; desativar/sair → scroll nativo volta (sem scroll duplo).

## Fora de escopo

- Smooth scroll em outras superfícies (thumb wheel, trackball, mice não-Logitech).
- Slider de sensibilidade personalizada.
- `ratchetSwitch` (0x10) e per-app overrides.
- Notarização (decisão anterior, separada).
- Detecção/mitigação de conflito com Logi Options+/BetterMouse (documentar no
  README; não rodar junto).

## Riscos

- **Feeling da curva de aceleração** — o maior risco; validar no hardware real
  cedo, antes do resto (disciplina acordada com o usuário).
- **Restaurar estado nativo no quit** — mitigado pelo `stop()`/deinit sempre
  chamando `setWheelMode(target: 0, resolution: 0)`.
- **Multiplier variável por firmware (8 vs 15)** — ler `getWheelCapability` no
  device real e usar o valor reportado, não um hardcoded.
- **`invert` não afeta HID++** — inverter no poster respeitando o config.
- **Scroll duplo em transições (wake/reconexão)** — `CGEventTap` de segurança +
  reaplicar `setWheelMode` no `onReconnected`.
