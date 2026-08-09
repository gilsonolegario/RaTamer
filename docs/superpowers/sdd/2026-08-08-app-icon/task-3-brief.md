### Task 3: Visual polish iteration

**Files:**
- Modify: `Sources/IconGen/main.swift` (only `drawMouse`/`drawIcon` drawing code)

**Interfaces:**
- Consumes: the render pipeline from Tasks 1–2.
- Produces: a final icon approved by the user; ICNS regenerated via Task 2 steps.

- [ ] **Step 1: Render the current master**

Run: `swift run IconGen`
Expected: regenerates `build/icon/RatTamer.icns`.

- [ ] **Step 2: Review the 1024 PNG with the screenshot-analyzer**

Dispatch `screenshot-analyzer` on `build/icon/icon_512x512@2x.png` (the 1024 master) with the spec description: graphite squircle, silver MX Master-style mouse top view with left thumb wing, amber ring around the wheel, no text.

Expected: a textual read of the composition (silhouette readable, elements centered, contrast adequate).

- [ ] **Step 3: Fix issues found**

Based on the analyzer's read, adjust in `drawMouse(in:)`:
- body proportions / wing placement (letters `x`, `y`, `w`, `h`, `r`),
- amber ring (add stroke around the wheel slot if not present yet),
- shadow blur/offset.

Re-run `swift run IconGen` and repeat Steps 2–3 until the icon is clean.

- [ ] **Step 4: Final verification**

Run: `swift build && swift test`
Expected: `swift test` reports 151 tests, 0 failures.

Run: `pkill -f "build/RatTamer.app/Contents/MacOS/RatTamer" || true; scripts/build-app.sh`
Expected: app rebuilt with the final icon.

Open the app and confirm the icon appears (cmd-tab when the Settings window is active / login item).
