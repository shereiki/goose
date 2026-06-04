# Phase 6: WHOOP Gen4 iOS Support — Pattern Map

**Phase:** 06
**Mapped:** 2026-06-03

---

## Files to Create or Modify

| File | Role | Change Type |
|------|------|-------------|
| `GooseSwift/GooseBLETypes.swift` | Value types for BLE | Add `WearableDescriptor` struct + `generation: String` to `GooseDiscoveredDevice` |
| `GooseSwift/GooseBLEClient+Commands.swift` | Command capability guards | Replace `isV5CommandCharacteristic` + rename `supportsV5*` properties |
| `GooseSwift/GooseBLEClient.swift` | Published capability state | Add `activeDescriptor: WearableDescriptor?`; rename `supportsV5*` call sites; update `canSync*` computed properties |
| `GooseSwift/GooseBLEClient+Parsing.swift` | BLE identity helpers | Add `generation(from:)` helper function |
| `GooseSwift/GooseBLEClient+CentralDelegate.swift` | Scan/connect delegate | Add `generation` when creating `GooseDiscoveredDevice`; set `activeDescriptor` on connect |
| `GooseSwift/GooseBLEClient+HistoricalCommands.swift` | Historical sync | Rename `supportsV5HistoricalSync` → `supportsHistoricalSync` |
| `GooseSwift/GooseBLEClient+UserActions.swift` | Sensor commands | Rename `supportsV5SensorCommands` → `supportsSensorCommands` |
| `GooseSwift/GooseAppModel.swift` | App coordinator | Add `@Published var connectedDeviceGeneration: String?` |
| `GooseSwift/DeviceView.swift` | Device UI | Update scan list row subtitle; add generation label to connected view |
| `GooseSwift/OnboardingModels.swift` | Onboarding content | Update device step copy to mention WHOOP 4.0 |
| `Rust/core/tests/bridge_tests.rs` | Rust integration tests | Add Gen4 frame parsing and device_generation assertion |

---

## Analog Patterns by File

### GooseBLETypes.swift — Adding `WearableDescriptor`

**Role:** New value type centralising per-device UUID prefix data.
**Closest existing analog:** `GooseNotificationEvent` — a pure Swift value type with computed properties.

```swift
// Existing pattern (lines 26-35) — pure value type with computed var
struct GooseNotificationEvent {
  let deviceID: UUID
  let serviceUUID: String
  let characteristicUUID: String
  let value: Data
  let capturedAt: Date

  var rustDeviceType: String {
    characteristicUUID.lowercased().hasPrefix("610800") ? "GEN4" : "GOOSE"
  }
}
```

**New type to add** — same pattern:
```swift
struct WearableDescriptor {
  let serviceUUIDPrefix: String
  let commandCharacteristicPrefix: String
  
  func isCommandCharacteristic(_ c: CBCharacteristic) -> Bool {
    c.uuid.uuidString.lowercased().hasPrefix(commandCharacteristicPrefix)
  }
  
  static let whoopGen5 = WearableDescriptor(
    serviceUUIDPrefix: "fd4b0001",
    commandCharacteristicPrefix: "fd4b0002"
  )
  static let whoopGen4 = WearableDescriptor(
    serviceUUIDPrefix: "61080001",
    commandCharacteristicPrefix: "61080002"
  )
}
```

**Adding `generation: String` to `GooseDiscoveredDevice`** (line 12-16):
```swift
// Current
struct GooseDiscoveredDevice: Identifiable, Equatable {
  let id: UUID
  let name: String
  let rssi: Int
}

// After
struct GooseDiscoveredDevice: Identifiable, Equatable {
  let id: UUID
  let name: String
  let rssi: Int
  let generation: String  // "4.0", "5.0", or "unknown"
}
```

---

### GooseBLEClient+Commands.swift — `supportsV5*` Replacement

**Role:** Command capability guards used by `GooseBLEClient` and views.
**Existing pattern** (lines 147-165):

```swift
var supportsV5HistoricalSync: Bool {
  commandCharacteristic.map(isV5CommandCharacteristic) == true
}
// ... (all 4 identical pattern)

func isV5CommandCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
  characteristic.uuid.uuidString.lowercased().hasPrefix("fd4b0002")
}
```

**Target pattern** — delegate to `WearableDescriptor`:
```swift
var supportsHistoricalSync: Bool {
  commandCharacteristic.map { activeDescriptor?.isCommandCharacteristic($0) == true } == true
}
// ... (same for Alarm, Clock, Sensor)
```

