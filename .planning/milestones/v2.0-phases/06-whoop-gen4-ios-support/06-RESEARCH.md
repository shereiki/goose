# Phase 6: WHOOP Gen4 iOS Support — Research

**Phase:** 06 — WHOOP Gen4 iOS Support
**Researched:** 2026-06-03
**Confidence:** HIGH — all findings from direct codebase inspection

---

## What Is Already Done (iOS + Rust)

The Rust core fully supports Gen4. The iOS BLE scan already includes both service UUIDs. The upload
already sends the correct `device_generation` field. What is blocked is the iOS app layer.

| Component | State | Notes |
|-----------|-------|-------|
| `Rust/core/src/protocol.rs` `DeviceType::Gen4` | DONE | 4-byte header, CRC8, full parse support |
| `GooseBLETypes.swift` `rustDeviceType` | DONE | `"610800"` prefix → `"GEN4"`, else `"GOOSE"` |
| `GooseUploadService.swift` `device_generation` | DONE | `GEN4 → "4.0"`, else `"5.0"` (line 86-93) |
| `GooseBLEClient.swift` `whoopServices` | DONE | Contains both `fd4b0001-...` and `61080001-...` |
| `commandCharacteristicIDs` | DONE | Contains both `fd4b0002-...` and `61080002-...` |
| `supportsV5HistoricalSync` | BROKEN | Returns false for Gen4 (only checks `fd4b0002` prefix) |
| `GooseDiscoveredDevice.generation` | MISSING | Struct only has `id`, `name`, `rssi` |
| UI generation label | MISSING | No "Gen 4" / "Gen 5" text anywhere in DeviceView/ConnectionView |
| Onboarding copy | MISSING | Only says "WHOOP" generically, no mention of 4.0 |
| Swift unit tests | MISSING | No Swift test target exists in the Xcode project |

---

## Critical Fix: `supportsV5*` Guards (GEN4-01)

### Current State (GooseBLEClient+Commands.swift lines 147-165)

```swift
var supportsV5HistoricalSync: Bool {
  commandCharacteristic.map(isV5CommandCharacteristic) == true
}
var supportsV5AlarmCommands: Bool {
  commandCharacteristic.map(isV5CommandCharacteristic) == true
}
var supportsV5ClockCommands: Bool {
  commandCharacteristic.map(isV5CommandCharacteristic) == true
}
var supportsV5SensorCommands: Bool {
  commandCharacteristic.map(isV5CommandCharacteristic) == true
}
func isV5CommandCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
  characteristic.uuid.uuidString.lowercased().hasPrefix("fd4b0002")
}
```

**Problem:** Gen4 command characteristic has prefix `61080002`, not `fd4b0002`.
All four `supportsV5*` properties return `false` for Gen4 — every command is silently blocked.

### All Usage Sites of `supportsV5*` (must be updated in rename)

| File | Line | Property |
|------|------|----------|
| `GooseBLEClient.swift` | 849 | `supportsV5HistoricalSync` |
| `GooseBLEClient.swift` | 853 | `supportsV5SensorCommands` |
| `GooseBLEClient.swift` | 861 | `supportsV5AlarmCommands` |
| `GooseBLEClient.swift` | 867 | `supportsV5ClockCommands` |
| `GooseBLEClient.swift` | 898 | `supportsV5AlarmCommands` |
| `GooseBLEClient+Commands.swift` | 209 | `supportsV5ClockCommands` |
| `GooseBLEClient+Commands.swift` | 302 | `supportsV5AlarmCommands` |
| `GooseBLEClient+Commands.swift` | 393 | `supportsV5SensorCommands` |
| `GooseBLEClient+Commands.swift` | 906 | `supportsV5SensorCommands` |
| `GooseBLEClient+Commands.swift` | 927 | `supportsV5HistoricalSync` |
| `GooseBLEClient+HistoricalCommands.swift` | 26 | `supportsV5HistoricalSync` |
| `GooseBLEClient+UserActions.swift` | 60 | `supportsV5SensorCommands` |

### Fix: `WearableDescriptor` + Rename

Introduce `WearableDescriptor` in `GooseBLETypes.swift`. Replace `isV5CommandCharacteristic`
with `WearableDescriptor.isCommandCharacteristic(_:)` that accepts both prefixes.

