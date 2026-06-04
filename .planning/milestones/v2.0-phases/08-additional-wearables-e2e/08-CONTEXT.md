# Phase 8: Additional Wearables E2E - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning (depends on Phase 6 completing first)

<domain>
## Phase Boundary

Support any standard Bluetooth heart rate monitor (0x180D service, 0x2A37 HR Measurement characteristic) end-to-end: BLE scan → frame capture → SQLite storage → upload with a distinct device identifier.

**What this phase delivers:**
1. `Rust/core/src/heart_rate_gatt_protocol.rs` — full 0x2A37 parser (HR value 8/16-bit, RR intervals, energy expended, sensor contact status)
2. A dedicated BLE scan mode in the iOS app for 0x180D HR Service devices
3. Captured HR frames stored in the existing WHOOP frames table with a distinct `device_type`
4. Upload payload uses the BLE-advertised device name as `device_type` (e.g., `"Polar H10"`)
5. Manual-only device connection (no auto-connect for HR monitors)
6. Integration tests in Rust covering 0x2A37 standard encoding variants

**Depends on Phase 6:** Requires `WearableDescriptor` abstraction and `rustDeviceType` heuristic introduced for Gen4.

**Out of scope:** Auto-connect for HR monitors, dedicated HR monitor UI tab, HR monitor-specific settings, Apple Watch support.

</domain>

<decisions>
## Implementation Decisions

### Rust HR GATT Parser
- **D-01:** Parse ALL standard 0x2A37 fields: HR value (8/16-bit auto-detect via flags bit 0), RR intervals (optional, flags bit 4), energy expended (optional, flags bit 3), sensor contact status (flags bits 1-2)
- **D-02:** New file: `Rust/core/src/heart_rate_gatt_protocol.rs` — keeps HR GATT parsing separate from WHOOP protocol parsing
- **D-03:** Integration tests in `Rust/core/tests/` covering: 8-bit HR only, 16-bit HR, HR+RR, HR+energy, all fields, zero-length edge cases

### Storage
- **D-04:** Reuse the existing WHOOP frames table — no new table migration needed
- **D-05:** `device_type` field distinguishes HR monitor frames from WHOOP frames
- Rationale: schema consistency, simpler upload pipeline, no migration risk

### Upload Identity
- **D-06:** `device_type` in upload payload = BLE-advertised device name (e.g., `"Polar H10"`, `"Garmin HRM"`)
  - Values are variable per brand/model — server receives them as-is
  - iOS must sanitize: trim whitespace, cap to a reasonable length (e.g., 64 chars), replace empty with `"unknown_hr_monitor"`
  - Server-side: no special handling needed — existing `device_type` column accepts arbitrary strings

### BLE Scan Mode (iOS)
- **D-07:** Separate/dedicated scan mode for HR monitors — not integrated with the WHOOP scan
  - New scan mode in `GooseBLEClient` that scans for `CBUUID("180D")` (Heart Rate Service)
  - Separate from `whoopServices` UUID array — avoids mixing WHOOP connection state with HR monitor connection state
  - Uses `WearableDescriptor.genericHRMonitor` to describe the device family (from Phase 6's abstraction)
- **D-08:** Manual connection only — HR monitor appears in a device list, user taps to connect
  - No auto-connect (WHOOP already has auto-connect; mixing would create ambiguity)
  - Scan starts when user enters the HR monitor connection UI

### Notification Routing
- **D-09:** HR monitor BLE notifications routed through existing notification pipeline via `rustDeviceType = "HR_MONITOR"`
  - `GooseAppModel` handles HR monitor notifications separately from WHOOP notifications (different characteristic UUIDs)
  - `GooseUploadService` handles all device classes — reads `device_type` from stored frames

### Claude's Discretion
- Exact `WearableDescriptor.genericHRMonitor` static instance shape (mirrors `whoopGen4`/`whoopGen5` pattern from Phase 6)
- UI for HR monitor scan/connect (minimal — a list view is sufficient, no custom design needed)
- Whether to split HR monitor BLE logic into `GooseBLEClient+HRMonitor.swift` extension or inline

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — WEAR-01, WEAR-02, WEAR-03 (full requirement text)

### Phase 6 Dependency
- `.planning/phases/06-whoop-gen4-ios-support/06-CONTEXT.md` — WearableDescriptor abstraction decisions
- `GooseSwift/GooseBLETypes.swift` — WearableDescriptor type (created in Phase 6), GooseDiscoveredDevice.generation
- `GooseSwift/GooseBLEClient.swift` — existing scan/connect flow to extend with HR monitor mode

### Rust Protocol
- `Rust/core/src/bridge.rs` — dispatch() function; HR frames will be submitted via existing bridge method pattern
- Bluetooth SIG 0x2A37 specification (public) — HR Measurement characteristic format

### Existing Pipeline
- `GooseSwift/GooseUploadService.swift` — upload pipeline; reads device_type from frames
- `GooseSwift/GooseAppModel+NotificationPipeline.swift` — notification routing; HR monitor notifications need routing here

### Storage
- `Rust/core/src/` — existing frame storage modules; HR frames reuse same table

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WearableDescriptor` (Phase 6) — `WearableDescriptor.genericHRMonitor` follows same pattern as `whoopGen4`/`whoopGen5`
- `GooseUploadService` — already handles `device_type` field; no changes needed if HR frames use same schema
- `GooseBLEClient` scan/connect flow — duplicate/extend for 0x180D scan mode

### Established Patterns
- New Rust protocol file per device family: `whoop_protocol.rs` → mirror with `heart_rate_gatt_protocol.rs`
- `GooseBLEClient+*.swift` extension pattern — HR monitor logic → `GooseBLEClient+HRMonitor.swift`
- `rustDeviceType` string in `GooseNotificationEvent` — add `"HR_MONITOR"` as a new valid value

### Integration Points
- `GooseAppModel` receives BLE notifications → routes to Rust bridge → stored in SQLite → uploaded by `GooseUploadService`
- HR monitor frames enter the same pipeline via `rustDeviceType = "HR_MONITOR"`

</code_context>

<specifics>
## Specific Ideas

- Device name sanitization in Swift before upload:
  ```swift
  let deviceType = (peripheral.name ?? "unknown_hr_monitor")
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .prefix(64)
    .description
  ```
- 0x2A37 flags byte bit layout:
  - Bit 0: HR format (0 = uint8, 1 = uint16)
  - Bits 1-2: sensor contact status
  - Bit 3: energy expended present
  - Bit 4: RR intervals present
- Rust parser returns a struct with `hr_bpm: u16`, `rr_intervals: Vec<u16>` (ms), `energy_expended: Option<u16>` (kJ), `sensor_contact: Option<bool>`

</specifics>

<deferred>
## Deferred Ideas

- Auto-connect for HR monitors — scope creep, belongs in future phase
- Dedicated HR monitor tab/UI — v3+ milestone
- Apple Watch HR data — different protocol, separate phase
- Third wearable type (WEAR-V3-01) — v3+ milestone per deferred list
- HR monitor-specific settings (alarm, clock sync) — not applicable to 0x180D devices

</deferred>

---

*Phase: 8-additional-wearables-e2e*
*Context gathered: 2026-06-03*
