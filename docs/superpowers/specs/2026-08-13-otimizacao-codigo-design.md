# Otimização de código (hot path + robustez + qualidade)

Date: 2026-08-13
Status: Approved

## Context

O app acabou de sair de duas frentes de crashes (assert do TSM no loop do botão e
kills de codesign no launch). Com o estado estável, o objetivo agora é otimizar o
código em três eixos acordados com o usuário: desempenho do hot path (smooth
scroll a 120 Hz), robustez/concorrência (I/O HID na main thread) e qualidade
(warnings de build e re-leitura de config).

Todos os itens abaixo foram verificados contra o código real. Um achado da
investigação prévia foi **refutado**: o suposto data race em
`EngineController.controls` — toda leitura/escrita de `controls` acontece na main
thread (escrita em `EngineController.swift:140`, leituras em `:141`, `:543`,
`AppModel.swift:75`, `ButtonsTabView.swift:33`). Não será alterado.

## Goal

1. **Hot path (120 Hz):** remover custo por frame não essencial do caminho do
   smooth scroll (log `os_log` por frame e `AXIsProcessTrusted()` sem cache).
2. **Robustez:** eliminar o risco de congelamento da UI por I/O HID síncrono na
   main thread nos views, e limitar o wait de aquisição de ownership do mailbox
   para que um device travado falhe rápido em vez de bloquear para sempre.
3. **Qualidade:** remover warnings de `try?` no CrashReporter e evitar a
   re-leitura/re-decode do `config.json` a cada interação de UI.

## Design

### 1. Hot path (smooth scroll a 120 Hz)

#### 1.1 Remover log por frame no `ScrollSmootherCoordinator.post`

Em `Sources/RatTamerCore/Core/ScrollSmootherCoordinator.swift:109`, `post` chama
`Self.log.info("OUT …")` para **todo** valor postado, inclusive os `0` que o
smoother emite enquanto acumula — até 120 chamadas `os_log`/seg. O gráfico de
scroll já recebe as amostras via `onSample` (sink só ligado quando o gráfico
está visível), então o log é redundante.

- Remover a linha do log por amostra de `post`.
- Manter os logs de lifecycle (`start`/`stop`), que são eventos raros.
- Nenhuma mudança de comportamento: `post` continua emitindo `.output` e
  chamando `poster`.

#### 1.2 Cache de `AXIsProcessTrusted()` com TTL

`Permissions.isAccessibilityTrusted()` (`Sources/RatTamerApp/Permissions.swift:6`)
chama `AXIsProcessTrusted()` sem cache; `EngineController.postSmoothScroll`
(`EngineController.swift:473`) o invoca a cada evento postado, até 120×/seg.
`AXIsProcessTrusted` é uma chamada síncrona com custo de IPC não desprezível.

- Adicionar cache com TTL de 0.5 s (NSLock + `cachedValue`/`cachedAt`), padrão
  idêntico ao `FrontmostAppGuard`. No pior caso 2 chamadas/seg.
- TTL de 0.5 s: mudança de confiança TCC (revogação/outorga) é refletida em até
  0.5 s — imperceptível, e a revogação durante o scroll já era detectada só na
  próxima postagem.
- `requestAccessibility()` invalida o cache antes de disparar o prompt, para a
  outorga ser vista imediatamente pelo próximo check.
- Auto-contido em `Permissions`; nenhum chamador muda.

#### 1.3 `FrontmostAppGuard.cacheTTL` 0.1 s → 0.25 s

`FrontmostAppGuard.isFrontmostTerminal()` já tem cache, mas o lookup de
`NSWorkspace.shared.frontmostApplication` (síncrono) roda a cada expiração — até
10×/seg no TTL atual. Com 0.25 s, cai para ≤4×/seg. Trocar a constante em
`Sources/RatTamerApp/FrontmostAppGuard.swift:10`. Resposta à troca de app de
~100 ms continua abaixo do perceptível.

### 2. Robustez/concorrência

#### 2.1 I/O HID fora da main thread nos views

Os loads de device I/O abaixo rodam síncronos na main thread via `.onAppear` e
bloqueiam a UI por até ~0.5 s por request (e mais com retries) se o device
estiver lento/travado:

- `Sources/RatTamerApp/Views/GeneralTabView.swift:173-185` — `load()` do DPI:
  `getSensorDpiList` + `getSensorDpi` + `configStore.load()`
- `Sources/RatTamerApp/Views/GeneralTabView.swift:277-286` — `load()` da
  inversão de scroll: `getInfo` + `getWheelMode`
