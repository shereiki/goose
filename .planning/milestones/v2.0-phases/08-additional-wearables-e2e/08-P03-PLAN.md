---
phase: "08"
plan: "08-P03"
title: "Upload Fix: Remove Silent Gen5 Fallback + device_class for HR Monitors + DeviceType::HrMonitor"
wave: 2
depends_on: ["08-P02"]
files_modified:
  - GooseSwift/GooseUploadService.swift
  - GooseSwift/GooseAppModel+Upload.swift
  - Rust/core/src/protocol.rs
  - Rust/core/src/bridge.rs
  - Rust/core/src/store.rs
  - Rust/core/tests/bridge_tests.rs
autonomous: true
requirements:
  - WEAR-03
---

<objective>
Addresses D-04 (reuse existing WHOOP frames table, no migration), WEAR-03, and cross-AI review
HIGH-1 / HIGH-2.

Fix `GooseUploadService` to remove the silent WHOOP Gen5 fallback (`"5.0"`) that incorrectly labels
HR monitor upload data as Gen5. After this plan, the upload payload identifies HR monitor data using
TWO explicit fields: `device_type` = sanitized BLE-advertised device name (e.g., `"Polar H10"`) AND
`device_class: "HR_MONITOR"` (review HIGH-1 — makes the class-vs-model distinction explicit without
breaking the server ingest schema). WHOOP Gen4/Gen5 payloads are unchanged (no `device_class` field).

On the Rust side, add a real `DeviceType::HrMonitor` enum variant (review HIGH-2) instead of aliasing
HR monitors to `DeviceType::Goose`, so downstream analytics/debugging never treat HR data as
WHOOP-like. Storage behavior is unchanged — HR frames remain raw evidence in the existing frames
table, filtered by `device_type` string; `parse_device_type("HR_MONITOR")` now returns the new variant.

`triggerManualUpload()` in `GooseAppModel+Upload.swift` is updated to derive the correct device type
from the active connection rather than hardcoding `"GOOSE"`.

Purpose: Resolve the ambiguous upload taxonomy and the weak-extensibility enum mapping flagged in
cross-AI review, fully satisfying WEAR-03.
Output: A correct, class-aware upload payload and a first-class `DeviceType::HrMonitor` variant.
</objective>

<must_haves>
  <truths>
    - D-04: HR monitor frames reuse the existing WHOOP frames/raw_evidence table — no new table migration is created in this phase
    - HIGH-2: `Rust/core/src/protocol.rs` `DeviceType` enum has an `HrMonitor` variant; `parse_device_type("HR_MONITOR")` returns `DeviceType::HrMonitor` (NOT `DeviceType::Goose`)
    - WEAR-03: `GooseUploadService.performUpload` does NOT contain the expression `deviceType == "GEN4" ? "4.0" : "5.0"` — the silent Gen5 fallback is removed
    - HIGH-1: the upload payload for HR monitor data contains BOTH `device_type` (sanitized BLE device name, e.g. `"Polar H10"`) AND `device_class: "HR_MONITOR"`
    - WHOOP Gen5 upload still works: `deviceType == "GOOSE"` produces `device_generation: "5.0"` and NO `device_class` key
    - WHOOP Gen4 upload still works: `deviceType == "GEN4"` produces `device_generation: "4.0"` and NO `device_class` key
    - `triggerManualUpload()` no longer hardcodes `deviceType: "GOOSE"` — it derives the correct device type from the active connection
    - `parse_device_type("HR_MONITOR")` and `parse_device_type("hr_monitor")` both return `Ok(DeviceType::HrMonitor)`
  </truths>
  <artifacts>
    - path: "Rust/core/src/protocol.rs"
      provides: "DeviceType::HrMonitor variant"
      contains: "HrMonitor"
    - path: "GooseSwift/GooseUploadService.swift"
      provides: "device_class-aware upload payload, no silent Gen5 fallback"
  </artifacts>
  <key_links>
    - from: "GooseUploadService.performUpload (default case)"
      to: "server ingest payload"
      via: "device_type + device_class keys for HR monitor"
    - from: "bridge.rs parse_device_type"
      to: "protocol.rs DeviceType::HrMonitor"
      via: "string match arm HR_MONITOR/hr_monitor"
  </key_links>
</must_haves>

