# Advanced Settings Tab — Design

**Date:** 2026-08-09
**Status:** Approved

## Problem

The smooth scroll tuning panel (15 advanced parameters + Glide/MOS presets) lives
inside a `DisclosureGroup("Avançado")` in the **General** settings tab. The settings
window is fixed at 760×560 and the expanded panel gets cut off — the top of the panel
and its group headers are not visible without resizing/scrolling the whole window.
Users cannot comfortably reach all controls.

## Goal

Move the advanced smooth scroll tuning into a dedicated **Advanced** settings tab.
Restructure the free/Pro boundary: **basic smooth scrolling becomes free** (toggle +
Smoothness slider + Discreta/Média/Fluida presets stay in General), while the **tuning
panel (15 params + Glide/MOS presets) becomes Pro-only** and lives in the new tab.

## Non-Goals

- No new tuning features (params, ranges, presets stay as-is).
- No changes to the smoother engine or config schema (fields already exist).
- No changes to the RatTest tool.

## Current State

- `Sources/RatTamerApp/SettingsView.swift` — `NavigationSplitView` with sidebar:
  General, Buttons, Pro, About. Detail switches on selection. Window sized in
  `SettingsWindow.swift` (760×560, min 680×460).
- `Sources/RatTamerApp/Views/GeneralTabView.swift` — `SmoothScrollRow` holds the
  toggle, level slider, presets, Glide/MOS buttons and the `DisclosureGroup("Avançado")`
  with the 15 tuning params.
- `Sources/RatTamerCore/Core/ConfigEntitlement.swift` — `filteringProFeatures` strips
  the *entire* smooth scroll (enabled + level + advanced) when not entitled.
- `Sources/RatTamerApp/AppModel.swift:40` — `isPro` returns `true` in dev builds
  (TEMP-DEV), so the new tab is unlocked for local testing.

## Design

### 1. Sidebar — `SettingsView.swift`

Add a new entry between **Buttons** and **Pro**:

```swift
Label("Advanced", systemImage: "slider.horizontal.3").tag("Advanced")
```

Always visible (locked for free users inside the tab, not hidden).

### 2. General tab — `GeneralTabView.swift`

`SmoothScrollRow` becomes the **free** tier:

- Remove the Pro gate on the "Smooth scrolling" toggle (`onChange` no longer checks
  `isPro(.smoothScroll)` / shows the upsell alert).
- Remove the `Glide / MOS` button row and the `DisclosureGroup("Avançado")` +
  `advancedPanel`.
- Keep: toggle "Smooth scrolling", the Smoothness slider with the level/custom
  label, and the Discreta/Média/Fluida preset labels.
- Keep `level` as `Double?` so a customized advanced config still shows "custom".

### 3. New tab — `Sources/RatTamerApp/Views/AdvancedTabView.swift`

New view gated by `isPro(.smoothScroll)`:

- **Not entitled:** lock icon + "Advanced tuning is a Pro feature." + "Get RatTamer
  Pro" button (reuses the `ButtonsTabView` upsell pattern — `proGate`, `lockIcon`,
  `showProAlert`, `ProStore.productURL`).
- **Entitled:** the tuning panel:
  - `Toggle("Smooth scrolling")` at the top, mirroring General. When off, all tuning
    controls render `.disabled(true)`.
  - Smoothness level slider + label (number or "custom") and the five presets:
    Discreta, Média, Fluida, **Glide**, Mos-like. (Renames the "Glide sã" typo to
    "Glide".)
  - The four parameter groups (Momentum, Glide, Feed, Bounce) plus Direção, with the
    same 15 controls and ranges already in the current `advancedPanel`.
  - Whole panel inside a `ScrollView` so it fits the 760×560 window without clipping
    (same pattern as `ButtonsTabView`).

State and config interaction (unchanged semantics, just relocated):

- Moving any tuning control → `level = nil` ("custom") → save
  `config.smoothScrollAdvanced` and apply live via
  `AppModel.shared.engine?.updateSmoothParameters(...)`.
- Choosing a level preset → params reset to `SmoothnessLevel.parameters(...)` for that
  level and `config.smoothScrollAdvanced` is cleared.
- `load()` reads `config.smoothScrollAdvanced ?? parameters(level ?? default)` so
  General and Advanced stay consistent across tab switches (detail view is recreated
  on selection change, so `onAppear` reloads state).

### 4. Entitlement — `ConfigEntitlement.swift`

Free tier keeps basic smooth scrolling; only tuning is Pro:

```swift
if !entitled(.smoothScroll) {
    filtered.smoothScrollEnabled = nil
    filtered.smoothScrollLevel = nil
    filtered.smoothScrollAdvanced = nil
}
```

becomes

```swift
if !entitled(.smoothScroll) {
    filtered.smoothScrollAdvanced = nil
}
```

### 5. Docs — `README.md`

Update the "Smooth scrolling" section and Pricing:

- Basic smooth scrolling (toggle + level slider + Discreta/Média/Fluida) is free.
- Advanced tuning (15 params, Glide/MOS presets) is a Pro feature.

## Open Questions / Edge Cases

- If a Pro user customizes params and the license later expires, `smoothScrollAdvanced`
  is stripped at load/apply and behavior falls back to the saved level. Accepted —
  no additional handling.
- RatTest stays as the developer tuning tool; no sync with the new tab required.

## Testing

- Build + full test suite pass.
- Manual: free license → Advanced tab shows upsell, General has free scroll controls.
- Manual: dev build (`isPro == true`) → Advanced tab shows full panel, toggle works,
  tuning sets "custom" in General, level presets reset the panel.
- Manual: settings window at 760×560 shows the whole Advanced panel via scroll.
