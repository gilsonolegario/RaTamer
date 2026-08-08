# RatTamer

A native macOS menu bar app that replaces Logitech Options+ for the MX Master 2S. It reads the mouse over the HID++ 2.0 protocol, captures its buttons, and runs the configured shortcut, system action or click for each one — no Logitech software required, native behavior restored on quit.

![Settings — About tab](screenshots/settings-about.png)

![Swift](https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift&logoColor=white&style=flat)
![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat)

## Features

| Feature | What it does |
|---|---|
| Menu bar | popover with connection status, battery level (HID++ feature `0x1000`) and a remapping toggle |
| DPI cycling | assign "Cycle DPI" to a button; steps through 1000 / 1600 / 2000 / 4000 via `0x2201` |
| Button remapping | per-button actions: shortcuts, system actions, clicks, gestures |
| Left/right swap | remaps `0x0050`/`0x0051` through `set_cid_reporting`; native mapping restored on quit |
| Thumb wheel | left/right horizontal scroll, each side with its own action |
| SmartShift | ratchet / free-spin / auto wheel mode plus sensitivity via `0x2110` |
| Gestures | raw XY from `0x1B04` classified into directions by the gesture detector |
| About tab | app icon and version 0.9.0 |

## Screenshots

![Settings — Buttons tab](screenshots/settings-buttons.png)

![Menu bar popover](screenshots/menu-bar.png)

## Requirements

- macOS 14+ (tested on macOS 15.7.8, Apple Silicon)
- Xcode Command Line Tools (`xcode-select --install`)
- MX Master 2S paired via a Unifying receiver (or direct USB)
- Logitech Options/Options+ uninstalled or stopped (it monopolizes the receiver and blocks notification reads)

## Permissions

The first run only asks for one thing, in System Settings → Privacy & Security:

- **Accessibility** — to post synthetic events (shortcuts and clicks) via `CGEvent`

Input Monitoring is **not** required: reading the Unifying receiver via `IOHIDDevice` works without it, even as a regular user.

## Quick start

```bash
swift run RatTamer        # development mode (no app bundle)
./scripts/build-app.sh    # app bundle at build/RatTamer.app
```

The bundle is only needed for "Start at login" (via `SMAppService`).

## How it works

- **Connection**: `IOServiceGetMatchingServices` + `IOHIDDeviceCreate` (`IOHIDManager` never enumerates this receiver on macOS 15/arm64).
- **Discovery**: the app resolves the `0x1B04` (`ReprogrammableControls`) feature index at runtime — it varies between sessions. The first HID++ response after opening the receiver can take more than 0.5s on a cold connection, so discovery retries 3 times.
- **Divert**: the divertable controls (Back, Forward, Thumb/Gesture, SmartShift, VirtualGesture) are "diverted": they stop running their native action and emit PRESS/RELEASE events to the app.
- **Action**: on press, the app runs the configured action for that control (keyboard shortcut, system action such as Mission Control / Show Desktop / volume, extra click, gesture, DPI cycle). Left, Right and Middle are not divertable and stay native.
- **Swap Left & Right**: a paired toggle remaps the physical Left (`0x0050`) and Right (`0x0051`) buttons via the HID++ `set_cid_reporting` remap field, restoring the native mapping on exit.
- **Restoration**: on quit, all diverts are reverted and every button returns to native behavior.

