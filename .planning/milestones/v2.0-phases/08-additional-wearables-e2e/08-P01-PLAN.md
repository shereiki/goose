---
phase: "08"
plan: "08-P01"
title: "Rust 0x2A37 HR GATT Parser + Integration Tests"
wave: 1
depends_on: []
files_modified:
  - Rust/core/src/heart_rate_gatt_protocol.rs
  - Rust/core/src/lib.rs
  - Rust/core/tests/heart_rate_gatt_protocol_tests.rs
autonomous: true
requirements:
  - WEAR-01
---

<objective>
Addresses D-02 (separate HR GATT parser file) and WEAR-01.
Create `Rust/core/src/heart_rate_gatt_protocol.rs` — a new Rust module that parses the standard
Bluetooth 0x2A37 HR Measurement characteristic format. All 0x2A37 fields are supported: HR value
(8-bit or 16-bit via flags bit 0), RR intervals (flags bit 4), energy expended (flags bit 3), and
sensor contact status (flags bits 1–2). Integration tests in
`Rust/core/tests/heart_rate_gatt_protocol_tests.rs` cover the standard encoding variants. The
module is registered in `lib.rs`.
</objective>

<must_haves>
  <truths>
    - D-02: New file `Rust/core/src/heart_rate_gatt_protocol.rs` is created in this plan — HR GATT parsing is kept separate from WHOOP protocol parsing in `protocol.rs`
    - WEAR-01: `Rust/core/src/heart_rate_gatt_protocol.rs` exists with a public `parse_hr_measurement(data: &[u8])` function that correctly decodes 0x2A37 payloads
    - `HrMeasurement` struct has fields: `hr_bpm: u16`, `rr_intervals_ms: Vec<f64>`, `energy_expended_kj: Option<u16>`, `sensor_contact: Option<bool>`
    - `Rust/core/tests/heart_rate_gatt_protocol_tests.rs` exists with tests covering: 8-bit HR only, 16-bit HR, HR + RR intervals, HR + energy expended, all fields, zero-length/truncated input
    - `Rust/core/src/lib.rs` has `pub mod heart_rate_gatt_protocol;` (inserted alphabetically)
    - `cargo test --test heart_rate_gatt_protocol_tests` passes with zero failures
    - `cargo test` (full suite) continues to pass
  </truths>
</must_haves>

<threat_model>
  <threats>
    <threat id="T-08-01" severity="low">
      Malformed 0x2A37 payloads (truncated, empty, or invalid flags). Mitigation: `parse_hr_measurement` returns `Err` on any input shorter than 2 bytes; all bit-field reads are bounds-checked before access.
    </threat>
  </threats>
</threat_model>

