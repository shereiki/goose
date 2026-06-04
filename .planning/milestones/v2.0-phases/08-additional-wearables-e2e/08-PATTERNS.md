# Phase 8: Additional Wearables E2E — Pattern Map

**Generated:** 2026-06-03
**Phase:** 08 — Additional Wearables E2E

---

## Files to Create / Modify

| File | Action | Role |
|------|--------|------|
| `Rust/core/src/heart_rate_gatt_protocol.rs` | Create | Rust: 0x2A37 parser module |
| `Rust/core/src/lib.rs` | Modify | Rust: register new module |
| `Rust/core/src/bridge.rs` | Modify | Rust: new bridge method + extend parse_device_type |
| `Rust/core/tests/heart_rate_gatt_protocol_tests.rs` | Create | Rust: integration tests |
| `GooseSwift/GooseBLETypes.swift` | Modify | Swift: WearableDescriptor.genericHRMonitor + rustDeviceType |
| `GooseSwift/GooseBLEClient+HRMonitor.swift` | Create | Swift: HR monitor scan/connect/notify extension |
| `GooseSwift/GooseUploadService.swift` | Modify | Swift: remove Gen5 silent fallback |
| `GooseSwift/GooseAppModel+NotificationPipeline.swift` | Modify | Swift: route 0x2A37 through onNotification |

---

## Pattern: Rust Integration Test File

**Analog:** `Rust/core/tests/protocol_tests.rs`

```rust
// pattern: declare imports from goose_core, then plain #[test] functions
use goose_core::protocol::{DeviceType, parse_frame_hex, ...};

#[test]
fn parses_hand_derived_goose_v5_get_hello_frame() {
    let parsed = parse_frame_hex(DeviceType::Goose, GET_HELLO_FRAME).unwrap();
    assert_eq!(parsed.raw_len, 16);
    // ...
}
```

For `heart_rate_gatt_protocol_tests.rs`:
```rust
use goose_core::heart_rate_gatt_protocol::{parse_hr_measurement, HrMeasurement};

#[test]
fn parses_8bit_hr_only() {
    // flags=0x00, hr=72
    let data = &[0x00, 72u8];
    let m = parse_hr_measurement(data).unwrap();
    assert_eq!(m.hr_bpm, 72);
    assert!(m.rr_intervals_ms.is_empty());
    assert!(m.energy_expended_kj.is_none());
    assert!(m.sensor_contact.is_none());
}
```

---

## Pattern: Rust Module Declaration

**Analog:** `Rust/core/src/lib.rs` lines 3–44

```rust
pub mod activity_candidates;
pub mod activity_identity;
// ... alphabetical list ...
pub mod heart_rate_gatt_protocol;  // <-- insert in alphabetical order
```

---

## Pattern: Bridge Method

**Analog:** bridge.rs pattern for `upload.get_recent_decoded_streams` at line 2644

```rust
// In the match arms in dispatch():
"hr_monitor.import_measurement" => {
    parse_args::<HrMonitorImportArgs>(&request)?
        .and_then(hr_monitor_import_measurement_bridge)
        .map(|r| json!(r))
}

// Args struct:
#[derive(Debug, Deserialize)]
struct HrMonitorImportArgs {
    database_path: String,
    device_id: String,
    device_type: String,  // sanitized device name, e.g. "Polar H10"
    measured_at: f64,     // unix timestamp
    hr_bpm: u16,
    rr_intervals_ms: Vec<f64>,
    #[serde(default)]
    energy_expended_kj: Option<u16>,
    #[serde(default)]
    sensor_contact: Option<bool>,
}
```

---

## Pattern: WearableDescriptor Static Instance

**Analog:** `GooseSwift/GooseBLETypes.swift` extension WearableDescriptor

