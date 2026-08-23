# Task 3 Report: Visual polish — redesigned `drawMouse(in:)`

Date: 2026-08-08
Veredito: implementado (aguardando re-review do screenshot-analyzer pelo controller)

## Files modified

- **Modified:** `Sources/IconGen/main.swift` — only `drawMouse(in:)` body/geometry drawing. `renderIcon`, `NSColor(hex:)`, the iconset/iconutil pipeline, `build-app.sh` and all other targets untouched.

## What changed (geometry + path approach)

**Path approach:** replaced the two-oval union (`appendOval` × 2) with a **single continuous `NSBezierPath`**: `move(to:)` at the nose + 5 cubic `curve(to:controlPoint1:controlPoint2:)` segments. Tangent continuity was verified numerically at all 4 junctions (direction diff 0.0° each): nose↔right flank, right↔rear, rear↔wing tip, wing↔left flank — so the wing is an **integrated bulge**, not a glued-on circle (no cusp at the tip, no corner at the flank transition).

**New constants (fractions of canvas `s`):**

| item | value |
|---|---|
| main body | cx 0.50, cy 0.50, rx 0.20, ry 0.29 → 0.40s × 0.58s |
| body h/w ratio | 0.58 / 0.40 = **1.45** (elongated; was ~1.08 with the 2-oval union) |
| full silhouette | x 0.199–0.700 = **0.501s (~50% of canvas)**; y 0.210–0.790 = 0.580s |
| wing tip | (0.20s, 0.59s), bulge on lower-left, y ≈ 0.53–0.71 of body |
| bezier ellipse factor | kx = 0.20×0.5523, ky = 0.29×0.5523 |

