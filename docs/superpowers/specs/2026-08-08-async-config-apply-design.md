# Aplicação assíncrona das configurações (UI nunca trava)

Data: 2026-08-08

## Objetivo

Eliminar o bloqueio da UI do RatTamer ao trocar configurações (modo/sensibilidade do
SmartShift, ações de botão, swap, DPI, invert scroll, toggle de enable). As escritas
HIDPP deixam de rodar no main thread e passam para a `ioQueue`, mantendo a UI
responsiva e o efeito no device imediato.

## Contexto e achados da investigação

- Toda ação de configuração na UI chama `engine.applyConfig()` **sincronamente** no
  main thread (`ButtonsTabView`, `GeneralTabView`, `AppModel`).
- `applyConfig()` executa escritas HIDPP bloqueantes (`session.request` com espera de
  resposta): diverts, swap, smartshift, DPI e invert scroll.
- Ao trocar modo/sensibilidade do SmartShift, a UI "trava" perceptivelmente durante o
  write síncrono (feedback do usuário).
- Já existe uma fila serializada `ioQueue` usada por `applyAction` e
  `executeThumbWheelNotch`; o loop de leitura de reports roda em thread própria e
  convive com escritas na `ioQueue` sem race (padrão já validado).
- Todos os 8 callers de `applyConfig()` são ações de UI e nenhum depende da escrita
  ser síncrona.

## Decisões de design

1. **`applyConfig()` vira fire-and-forget assíncrono**: continua chamando
   `refreshConfig()` (leitura pequena do arquivo + cache sob lock) sincronamente no
   thread chamador — assim o event tap do thumb wheel (`hasThumbWheelAction` →
   `currentConfig()`) enxerga a config nova imediatamente — e despacha as escritas
   para `ioQueue.async`.
2. **Helper `applyAll(controlsService:)`**: extrai o bloco comum de escritas
   (diverts, swap, smartshift, DPI, invert) para eliminar a duplicação entre
   `applyConfig()`, o setter de `enabled` e o `start()`.
3. **Setter de `enabled`**: atualiza `_enabled` sincronamente (flag consultado pelo
   event tap e por `handlePress`) e despacha `applyAll`/`restoreNativeDiverts` para a
   `ioQueue`.
4. **`start()` (conexão)**: mantém o apply atual síncrono. É evento único de
   conexão, não interação do usuário; mexer nele adicionaria race no connect sem
   benefício percebido.
5. **Ordem preservada**: `ioQueue` é serial e já é usada pelos demais writes
   (`applyAction`, `executeThumbWheelNotch`), então as configurações aplicam em ordem
   e sem colidir com o loop de leitura.
6. **Sem mudança de API**: `EngineController` não expõe nada novo; os callers de UI
   continuam chamando `applyConfig()` do mesmo jeito.

## Componentes

### `Sources/RatTamerApp/EngineController.swift`

- `func applyConfig()`:
  ```swift
  func applyConfig() {
      refreshConfig()
      ioQueue.async { [weak self] in
          guard let self, let controlsService = self.controlsService, !self.stopped else { return }
          self.applyAll(controlsService: controlsService)
      }
  }
  ```
- Novo `private func applyAll(controlsService: ReprogrammableControls)` com o bloco
  comum das 5 escritas.
- Setter de `enabled`:
  ```swift
  set {
      enabledLock.lock()
      _enabled = newValue
      enabledLock.unlock()
      guard !stopped else { return }
      if newValue {
          ioQueue.async { [weak self] in
              guard let self, let controlsService = self.controlsService else { return }
              self.applyAll(controlsService: controlsService)
          }
      } else {
          ioQueue.async { [weak self] in
              guard let self else { return }
              self.restoreNativeDiverts()
          }
      }
  }
  ```
- `start()` usa `applyAll` no trecho atual (linhas ~147–158) para evitar duplicação,
  sem alterar a sincronicidade.

## Fluxo de dados

```
UI (slider/menu/toggle) → save config → applyConfig()
  → refreshConfig()  (síncrono: atualiza cachedConfig p/ o event tap)
  → ioQueue.async → applyAll(controlsService)
      → setDiverted / setRemapped / setRatchetControlMode / setSensorDpi / setInverted
```

## Tratamento de erro e casos de borda

- **Dispositivo desconectado durante a fila**: os guards `self.controlsService` /
  `!self.stopped` já existentes fazem o task sair silenciosamente.
- **Múltiplas trocas rápidas**: as tasks enfileiram em ordem; a última aplicada é a
  config mais recente (cada task lê `currentConfig()` na execução).
- **App fechando**: `stop()` seta `stopped = true`; tasks pendentes na `ioQueue` saem
  pelos guards.

## Testes

Sem test target no `RatTamerApp` e o bloqueio está em chamadas IOKit
(`session.request`), não unitarizável sem injetar sessão fake (refactor grande).
Verificação manual com o device físico (padrão das features anteriores).

## Fora de escopo

- Debounce/throttle de trocas rápidas (descartado pelo usuário).
- Async no `start()` / fluxo de conexão.
- Mudança de API ou UI.

## Critérios de sucesso

- Trocar modo/sensibilidade do SmartShift e outras configs não bloqueia a UI
  perceptivelmente.
- As escritas continuam chegando ao device (verificável via `RatDiagnose` read-back).
- `swift build` e `swift test` verdes.

## Stack de verificação

**v1 (automatizado)**: `swift build` e `swift test` (140 testes) verdes.

**v2 (manual)**: com o MX Master conectado, arrastar o slider de sensibilidade e
trocar modos rapidamente — UI fluida, sem congelamento; conferir via `RatDiagnose`
que o valor aplicado no device corresponde ao config salvo.
