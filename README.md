# RatTamer

A native macOS menu bar app that replaces Logitech Options+ for the MX Master 2S. It talks to the mouse over HID++ 2.0, captures its buttons, and runs the configured shortcut, system action or click for each one — no Logitech software required, native behavior restored on quit.

![App icon](screenshots/icone.png)

![Settings — About tab](screenshots/settings-about.png)

![Swift](https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift&logoColor=white&style=flat)
![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat)

## Features

| Feature | What it does |
|---|---|
| Menu bar | popover with connection status, battery level and a remapping toggle |
| DPI cycling | assign "Cycle DPI" to a button; steps through 1000 / 1600 / 2000 / 4000 |
| Button remapping | per-button actions: shortcuts, system actions, clicks, gestures |
| Left/right swap | remaps the physical buttons; native mapping restored on quit |
| Thumb wheel | left/right horizontal scroll, each side with its own action |
| SmartShift | ratchet / free-spin / auto wheel mode plus sensitivity |
| Gestures | raw XY movement classified into directions by the gesture detector |

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

- **Connection**: walks the kernel registry with `IOServiceGetMatchingServices` + `IOHIDDeviceCreate` (`IOHIDManager` never enumerates this receiver on macOS 15/arm64).
- **Discovery**: resolves the `0x1B04` (`ReprogrammableControls`) feature index at runtime — it varies between sessions.
- **Divert**: the divertable controls (Back, Forward, Thumb/Gesture, SmartShift, VirtualGesture) stop running their native action and emit PRESS/RELEASE events to the app.
- **Action**: on press, the app runs the configured action for that control (keyboard shortcut, system action, click, gesture, DPI cycle). Left, Right and Middle are not divertable and stay native.
- **Restoration**: on quit, all diverts are reverted and every button returns to native behavior.

The codebase is split into three layers — **HIDPP** (talks to the receiver), **Core** (remapping logic + persistence) and **App** (SwiftUI shell). The byte-level protocol details live in [docs/HIDPP.md](docs/HIDPP.md).

## Configuration

In the **Buttons** tab every divertable button gets an action: Disabled (native), shortcuts (e.g. Cmd+W), system actions (Volume, Mission Control, Show Desktop, Spaces), clicks (Forward/Back), gestures or DPI cycling. The thumb wheel has separate left/right actions, and the SmartShift wheel mode (ratchet, free-spin, auto + sensitivity) is set in the same tab.

The configuration is stored in `~/Library/Application Support/RatTamer/config.json` (schema v2) and applied on connect.

## Developer tools

**RatTest** — identifies buttons. It diverts all controls and shows, in real time, which row corresponds to each physical button as you press it. You can also change a button's action and run it ("Run") without leaving the window.

```bash
swift run RatTest
```

Close `RatTamer` first — only one process can receive the divert events.

**RatDiagnose** — inspects the protocol:

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

## History

**0.9.0** — About tab with app icon and version; menu bar popover with status and battery; DPI cycling (1000/1600/2000/4000); button remapping with left/right swap; thumb wheel actions; SmartShift wheel mode control; gestures; HID++ protocol documentation and distribution notes; screenshots.