**Elements recomputed to sit inside the new contour** (verified against ellipse half-width at each y):
- Wheel slot: x 0.465–0.535, y 0.28–0.52 (upper-front center) — amber ring stroke (margin 0.008, radius 0.012, width 0.012) same style as before; no fill (per plan).
- Gesture button: x 0.405–0.595, y 0.535–0.625, radius 0.03 (#C9CBD1), behind/below the wheel.
- Anchor dot: (0.224–0.246, 0.604–0.626), diameter 0.022, amber, on the wing bulge.

Also: composition re-centered (cy 0.52 → 0.50) to fix the "slightly above center" finding. Shadow kept (blur 0.05s, offset −0.03s, alpha 0.45). All elements ≥0.07s from the squircle boundary — no clipping.

## Exact command output

### `swift run IconGen`

```
[0/1] Planning build
Building for debugging...
[0/4] Write sources
[1/4] Write swift-version--58304C5D6DBC2206.txt
[3/6] Emitting module IconGen
[4/6] Compiling IconGen main.swift
[4/7] Write Objects.LinkFileList
[5/7] Linking IconGen
[6/7] Applying IconGen
Build of product 'IconGen' complete! (0.80s)
wrote /Users/issoeocio/Documents/Projetos/RaTamer/build/icon/RatTamer.icns
```

`swift test` not run per instructions; no other targets/files touched.

## Interpretation note (deviation from literal wording)

The brief asks for "body width/height ratio ~1.3–1.5:1". Read literally (wider than tall), that contradicts the fixed orientation cues the same brief gives — wheel slot vertical in **upper-front** center and thumb wing on the **lower-left** imply a nose-up mouse, which must be *taller* than wide. The analyzer's complaint was the body reading ~1:1 (main oval 0.46×0.496). I implemented the elongated axis vertically: main body **h/w = 1.45**, and silhouette aspect 0.86:1 — unambiguous mouse silhouette while keeping every layout cue. Flagging so the controller can redirect if a horizontal orientation was actually intended.

## Uncertainties for the analyzer pass

1. Wing protrusion (0.20s left edge) may read as aggressive or too subtle at 1024 — easy to tweak via the two wing control points.
2. Gesture button enlarged to 0.19s wide (was ~0.10s) for dock legibility — check it doesn't read as a second "button" blob.
3. Wheel slot has no fill (amber ring only, per plan) — at dock sizes the ring alone may be all that reads; a subtle dark recess could be added in a later iteration if the analyzer judges it necessary.
4. Whether the amber ring alone reads as "wheel" vs "ring around nothing".

---

## Addendum (iteration: convex wing return, no concave pinch)

**Issue:** vision-model analysis of the 1024 render saw a concave "pinch" at ~22% canvas width / ~50% height where the thumb wing returns to the body — the second wing curve (tip → left flank) had an inflection (S-curve): its control polygon straddled the tip→flank chord (cross products +0.001 for cp2 vs −0.0069 for cp1), folding the edge inward instead of arcing convexly.

**Fix (only the two wing curves in `drawMouse(in:)`; nothing else moved/flipped):**

```swift
body.curve(to: NSPoint(x: s * 0.20, y: s * 0.59),
           controlPoint1: NSPoint(x: s * 0.44, y: bottom),
           controlPoint2: NSPoint(x: s * 0.185, y: s * 0.70))
body.curve(to: NSPoint(x: left, y: cy),
           controlPoint1: NSPoint(x: s * 0.17, y: s * 0.56),
           controlPoint2: NSPoint(x: s * 0.27, y: s * 0.52))
```

- Curva 1 (rear → tip): cp1 0.42→0.44 (y = bottom mantém junção traseira tangente-contínua), cp2 0.22→0.185 — tangente na ponta em −82°, canto de ~53° com a saída da curva 2 (−135°) → ponta agora pontiaguda (antes: colinear, ponta arredondada).
- Curva 2 (tip → flank): cp1 0.19→0.17, cp2 0.30→0.27 — todos os controles do mesmo lado da corda tip→flank (cross −0.0057 / −0.0007, ambos negativos) → sem inflecção, retorno convexo para fora, sem entalhe em (0.22s, 0.50s). Ponta mantida em (0.20, 0.59), flanco em (0.30, 0.50).
- Nota: tangente contínua de 90° no flanco é incompatível com a convexidade (cp2.x = 0.30 obrigatoriamente recria a inflecção); o cotovelo de ~56° no flanco é o mínimo prático sob convexidade (ótimo teórico ~48°), amortecido pela sombra.
- Ancoragem dot (0.224–0.246) permanece bem dentro do contorno novo (contorno ≈ 0.203s na altura do dot).

**Verificação:** `swift run IconGen` — build OK, `wrote .../build/icon/RatTamer.icns`. Convexidade verificada numericamente (sem ponto de inflecção nas duas curvas; pontos amostrados à esquerda da corda). Re-review visual do screenshot-analyzer fica a cargo do controller.

## Addendum (controller): orientation flip + layout fix

- **Root cause found via pixel forensics**: `NSGraphicsContext(bitmapImageRep:)` is y-up (origin bottom-left); the PNG output is top-down. Drawing with "nose at low y" rendered the mouse UPSIDE DOWN in the final image (nose at bottom, wheel bottom, gesture button above and overlapping the ring's top). The screenshot-analyzer's repeated "inverted" flags were correct.
- **Fix in `Sources/IconGen/main.swift`** (applied directly by controller):
  - In `renderIcon`, wrap `drawMouse(in: canvas)` with an `NSAffineTransform` y-flip (`translateX(by: 0, yBy: size)`, `scaleX(by: 1, yBy: -1)`), so low-y geometry (nose) appears at the image top.
  - Moved gesture button y `0.535 → 0.565` and wheel slot `slotY 0.28 → 0.30`, `slotH 0.24 → 0.22`, so the button sits clearly below the ring (no overlap).
- **Verified objectively**: amber ring bbox y 293–557 (upper-center), gray button at row 625 (below ring, no overlap), nose silver at row 215 (top), amber dot on wing at cols 230–252 / rows 618–641 (left). screenshot-analyzer: all 6 criteria passed, no issues.
- `swift test`: 151 tests, 0 failures. `scripts/build-app.sh`: ok; bundle has Resources/RatTamer.icns (366458 B) + CFBundleIconFile; app relaunched (PID 65812).