Rename the four computed properties:
- `supportsV5HistoricalSync` → `supportsHistoricalSync`
- `supportsV5AlarmCommands` → `supportsAlarmCommands`
- `supportsV5ClockCommands` → `supportsClockCommands`
- `supportsV5SensorCommands` → `supportsSensorCommands`

`WearableDescriptor` static instances:
- `.whoopGen5` — serviceUUID prefix `fd4b0001`, commandPrefix `fd4b0002`
- `.whoopGen4` — serviceUUID prefix `61080001`, commandPrefix `61080002`

The existing `shouldUseCommandCharacteristic` function (line 167-174) also uses
`isV5CommandCharacteristic` — it needs updating to use the descriptor.

---

## Generation Field: `GooseDiscoveredDevice` (GEN4-02)

### Where Device is Created

`GooseBLEClient+CentralDelegate.swift` line 119:
```swift
let device = GooseDiscoveredDevice(
  id: peripheral.identifier,
  name: name,
  rssi: RSSI.intValue
)
```

The `advertisedServices` variable is already computed at this point (line 103):
```swift
let advertisedServices = advertisedServiceUUIDs(from: advertisementData)
```

### Generation Derivation Rule (from CONTEXT.md, Decision 3)

```swift
func generation(from serviceUUIDs: [CBUUID]) -> String {
  if serviceUUIDs.contains(where: { $0.uuidString.lowercased().hasPrefix("61080001") }) {
    return "4.0"
  } else if serviceUUIDs.contains(where: { $0.uuidString.lowercased().hasPrefix("fd4b0001") }) {
    return "5.0"
  }
  return "unknown"
}
```

`advertisedServices` is already available at the call site — no additional BLE calls needed.

### Propagation to AppModel

`GooseAppModel` needs `@Published var connectedDeviceGeneration: String?`
Set when device connects (in `GooseBLEClient+Commands.swift` where `sendClientHello` is called,
or in `GooseBLEClient+CentralDelegate.swift` `didConnect` / `processDiscoveredCharacteristics`).

---

## Validation Architecture

### Testable Units (GEN4-05)

No Swift test target exists in `GooseSwift.xcodeproj`. Three options for GEN4-05:

**Option A: Rust integration test (simplest)**
Add a `cargo test` in `Rust/core/tests/bridge_tests.rs` that asserts:
- `parse_frame_hex(DeviceType::Gen4, ...)` succeeds for a sample Gen4 frame
- Bridge method with `device_type: "GEN4"` correctly stores and retrieves data
This verifies the Gen4 upload path (the server receives `device_generation: "4.0"`
when a frame is inserted via the Rust bridge with `device_type: "GEN4"`).

**Option B: Swift unit test target (more complete)**
Add an `XCTestCase` target to `GooseSwift.xcodeproj` — no physical device needed for:
- `GooseDiscoveredDevice.generation` derivation from service UUID
- `WearableDescriptor.isCommandCharacteristic` prefix matching
- `GooseNotificationEvent.rustDeviceType` for `"610800"` prefix

**Recommendation: Option A for GEN4-05 (Rust test), Option B optional.**
The Rust bridge already handles `device_type: "GEN4"` → `device_generation: "4.0"` at the
Swift layer (`GooseUploadService.swift` line 86). A Rust test verifying `DeviceType::Gen4`
frame parsing is sufficient to satisfy GEN4-05's intent ("verified by a unit or integration test").

The Swift `WearableDescriptor` logic is pure value type and easily testable — a Swift test target
should be added regardless since the project currently has zero Swift tests.

---

## UI Changes (GEN4-03, GEN4-04)

### Onboarding (GEN4-03)

`OnboardingModels.swift` line 25: `"Connect your WHOOP"` → needs to mention both generations.
`OnboardingStepViews.swift` uses `"WHOOP"` generically throughout (lines 261-412).
Minimal change: Update the device step title/body to say "WHOOP 4.0 or 5.0" or add a footnote.

### Device Scan List (GEN4-04 — scan list subtitle)

`DeviceView.swift` lines 564-589 — `ForEach(ble.discoveredDevices)` renders a `VStack`:
```swift
VStack(alignment: .leading, spacing: 4) {
  Text(device.name)  // primary text
  Text(device.id.uuidString)  // UUID in monospaced
}
```

Replace the UUID line with a generation-RSSI caption:
```swift
Text("Gen \(device.generation.prefix(1)) · \(device.rssi) dBm")
  .font(.caption)
  .foregroundStyle(.secondary)
```

