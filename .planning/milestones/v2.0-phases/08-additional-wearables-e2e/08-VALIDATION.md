---
phase: 8
slug: additional-wearables-e2e
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-03
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `cargo test` (Rust), manual BLE testing (Swift — no Swift test target) |
| **Config file** | `Rust/core/Cargo.toml` |
| **Quick run command** | `cd Rust/core && cargo test --test heart_rate_gatt_protocol_tests 2>&1` |
| **Full suite command** | `cd Rust/core && cargo test 2>&1` |
| **Estimated runtime** | ~30 seconds (Rust full suite) |

---

## Sampling Rate

- **After every task commit:** Run `cd Rust/core && cargo test --test heart_rate_gatt_protocol_tests`
- **After every plan wave:** Run `cd Rust/core && cargo test`
- **Before `/gsd-verify-work`:** Full Rust suite must be green; Swift build must succeed
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | WEAR-01 | — | N/A | integration | `cd Rust/core && cargo test --test heart_rate_gatt_protocol_tests` | ❌ W0 | ⬜ pending |
| 08-01-02 | 01 | 1 | WEAR-01 | — | N/A | integration | `cd Rust/core && cargo test --test heart_rate_gatt_protocol_tests` | ❌ W0 | ⬜ pending |
| 08-02-01 | 02 | 1 | WEAR-02 | — | N/A | manual | Swift build succeeds + source assertion | ❌ W0 | ⬜ pending |
| 08-02-02 | 02 | 1 | WEAR-02 | — | N/A | manual | Swift build succeeds + source assertion | ❌ W0 | ⬜ pending |
| 08-03-01 | 03 | 2 | WEAR-03 | — | No silent Gen5 fallback | manual | Source assertion: GooseUploadService.swift does not contain `"5.0"` for unknown deviceType | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Rust/core/tests/heart_rate_gatt_protocol_tests.rs` — create integration test file with failing stubs for all WEAR-01 test cases
- [ ] `Rust/core/src/heart_rate_gatt_protocol.rs` — create module with `pub fn parse_hr_measurement` stub (returns Err)
- [ ] `Rust/core/src/lib.rs` — add `pub mod heart_rate_gatt_protocol;`

*These must exist before any plan executes so the `cargo test` command returns a meaningful result rather than compile error.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| HR monitor scan discovers BLE devices advertising 0x180D | WEAR-02 | No Swift test target; requires Bluetooth hardware | Start HR monitor scan in app; verify device appears in list |
| HR monitor notification routes to capture pipeline | WEAR-02 | Requires physical BLE device | Connect HR monitor; verify OSLog shows `capture.import.ok` for HR_MONITOR frames |
| Upload payload contains sanitized device name as device_type | WEAR-03 | Requires server + device | Upload HR monitor data; verify server receives correct device_type field |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