- `Sources/RatTamerApp/Views/GeneralTabView.swift:318-321` — `load()` da
  bateria (`BatteryStatusRow`): `getBatteryInfo`
- `Sources/RatTamerApp/Views/MenuBarPopoverView.swift:141-153` — `loadDPI()`:
  `getSensorDpiList` + `getSensorDpi`

O `AdvancedTabView` **não** faz device I/O no load (só lê config) — fora do
escopo.

Solução: seguir o padrão já validado de `AppModel.preloadDPI`
(`Sources/RatTamerApp/AppModel.swift:90-102`) — `DispatchQueue.global(qos:
.utility).async` faz as leituras, hop para `DispatchQueue.main.async` para
atualizar os `@State`. Padrão já compila neste codebase (Swift 6).

- As **escritas** já são off-main (`engine.applyConfig()` → `ioQueue.async`,
  `EngineController.swift:256`; `applyDPIIfNeeded` etc. rodam em `ioQueue`) —
  não serão alteradas.
- `AppModel.preloadDPI` já está correto; não mexer.

#### 2.2 Wait limitado no `HIDReportMailbox.beginRequest`

`beginRequest()` (`Sources/RatTamerCore/HIDPP/HIDReportMailbox.swift:108-116`)
espera `while activeRequests > 0 { condition.wait() }` sem limite. Se um request
ficar preso (ex.: `device.write` estacionado num device travado), o chamador
bloqueia indefinidamente.

- Novo método `beginRequest(timeout: TimeInterval) -> Bool`: retorna `false` se
  não adquirir ownership até o deadline, em vez de bloquear para sempre.
- `HIDPPSession.request` e `HIDPPSession.ping`
  (`Sources/RatTamerCore/HIDPP/HIDPPSession.swift:77-95` e `:111-135`) usam o
  novo método com deadline alinhado aos seus timeouts existentes (0.5 s/0.4 s) e
  lançam `HIDPPSessionError.noResponse` se a aquisição estourar.
- Manter `beginRequest()` sem argumentos (unbounded) — usado pelos testes
  existentes (`HIDReportMailboxTests.swift:83`) e como utilitário interno.

### 3. Qualidade

#### 3.1 Cache mtime-guardado no `ConfigStore.load()`

`ConfigStore.load()` (`Sources/RatTamerCore/Core/ConfigStore.swift:317-327`) lê o
arquivo do disco e re-decodifica o JSON a cada chamada; vários views e o engine
chamam `configStore.load()` em cada interação.

- Memoizar o config após a primeira leitura; invalidar o cache no `save()` ou se
  o mtime do arquivo em disco mudar (comparação de `modificationDate`).
- A guarda por mtime preserva o suporte a edição externa do `config.json`
  (Application Support).
- `loadStrict()` continua lendo do disco sempre (sem cache) — comportamento
  inalterado.

#### 3.2 Fix dos warnings `try?` no `CrashReporter`

Em `Sources/RatTamerApp/CrashReporter.swift:128-141`, dois warnings reais de build
(verificado empiricamente no SDK 26.2): `seek(toFileOffset:)` é non-throwing (o
`try?` produz "no calls to throwing functions occur within 'try' expression") e
`seekToEnd()` lança **e** retorna `UInt64` não usado (o `try?` produz "result of
'try?' is unused").

- `try? handle.seek(toFileOffset:)` → `handle.seek(toFileOffset:)`
- `try? handle.seekToEnd()` → `_ = try? handle.seekToEnd()`
- `try? handle.close()` e `(try? handle.readToEnd()) ?? Data()` são **mantidos**:
  `close()` e `readToEnd()` lançam neste SDK — remover o `try?` não compila.

## Testing

### Novos testes (RatTamerCoreTests)

- `HIDReportMailboxTests`: `beginRequest(timeout:)` retorna `false` quando outro
  request detém o ownership além do deadline, e `true` quando adquire a tempo.
- `ConfigStoreTests`: (a) `load()` após um `save()` retorna o valor salvo; (b)
  `load()` usa o cache (o arquivo não é relido) até o mtime mudar — simulação
  com arquivo temporário e toque no mtime via `FileManager`.

### Regressão

- `swift test` completo (345 testes atuais devem passar sem mudanças de
  assinatura quebradas — `beginRequest()` sem args é preservado).
- Build do app (`swift build` / Xcode) sem novos warnings.

## Fora de escopo

- Migração da camada HID para actors/async e auditoria Sendable completa
  (Abordagem 2).
- `EngineController.controls` (data race refutado — ver Context).
- Micro-otimizações de `CGEventPoster` / `ActionEngine`.
- Qualquer mudança no teardown do mailbox (reconexão).