### Connected Device View (GEN4-04 — connected view)

`DeviceView.swift` line 166 — `Image("whoop_gen5_front")` — the image is always Gen5 art.
The generation label should appear near the device name / battery area.

Pattern: Match `.foregroundStyle(.secondary)` used throughout `DeviceView.swift`.
Add `Text("Gen \(ble.connectedDeviceGeneration ?? "?")")` near the battery section.

---

## shouldUseCommandCharacteristic — Race-Condition Note

The `shouldUseCommandCharacteristic` function (GooseBLEClient+Commands.swift line 167-174)
currently prefers Gen5 over Gen4: it picks the `fd4b0002` characteristic when both are present.
With `WearableDescriptor`, this logic should prefer the characteristic matching the _discovered_
device's generation, not always prefer Gen5. Since discovery happens before characteristic routing,
`GooseBLEClient` should store the active `WearableDescriptor` when a device connects.

Implementation: Add `private var activeDescriptor: WearableDescriptor?` to `GooseBLEClient`.
Set in `didConnect` / `processDiscoveredCharacteristics` based on the connected device's generation.
`shouldUseCommandCharacteristic` uses `activeDescriptor?.isCommandCharacteristic` instead of
the hardcoded `fd4b0002` check.

---

## Files to Create or Modify

| File | Change |
|------|--------|
| `GooseSwift/GooseBLETypes.swift` | Add `WearableDescriptor` struct; add `generation: String` to `GooseDiscoveredDevice` |
| `GooseSwift/GooseBLEClient.swift` | Add `activeDescriptor: WearableDescriptor?`; rename `supportsV5*` → `supportsV5-less`; update `canSync*` computed vars |
| `GooseSwift/GooseBLEClient+Commands.swift` | Replace `isV5CommandCharacteristic`; rename `supportsV5*` properties; update `shouldUseCommandCharacteristic`; update guard call sites |
| `GooseSwift/GooseBLEClient+Parsing.swift` | Add `generation(from:)` helper; update `isWhoopService` comment |
| `GooseSwift/GooseBLEClient+CentralDelegate.swift` | Add `generation` field when creating `GooseDiscoveredDevice`; set `activeDescriptor` on connect |
| `GooseSwift/GooseBLEClient+HistoricalCommands.swift` | Rename `supportsV5HistoricalSync` reference |
| `GooseSwift/GooseBLEClient+UserActions.swift` | Rename `supportsV5SensorCommands` reference |
| `GooseSwift/GooseAppModel.swift` | Add `@Published var connectedDeviceGeneration: String?` |
| `GooseSwift/DeviceView.swift` | Update scan list row (generation subtitle); update connected device view (generation label) |
| `GooseSwift/OnboardingModels.swift` or `OnboardingStepViews.swift` | Update device step copy to mention WHOOP 4.0 |
| `Rust/core/tests/` | Add Gen4 bridge test for GEN4-05 |

---

## Validation Architecture

### Required Test Coverage (GEN4-05)

1. **Rust test** (`Rust/core/tests/bridge_tests.rs` or new file):
   - Assert `DeviceType::Gen4` is serialised correctly in a bridge call
   - Assert `device_generation: "4.0"` appears in the upload payload data for a `"GEN4"` `device_type`

2. **Swift test target** (new `GooseSwiftTests` target in Xcode project):
   - `WearableDescriptor.whoopGen4.isCommandCharacteristic(CBCharacteristic with UUID "61080002-...")` → `true`
   - `WearableDescriptor.whoopGen5.isCommandCharacteristic(CBCharacteristic with UUID "fd4b0002-...")` → `true`
   - `GooseDiscoveredDevice.generation` derived from `["61080001-..."]` → `"4.0"`
   - `GooseDiscoveredDevice.generation` derived from `["fd4b0001-..."]` → `"5.0"`

### Non-Hardware Verification Approach

Since no Gen4 hardware is available, all verification is logic-only:
- `WearableDescriptor` prefix matching is a pure string operation — fully unit testable
- `generation(from:)` derivation is a pure function — fully unit testable
- The upload path is already tested in Rust (DeviceType::Gen4 → device_generation "4.0")
- Release note will document "untested on real hardware — Gen4 users: please report bugs"

---

## ## RESEARCH COMPLETE
