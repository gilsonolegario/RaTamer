# About com imagem maior e toggle de ícone na Dock

Data: 2026-08-08

## Objetivo

1. Aumentar a imagem do ícone na tab About (hoje 100×100).
2. Dar ao usuário a opção de rodar só na menu bar/popover, escondendo o
   ícone da Dock, com um toggle nas Settings.

## Contexto

- A tab About (`Sources/RatTamerApp/Views/SimpleTabs.swift`) mostra o ícone do
  app em 100×100 com `cornerRadius(22)`.
- O app tenta rodar como `.accessory` (`Sources/RatTamerApp/main.swift:6`
  chama `setActivationPolicy(.accessory)` antes do `run()`), mas na prática o
  ícone **aparece na Dock** — a policy aplicada antes do `run()` não é
  confiável neste setup.
- O bundle é SwiftPM puro (sem Xcode assets). `build-app.sh` gera o `.icns` e o
  `Info.plist` (sem `LSUIElement`).
- Decisão do usuário (brainstorming):
  - **Default: mostrar ícone na Dock**.
  - Toggle nas Settings para "só menu bar/popover" (esconder da Dock).
  - Imagem do About maior.

## Decisões de design

1. **About**: ícone de 100×100 → **160×160**, `cornerRadius` ~35 (proporcional).
   SF Symbol da menu bar (`computermouse`) inalterado (fora de escopo, decisão
   anterior).
2. **Config**: novo campo `menuBarOnly: Bool?` em
   `Sources/RatTamerCore/Core/ConfigStore.swift` (struct `Config`):
   - default `false`/`nil` = mostra na Dock (`.regular`);
   - `true` = só menu bar (`.accessory`).
   - Decodificar com `decodeIfPresent` para não quebrar configs existentes;
     adicionar ao `CodingKeys` e aos init (decoder + memberwise).
3. **Aplicação da policy**:
   - `main.swift`: remover o `setActivationPolicy(.accessory)` forçado (não
     confiável antes do `run()`).
   - `AppDelegate.applicationDidFinishLaunching`: aplicar a policy com base na
     config persistida (`menuBarOnly == true ? .accessory : .regular`).
   - Toggle nas Settings: ao mudar, salvar a config e aplicar a policy
     imediatamente (`.accessory` ao ligar, `.regular` ao desligar).
4. **Settings → General**: nova seção com
   `Toggle("Menu bar only (hide from Dock)")`, observando `AppModel.shared`
   (mesmo padrão das outras rows). A row lê a config no `onAppear`, aplica e
   salva no `onChange`.

## Componentes

### `Sources/RatTamerApp/Views/SimpleTabs.swift`
- `AboutTabView`: frame 100 → 160, cornerRadius 22 → 35.

### `Sources/RatTamerCore/Core/ConfigStore.swift`
- Campo `menuBarOnly: Bool?` + `CodingKeys` + decoder + init.

### `Sources/RatTamerApp/main.swift`
- Remover `application.setActivationPolicy(.accessory)`.

### `Sources/RatTamerApp/AppDelegate.swift`
- `applicationDidFinishLaunching`: aplicar a policy pela config.

### `Sources/RatTamerApp/Views/GeneralTabView.swift`
- Nova seção "Dock" (ou "Appearance") com o toggle `Menu bar only`.

## Fluxo de dados

```
Toggle (Settings/General) → onChange
  → config.menuBarOnly = valor
  → ConfigStore.save(config)
  → NSApp.setActivationPolicy(.accessory | .regular)

Launch → main.swift (sem policy) → applicationDidFinishLaunching
  → ConfigStore.load() → setActivationPolicy(menuBarOnly ? .accessory : .regular)
```

## Tratamento de erro e casos de borda

- **Config antiga sem o campo**: `decodeIfPresent` → `nil` → default `.regular`
  (ícone na Dock), preservando o comportamento atual do usuário.
- **Toggle ativado com janela de Settings aberta**: a janela permanece visível;
  o ícone some da Dock na hora. Para reverter, usuário usa a menu bar → Settings.
- **Policy não "pegar" no launch**: aplicar em `applicationDidFinishLaunching` é
  o ponto confiável documentado; o teste manual valida antes de considerar feito.

## Testes

- `swift build` e `swift test` verdes (151 testes).
- Teste unitário do decode/encode de `menuBarOnly`? O `Config` é `Codable`;
  cobertura unitária é opcional dado o padrão existente do projeto. Não criar
  teste novo para o toggle (UI + policy de runtime, sem alvo fácil).
- **Manual** (necessário — comportamento de Dock não é automatizável):
  1. Rodar o app: ícone na Dock presente por padrão.
  2. Ligar "Menu bar only": ícone some da Dock; janela de Settings segue aberta.
  3. Desligar: ícone volta.
  4. Sair e relançar com a config ativa: policy aplicada conforme a config.

## Fora de escopo

- SF Symbol da menu bar (mantido).
- `LSUIElement` no Info.plist (a policy em runtime cobre o caso; não mudar o
  bundle para não afetar o fluxo de build atual).
- Qualquer outro ícone/janela.

## Critérios de sucesso

- About mostra o ícone em 160×160.
- Toggle "Menu bar only" nas Settings General funciona e persiste entre
  execuções.
- Default: ícone na Dock visível.
- `swift build`/`swift test` verdes.

## Stack de verificação

**v1 (automatizado)**: `swift build` + `swift test`.

**v2 (manual)**: cenários 1–4 acima (Dock icon aparece/some/persiste).
