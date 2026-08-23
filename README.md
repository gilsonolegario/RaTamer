<img src="screenshots/icone.png" alt="App icon" width="128">

# RatTamer

A native macOS menu bar app that replaces Logitech Options+ for the MX Master 3 and MX Master 2S — tested on those models and designed to adapt to other HID++ Logitech devices (MX Master 3S, MX Anywhere, MX Vertical). It captures the mouse buttons over HID++ 2.0 and runs your own shortcut, system action or click for each one — no Logitech software required, native behavior restored on quit.

![Swift](https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift&logoColor=white&style=flat)
![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat)
![Universal](https://img.shields.io/badge/arch-arm64%20%2B%20x86__64-blueviolet?style=flat)
![License](https://img.shields.io/badge/license-MIT-green?style=flat)
![Version](https://img.shields.io/badge/version-1.0.2-FF9F1C?style=flat)

[![Settings — About tab](screenshots/settings-about.png)](screenshots/settings-about.png)

## Download

Grab the latest pre-built app from the [Releases page](https://github.com/gilsonolegario/RaTamer/releases) — or build it locally:

```bash
./scripts/build-app.sh    # universal binary (arm64 + x86_64) → build/RatTamer.app
```

or run straight from the source tree:

```bash
swift run RatTamer        # development mode, no app bundle
```

Releases are published with `./scripts/release.sh [VERSION] [draft]` — it builds the bundle, zips it and uploads it to the GitHub Release via `gh`. See [First launch (macOS 15+)](#first-launch-macos-15) for how to open the pre-built download the first time.

## First launch (macOS 15+)

The release download is **not notarized** — notarization requires a paid Apple
Developer account — so macOS blocks the first launch. Since macOS 15 (Sequoia)
the old right-click → Open bypass is **gone**, so use this flow instead:

1. Double-click `RatTamer.app` → the dialog says it can't be opened → click **Done**.
2. Open **System Settings → Privacy & Security → Security** (scroll to the bottom).
3. Under "Allow applications from", find *"RatTamer was blocked to protect your Mac"* → click **Open Anyway** → confirm with your password.
4. Launch RatTamer normally from now on.

> **Tip:** `Open Anyway` only appears for ~1 hour after the blocked launch. If you don't see it, double-click the app once more and go straight back to System Settings.
>
> **Troubleshooting:** if macOS claims the app is "damaged", remove the quarantine attribute once:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/RatTamer.app
> ```

**Prefer to skip all of this?** Build locally — a `swift build` output never receives the quarantine attribute, so Gatekeeper stays out of the way (requires only the Xcode Command Line Tools).

## Major features

- **Menu bar popover** with connection status, battery level, pointer resolution and a remapping toggle.
- **Button remapping** — per-button actions: keyboard shortcuts, system actions, clicks, gestures.
- **DPI cycling** — assign "Cycle DPI" to a button; steps through 1000 / 1600 / 2000 / 4000.
- **Left/right swap** — remaps the physical buttons; native mapping restored on quit.
- **Thumb wheel** — left/right horizontal scroll, each side with its own action.
- **SmartShift** — ratchet / free-spin / auto wheel mode plus sensitivity.
- **Gestures** — raw XY movement classified into directions by the gesture detector.
- **Dock icon** — show in the Dock or run menu bar only (Settings → General).
- **About** — app icon and version in the Settings About tab.
- **Completely free**, native SwiftUI, no daemons, no telemetry.

## Smooth scrolling

Trackpad-style vertical smooth scrolling for Logitech wheels. It reads hi-res wheel
deltas over HID++ and re-emits them as continuous pixel scroll events. A Smoothness
slider (0–100) lives in Settings → General with nine presets — Native (0), Smooth
(35), Glide (60), Mos (80), Soft (84), RaT (87, default), Warm (89), Flow (90) and
Fluid (100). Settings → **Advanced** adds full tuning of the momentum, glide, feed
and bounce parameters — all free.

> Do not run RatTamer together with Logitech Options+, BetterMouse or similar mouse-config tools: they reprogram the same HID++ features and will fight over wheel mode.

### Tuning

Run `swift run RatTest` for a live tuning panel with all smooth-scroll parameters (maxBoost, momentumDecay, pixelsPerNotch). Twist the wheel in ratcheted mode and the response updates instantly.

### Screenshots

[![Settings — Buttons tab](screenshots/settings-buttons.png)](screenshots/settings-buttons.png)

[![Menu bar popover](screenshots/menu-bar.png)](screenshots/menu-bar.png)

## How to install and use the app

1. Build the app: `./scripts/build-app.sh` (or `swift run RatTamer` for development).
2. Copy `build/RatTamer.app` to your Applications folder.
3. Open RatTamer — the first run shows a short onboarding. If macOS blocks it, follow [First launch (macOS 15+)](#first-launch-macos-15).
4. Grant **Accessibility** in System Settings → Privacy & Security as prompted (required to post shortcuts and clicks).
5. Click the mouse icon in the menu bar to open the popover: connection status, battery, pointer resolution and a remapping toggle.
6. Open **Settings…** to configure buttons, thumb wheel, SmartShift, DPI presets, login item and the Dock icon option.
7. To start at login, toggle "Start at login" in Settings → General or in the popover.

### macOS compatibility

| Version | Notes |
|---|---|
| macOS 14+ (Sonoma) | supported |
| macOS 15 (Sequoia) | tested on 15.7.8, Apple Silicon |

| Device | Notes |
|---|---|
| MX Master 3 | fully tested |
| MX Master 2S | fully tested |
| MX Master 3S, MX Anywhere, MX Vertical | supported by feature detection, not tested on hardware |

> **Note:** On macOS, some Logitech mice (e.g. MX Master 3, MX Vertical, MX Keys Mini) do not expose the HID++ interface over Bluetooth. For full support, connect via the Unifying/Bolt receiver.

## Configuration

In the **Buttons** tab every divertable button gets an action: Disabled (native), shortcuts (e.g. Cmd+W), system actions (Volume, Mission Control, Show Desktop, Spaces), clicks (Forward/Back), gestures or DPI cycling. The thumb wheel has separate left/right actions, and the SmartShift wheel mode (ratchet, free-spin, auto + sensitivity) is set in the same tab.

The configuration is stored in `~/Library/Application Support/RatTamer/config.json` and applied on connect.

## Pricing

RatTamer is free and always will be. Every feature is included — button remapping,
gestures, SmartShift, Run Shortcut, thumb wheel, DPI cycling, smooth scrolling with
full advanced tuning. No license keys, no accounts, no telemetry.

## Documentation

- **How the app works, the config schema, developer tools and build details** — [docs/TECHNICAL.md](docs/TECHNICAL.md)
- **The HID++ protocol, byte by byte** — [docs/HIDPP.md](docs/HIDPP.md)

## History

**1.0.2** — Native smoothness control: a standard slider plus a compact preset menu
replaces the tick bar and chip grid; remaining Portuguese UI strings translated to
English; universal binary (Apple Silicon + Intel); updated screenshots.

**1.0.1** — HID++ hardening: FIFO report mailbox with exclusive request ownership,
covered by concurrency tests.

**1.0.0** — First stable release; RatTest live tuning panel, complete button action
catalog, glide convergence fixes.

**0.9.0** — Initial public beta: About tab with app icon and version; menu bar
popover with status, battery, pointer resolution and a remapping toggle; option to
hide the Dock icon (menu bar only); DPI cycling (1000/1600/2000/4000); button
remapping with left/right swap; thumb wheel actions; SmartShift wheel mode control;
gestures.

## License

RatTamer is released under the [MIT License](LICENSE).

---

Built with [opencode](https://opencode.ai) — the open-source AI coding agent.
