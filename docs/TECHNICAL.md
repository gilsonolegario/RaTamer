# RaTamer — Technical details

Developer-oriented notes: how the app works internally, the configuration schema, the developer tools and the build/distribution specifics. The byte-level HID++ protocol lives in [docs/HIDPP.md](docs/HIDPP.md).

## Architecture

Three layers, in `Sources/`:

| Layer | Path | Responsibility |
|---|---|---|
| **HIDPP** | `RaTamerCore/HIDPP/` | talks to the Unifying receiver: framing, feature discovery, `ReprogrammableControls`, DPI, battery, HiRes wheel, SmartShift |
| **Core** | `RaTamerCore/Core/` | remapping logic, gesture classification, throttling, watchdog, config persistence |
| **App** | `RaTamerApp/` | SwiftUI shell: menu bar popover, settings window, onboarding, engine controller |

The data flow is `HIDPP → Core → App` — see the diagram at the end of [docs/HIDPP.md](docs/HIDPP.md).

## Runtime behavior

- **Connection** — `HIDLocator` walks the kernel registry with `IOServiceGetMatchingServices` + `IOHIDDeviceCreate`; `IOHIDManager` never enumerates this receiver on macOS 15/arm64. No TCC permission needed.
- **Discovery** — the `0x1B04` (`ReprogrammableControls`) feature index is resolved at runtime; it varies between sessions.
- **Divert** — divertable controls (Back, Forward, Thumb/Gesture, SmartShift, VirtualGesture) stop running their native action and emit PRESS/RELEASE events to the app. Left, Right and Middle are not divertable and stay native.
- **Action** — on press, `EngineController.handlePress` → `ActionEngine.execute(ButtonAction)` performs the configured action.
- **Restoration** — on quit, all diverts are reverted and every button returns to native behavior.

## Configuration

Stored in `~/Library/Application Support/RatTamer/config.json` (schema v2), applied on connect.

| Key | Type | Meaning |
|---|---|---|
| `version` | Int | schema version (2) |
| `deviceIndex` | UInt8? | receiver slot of the mouse |
| `buttons` | `[String: ButtonAction]` | action per control, keyed `"0x00C4"` style |
| `swapLeftRight` | Bool | physical left/right swap |
| `smartShiftMode` | String? | `freespin` / `ratcheted` / `smartshift` |
| `smartShiftSensitivity` | Int? | wheel sensitivity |
| `dpiValue` | UInt16? | current pointer resolution |
| `dpiCycleValues` | [UInt16]? | cycle presets |
| `invertScrollDirection` | Bool? | HiRes wheel direction |
| `thumbWheelLeft` / `thumbWheelRight` | ButtonAction? | thumb wheel actions |
| `menuBarOnly` | Bool? | hide the Dock icon (Settings → General) |

`ButtonAction` is an enum with the JSON shapes:

| Kind | JSON |
|---|---|
| shortcut | `{"action":"shortcut","key":"w","modifiers":["command"]}` |
| system | `{"action":"system","system":"missionControl"}` |
| runShortcut | `{"action":"runShortcut","shortcut":"SS Volume Up"}` |
| click | `{"action":"click","button":4}` |
| gesture | `{"action":"gesture","gesture":{…}}` |
| cycleDPI | `{"action":"cycleDPI"}` |
| disabled | `{"action":"disabled"}` |

## Developer tools

**RatTest** — identifies buttons. It diverts all controls and shows, in real time, which row corresponds to each physical button as you press it. You can also change a button's action and run it ("Run") without leaving the window.

```bash
swift run RatTest
```

Close `RaTamer` first — only one process can receive the divert events.

**RatDiagnose** — inspects the protocol:

```bash
swift run RatDiagnose                 # lists features and the controls (cid/tid/divertable table)
swift run RatDiagnose --divert 10     # diverts everything for 10s and prints PRESS/RELEASE per button
```

## How to build

### Required

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`)

### Steps

```bash
swift build            # compile
swift test             # test suite (194 tests)
./scripts/build-app.sh # app bundle at build/RaTamer.app
swift run IconGen      # regenerate the app icon (build/icon/RaTamer.icns)
```

### Dependencies

None — SwiftPM-only. The app links only Apple system frameworks (IOKit, CoreGraphics, Carbon, ApplicationServices).

## Distribution deep-dive

The app is **not notarized** — notarization requires a paid Apple Developer account — so macOS may block a downloaded copy.

1. **Local build (recommended).** `./scripts/build-app.sh` produces `build/RaTamer.app`, ad-hoc signed (`codesign -s -`, no identity). Files built locally never receive `com.apple.quarantine`, so Gatekeeper stays out of the way. "Start at login" works via `SMAppService`.
2. **GitHub Release (convenience).** The ad-hoc signed app is published as a zip. A browser download sets the quarantine attribute, so remove it once:

   ```bash
   xattr -dr com.apple.quarantine RaTamer.app
   ```

   or right-click → Open → Open Anyway in Gatekeeper.

## References

RaTamer was built by studying the projects below — reversing the HID++ wire format, porting system-action triggers, and learning how existing tools work around macOS limitations. The research notes behind each one are in `specs/` (not tracked).

**HID++ protocol**
- Logitech HID++ 2.0 specification and the community reverse-engineering work (receiver framing, `0x1B04` ReprogrammableControls, `0x1000` Battery, `0x2201` DPI) — see [docs/HIDPP.md](docs/HIDPP.md) for the wire details.
- The byte-level gotchas were validated on hardware (macOS 15, Apple Silicon): `IOHIDManager` never enumerates the Unifying receiver, writes must use `kIOHIDReportTypeOutput`, cold-start RF can take > 0.5s.

**Mouse remapping / system actions**
- [mrmouse](https://github.com/zackbart/mrmouse) — same idea as RaTamer (MX Master remapping in Swift); its system-action mapping informed the `ActionEngine`.
- [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) (MIT) — reference for `TouchSimulator.m` (dock-swipe gestures) and `SymbolicHotKeys.m` (system action hijacking).
- [input-leap](https://github.com/input-leap/input-leap) (GPL-2.0) — reference only: confirms keycodes 160 (Mission Control) and 131 (Launchpad) via `IOHIDPostEvent`.
- [dockswipe](https://github.com/oomol-lab/dockswipe) (MIT) — CLI that synthesizes dock-swipe gestures; explored as a trigger for App Exposé / Show Desktop, superseded by the System Events key-code approach used today (`ActionEngine.systemKey`).
- [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) (MIT) — `hs.spaces` toggles; confirmed `CoreDockSendNotification` is dead on macOS 15.
- [Karabiner-Elements issue #3310](https://github.com/pqrs-org/Karabiner-Elements/issues/3310) — consumer usages `0x29F` / `0x2A0` for Mission Control / Launchpad.
- [zenangst/Dock](https://github.com/zenangst/Dock) (MIT) — `CoreDockSendNotification` wrapper; **does not work** on macOS 15 (symbol gone).

**Audio / HDMI volume — researched, not implemented**
- A SoundSource-style virtual HAL driver (software volume for HDMI outputs that expose no volume control) was researched but **not built**. Volume actions in RaTamer use AppleScript (`set volume output volume`) instead. Candidates studied: [proxy-audio-device](https://github.com/briankendall/proxy-audio-device) (Unlicense, the recommended path), [libASPL](https://github.com/gavv/libASPL) (MIT), [BlackHole](https://github.com/ExistentialAudio/BlackHole) (GPL-3.0, loopback-only — not usable here) and [eqMac](https://github.com/bitgapp/eqMac) (Apache-2.0).
