# RatTamer Scroll Thermograph (RAT.ENERGY) — gráfico térmico de rolagem

Data: 2026-08-10 (Rev 2: janela externa + gráfico descritivo)
Status: Aprovado em brainstorm (Rev 2 aprovada pelo usuário)

## Objetivo

Mostrar **ao vivo** um gráfico de fluxo térmico da rolagem: entrada crua da
roda (flares de ignição) vs saída domada (onda térmica), com **personalidade
própria** do RatTamer — *não* uma cópia do gráfico do Mos (que é um line chart
plano). O visual é de **câmera de infravermelho**: onde a rolagem tem energia
queima (branco → amarelo → laranja → vermelho); onde esfria, apaga para
marrom/preto. Ao parar de rolar, a cena esfria até a baseline.

O gráfico vive em uma **janela externa** (não no tab de settings), aberta sob
demanda por um **botão** e por um **item de menu**. A janela é a única coisa que
consome CPU/RAM do gráfico: **fechada por padrão no lançamento**; enquanto
fechada, não há timer, não há sink, não há amostras. Além da estética térmica,
o gráfico é **descritivo**: eixos com escala (tempo e pixels), leituras
numéricas ao vivo e legenda raw vs suavizado.

## Requisitos

- **Séries de dados**: entrada crua (raw, estilo Mos nos dados) + saída
  suavizada (output). Duas leituras do mesmo fenômeno.
- **Janela temporal**: 5 segundos rolante (borda direita = `now`, -5s à esquerda).
- **Janela externa**: `ScrollGraphWindow` (NSWindow normal, padrão
  `SettingsWindow`), redimensionável, fecha com Cmd+W/Esc,
  `isReleasedWhenClosed = false`. **Fechada por padrão no lançamento.**
- **Acesso**: botão "Open Scroll Thermograph…" no tab Advanced (substitui o
  gráfico inline — resolve a rolagem das settings) + item de menu
  "Scroll Thermograph…" no menu do app (criar o main menu programaticamente se
  não existir). Ambos chamam `ScrollGraphWindow.shared.show()`.
- **Descritividade**: eixo Y com rótulos de pixels, eixo X com rótulos de tempo
  (0..-5s), leituras numéricas ao vivo (`out`, `raw`, `peak`, `avg`) e legenda
  "RAW entrada" / "SMOOTHED saída".
- **Smooth scroll desligado**: a janela abre mesmo assim, mostrando estado
  vazio + aviso "Ligue o Smooth scrolling para capturar". Não há botão
  Limpar/pausa (decisão do usuário).
- **Estilo**: termografia custom desenhada em `Canvas` (Swift Charts não
  comporta o look). Escuro sempre (o gráfico é uma "tela de instrumento").
- **Sem framework externo** e sem dependências novas no `Package.swift`.

## Arquitetura

### Core (`RatTamerCore`) — captura pura e testável

- **`ScrollSample`** (novo): `struct { time: Date, kind: Kind, value: Double }`
  com `Kind { raw, output }`. Tipo de dados trocado entre camadas.
- **`ScrollSampleBuffer`** (novo): ring buffer thread-safe (`NSLock`),
  capacidade ~900 amostras. API: `append(_:)`,
  `samples(in window: TimeInterval, before now: Date) -> [ScrollSample]`
  (trunca à janela e devolve ordenado por tempo). Puro e testável.
- **`ScrollSmoother.rawPixels(for:)`** (novo): `notches * pixelsPerNotch`
  (`notches = deltaV / multiplier`). O `feed` passa a **reutilizar** esse método
  (DRY — remove a duplicação interna atual, ScrollSmoother.swift:120-121).
- **`ScrollSmootherCoordinator.onSample`** (novo): `((ScrollSample) -> Void)?`,
  chamado **na queue do coordinator**, **antes do `poster`**:
  - `.raw` a cada `onWheelMovement` (via `smoother.rawPixels(for:)`);
  - `.output` a cada valor postado (tanto do `feed` quanto do `tick`, incluindo
    os `0` que o `feed` retorna no modo smoothing — representam "acumulando,
    ainda sem saída"; o guard de `postSmoothScroll` contra `0` não impede a
    amostra, pois o sample é emitido no coordinator, antes do poster).

### App (`RatTamerApp`) — janela + store + render

- **`ScrollGraphStore: ObservableObject`**: recebe `add(_:)` (chamado na queue
  do coordinator; append com lock no buffer), e publica snapshots na main a
  **30 Hz** em `@Published samples: [ScrollSample]`. O timer de flush é criado
  no `start()` e invalidado no `stop()` — **nenhum timer global**.
- **`ScrollGraphWindow`** (novo, singleton estilo `SettingsWindow`): dono do
  `ScrollGraphStore` e do lifecycle. `show()` conecta
  `engine.scrollSampleSink` e chama `store.start()`; `windowWillClose` desliga o
  sink e `store.stop()`. Content = `NSHostingController(rootView:
  ScrollGraphView(store:))`. **Fechada por padrão → zero wakeups, zero amostras,
  zero timer** até o usuário abrir.
- **`ScrollGraphView`**: recebe o `store` por parâmetro (`@ObservedObject`),
  **sem** `@StateObject`/onAppear/onDisappear — o lifecycle é do
  `ScrollGraphWindow`. Desenha tudo em `Canvas`.
- **`EngineController.scrollSampleSink`** (novo): `((ScrollSample) -> Void)?`.
  `applySmoothScrollIfNeeded` roteia `coordinator.onSample` → `scrollSampleSink`.

## Fluxo de dados

