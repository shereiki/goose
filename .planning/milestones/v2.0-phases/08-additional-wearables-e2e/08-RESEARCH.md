# Phase 8: Additional Wearables E2E — Research

**Researched:** 2026-06-03
**Phase:** 08 — Additional Wearables E2E
**Requirements:** WEAR-01, WEAR-02, WEAR-03

---

## Summary

Phase 8 adds standard Bluetooth HR monitor (0x180D / 0x2A37) support end-to-end. The Rust core and Swift BLE layer already have partial infrastructure in place — the challenge is wiring them together correctly and handling the `rustDeviceType` routing without breaking the existing WHOOP pipeline.

---

## Validation Architecture

### Dimension 1 — Unit/Integration Tests (Rust)
- `Rust/core/tests/heart_rate_gatt_protocol_tests.rs` — new integration test file covering all 0x2A37 encoding variants
- Pattern: mirrors `protocol_tests.rs` structure (plain `#[test]` functions, no async)

### Dimension 2 — Functional Verification (Swift)
- `GooseNotificationEvent.rustDeviceType` computes `"HR_MONITOR"` for 0x2A37 characteristic
- `GooseBLEClient+HRMonitor.swift` scans for `CBUUID("180D")` only — not mixed with `whoopServices`
- `GooseBLEClient` shows HR monitor peripherals in `discoveredDevices` (separate array)

### Dimension 3 — Upload Integration
- `GooseUploadService.upload(deviceType:)` receives `"HR_MONITOR"` (or sanitized device name)
- `GooseUploadService.performUpload` produces `device_generation: <sanitized-name>` instead of fallback `"5.0"`
- Upload payload includes HR monitor's device name as `device_type` field

### Dimension 4 — Storage
- `CapturedFrameInput.device_type` accepts new `DeviceType::HrMonitor` variant in Rust (or passes through as raw string)
- Existing `captured_frames` table stores HR monitor frames alongside WHOOP frames distinguished by `device_type`

---

## Findings

### F-01: Swift Already Parses 0x2A37 — But Does Not Store It

`GooseBLEClient+Parsing.swift` at line 502 has a complete `parseStandardHeartRateMeasurement(_:)` function that decodes the 0x2A37 flags byte (8/16-bit HR, RR intervals, energy expended). This function is already battle-tested.

**However:** The Swift parser only updates `liveHeartRateBPM` / `liveHRVRMSSD` published properties — it does NOT store frames in SQLite (no `CaptureFrameWriteQueue` path). HR monitor frames from 0x2A37 need to be routed through the capture pipeline to be stored and uploaded.

**Action required:** `GooseBLEClient+PeripheralDelegate.swift` line 72–82 intercepts 0x2A37 notifications and calls `handleStandardHeartRate` — this path bypasses `fanOutNotification` / `onNotification` completely. The new HR monitor plan needs a separate code path that routes 0x2A37 frames to `onNotification` **in addition to** calling `handleStandardHeartRate`.

### F-02: `GooseNotificationEvent.rustDeviceType` Must Be Extended

Current logic (GooseBLETypes.swift line 66–68):
```swift
var rustDeviceType: String {
    characteristicUUID.lowercased().hasPrefix("610800") ? "GEN4" : "GOOSE"
}
```

For an HR monitor notification on characteristic `2A37`, this returns `"GOOSE"` — which is wrong. The new variant `"HR_MONITOR"` must be added. Logic update:
```swift
var rustDeviceType: String {
    if characteristicUUID.lowercased().hasPrefix("610800") { return "GEN4" }
    if characteristicUUID.uppercased() == "2A37" { return "HR_MONITOR" }
    return "GOOSE"
}
```

### F-03: `DeviceType` Rust Enum Does NOT Have `HrMonitor` Variant — And Cannot Parse 0x2A37 Frames

