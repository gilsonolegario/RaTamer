# Ícone do app RatTamer

Data: 2026-08-08

## Objetivo

Criar o ícone de aplicativo do RatTamer (arquivo `.icns` para o bundle
`build/RatTamer.app`), gerado programaticamente em Swift/CoreGraphics — sem
ferramentas externas de design e sem Xcode assets. O ícone é usado no login item,
notificações e cmd-tab quando a janela está ativa. A menu bar mantém o SF Symbol
atual (fora de escopo, decisão do usuário).

## Contexto e achados da investigação

- O bundle atual **não tem ícone**: `build/RatTamer.app/Contents/` só tem
  `Info.plist` e `MacOS/`; sem `Resources/`, sem `CFBundleIconFile`.
- O bundle é montado por `scripts/build-app.sh` (build release + Info.plist +
  codesign). O fluxo de dev diário copia o binário debug para o bundle com `cp`.
- O projeto é SwiftPM puro (sem Xcode project/assets). Package.swift tem targets
  executáveis (`RatTamerApp`, `RatDiagnose`, `RatTest`) além do core.
- O app roda com activation policy `.accessory` (sem dock icon), mas o ícone do
  bundle ainda aparece no login item, notificações e switcher quando a janela está
  ativa.
- Decisões do usuário (brainstorming): escopo = **só ícone do app**; conceito =
  **silhueta de mouse + elemento "tamer"**; estilo = **escuro premium + acento**;
  cor do acento = **laranja/âmbar**.

## Decisões de design

1. **Novo target executável `IconGen`** (independente, não vira dependência do
   app): desenha o design com AppKit/CoreGraphics e grava os PNGs + ICNS.
   Reproduzível: rodar `swift run IconGen` regenera tudo.
2. **Desenho (1024×1024, base de todas as resoluções)**:
   - Fundo squircle em grafite com gradiente vertical sutil
     (`#23262E` → `#16181C`), canto arredondado ~22% (padrão macOS).
   - Silhueta do mouse em vista superior, prata clara (`#E8E9ED`), com sombra
     leve para profundidade: corpo alongado arredondado com asa do polegar à
     esquerda (referência MX Master 2S), botão de gesto atrás da roda e o slot
     vertical da roda no centro-dianteiro.
   - Elemento "tamer": argola âmbar (`#FF9F1C`) envolvendo a roda + ponto de
     âncora âmbar na asa do polegar.
   - Sem texto.
3. **Exportação e ICNS**: PNG 1024 → downscale para as resoluções do ICNS
   (16/32/64/128/256/512/1024 + @2x 32/64/256/512/1024) em `build/icon/`;
   `iconutil -c icns` gera `build/icon/RatTamer.icns`.
4. **Bundle**: `scripts/build-app.sh` passa a gerar o ICNS (ou garantir que ele
   existe), copiar para `Contents/Resources/RatTamer.icns` e adicionar
   `CFBundleIconFile = RatTamer` ao Info.plist.
5. **Verificação visual iterativa**: renderizar o PNG 1024 e revisar com o
   screenshot-analyzer; iterar o desenho (cores/proporções) até o look aprovado.
6. **Sem mudança no app em runtime**: nenhum código do `RatTamerApp` muda; o
   ICNS é só um recurso do bundle.

## Componentes

### Novo `Sources/IconGen/main.swift`

- `render(size:)` — desenha o ícone num bitmap context (NSBitmapImageRep) na
  resolução pedida:
  - fundo: `NSBezierPath(roundedRect:xRadius:yRadius:)` + gradiente axial;
  - corpo do mouse: path arredondado com asa do polegar (path customizado) + sombra
    (NSShadow) + brilho sutil;
  - roda: slot vertical com a argola âmbar (stroke grosso) e elo de âncora;
- grava `build/icon/icon_{size}.png` (PNG via NSBitmapImageRep) para cada tamanho;
- chama `iconutil -c icns build/icon/icon_512@2x.png …` (ou monta o diretório
  `iconset` no formato do iconutil e invoca via Process).
  - Observação: o formato do iconutil usa nomes `icon_16x16.png`, `icon_16x16@2x.png`
    etc.; o tool monta o diretório `RatTamer.iconset/` e roda
    `iconutil -c icns RatTamer.iconset`.

### `scripts/build-app.sh`

- Após `swift build`, rodar `swift run IconGen` (gera `build/icon/RatTamer.icns`).
- `mkdir -p "$APP/Contents/Resources"`; `cp` do icns para
  `Contents/Resources/RatTamer.icns`.
- Adicionar `<key>CFBundleIconFile</key><string>RatTamer</string>` ao Info.plist.

## Fluxo de dados

```
swift run IconGen
  → desenha em 1024 → downscale p/ sizes do iconset
  → iconutil -c icns → build/icon/RatTamer.icns
  → (build-app.sh) → cp para Contents/Resources + CFBundleIconFile no Info.plist
```

## Tratamento de erro e casos de borda

- **iconutil ausente** (não deveria ocorrer em macOS): o tool falha com mensagem
  clara; o build-app.sh propaga o erro.
- **Regeneração**: sempre do zero (pasta `build/icon` recriada) — sem lixo de
  versões antigas.
- **App já aberto durante build**: o dev-loop existente (pkill + cp + open) cobre;
  o ICNS novo vale na próxima abertura.
- **Design não fica bom na primeira render**: iterar o desenho no `IconGen` (é
  código — fácil de ajustar) até o screenshot-analyzer aprovar.

## Testes

- Sem test target para executável de geração (não é lógica de produto). Verificação:
  - `swift run IconGen` gera o `RatTamer.icns` sem erro;
  - `file RatTamer.icns` confirma o formato;
  - `iconutil` lê sem warnings;
  - `swift build` e `swift test` (151 testes) continuam verdes.
  - Visual: screenshot-analyzer avalia o PNG 1024 (composição, contraste, cortes).

## Fora de escopo

- Ícone da menu bar (SF Symbol `computermouse` mantido — decisão do usuário).
- Ícone na janela/About panel.
- Assets Xcode / AppIcon set.

## Critérios de sucesso

- `build/RatTamer.app` tem `Contents/Resources/RatTamer.icns` e
  `CFBundleIconFile` no Info.plist.
- O ícone aparece no login item / notificações / cmd-tab.
- Visual aprovado pelo usuário (após iteração com screenshot-analyzer).
- `swift run IconGen` e `scripts/build-app.sh` reproduzem tudo do zero.

## Stack de verificação

**v1 (automatizado)**: `swift run IconGen` gera ICNS válido; `swift build` e
`swift test` verdes.

**v2 (visual)**: render 1024 avaliado pelo screenshot-analyzer; ajustes iterados
no desenho até aprovação.

**v3 (manual)**: `scripts/build-app.sh` e abertura do app — ícone visível no
cmd-tab/login item e notificações.
