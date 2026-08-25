# Advanced: the HID++ protocol

RaTamer talks to the MX Master 2S through the Unifying receiver using HID++ 2.0 — the same protocol Logitech's own software speaks. Everything below is implemented in `Sources/RaTamerCore/HIDPP/`.

## Framing

Two report sizes:

- **Short** — report ID `0x10`, 7 bytes.
- **Long** — report ID `0x11`, 20 bytes.

The body, after the report ID:

```text
[deviceIndex, featureIndex, (functionID << 4) | softwareID, params …]
```

## Feature discovery

The feature index is **not stable across sessions** — observed at `0x0E`/`0x0F` in the read-only era and `0x0A` once divert was in use. It is learned at runtime via `getFeatureIndex(featureID:)`: the Root feature (`0x0000`, function `0x00` = `getFeature`) is called with `[hi, lo, 0x00]`; the response carries the index in `resp[4]`, and index 0 means the feature is absent.

## Reprogrammable controls (0x1B04)

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

## Feature functions

Function IDs are nibbles in code; the wire byte is `nibble << 4`:

| Nibble | Function | Notes |
|---|---|---|
| `0x00` | `getCount` | |
| `0x01` | `getControlInfo` | params `[index]` |
| `0x02` | `getCidReporting` | |
| `0x03` | `setCidReporting` | params `[cid_hi, cid_lo, flags, remap_hi, remap_lo]` |

## Reporting flags

`setDiverted`/`setRemapped` build the flags byte: divert `0x01`, divert-valid `0x02`, rawXY `0x10`, rawXY-valid `0x20`.

## Diverted event

A **state report** on a long frame:

```text
11 <dev> <feat> 00 <cid × 4>
```

It lists the currently pressed divertable CIDs — up to 4 slots, big-endian; all zeros means nothing is pressed. Pressing SmartShift puts `0x00C4` in a slot; releasing it clears the slot.

## Raw XY event

```text
11 <dev> <feat> 10 <dx_hi> <dx_lo> <dy_hi> <dy_lo>
```

Signed big-endian Int16 deltas; positive dy = down (HID convention).

## Response matching

`request` accepts a report only when `resp[1] == device`, `resp[2] == feature`, `resp[3] >> 4 == functionID` and the softwareID nibble matches (own or 0).

Requests are serialized through an exclusive ownership gate (`beginRequest`/`endRequest`): the monitor loop blocks while a request is in flight, so concurrent requests can never steal each other's replies. Reports queue in a FIFO mailbox (capacity 16); beyond that, the oldest entry is dropped.

## Gotchas found on hardware

- `IOHIDManager` **never enumerates** the Unifying receiver on macOS 15/arm64. `HIDLocator` walks the kernel registry with `IOServiceGetMatchingServices` + `IOHIDDeviceCreate` instead — and that works as a regular user, with no TCC permission.
- The receiver exposes 3 interfaces: D1 = HID++ (usage `0xFF00`/1,2,4), D2 = mouse HID, D3 = keyboard. Only D1 matters.
- Writes go out only as `kIOHIDReportTypeOutput` — `kIOHIDReportTypeFeature` STALLS. Long reports need the full 20-byte buffer (the `0xE0005000` stall was a buffer-length bug, not a macOS limitation).
- **Cold-start RF**: the first response after opening the receiver can take > 0.5s (0.85s measured; ~15ms warm) — `getFeatureIndex` retries 3 × 0.5s.
- Diverting SmartShift suppresses the native ratchet/free-spin toggle.

## Data flow

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