<threat_model>
  <threats>
    <threat id="T-08-04" severity="low">
      BLE-advertised device names could be unexpectedly long or contain special characters that cause JSON serialization issues. Mitigation: device name sanitization (trim + max 64 chars + empty fallback) is applied in `GooseBLEHRMonitorManager` (Plan 2) before the name is used as `deviceType`; the upload service relies on the pre-sanitized value.
    </threat>
    <threat id="T-08-05" severity="low">
      Changing the upload payload structure for WHOOP devices could break the server ingest endpoint. Mitigation: WHOOP payloads are unchanged — `device_generation: "4.0"`/`"5.0"` continue as before with NO `device_class` key added. Only HR monitor payloads gain `device_type` + `device_class`.
    </threat>
    <threat id="T-08-07" severity="medium">
      Adding `DeviceType::HrMonitor` introduces a new enum variant that exhaustive `match` arms in protocol.rs and store.rs must handle, or the crate will not compile. Mitigation: P03-T03 updates every exhaustive match (header_len, expected_frame_len, declared_len, header_crc_valid in protocol.rs; device_type_name in store.rs) and `cargo test` verifies the full suite compiles and passes.
    </threat>
  </threats>
</threat_model>

<tasks>

  <task id="P03-T01" type="execute">
    <title>Fix GooseUploadService.performUpload: remove silent Gen5 fallback, add device_class for HR monitors</title>
    <read_first>
      - GooseSwift/GooseUploadService.swift (full file — focus on lines 86–94: the `deviceGeneration` mapping and payload construction; capture the exact `streams` dictionary literal)
      - .planning/phases/08-additional-wearables-e2e/08-CONTEXT.md (D-06: device_type = BLE-advertised device name, sanitized; D-05: server receives as-is)
      - .planning/phases/08-additional-wearables-e2e/08-RESEARCH.md (F-04: the exact silent fallback code that must be replaced)
      - .planning/phases/08-additional-wearables-e2e/08-REVIEWS.md (HIGH-1: add device_class: "HR_MONITOR" alongside device_type; WHOOP payloads unchanged)
      - .planning/REQUIREMENTS.md — WEAR-03
    </read_first>
    <action>
      In `GooseSwift/GooseUploadService.performUpload`, remove the ternary
      `let deviceGeneration = deviceType == "GEN4" ? "4.0" : "5.0"` and replace the single payload literal
      with a `switch deviceType` that builds the payload per device class. The `device` dictionary and the
      `streams` dictionary MUST be byte-for-byte identical across all three cases — copy the existing
      `streams` literal exactly (`hr`, `rr`, `events`, `battery`, `spo2`, `skin_temp`, `resp`, `gravity`)
      so WHOOP payload structure is provably unchanged.

      Cases:
      - `case "GEN4":` payload contains `"device_generation": "4.0"`, and NO `device_class` key.
      - `case "GOOSE":` payload contains `"device_generation": "5.0"`, and NO `device_class` key.
      - `default:` (HR monitor or any future non-WHOOP device): payload contains `"device_type": deviceType`
        (the pre-sanitized BLE device name) AND `"device_class": "HR_MONITOR"`. Do NOT include a
        `device_generation` key in this case. Add a comment explaining: `device_type` carries the model/name,
        `device_class` carries the wearable class so the server can distinguish class from model (review HIGH-1).

      Do not change any other part of `performUpload` (auth header, URL, encoding, response handling).
    </action>
    <acceptance_criteria>
      - `grep -c "GEN4\" ? \"4.0\" : \"5.0\"" GooseSwift/GooseUploadService.swift` returns 0 (ternary fallback removed)
      - `GooseUploadService.swift` contains a `switch deviceType` with explicit `case "GEN4"` and `case "GOOSE"`
      - The `default` case contains BOTH `"device_type": deviceType` AND `"device_class": "HR_MONITOR"`
      - Neither the `"GEN4"` nor the `"GOOSE"` case contains a `device_class` key
      - The `streams` dictionary literal is identical across all three cases
      - Swift build succeeds with no compile errors
    </acceptance_criteria>
  </task>

  <task id="P03-T02" type="execute">
    <title>Fix triggerManualUpload in GooseAppModel+Upload.swift to derive device type from the active connection</title>
    <read_first>
      - GooseSwift/GooseAppModel+Upload.swift (full file — triggerManualUpload currently hardcodes "GOOSE")
      - GooseSwift/GooseAppModel.swift (lines 1–100 — confirm how the BLE client is referenced; check for activeDescriptor / generation state)
      - GooseSwift/GooseBLEClient+HRMonitor.swift (GooseBLEHRMonitorManager: hrPeripheral, hrConnectionState, connectedDeviceName — confirm they are internal/accessible from Plan 2)
      - GooseSwift/GooseBLEClient.swift + GooseSwift/GooseBLEClient+Commands.swift (check for an existing `activeDescriptor: WearableDescriptor?` or a `generation` field on discovered/remembered devices from Phase 6)
      - .planning/phases/08-additional-wearables-e2e/08-RESEARCH.md (F-10: manual upload trigger context)
    </read_first>
    <action>
      Update `triggerManualUpload()` so it no longer passes the string literal `"GOOSE"`. Compute
      `sinceTimestamp` as before. Then:

      1. WHOOP upload: if `ble.activeDeviceIdentifier` is non-nil, derive the WHOOP device type from the
         Phase 6 generation signal. Prefer an existing `ble.activeDescriptor` if Phase 6 added one — map it
         to `"GEN4"` when its `commandCharacteristicPrefix` begins with `"610800"`, else `"GOOSE"`. If no
         `activeDescriptor` exists, fall back to the discovered/remembered device `generation` field
         (`"4.0"` → `"GEN4"`, otherwise `"GOOSE"`). Call
         `uploadService.upload(deviceID: <activeDeviceIdentifier>, deviceType: <derivedWhoopType>, sinceTimestamp: sinceTimestamp)`.
         Before implementing, READ `GooseBLEClient.swift`/`+Commands.swift` to determine which of these
         signals actually exists in the current code — use the one that is present; do not invent a property.

      2. HR monitor upload: read `ble.hrMonitorManager`. If `hrConnectionState != "disconnected"` and
         `hrPeripheral` is non-nil, call
         `uploadService.upload(deviceID: hrPeripheral.identifier, deviceType: (connectedDeviceName ?? "unknown_hr_monitor"), sinceTimestamp: sinceTimestamp)`.
         Because `connectedDeviceName` is the sanitized BLE advertised name, the upload service `default`
         case (P03-T01) will tag it with `device_class: "HR_MONITOR"`.

      If the chosen WHOOP-type signal is not yet exposed, raise the access level (private → internal) of the
      backing property rather than hardcoding a generation. Do NOT reintroduce a `"GOOSE"` string literal as
      an unconditional default.
    </action>
    <acceptance_criteria>
      - `grep "triggerManualUpload" -A20 GooseSwift/GooseAppModel+Upload.swift` shows NO unconditional `deviceType: "GOOSE"` string literal
      - `triggerManualUpload()` derives the WHOOP device type from `activeDescriptor` or a `generation` field
      - HR monitor upload is triggered when `ble.hrMonitorManager.hrConnectionState != "disconnected"`, passing `connectedDeviceName` (or `"unknown_hr_monitor"`) as `deviceType`
      - Swift build succeeds with no compile errors
    </acceptance_criteria>
  </task>

  <task id="P03-T03" type="execute">
    <title>Add DeviceType::HrMonitor variant in protocol.rs and update all exhaustive match arms</title>
    <read_first>
      - Rust/core/src/protocol.rs (lines 24–59: DeviceType enum + header_len + expected_frame_len; lines 240–275: declared_len and header_crc_valid match arms; confirm these are the only exhaustive matches on DeviceType in this file)
      - Rust/core/src/store.rs (lines 7543–7550: device_type_name exhaustive match — must add HrMonitor arm)
      - Rust/core/src/bridge.rs (lines 7956–7966: parse_device_type)
      - .planning/phases/08-additional-wearables-e2e/08-REVIEWS.md (HIGH-2: add real DeviceType::HrMonitor; map HR_MONITOR to it, not Goose; storage unchanged)
      - .planning/phases/08-additional-wearables-e2e/08-CONTEXT.md (D-04: reuse existing frames table, no migration)
    </read_first>
    <action>
      In `Rust/core/src/protocol.rs`, add `HrMonitor` to the `DeviceType` enum (after `Goose`). The enum
      derives `Serialize`/`Deserialize` with `#[serde(rename_all = "SCREAMING_SNAKE_CASE")]`, so the new
      variant serializes as `"HR_MONITOR"` automatically — confirm this matches the wire string.

      Update every exhaustive `match self` / `match device_type` in protocol.rs to handle `HrMonitor`.
      Because HR monitor data is standard GATT bytes that never flow through WHOOP frame parsing
      (`parse_frame`/`parse_frame_hex` are never called with `DeviceType::HrMonitor` — Plan 2 stores HR
      bytes as raw evidence), the new arm only needs to compile safely. Add `HrMonitor` to the existing
      8-byte family arm (i.e., the `DeviceType::Maverick | DeviceType::Puffin | DeviceType::Goose` arms) in:
      - `header_len()` (line ~37)
      - `expected_frame_len()` (line ~50)
      - the `declared_len` match (line ~250)
      - the `header_crc_valid` match (line ~261)
      Add a brief comment on one of these arms noting HrMonitor never reaches frame parsing (raw-evidence
      storage only); grouping it with the 8-byte family is a compile-time formality.

      In `Rust/core/src/store.rs`, add `DeviceType::HrMonitor => "HR_MONITOR",` to the `device_type_name`
      match (line ~7543).

      In `Rust/core/src/bridge.rs` `parse_device_type` (line ~7956), add the arm
      `"HR_MONITOR" | "hr_monitor" => Ok(DeviceType::HrMonitor),` (NOT `DeviceType::Goose`). Place it after
      the `"GOOSE"` arm.

      After editing, run `cargo check` from `Rust/core/` and resolve any remaining non-exhaustive-match
      compile errors by adding an `HrMonitor` arm consistent with the surrounding logic. Do NOT add a
      catch-all `_ =>` arm to the `DeviceType` matches — keep them exhaustive so future variants are caught
      by the compiler.
    </action>
    <acceptance_criteria>
      - `grep -c "HrMonitor" Rust/core/src/protocol.rs` returns at least 5 (enum variant + 4 match arms)
      - `Rust/core/src/store.rs` `device_type_name` contains `DeviceType::HrMonitor => "HR_MONITOR"`
      - `Rust/core/src/bridge.rs` `parse_device_type` contains `"HR_MONITOR" | "hr_monitor" => Ok(DeviceType::HrMonitor)`
      - `parse_device_type` does NOT map HR_MONITOR to `DeviceType::Goose`
      - `cd Rust/core && cargo check` succeeds with no errors
      - No catch-all `_ =>` arm was added to any `DeviceType` match
    </acceptance_criteria>
  </task>

  <task id="P03-T04" type="tdd">
    <title>Add Rust tests asserting parse_device_type returns DeviceType::HrMonitor and verify full suite</title>
    <read_first>
      - Rust/core/tests/bridge_tests.rs (existing bridge test file from Phase 6 — test structure; check whether parse_device_type is reachable from integration tests or only via a #[cfg(test)] module in bridge.rs)
      - Rust/core/src/bridge.rs (current state after T03 — parse_device_type with HR_MONITOR arm; check if parse_device_type is pub or private)
      - .planning/phases/08-additional-wearables-e2e/08-REVIEWS.md (HIGH-2: assert parse_device_type("HR_MONITOR") returns HrMonitor)
    </read_first>
    <action>
      Add a test that asserts `parse_device_type("HR_MONITOR")` and `parse_device_type("hr_monitor")` both
      return `Ok(DeviceType::HrMonitor)` (assert the exact variant via `==`, not just `.is_ok()` — review
      HIGH-2 wants the variant verified). Also assert `parse_device_type("GOOSE")` still returns
      `Ok(DeviceType::Goose)` to prove no regression.

      `parse_device_type` is currently private to `bridge.rs`. Prefer adding a `#[cfg(test)] mod tests`
      block inside `bridge.rs` (with `use super::*;`) containing the assertions, so the private function is
      directly testable. If a suitable `#[cfg(test)]` module already exists in `bridge.rs`, add the test
      there instead of creating a duplicate module.

      Then run the full Rust suite (`cargo test` from `Rust/core/`) and confirm zero failures and no
      regression from the new `HrMonitor` variant. Fix any newly-revealed non-exhaustive match in a way
      consistent with T03 (group with the 8-byte family or add `"HR_MONITOR"` name mapping); do not modify
      existing passing tests' expectations.
    </action>
    <acceptance_criteria>
      - A test asserts `parse_device_type("HR_MONITOR") == Ok(DeviceType::HrMonitor)` and `parse_device_type("hr_monitor") == Ok(DeviceType::HrMonitor)`
      - A test asserts `parse_device_type("GOOSE") == Ok(DeviceType::Goose)` (no regression)
      - `cd Rust/core && cargo test 2>&1 | tail -10` exits 0 with `test result: ok` for all test files
      - No existing passing test was modified to accommodate the change
    </acceptance_criteria>
  </task>

  <task id="P03-T05" type="execute">
    <title>Final source assertions: fallback removed, device_class present, HrMonitor wired</title>
    <read_first>
      - GooseSwift/GooseUploadService.swift (current state after T01)
      - GooseSwift/GooseAppModel+Upload.swift (current state after T02)
      - Rust/core/src/protocol.rs, Rust/core/src/bridge.rs, Rust/core/src/store.rs (current state after T03/T04)
    </read_first>
    <action>
      Run the following source assertions and the Rust suite; fix any failure without breaking existing tests:

      1. `grep -c "GEN4\" ? \"4.0\" : \"5.0\"" GooseSwift/GooseUploadService.swift` — must return 0.
      2. `grep -c "device_class\": \"HR_MONITOR\"" GooseSwift/GooseUploadService.swift` — must return at least 1.
      3. `grep -c "DeviceType::HrMonitor" Rust/core/src/bridge.rs` — must return at least 1.
      4. `grep "HrMonitor" Rust/core/src/protocol.rs` — variant + match arms present.
      5. `cd Rust/core && cargo test 2>&1 | tail -10` — exits 0.

      Confirm the Swift project still builds (Xcode build or xcodebuild on iOS Simulator). Do not break the
      GooseSwiftTests target.
    </action>
    <acceptance_criteria>
      - `GooseUploadService.swift` source does not contain the ternary `"GEN4" ? "4.0" : "5.0"` fallback
      - `GooseUploadService.swift` contains `"device_class": "HR_MONITOR"` in the default case
      - `bridge.rs` `parse_device_type` returns `Ok(DeviceType::HrMonitor)` for `"HR_MONITOR"`
      - `cargo test` passes; Swift build succeeds
    </acceptance_criteria>
  </task>

</tasks>

<verification>
  1. `grep "GEN4\" ? \"4.0\" : \"5.0\"" GooseSwift/GooseUploadService.swift` — zero matches (fallback gone)
  2. `grep "device_class\": \"HR_MONITOR\"" GooseSwift/GooseUploadService.swift` — present in default case
  3. `grep "HrMonitor" Rust/core/src/protocol.rs` — enum variant + match arms present
  4. `grep "DeviceType::HrMonitor" Rust/core/src/bridge.rs` — parse_device_type maps HR_MONITOR to HrMonitor
  5. `grep "DeviceType::HrMonitor => \"HR_MONITOR\"" Rust/core/src/store.rs` — device_type_name arm present
  6. `cd Rust/core && cargo test 2>&1 | grep -E "FAILED|test result"` — test result: ok
  7. `grep "triggerManualUpload" -A20 GooseSwift/GooseAppModel+Upload.swift` — no unconditional hardcoded "GOOSE"
</verification>

<success_criteria>
  - [ ] Silent WHOOP Gen5 fallback removed from `GooseUploadService.performUpload`
  - [ ] HR monitor upload payload contains BOTH `device_type` (sanitized name) AND `device_class: "HR_MONITOR"`
  - [ ] WHOOP Gen4 and Gen5 upload payloads are structurally unchanged (no `device_class` key)
  - [ ] `triggerManualUpload()` no longer hardcodes `deviceType: "GOOSE"`
  - [ ] `DeviceType::HrMonitor` variant added; `parse_device_type("HR_MONITOR")` returns it (not Goose)
  - [ ] All exhaustive DeviceType matches in protocol.rs and store.rs handle HrMonitor
  - [ ] `cargo test` passes; Rust tests assert the HrMonitor variant
  - [ ] WEAR-03 requirement is fully satisfied
</success_criteria>