```
ScrollGraphWindow.show()
  → engine.scrollSampleSink = store.add; store.start()
wheel → handleWheelMovement → coordinator.onWheelMovement
  → (onSample .raw; feed/tick → poster; onSample .output)
  → ScrollGraphStore.add (lock)
  → flush 30 Hz na main (só com janela aberta)
  → @Published samples
  → ScrollGraphView.canvas
ScrollGraphWindow.windowWillClose()
  → engine.scrollSampleSink = nil; store.stop()
```

## Render no Canvas

- **Eixos**: X = tempo relativo (direita = `now`, -5s à esquerda); Y simétrico
  em torno de 0, `±max(|v|)` da janela com piso `±60` (0 = baseline/repouso).
- **Eixo Y descritivo**: margem esquerda ~34px com rótulos de pixels (ex.
  `120 / 60 / 0 / −60 / −120`) alinhados às gridlines horizontais (range
  arredondado para múltiplo de 30/60).
- **Eixo X descritivo**: margem inferior ~18px com rótulos `0 −1s −2s −3s −4s
  −5s` alinhados às gridlines verticais de 1s.
- **Grid**: linhas horizontais/verticais sutis, cor escura (ex. `#2b1522`).
- **Área térmica**: `Path` fechado sob a curva de saída, `LinearGradient`
  vertical com stops térmicos — pico branco `#FFFCE8`, depois amarelo
  `#FFE066`, laranja `#FFB454`, vermelho `#FF5E3A`/`#C2252F`, marrom `#6D0F2A`,
  violeta-escuro `#2D0B3D`, base preto `#0A0413`.
- **Linha de saída**: incandescente `#FFFCE8`, `strokeWidth` ~2.5, com `shadow`
  (glow). Sem blur filter pesado por frame — glow via shadow é mais barato.
- **Flares de ignição (raw)**: nas posições x dos samples `.raw` (ordenados),
  linha vertical curta: núcleo branco + halo laranja translúcido.
- **Brasas**: pequenos círculos translúcidos (`#FFCF7D`) próximos aos picos
  recentes da curva de saída, com alfa decaindo.
- **Barra de temperatura**: coluna vertical à direita do plot, preenchida com o
  mesmo gradiente térmico, labels "quente" (topo) / "frio" (base).
- **Leituras ao vivo** (topo direito, monospaced, só com dados): `out`
  (último output), `raw` (último notch), `peak` (maior |output| da janela),
  `avg` (média de |output| da janela), em pixels.
- **Legenda** (embaixo direito): linha de flare = `RAW entrada`; onda térmica =
  `SMOOTHED saída`.
- **HUD**: legenda discreta `RAT.ENERGY · TERMO`, janela `5s`, indicador
  `● LIVE` / `○ IDLE`.
- **Estado vazio (smooth desligado)**: gráfico apagado + aviso central "Ligue o
  Smooth scrolling para capturar" (lido do `AppModel.shared.configStore` a cada
  frame — a view re-renderiza a 30 Hz, então o aviso some sozinho quando ligar).
- **Repouso**: sem samples novos, a janela drena e a cena esfria até a baseline
  (comportamento aprovado: "o gráfico descansa como a roda").

## Threading & performance

- **RAM/CPU sob demanda**: com a janela fechada não existe timer, sink ou
  amostras — apenas um NSWindow alocado, sem conteúdo vivo. Abrir a janela liga
  o pipeline; fechar desliga tudo (`windowWillClose`).
- O flush de 30 Hz **existe apenas enquanto a janela do gráfico está aberta**
  (start/stop no `ScrollGraphWindow`). Janela fechada → **zero wakeups**
  (consistente com a otimização de wakeups já feita).
- Buffer ≤ ~900 amostras (5s @ 120 Hz + margem para raw); redraw em `Canvas` a
  30 fps é leve (paths simples, ≤ 900 pontos).
- Append do coordinator usa lock; snapshot é copiado no flush para a main.

## Edge cases

- **Smooth scroll desligado**: sem coordinator → sem samples; a janela abre com
  o estado vazio + aviso "Ligue o Smooth scrolling para capturar".
- **Janela fechada no lançamento**: sem timer, sem sink, sem amostras — zero
  consumo até abrir.
- **Abrir/fechar repetido**: `isReleasedWhenClosed = false` + store persistente;
  abrir re-liga o sink e o timer; fechar desliga ambos.
- **Scroll rápido**: buffer trunca na capacidade; a janela desliza normalmente.
- **Smooth ligado com a janela aberta**: o coordinator já roteia para o sink; o
  gráfico nasce ao rolar.
- **Reversão de direção**: valores negativos → domínio Y simétrico cobre.

## Testes

- **`ScrollSampleBufferTests`** (novo): append + janela; trim na capacidade;
  ordenação por tempo; exclusão de amostras fora da janela.
- **`ScrollSmootherTests`** (ajuste): `rawPixels(for:)` == caminho nativo do
  `feed` (e.g. deltaV=80, multiplier=8, ppn=10 → 100).
- **`ScrollSmootherCoordinatorTests`** (ajuste): feed emite `.raw` + `.output`
  na ordem; tick emite `.output`; valores de `.raw` batem com `rawPixels`; os
  `.output` batem com o que foi postado (incluindo `0` no settle).
- App (store/Canvas) fora de cobertura unitária (padrão do projeto — sem infra
  de UI tests).

## Fora de escopo

- Persistência do gráfico, pausa manual, botão Limpar, exportar/print.
- Tema claro para o gráfico (termografia é intencionalmente escura).
- Replicar o gráfico exato do Mos.
- Gráfico inline no tab Advanced (foi substituído pelo botão + janela externa,
  decisão da Rev 2).