```swift
extension WearableDescriptor {
    // existing:
    static let whoopGen5 = WearableDescriptor(
        serviceUUIDPrefix: "fd4b0001",
        commandCharacteristicPrefix: "fd4b0002"
    )
    static let whoopGen4 = WearableDescriptor(
        serviceUUIDPrefix: "61080001",
        commandCharacteristicPrefix: "61080002"
    )

    // new (Phase 8):
    // HR monitors have no command characteristic — notifications only
    static let genericHRMonitor = WearableDescriptor(
        serviceUUIDPrefix: "180d",
        commandCharacteristicPrefix: ""
    )
}
```

---

## Pattern: `rustDeviceType` Computed Property Extension

**Analog:** `GooseSwift/GooseBLETypes.swift` lines 66–68 (GooseNotificationEvent)

```swift
// Current:
var rustDeviceType: String {
    characteristicUUID.lowercased().hasPrefix("610800") ? "GEN4" : "GOOSE"
}

// After Phase 8:
var rustDeviceType: String {
    if characteristicUUID.lowercased().hasPrefix("610800") { return "GEN4" }
    if characteristicUUID.uppercased() == "2A37" { return "HR_MONITOR" }
    return "GOOSE"
}
```

---

## Pattern: BLE Extension File

**Analog:** `GooseSwift/GooseBLEClient+UserActions.swift`, `GooseBLEClient+Commands.swift`

```swift
// GooseBLEClient+HRMonitor.swift
import CoreBluetooth
import Foundation
import OSLog

extension GooseBLEClient {
    // Separate CBCentralManager for HR monitor (avoids scan-filter conflict with WHOOP)
    // Stored as lazy-init or in a companion class
    func startHRMonitorScan() { ... }
    func stopHRMonitorScan() { ... }
    func connectHRMonitor(_ device: GooseDiscoveredDevice) { ... }
}
```

---

## Pattern: `handleStandardHeartRate` → route to capture

**Analog:** `GooseBLEClient+PeripheralDelegate.swift` lines 66–82

```swift
// Current: intercepts 0x2A37, calls handleStandardHeartRate, returns early
// After Phase 8: also fanOut to onNotification BEFORE calling handleStandardHeartRate

if !Thread.isMainThread, error == nil, let value,
   characteristic.uuid == standardHeartRateMeasurementID {
    let event = notificationEvent(peripheral, characteristic: characteristic, value: value, capturedAt: capturedAt)
    fanOutRawNotification(event)
    fanOutNotification(event)        // <-- ADD THIS to route to GooseAppModel.handleNotification
    handleStandardHeartRate(value, characteristic: characteristic, capturedAt: capturedAt)
    return
}
```

---

## Pattern: GooseUploadService `deviceGeneration` Fix

**Analog:** `GooseSwift/GooseUploadService.swift` line 86–94

```swift
// Current (BROKEN for WEAR-03):
let deviceGeneration = deviceType == "GEN4" ? "4.0" : "5.0"
let payload = ["device_generation": deviceGeneration, ...]

// After Phase 8:
// Pass device_type directly for non-WHOOP devices
// HR monitor deviceType = sanitized BLE device name (e.g., "Polar H10")
let deviceGeneration: String
switch deviceType {
case "GEN4": deviceGeneration = "4.0"
case "GOOSE": deviceGeneration = "5.0"
default: deviceGeneration = deviceType  // HR monitor: use device name as-is
}
```

---

## Pattern: Rust `parse_device_type` Extension

**Analog:** `Rust/core/src/bridge.rs` lines 7956–7966

```rust
fn parse_device_type(value: &str) -> GooseResult<DeviceType> {
    match value {
        "GEN4" | "GEN_4" | "Gen4" | "gen4" => Ok(DeviceType::Gen4),
        "MAVERICK" | "Maverick" | "maverick" => Ok(DeviceType::Maverick),
        "PUFFIN" | "Puffin" | "puffin" => Ok(DeviceType::Puffin),
        "GOOSE" | "Goose" | "goose" => Ok(DeviceType::Goose),
        "HR_MONITOR" | "hr_monitor" => Ok(DeviceType::HrMonitor),  // <-- new
        other => Err(GooseError::message(...)),
    }
}
```

## PATTERN MAPPING COMPLETE
