# Review: Task 2 — Iconset export, ICNS via iconutil, bundle wiring

Date: 2026-08-08
Reviewer: automated
Veredito: **aprovado**

## Escopo

Revisão de `Sources/IconGen/main.swift` e `scripts/build-app.sh` contra `docs/superpowers/sdd/2026-08-08-app-icon/task-2-brief.md`. Sem edição de código.

## Achados

### main.swift (Sources/IconGen/main.swift)

- Bloco iconset (linhas 85–119) idêntico ao brief:
  - `baseDir` de `CommandLine.arguments` com default `"build/icon"` (l. 86) ✓
  - `iconsetDir` = `baseDir/RatTamer.iconset` (l. 87) ✓
  - `removeItem` + `createDirectory` (l. 88–89) ✓
  - 10 entradas com nomes exatos `icon_16x16.png`, `icon_16x16@2x.png`, `icon_32x32.png`, `icon_32x32@2x.png`, `icon_128x128.png`, `icon_128x128@2x.png`, `icon_256x256.png`, `icon_256x256@2x.png`, `icon_512x512.png`, `icon_512x512@2x.png` (l. 98–104) ✓
  - Loop `renderIcon` + `savePNG` (l. 105–108) ✓
  - `Process` com `/usr/bin/iconutil -c icns` (l. 110–112) ✓
  - Guard `terminationStatus == 0` com `fputs` + `exit(1)` (l. 115–118) ✓
  - Print final (l. 119) ✓
- `renderIcon` (l. 3–28), `drawMouse` (l. 30–74), `NSColor(hex:)` (l. 76–83), `savePNG` (l. 91–96) intactos ✓
- Risco de compilação Swift 5.9: nenhum. APIs AppKit/Foundation padrão, sem concorrência, sem macros, sem Swift 6 language mode ✓
- `savePNG` posicionado entre criação do dir e array de sizes (l. 91–96): diferença organizacional mínima sem impacto funcional; ordem de declarações top-level irrelevante em Swift ✓

### build-app.sh (scripts/build-app.sh)

- `set -euo pipefail` preservado (l. 2) ✓
- `SCRATCH`/`RATTAMER_SCRATCH` preservado (l. 5) ✓
- `swift run IconGen` após `swift build` (l. 7) ✓
- `mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"` (l. 11) ✓
- `cp "$ROOT/build/icon/RatTamer.icns" "$APP/Contents/Resources/RatTamer.icns"` (l. 13) ✓
- `<key>CFBundleIconFile</key><string>RatTamer</string>` após `CFBundleExecutable` (l. 22) ✓
- `CODESIGN_IDENTITY` + `codesign` preservados (l. 29–30) ✓
- Sem mudanças não relacionadas ✓

### Desvio reportado (iconutil validation)

- `iconutil -c iconset ... -o /tmp/rattamer-check` (sem extensão) falha neste macOS: "The file extension must equal iconset".
- Correto: é problema do **comando de verificação**, não do código. O código usa a direção inversa (`-c icns` para criar), que funciona.
- `file` confirma: "Mac OS X icon, 362039 bytes, ic12 type" ✓
- Round-trip com `-o /tmp/rattamer-check.iconset` extrai todas as 10 entradas ✓
- ICNS válido; nenhum defeito de implementação.

### Outros

- Nenhum target/teste adicional tocado ✓
- Warnings preexistentes em `RatDiagnose/main.swift` (l. 128, 160 no log) fora de escopo ✓

## Veredito

**aprovado** — sem achados bloqueantes. Implementação segue o brief verbatim; desvio é limitado ao comando de validação e não afeta código; ICNS válido e bundle wiring correto.
