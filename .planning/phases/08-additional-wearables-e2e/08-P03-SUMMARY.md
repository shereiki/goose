---
phase: "08"
plan: "08-P03"
subsystem: upload+rust-core
tags: [swift, rust, upload, device-type, hr-monitor, enum, taxonomy]
dependency_graph:
  requires:
    - phase: 08-additional-wearables-e2e
      plan: 08-P02
      provides: "GooseBLEHRMonitorManager with hrConnectionState, connectedDeviceName, hrPeripheral"
  provides:
    - "Silent WHOOP Gen5 fallback removed from GooseUploadService.performUpload"
    - "device_class: HR_MONITOR in upload payload for non-WHOOP devices"
    - "DeviceType::HrMonitor variant in Rust protocol.rs"
    - "parse_device_type(HR_MONITOR) => DeviceType::HrMonitor (not Goose)"
    - "triggerManualUpload derives WHOOP device type from activeDescriptor"
    - "WEAR-03 satisfied"
  affects:
    - 08-P04 (e2e verification uses the corrected upload taxonomy)
tech_stack:
  added: []
  patterns:
    - "switch deviceType in upload payload builder — explicit per-class payload construction"
    - "DeviceType::HrMonitor grouped with 8-byte family in protocol.rs match arms (compile-time formality; HrMonitor never reaches WHOOP frame parsing)"
    - "parse_device_type extension: case-insensitive HR_MONITOR/hr_monitor arm"
key_files:
  modified:
    - GooseSwift/GooseUploadService.swift
    - GooseSwift/GooseAppModel+Upload.swift
    - Rust/core/src/protocol.rs
    - Rust/core/src/bridge.rs
    - Rust/core/src/store.rs
    - Rust/core/src/openwhoop_reference.rs
decisions:
  - "switch deviceType replaces ternary in performUpload — three explicit cases: GEN4, GOOSE, default (HR monitor)"
  - "streams dictionary is factored out and shared identically across all three payload cases"
  - "HrMonitor grouped with Maverick/Puffin/Goose (8-byte family) in all protocol.rs match arms — compile-time formality; the variant never reaches parse_frame"
  - "whoop_generation_from_device_type: HrMonitor grouped with Puffin (returns None) — not a WHOOP device"
  - "parse_device_type tests use .expect().unwrap pattern — GooseError does not implement PartialEq so assert_eq! on GooseResult is not usable"
metrics:
  duration: "~25 minutes"
  completed: "2026-06-03"
  tasks_completed: 5
  files_created: 0
  files_modified: 6
---

# Phase 08 Plan 03: Upload Fix — Remove Silent Gen5 Fallback + device_class for HR Monitors + DeviceType::HrMonitor Summary

**One-liner:** Device-class-aware upload taxonomy with explicit GEN4/GOOSE/HR_MONITOR switch, DeviceType::HrMonitor Rust variant, and descriptor-derived WHOOP type in manual upload trigger.

## What Was Built

Resolved the ambiguous upload taxonomy (HIGH-1, HIGH-2 from cross-AI review) and the silent WHOOP Gen5 fallback flagged as WEAR-03.

**GooseUploadService.performUpload (T01):** Replaced the ternary `deviceType == "GEN4" ? "4.0" : "5.0"` with a `switch deviceType` that builds an explicit payload per device class:
- `case "GEN4"`: `device_generation: "4.0"`, no `device_class` key
- `case "GOOSE"`: `device_generation: "5.0"`, no `device_class` key
- `default`: `device_type: deviceType` (sanitized BLE name) + `device_class: "HR_MONITOR"` — the server can distinguish wearable class from model name
The `streams` dictionary (`hr`, `rr`, `events`, `battery`, `spo2`, `skin_temp`, `resp`, `gravity`) is factored out and byte-for-byte identical across all three cases.

**GooseAppModel+Upload.triggerManualUpload (T02):** Removed the hardcoded `deviceType: "GOOSE"` literal. Now:
1. WHOOP upload: derives device type from `ble.activeDescriptor.commandCharacteristicPrefix` — prefix starts with `"610800"` → `"GEN4"`, otherwise `"GOOSE"`. Only triggered when `ble.activeDeviceIdentifier` is non-nil.
2. HR monitor upload: triggered when `ble.hrMonitorManager.hrConnectionState != "disconnected"` and `hrPeripheral` is non-nil, passing `connectedDeviceName ?? "unknown_hr_monitor"` as `deviceType`.

**Rust DeviceType::HrMonitor (T03):** Added `HrMonitor` variant to the `DeviceType` enum in `protocol.rs`. Updated all exhaustive match arms:
- `header_len`, `expected_frame_len` — grouped with Maverick/Puffin/Goose (8-byte family)
- `declared_len`, `header_crc_valid` in `parse_frame` — same grouping
- `device_type_name` in `store.rs` — `HrMonitor => "HR_MONITOR"`
- `whoop_generation_from_device_type` in `openwhoop_reference.rs` — grouped with Puffin (`=> None`)
- `parse_device_type` in `bridge.rs` — `"HR_MONITOR" | "hr_monitor" => Ok(DeviceType::HrMonitor)` (NOT `DeviceType::Goose`)