<tasks>

  <task id="P01-T01" type="execute">
    <title>Create heart_rate_gatt_protocol.rs with HrMeasurement struct and parser</title>
    <read_first>
      - Rust/core/src/lib.rs (module list to know insertion point)
      - Rust/core/src/protocol.rs (DeviceType enum, parse_frame pattern — for code style reference)
      - GooseSwift/GooseBLEClient+Parsing.swift (lines 502–535 — Swift reference implementation of the same 0x2A37 parser; use as test-vector source of truth)
      - .planning/phases/08-additional-wearables-e2e/08-CONTEXT.md (D-01 flags bit layout, HrMeasurement struct shape)
      - .planning/phases/08-additional-wearables-e2e/08-RESEARCH.md (F-07 — module structure, RR interval unit note)
    </read_first>
    <action>
      Create `Rust/core/src/heart_rate_gatt_protocol.rs` with:

      1. Public struct `HrMeasurement`:
         - `pub hr_bpm: u16`
         - `pub rr_intervals_ms: Vec<f64>` — converted from raw 1/1024-sec units via `raw as f64 * 1000.0 / 1024.0` (matches Swift reference)
         - `pub energy_expended_kj: Option<u16>` — present when flags bit 3 is set
         - `pub sensor_contact: Option<bool>` — present when flags bits 1–2 indicate supported; `Some(true)` when contact detected (bits 1–2 == 0b11), `Some(false)` when not detected (bits 1–2 == 0b10), `None` when sensor contact not supported (bits 1–2 == 0b00 or 0b01)

      2. Public function `pub fn parse_hr_measurement(data: &[u8]) -> Result<HrMeasurement, String>`:
         - Returns `Err("hr_measurement: data too short".to_string())` if `data.len() < 2`
         - Reads `flags = data[0]`
         - `offset = 1`
         - HR value: if `flags & 0x01 == 0` → `hr_bpm = data[offset] as u16`, advance offset 1; else if `data.len() >= offset + 2` → `hr_bpm = u16::from_le_bytes([data[offset], data[offset+1]])`, advance offset 2; else return `Err("hr_measurement: truncated 16-bit hr".to_string())`
         - Sensor contact: `if flags & 0x04 != 0 { None } else { None }` — extract bits 1–2: `let sc_bits = (flags >> 1) & 0x03;` → `Some(true)` if `sc_bits == 3`, `Some(false)` if `sc_bits == 2`, `None` otherwise
         - Energy expended: if `flags & 0x08 != 0`, consume 2 bytes at offset if available, set `energy_expended_kj = Some(u16::from_le_bytes([data[offset], data[offset+1]]))`, advance offset 2; if not enough bytes, advance past and set `None`
         - RR intervals: if `flags & 0x10 != 0`, while `data.len() >= offset + 2`, read `raw = u16::from_le_bytes([data[offset], data[offset+1]])`, push `raw as f64 * 1000.0 / 1024.0`, advance offset 2

      3. Derive `#[derive(Debug, Clone, PartialEq)]` on `HrMeasurement`.

      File header should include a comment: `// Standard Bluetooth 0x2A37 HR Measurement characteristic parser.`
    </action>
    <acceptance_criteria>
      - `Rust/core/src/heart_rate_gatt_protocol.rs` exists
      - Contains `pub struct HrMeasurement` with fields `hr_bpm: u16`, `rr_intervals_ms: Vec<f64>`, `energy_expended_kj: Option<u16>`, `sensor_contact: Option<bool>`
      - Contains `pub fn parse_hr_measurement(data: &[u8]) -> Result<HrMeasurement, String>`
      - `cargo check` succeeds with no compile errors in the new file
    </acceptance_criteria>
  </task>

  <task id="P01-T02" type="execute">
    <title>Register heart_rate_gatt_protocol in lib.rs</title>
    <read_first>
      - Rust/core/src/lib.rs (full file — insert in alphabetical order)
    </read_first>
    <action>
      In `Rust/core/src/lib.rs`, insert `pub mod heart_rate_gatt_protocol;` in the alphabetically
      correct position — between `pub mod health_sync;` and `pub mod historical_sync;`.
    </action>
    <acceptance_criteria>
      - `Rust/core/src/lib.rs` contains `pub mod heart_rate_gatt_protocol;`
      - The line appears between `pub mod health_sync;` and `pub mod historical_sync;`
      - `cargo build` succeeds with no errors
    </acceptance_criteria>
  </task>

  <task id="P01-T03" type="tdd">
    <title>Create heart_rate_gatt_protocol_tests.rs with all standard encoding variant tests</title>
    <read_first>
      - Rust/core/tests/protocol_tests.rs (test file structure pattern — plain #[test], no async, use assertions)
      - Rust/core/src/heart_rate_gatt_protocol.rs (HrMeasurement struct and parse_hr_measurement signature)
      - GooseSwift/GooseBLEClient+Parsing.swift (lines 502–535 — Swift reference for test vector derivation)
      - .planning/phases/08-additional-wearables-e2e/08-RESEARCH.md (F-07 — test cases to cover)
      - .planning/phases/08-additional-wearables-e2e/08-PATTERNS.md (Pattern: Rust Integration Test File — example test structure)
    </read_first>
    <action>
      Create `Rust/core/tests/heart_rate_gatt_protocol_tests.rs` with these test functions:

      1. `test_parses_8bit_hr_only` — flags=0x00, data=[0x00, 72], assert hr_bpm=72, rr_intervals empty, energy None, sensor_contact None
      2. `test_parses_16bit_hr` — flags=0x01, data=[0x01, 0xC4, 0x00] (HR=196 via 0x00C4 LE), assert hr_bpm=196
      3. `test_parses_hr_with_rr_intervals` — flags=0x10, data=[0x10, 60, 0x00, 0x04, 0x00, 0xFF] where bytes 3–4 = RR1 = 0x0400 = 1024 → rr_ms = 1000.0ms, bytes 5–6 incomplete so only one RR; assert rr_intervals_ms.len()==1 and approximately 1000.0
      4. `test_parses_hr_with_energy_expended` — flags=0x08, data=[0x08, 75, 0xE8, 0x03] (energy=1000 kJ), assert energy_expended_kj=Some(1000)
      5. `test_parses_all_fields` — flags=0b00011010 (bits: 16-bit HR, sensor contact supported+detected, energy, RR), compose a valid payload with all fields; assert all fields populated
      6. `test_returns_error_on_empty_data` — assert `parse_hr_measurement(&[]).is_err()`
      7. `test_returns_error_on_single_byte` — assert `parse_hr_measurement(&[0x00]).is_err()`
      8. `test_16bit_hr_truncated_returns_error` — flags=0x01 (16-bit), data=[0x01, 0xC4] (only 1 byte for HR value), assert result is `Err`
      9. `test_sensor_contact_not_detected` — flags has bits 1–2 = 0b10 (supported, not detected), assert `sensor_contact == Some(false)`
      10. `test_sensor_contact_detected` — flags has bits 1–2 = 0b11 (detected), assert `sensor_contact == Some(true)`

      Use `use goose_core::heart_rate_gatt_protocol::{HrMeasurement, parse_hr_measurement};` at top.
      Use `#[test]` (no async). Use `assert_eq!` and `assert!(...)`. For floating-point RR intervals, use `(result - expected).abs() < 0.01`.
    </action>
    <acceptance_criteria>
      - `Rust/core/tests/heart_rate_gatt_protocol_tests.rs` exists with at least 8 `#[test]` functions
      - `cargo test --test heart_rate_gatt_protocol_tests` passes with 0 failures
      - Tests cover: 8-bit HR, 16-bit HR, RR intervals, energy expended, all fields, error cases
    </acceptance_criteria>
  </task>

  <task id="P01-T04" type="execute">
    <title>Verify full cargo test suite still passes</title>
    <read_first>
      - Rust/core/src/heart_rate_gatt_protocol.rs (current state after T01)
      - Rust/core/src/lib.rs (current state after T02)
    </read_first>
    <action>
      Run `cargo test` from `Rust/core/` and confirm zero test failures. If any tests fail due to
      the new module (e.g., missing pub visibility on HrMeasurement or parse_hr_measurement),
      fix the visibility. Do not modify any existing passing tests.
    </action>
    <acceptance_criteria>
      - `cd Rust/core && cargo test 2>&1` exits 0
      - Output contains `test result: ok` for all test files including `heart_rate_gatt_protocol_tests`
      - No regression in existing test suite
    </acceptance_criteria>
  </task>

</tasks>

<verification>
  1. `ls Rust/core/src/heart_rate_gatt_protocol.rs` — file exists
  2. `grep "pub mod heart_rate_gatt_protocol" Rust/core/src/lib.rs` — module registered
  3. `ls Rust/core/tests/heart_rate_gatt_protocol_tests.rs` — test file exists
  4. `cd Rust/core && cargo test --test heart_rate_gatt_protocol_tests 2>&1 | tail -5` — exits 0, `test result: ok`
  5. `cd Rust/core && cargo test 2>&1 | tail -5` — full suite passes
</verification>

<success_criteria>
  - [ ] `Rust/core/src/heart_rate_gatt_protocol.rs` exists with `pub fn parse_hr_measurement` and `pub struct HrMeasurement`
  - [ ] `lib.rs` registers the new module alphabetically
  - [ ] Integration tests exist covering all WEAR-01 encoding variants
  - [ ] `cargo test --test heart_rate_gatt_protocol_tests` passes
  - [ ] `cargo test` (full suite) passes with no regressions
  - [ ] WEAR-01 requirement is fully satisfied
</success_criteria>
