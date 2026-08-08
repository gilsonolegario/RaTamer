# Multi-device support (feature-driven)

Date: 2026-08-08
Status: Approved

## Goal

Make RatTamer work with the wider Logitech MX line (MX Master 3/3S, MX Anywhere,
MX Vertical) without per-model code. The app already connects to any Logitech
device exposing an HID++ interface (`HIDLocator` does not filter by model) and
queries features dynamically; this spec removes the remaining hardcoded
"MX Master 2S" assumptions and makes the UI adapt to device capabilities.

Only hardware available for testing: MX Master 2S. Other models are supported
by construction (feature-driven) and documented as such; no tester campaign.

## Design

### 1. Device name

- Expose `productName` on `HIDDevice`/`HIDPPSession`, read from
  `kIOHIDProductKey` in the device wrapper.
- Replace the hardcoded "MX Master 2S" strings:
  - `Sources/RatTamerApp/AppDelegate.swift` — connect/disconnect notification bodies
  - `Sources/RatTamerApp/Views/SimpleTabs.swift` — About tab headline
  - Fallback: "HID++ device" when the product name is unavailable.

### 2. Device capabilities

New pure struct `DeviceCapabilities` (RatTamerCore) built after connect:

- `hasReprogrammableControls` — feature 0x1B04 present (already enforced).
- `hasBattery` — feature 0x1000 present (UI already hides the row when absent).
- `hasDPI` — feature 0x2201 present (UI already shows "unavailable" when absent).
- `hasSmartShift` — `HiResWheel.getInfo().hasSwitch` when the HiResWheel
  service exists, else false.

UI: hide the "SmartShift (auto)" option in the wheel-mode menu
(`ButtonsTabView` smartShiftMenu) when `hasSmartShift` is false. The menu is
otherwise tied to control CID 0x00C4 and only appears on devices that expose it.

### 3. DPI cycle defaults per device

- Keep `DPICycle.defaultPresets` as fallback.
- Add `DPICycle.recommendedPresets(from validList: [UInt16], limit: Int = 4)`:
  derive up to 4 evenly spaced valid values from the device-reported list
  (`AdjustableDPI.getSensorDpiList`), clamping to `validList` values.
- In `EngineController.cycleDPI()`, use
  `config.dpiCycleValues ?? recommendedPresets(from: service.getSensorDpiList(sensor: 0))`
  falling back to `DPICycle.defaultPresets` when the list is unavailable.

### 4. Docs

- README: replace "for the MX Master 2S" with "tested on the MX Master 2S;
  adapts to other HID++ Logitech devices (MX Master 3/3S, MX Anywhere,
  MX Vertical)" and note receiver + Bluetooth operation.
- Update `docs/TECHNICAL.md` feature list if it names the device.

### 5. Tests

- `DPICycle.recommendedPresets`: valid list, short list, empty list, clamping.
- `DeviceCapabilities` pure helpers if any gain pure logic.
- Manual regression on MX Master 2S: buttons, thumb wheel, DPI slider + cycle,
  SmartShift, battery, reconnect, notifications show the real device name.

## Out of scope (YAGNI)

- Thumb wheel stays as-is: it is intercepted at the system level
  (`ScrollWheelTap`) and is harmless on devices without a lateral wheel.
- No per-model code, no model lookup tables, no tester campaign.