**Rust tests (T04):** Added three tests inside the existing `#[cfg(test)] mod tests` block in `bridge.rs`:
- `parse_device_type_hr_monitor_uppercase`: `HR_MONITOR` => `DeviceType::HrMonitor`
- `parse_device_type_hr_monitor_lowercase`: `hr_monitor` => `DeviceType::HrMonitor`
- `parse_device_type_goose_no_regression`: `GOOSE` => `DeviceType::Goose`
Full `cargo test` suite: zero failures across all test files.

**Final assertions (T05):** All source assertions verified; no code changes required.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| P03-T01 | Remove silent Gen5 fallback; switch deviceType in performUpload; add device_class for HR monitors | d3e522b |
| P03-T02 | Derive WHOOP device type from activeDescriptor; add HR monitor upload path | e75ab30 |
| P03-T03 | Add DeviceType::HrMonitor variant; update all exhaustive match arms; cargo check passes | 515794a |
| P03-T04 | Add parse_device_type tests; full cargo test suite passes | 9a48d36 |
| P03-T05 | Final source assertions — all verified; no code changes needed | (verification only) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added HrMonitor arm to whoop_generation_from_device_type in openwhoop_reference.rs**
- **Found during:** T03 — cargo check revealed a non-exhaustive match in `src/openwhoop_reference.rs` (not listed in the plan's read_first files)
- **Issue:** `pub fn whoop_generation_from_device_type(device_type: DeviceType)` only handled `Gen4`, `Maverick`, `Goose`, `Puffin` — adding `HrMonitor` to the enum caused a compile error
- **Fix:** Added `DeviceType::HrMonitor` to the `Puffin` arm (`=> None`) since an HR monitor has no WHOOP generation
- **Files modified:** `Rust/core/src/openwhoop_reference.rs`
- **Committed in:** 515794a

**2. [Rule 1 - Bug] Changed parse_device_type tests to use .expect() instead of assert_eq! on GooseResult**
- **Found during:** T04 — `GooseError` does not derive `PartialEq`, so `assert_eq!(parse_device_type(...), Ok(DeviceType::HrMonitor))` would not compile
- **Fix:** Tests use `parse_device_type("...").expect("...")` + `assert_eq!(result, DeviceType::HrMonitor)` — verifies the exact variant as required by HIGH-2
- **Files modified:** `Rust/core/src/bridge.rs`
- **Committed in:** 9a48d36 (test commit, RED/GREEN not applicable — tests added with implementation in place per plan instruction for unit-test-inside-module pattern)

## Verification Results

```
1. grep -c 'GEN4" ? "4.0" : "5.0"' GooseUploadService.swift  => 0 (ternary removed)
2. grep -c '"device_class": "HR_MONITOR"' GooseUploadService.swift => 1
3. grep -c "DeviceType::HrMonitor" Rust/core/src/bridge.rs => 3
4. grep "HrMonitor" Rust/core/src/protocol.rs => 6 occurrences (enum + 4 match arms + 1 comment)
5. cargo test => zero failures across all test files
6. triggerManualUpload: no unconditional deviceType: "GOOSE" literal
7. device_type_name: DeviceType::HrMonitor => "HR_MONITOR" in store.rs
8. parse_device_type: "HR_MONITOR" | "hr_monitor" => Ok(DeviceType::HrMonitor) in bridge.rs
```

## Known Stubs

None. All functionality is complete and wired.

## Threat Flags

No new network endpoints, auth paths, or schema changes introduced. The upload payload structure change is backward-compatible on the server side (new keys in the HR monitor case only; WHOOP payloads structurally unchanged).

## Self-Check: PASSED

- [x] `GooseSwift/GooseUploadService.swift` — ternary removed, switch deviceType present, device_class in default case
- [x] `GooseSwift/GooseAppModel+Upload.swift` — no hardcoded "GOOSE" in triggerManualUpload; HR monitor upload path present
- [x] `Rust/core/src/protocol.rs` — HrMonitor variant + 4 match arm groupings (6 grep hits)
- [x] `Rust/core/src/store.rs` — `DeviceType::HrMonitor => "HR_MONITOR"` present
- [x] `Rust/core/src/bridge.rs` — `"HR_MONITOR" | "hr_monitor" => Ok(DeviceType::HrMonitor)` present; 3 parse_device_type tests added
- [x] `Rust/core/src/openwhoop_reference.rs` — HrMonitor handled in whoop_generation_from_device_type
- [x] Commits d3e522b, e75ab30, 515794a, 9a48d36 verified in git log
- [x] `cargo test` full suite: zero failures
- [x] WEAR-03 requirement satisfied