`Rust/core/src/protocol.rs` `DeviceType` enum has: `Gen4`, `Maverick`, `Puffin`, `Goose`. Adding `HrMonitor` would require schema migration and changes to `parse_device_type()` in bridge.rs plus `CapturedFrameInput.device_type` deserialization.

**Key insight:** HR monitor BLE notifications (raw `Data` bytes from 0x2A37) are NOT WHOOP proprietary frames — they are standard GATT measurements, not the `0xaa`-delimited frame protocol. The existing `gooseFrames(in:event:)` reassembly in `GooseAppModel+NotificationPipeline.swift` looks for `0xaa` start bytes. A raw 0x2A37 value will never match `0xaa` format — it will be dropped as zero frames.

**Two options for storage:**
- **Option A (simpler):** Store 0x2A37 raw bytes in the WHOOP frames table as `device_type = "HR_MONITOR"` with a new `DeviceType::HrMonitor` Rust enum variant. `import_captured_frame_batch` would need to skip CRC validation for HR_MONITOR frames (they don't have the WHOOP CRC structure).
- **Option B (cleanest):** Store HR data directly via a dedicated Rust bridge method `hr_monitor.import_gatt_frame` that takes the parsed HR+RR values as JSON, bypassing the WHOOP frame pipeline entirely.

**CONTEXT.md decision D-04** says to reuse the existing table. Option A matches D-04 but requires handling `0xaa` byte sync issue. Option B also reuses the same table but through a different path.

**Recommended approach (per CONTEXT.md D-04 + D-05):** Use a dedicated bridge method for HR monitor data — `hr_monitor.import_measurement` that accepts parsed HR/RR JSON and writes to the existing `captured_frames` table / decoded tables with `device_type = "HR_MONITOR"`. This avoids frame reassembly issues entirely.

### F-04: `GooseUploadService` Has a Silent WHOOP Gen5 Fallback

Line 86 of `GooseUploadService.swift`:
```swift
let deviceGeneration = deviceType == "GEN4" ? "4.0" : "5.0"
```

When `deviceType == "HR_MONITOR"`, this silently returns `"5.0"`. **WEAR-03 explicitly requires removing this fallback.** The fix: use the sanitized BLE device name as the `device_type` value in the upload payload. For HR monitors, `deviceType` will be the sanitized advertised name (e.g., `"Polar H10"`), not the enum string `"HR_MONITOR"`.

**Upload payload change:** Replace `"device_generation": deviceGeneration` with `"device_type": deviceType` for HR monitor payloads — OR always pass the raw `deviceType` string to the server and let the server handle it. Decision from CONTEXT.md: the iOS app passes the sanitized BLE device name as `device_type`.

### F-05: Separate Scan Mode — Minimal State Additions Needed

Current `GooseBLEClient` scan methods only scan for `whoopServices`. The new HR monitor scan needs to scan for `[CBUUID("180D")]` only. Looking at the existing scan infrastructure:

```swift
func startScan(reason: String, clearDiscovered: Bool) {
    central.scanForPeripherals(withServices: whoopServices, options: ...)
}
```

For the HR monitor scan, a parallel `startHRMonitorScan(reason:)` method in `GooseBLEClient+HRMonitor.swift` can call `central.scanForPeripherals(withServices: [standardHeartRateServiceID], ...)` but must use a **separate** `CBCentralManager` instance OR the same central with a different scan filter — CoreBluetooth allows only one active scan at a time.

**Critical CoreBluetooth constraint:** `CBCentralManager` does not support simultaneous scans with different service filters. Solution: Either (a) use the same central manager but call `stopScan()` then `startScan(withServices: [standardHeartRateServiceID])` when entering HR monitor mode, or (b) a second `CBCentralManager` instance (recommended for isolation — avoids disrupting WHOOP connection state).

**Recommended:** A dedicated second `CBCentralManager` for HR monitor scanning inside `GooseBLEClient+HRMonitor.swift`. This keeps WHOOP scan state completely isolated.

### F-06: WearableDescriptor.genericHRMonitor Shape

From CONTEXT.md and the existing `WearableDescriptor` in `GooseBLETypes.swift`:

```swift
struct WearableDescriptor {
    let serviceUUIDPrefix: String
    let commandCharacteristicPrefix: String
    func isCommandCharacteristic(_ c: CBCharacteristic) -> Bool { ... }
    func isCommandUUID(_ uuid: CBUUID) -> Bool { ... }
}
```

**Note:** The current `WearableDescriptor` does NOT have `serviceUUIDs: [CBUUID]`, `notificationCharacteristicPrefixes: [String]`, or `rustDeviceType: String` properties — those were in the Phase 6 CONTEXT.md design sketch but the actual implementation is simpler. The current struct only has `serviceUUIDPrefix` and `commandCharacteristicPrefix`.

For `WearableDescriptor.genericHRMonitor`, a new static instance is needed. Since HR monitors have no command characteristic (they only notify), the `commandCharacteristicPrefix` can be empty string `""`.

```swift
extension WearableDescriptor {
    // Standard Bluetooth Heart Rate Service (0x180D), HR Measurement (0x2A37)
    // No command characteristic — HR monitors are read-only notify
    static let genericHRMonitor = WearableDescriptor(
        serviceUUIDPrefix: "180d",
        commandCharacteristicPrefix: ""
    )
}
```

### F-07: Rust New Module — `heart_rate_gatt_protocol.rs`

New file at `Rust/core/src/heart_rate_gatt_protocol.rs`. The module must:
1. Define `HrMeasurementFlags` struct or bitfield for 0x2A37 flags byte
2. Define `HrMeasurement` output struct: `hr_bpm: u16`, `rr_intervals_ms: Vec<u16>`, `energy_expended_kj: Option<u16>`, `sensor_contact: Option<bool>`
3. Export `parse_hr_measurement(data: &[u8]) -> Result<HrMeasurement, ...>`
4. Add `pub mod heart_rate_gatt_protocol;` to `lib.rs`
5. Integration tests cover: 8-bit HR only, 16-bit HR only, HR+RR, HR+energy, all fields present, too-short input, energy-expended-bit-set-but-truncated

The Swift `parseStandardHeartRateMeasurement` already implements the same logic — use it as the reference implementation for the Rust test vectors.

**Rust RR interval units:** Bluetooth SIG specifies RR interval units as 1/1024 second (not milliseconds). The Swift parser converts: `Double(raw) * 1000.0 / 1024.0`. The Rust parser should store raw 1/1024-sec values and let the bridge/caller convert, OR convert to ms in the struct — match whatever the bridge method expects.

### F-08: Bridge Method for HR Monitor Data

A new bridge method `hr_monitor.import_measurement` is needed to:
1. Accept `{ database_path, device_id, device_type, measured_at, hr_bpm, rr_intervals_ms, energy_expended_kj, sensor_contact }` JSON args
2. Store HR measurement in a dedicated SQLite table (or reuse decoded_frames)
3. Return import count

Alternatively, the HR measurements could be written to the same `upload.get_recent_decoded_streams` path if a new Rust function inserts synthetic decoded stream rows. The safest path given existing infrastructure is a new lightweight table `hr_monitor_measurements` with columns: `id`, `device_type`, `device_id`, `measured_at`, `hr_bpm`, `rr_intervals_ms_json`, `energy_expended_kj`, `sensor_contact`, `captured_at`.

**Upload integration:** The upload bridge `upload.get_recent_decoded_streams` queries `decoded_frames`. For HR monitor data to be uploaded, either: (a) the new table needs a separate upload bridge method, or (b) HR measurements are inserted as synthetic decoded stream rows into the existing `decoded_frames` path. Option (b) is the simplest for upload reuse.

### F-09: Connection State Separation

An HR monitor connected device must NOT set `activePeripheral` on `GooseBLEClient` (that's WHOOP-only). The HR monitor connection state should be tracked separately in `GooseBLEClient+HRMonitor.swift` via private stored properties:
- `private var hrMonitorPeripheral: CBPeripheral?`
- `private var hrMonitorCentral: CBCentralManager?`
- `private var hrMonitorConnectionState: String`

The HR monitor's `CBPeripheralDelegate` callbacks will be handled by a separate delegate class or nested extension in `GooseBLEClient+HRMonitor.swift`.

### F-10: Manual Upload Trigger

`triggerManualUpload()` in `GooseAppModel+Upload.swift` currently hardcodes `deviceType: "GOOSE"`. After Phase 8, HR monitor data needs to be included in uploads. The simplest fix: if an HR monitor is connected, also trigger an upload with the HR monitor's device type. But per CONTEXT.md D-09, `GooseUploadService` already handles all device classes — the `upload.get_recent_decoded_streams` bridge just needs to return HR monitor data too.

---

## Validation Strategy

### WEAR-01 Validation
- `cargo test --test heart_rate_gatt_protocol_tests` — all 6+ test cases pass
- `Rust/core/src/heart_rate_gatt_protocol.rs` is present with `parse_hr_measurement` public function
- `lib.rs` has `pub mod heart_rate_gatt_protocol;`

### WEAR-02 Validation
- `GooseBLEClient+HRMonitor.swift` exists with `startHRMonitorScan()` method
- `GooseNotificationEvent.rustDeviceType` returns `"HR_MONITOR"` when `characteristicUUID.uppercased() == "2A37"`
- `WearableDescriptor.genericHRMonitor` static instance exists in `GooseBLETypes.swift`
- Frames from HR monitor route to `onNotification` callback (same as WHOOP path)

### WEAR-03 Validation
- `GooseUploadService.performUpload` does not contain the `"5.0"` fallback for unknown device types
- Upload payload for HR monitor contains `device_type` field with sanitized device name (not `"5.0"`)
- Upload unit test or integration test demonstrates HR monitor upload path

---

## Files to Create / Modify

| File | Action | Notes |
|------|--------|-------|
| `Rust/core/src/heart_rate_gatt_protocol.rs` | Create | 0x2A37 parser + `HrMeasurement` struct |
| `Rust/core/src/lib.rs` | Modify | Add `pub mod heart_rate_gatt_protocol;` |
| `Rust/core/src/bridge.rs` | Modify | Add `hr_monitor.import_measurement` bridge method, extend `parse_device_type` for `"HR_MONITOR"` |
| `Rust/core/src/protocol.rs` | Modify | Add `DeviceType::HrMonitor` variant OR decide against it |
| `Rust/core/tests/heart_rate_gatt_protocol_tests.rs` | Create | Integration tests for parser |
| `GooseSwift/GooseBLETypes.swift` | Modify | `WearableDescriptor.genericHRMonitor`, extend `GooseNotificationEvent.rustDeviceType` |
| `GooseSwift/GooseBLEClient+HRMonitor.swift` | Create | Dedicated HR monitor scan/connect extension |
| `GooseSwift/GooseUploadService.swift` | Modify | Remove silent Gen5 fallback, handle HR_MONITOR device type |
| `GooseSwift/GooseAppModel+NotificationPipeline.swift` | Modify | Route 0x2A37 notifications through `onNotification` callback |

---

## Risk Summary

| Risk | Severity | Mitigation |
|------|----------|------------|
| CoreBluetooth single-scan constraint | High | Use separate `CBCentralManager` for HR monitor scanning |
| 0xaa frame reassembly won't work for standard GATT bytes | High | Use dedicated bridge method bypassing frame reassembly |
| `rustDeviceType` returns `"GOOSE"` for 0x2A37 | High | Extend computed property before routing |
| Silent `"5.0"` fallback in upload (WEAR-03) | High | Replace with sanitized device name |
| No WHOOP protocol state pollution from HR monitor | Medium | Keep HR monitor state in separate extension properties |

## RESEARCH COMPLETE