**`shouldUseCommandCharacteristic` fix** (line 167-174):
```swift
// Current: always prefers fd4b0002
return !isV5CommandCharacteristic(current) && isV5CommandCharacteristic(characteristic)

// Target: prefers characteristic matching active descriptor
return activeDescriptor?.isCommandCharacteristic(characteristic) == true
    && activeDescriptor?.isCommandCharacteristic(current) == false
```

---

### GooseBLEClient+CentralDelegate.swift — `GooseDiscoveredDevice` Creation

**Role:** Scan delegate creates `GooseDiscoveredDevice` from peripheral advertisement data.
**Existing pattern** (lines 100-127):

```swift
let advertisedServices = advertisedServiceUUIDs(from: advertisementData)
// ...
let device = GooseDiscoveredDevice(
  id: peripheral.identifier,
  name: name,
  rssi: RSSI.intValue
)
```

**Target pattern** — derive generation from already-computed `advertisedServices`:
```swift
let device = GooseDiscoveredDevice(
  id: peripheral.identifier,
  name: name,
  rssi: RSSI.intValue,
  generation: Self.generation(from: advertisedServices)  // new field
)
```

**Active descriptor set on connect** — follow the existing `commandCharacteristic` assignment pattern:
```swift
// Existing: commandCharacteristic = characteristic
// New parallel: activeDescriptor = WearableDescriptor(for: device.generation)
```

---

### GooseBLEClient+Parsing.swift — Generation Helper

**Role:** Pure helper function deriving generation string from service UUIDs.
**Closest analog:** `isWhoopService` (line 335) — pure function, uses `whoopServices.contains`:

```swift
func isWhoopService(_ uuid: CBUUID) -> Bool {
  whoopServices.contains(uuid)
}
```

**New function** — same style, pure:
```swift
static func generation(from serviceUUIDs: [CBUUID]) -> String {
  if serviceUUIDs.contains(where: { $0.uuidString.lowercased().hasPrefix("61080001") }) {
    return "4.0"
  }
  if serviceUUIDs.contains(where: { $0.uuidString.lowercased().hasPrefix("fd4b0001") }) {
    return "5.0"
  }
  return "unknown"
}
```

---

### GooseAppModel.swift — `@Published var connectedDeviceGeneration`

**Role:** Published property exposing connected device generation to views.
**Existing analog:** `@Published var activeDeviceName = "WHOOP"` (GooseBLEClient.swift line 25).
The generation should live on `GooseAppModel` (accessible via `@EnvironmentObject`) OR on
`GooseBLEClient` (accessible via `model.ble.connectedDeviceGeneration`).

**CONTEXT.md decision 4:** Places it on `GooseAppModel`.

```swift
// In GooseAppModel.swift, follow existing @Published convention
@Published var connectedDeviceGeneration: String?
```

Set when `GooseBLEClient` connects — `GooseAppModel` observes `ble.connectionState` or
the `sendClientHello` completes. The connected device's `generation` comes from
`ble.discoveredDevices.first(where: { $0.id == ble.activeDeviceIdentifier })?.generation`.

---

### DeviceView.swift — UI Changes

**Scan list row subtitle** — existing pattern (lines 569-578):
```swift
VStack(alignment: .leading, spacing: 4) {
  Text(device.name)
    .font(deviceBodyFont.weight(.black))
    .foregroundStyle(devicePrimaryText)
    .lineLimit(1)
  Text(device.id.uuidString)  // replace this
    .font(.system(size: 12, weight: .semibold, design: .monospaced))
    .foregroundStyle(mutedText)
    .lineLimit(1)
}
```

**Target** — replace UUID line with generation+RSSI:
```swift
Text("Gen \(generationMajor(device.generation)) · \(device.rssi) dBm")
  .font(.caption)
  .foregroundStyle(.secondary)
```

**Connected device view** — find the battery/name area in `DeviceImageAndBattery` or a parent `VStack` in `DeviceView`. Follow `.foregroundStyle(.secondary)` pattern used throughout.

---

### Rust bridge_tests.rs — Gen4 Test

**Existing pattern** (lines 113-114):
```rust
assert_eq!(result["service_roles"][0]["generation"], "Gen4");
assert_eq!(result["service_roles"][1]["generation"], "Gen5");
```

**New test** — add to `bridge_tests.rs` or a new `gen4_tests.rs`:
```rust
#[test]
fn test_gen4_frame_parsing() {
  // Use DeviceType::Gen4 for parse_frame_hex
  // Assert device_generation "4.0" in upload payload
}
```

---

## ## PATTERN MAPPING COMPLETE