The byte-level details — framing, feature discovery, event formats, hardware gotchas — are in [Advanced: the HID++ protocol](#advanced-the-hidpp-protocol).

### Architecture

The codebase is split into three layers — HIDPP, Core and App — so the HID++ protocol details stay isolated from the remapping logic and the SwiftUI shell:

```text
HIDPP layer                                        Core layer                            App layer
────────────                                      ──────────                            ─────────
HIDDevice (protocol)                 ┌───────────  ConfigStore ──────→  Config/ButtonAction
HIDPPSession ─────────┐              │             (persistence, no HIDPP)
ReprogrammableControls ──┼─ feed ────┴──► DivertedButtonMonitor ──► onControlPressed/Released/RawXY
  .parseDivertedEvent  │                                                        │
  .parseRawXYEvent     │                                                        ▼
Protocol.HIDPP (bytes) │                                        EngineController.handlePress
                       │                                                        │
                       │                                        ActionEngine.execute(ButtonAction)
                       │                                                        │
                       │                                        GestureDetector ──► GestureMath
                       └── setDiverted/setRemapped                          (direction classification)
                            (divert flags for 0x1B04 feature)
```

- **HIDPP layer** (`RatTamerCore`): talks to the receiver via IOKit. `HIDPPSession` owns the device, `ReprogrammableControls` parses the diverted PRESS/RELEASE events and the raw XY gesture data, and `Protocol.HIDPP` handles the byte-level encoding. `setDiverted`/`setRemapped` configure the `0x1B04` feature flags.
- **Core layer** (`RatTamerCore`): `DivertedButtonMonitor` receives the feed and emits `onControlPressed`/`onControlReleased`/`RawXY` events. `ConfigStore` persists the configuration without touching HIDPP, and `GestureDetector`/`GestureMath` classify the gesture direction.
- **App layer** (`RatTamerApp`): `EngineController.handlePress` forwards each press to `ActionEngine.execute(ButtonAction)`, which runs the configured shortcut, system action or click.

## Configuration

In the **Buttons** tab every divertable button gets an action: Disabled (native), shortcuts (e.g. Cmd+W), system actions (Volume, Mission Control, Show Desktop, Spaces), clicks (Forward/Back), gestures or DPI cycling. The thumb wheel has separate left/right actions, and the SmartShift wheel mode (ratchet, free-spin, auto + sensitivity) is set in the same tab.

The configuration is stored in `~/Library/Application Support/RatTamer/config.json` (schema v2) and applied on connect.

## Identifying buttons: RatTest

The `RatTest` micro-app diverts all controls and shows, in real time, which row corresponds to each physical button as you press it — the footer shows "Pressed: `<name>` (cid)". You can also change a button's action and run it ("Run") without leaving the window.

```bash
swift run RatTest
```

Close `RatTamer` first — only one process can receive the divert events.

## Diagnostics

```bash
swift run RatDiagnose                 # lists features and the controls (cid/tid/divertable table)
swift run RatDiagnose --divert 10     # diverts everything for 10s and prints PRESS/RELEASE per button
```

## Distribution

The app is **not notarized** — notarization requires a paid Apple Developer account — so macOS may block a downloaded copy. Two free paths work around that:

1. **Local build (recommended).** Clone the repo and run `./scripts/build-app.sh`; you get `build/RatTamer.app` and "Start at login" works via `SMAppService`. Files built locally never receive the `com.apple.quarantine` attribute, so Gatekeeper stays out of the way. Requires only the Xcode Command Line Tools (already a build requirement).
2. **GitHub Release (convenience).** The app is ad-hoc signed (`codesign -s -`, no identity) and published as a zip. A browser download sets the quarantine attribute, so remove it once:

   ```bash
   xattr -dr com.apple.quarantine RatTamer.app
   ```

   or right-click → Open → Open Anyway in Gatekeeper.

## Advanced: the HID++ protocol

RatTamer talks to the MX Master 2S through the Unifying receiver using HID++ 2.0 — the same protocol Logitech's own software speaks. Everything below is implemented in `Sources/RatTamerCore/HIDPP/`.

### Framing

Two report sizes:

- **Short** — report ID `0x10`, 7 bytes.
- **Long** — report ID `0x11`, 20 bytes.

The body, after the report ID:

```text
[deviceIndex, featureIndex, (functionID << 4) | softwareID, params …]
```

### Feature discovery

The feature index is **not stable across sessions** — observed at `0x0E`/`0x0F` in the read-only era and `0x0A` once divert was in use. It is learned at runtime via `getFeatureIndex(featureID:)`: the Root feature (`0x0000`, function `0x00` = `getFeature`) is called with `[hi, lo, 0x00]`; the response carries the index in `resp[4]`, and index 0 means the feature is absent.

### Reprogrammable controls (0x1B04)

The MX Master 2S exposes 8 controls, read with `getControlInfo` (9-byte rows):

| CID | Control |
|---|---|
| `0x0050` | Left |
| `0x0051` | Right |
| `0x0052` | Middle |
| `0x0053` | Back |
| `0x0056` | Forward |
| `0x00C3` | Thumb/Gesture |
| `0x00C4` | SmartShift (taskID `0x009D`, divertable) |
| `0x00D7` | VirtualGesture |

### Feature functions

Function IDs are nibbles in code; the wire byte is `nibble << 4`:

| Nibble | Function | Notes |
|---|---|---|
| `0x00` | `getCount` | |
| `0x01` | `getControlInfo` | params `[index]` |
| `0x02` | `getCidReporting` | |
| `0x03` | `setCidReporting` | params `[cid_hi, cid_lo, flags, remap_hi, remap_lo]` |

### Reporting flags

`setDiverted`/`setRemapped` build the flags byte: divert `0x01`, divert-valid `0x02`, rawXY `0x10`, rawXY-valid `0x20`.

### Diverted event

A **state report** on a long frame:

```text
11 <dev> <feat> 00 <cid × 4>
```

It lists the currently pressed divertable CIDs — up to 4 slots, big-endian; all zeros means nothing is pressed. Pressing SmartShift puts `0x00C4` in a slot; releasing it clears the slot.

### Raw XY event

```text
11 <dev> <feat> 10 <dx_hi> <dx_lo> <dy_hi> <dy_lo>
```

Signed big-endian Int16 deltas; positive dy = down (HID convention).

### Response matching

`request` accepts a report only when `resp[1] == device`, `resp[2] == feature`, `resp[3] >> 4 == functionID` and the softwareID nibble matches (own or 0).

### Gotchas found on hardware

- `IOHIDManager` **never enumerates** the Unifying receiver on macOS 15/arm64. `HIDLocator` walks the kernel registry with `IOServiceGetMatchingServices` + `IOHIDDeviceCreate` instead — and that works as a regular user, with no TCC permission.
- The receiver exposes 3 interfaces: D1 = HID++ (usage `0xFF00`/1,2,4), D2 = mouse HID, D3 = keyboard. Only D1 matters.
- Writes go out only as `kIOHIDReportTypeOutput` — `kIOHIDReportTypeFeature` STALLS. Long reports need the full 20-byte buffer (the `0xE0005000` stall was a buffer-length bug, not a macOS limitation).
- **Cold-start RF**: the first response after opening the receiver can take > 0.5s (0.85s measured; ~15ms warm) — `getFeatureIndex` retries 3 × 0.5s.
- Diverting SmartShift suppresses the native ratchet/free-spin toggle.

### Data flow

The pipeline is exactly the architecture above, reading bottom-up: the **HIDPP layer** turns raw receiver bytes into `onControlPressed`/`onControlReleased`/`RawXY` events; the **Core layer** (`DivertedButtonMonitor`, `GestureDetector`/`GestureMath`, `ConfigStore`) classifies and maps them to button actions; the **App layer** (`EngineController.handlePress` → `ActionEngine.execute`) performs the configured action — `HIDPP → Core → App`.

```text
HIDPP layer                                        Core layer                            App layer
────────────                                      ──────────                            ─────────
HIDDevice (protocol)                 ┌───────────  ConfigStore ──────→  Config/ButtonAction
HIDPPSession ─────────┐              │             (persistence, no HIDPP)
ReprogrammableControls ──┼─ feed ────┴──► DivertedButtonMonitor ──► onControlPressed/Released/RawXY
  .parseDivertedEvent  │                                                        │
  .parseRawXYEvent     │                                                        ▼
Protocol.HIDPP (bytes) │                                        EngineController.handlePress
                       │                                                        │
                       │                                        ActionEngine.execute(ButtonAction)
                       │                                                        │
                       │                                        GestureDetector ──► GestureMath
                       └── setDiverted/setRemapped                          (direction classification)
                            (divert flags for 0x1B04 feature)
```

## History

The Python scripts from the original proof-of-concept (`hidpp.py`, `discover.py`, `daemon.py`, `com.mxremap.daemon.plist`) were removed from the repository — they were a historical reverse-engineering reference and are no longer used. The native app does not use them.

**0.9.0** — About tab with app icon and version; menu bar popover with status and battery; DPI cycling (1000/1600/2000/4000); button remapping with left/right swap; thumb wheel actions; SmartShift wheel mode control; gestures; this README's HID++ documentation and distribution notes; screenshots.
