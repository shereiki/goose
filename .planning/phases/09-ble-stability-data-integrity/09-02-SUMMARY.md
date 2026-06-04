---
phase: 09-ble-stability-data-integrity
plan: "02"
subsystem: rust-core
tags: [device-id, capture-sessions, bridge, fix-01, d-02, regression-test]
dependency_graph:
  requires:
    - 09-01 (bridge.rs edits landed via cherry-pick before this plan)
  provides:
    - active_device_id field on CaptureImportFrameBatchArgs (FIX-01)
    - active_device_id field on CapturedFrameBatchOptions (FIX-01)
    - GooseStore::set_capture_session_device_id (new store method)
    - FIX-01 device_id propagation logic in import_captured_frame_batch_with_output_options_in_transaction
    - D-02 regression test: device_type separation HR vs Goose
  affects:
    - Rust/core/src/bridge.rs
    - Rust/core/src/capture_import.rs
    - Rust/core/src/store.rs
    - Rust/core/tests/capture_import_tests.rs
    - Rust/core/tests/export_tests.rs
    - Rust/core/tests/history_sync_tests.rs
    - Rust/core/tests/metric_features_tests.rs
    - Rust/core/tests/metric_feature_report_cli_tests.rs
    - Rust/core/tests/capture_correlation_tests.rs
    - Rust/core/tests/local_health_validation_suite_cli_tests.rs
    - Rust/core/tests/metric_readiness_tests.rs
    - Rust/core/tests/sleep_validation_tests.rs
    - Rust/core/tests/step_motion_estimator_tests.rs
    - Rust/core/src/perf_budget.rs
tech_stack:
  added: []
  patterns:
    - "Optional field with #[serde(default)] on bridge args struct for backward-compatible wire format extension"
    - "WHERE active_device_id IS NULL guard on UPDATE for idempotent device_id backfill"
    - "BTreeSet deduplication of capture_session_id refs from frame batch before UPDATE loop"
decisions:
  - "active_device_id propagation implemented in import_captured_frame_batch_with_output_options_in_transaction after frame loop: collect distinct capture_session_ids from frames, call GooseStore::set_capture_session_device_id for each — cleaner than modifying the SQLite path and avoids creating sessions in the batch import function"
  - "GooseStore::set_capture_session_device_id added to store.rs instead of raw SQL in capture_import.rs — keeps SQL private to store layer"
  - "D-02 regression test added to capture_import_tests.rs using store.decoded_frames_between (avoids bridge JSON overhead); bridge_tests.rs device_id tests untouched per plan"
  - "Worktree did not have Plan 01 changes — cherry-picked commits 8645088 fa9b41f 71686d6 before starting Plan 02 tasks"
key_files:
  created: []
  modified:
    - Rust/core/src/bridge.rs
    - Rust/core/src/capture_import.rs
    - Rust/core/src/store.rs
    - Rust/core/tests/capture_import_tests.rs
    - "Rust/core/tests/{export,history_sync,metric_features,metric_feature_report_cli,capture_correlation,local_health_validation_suite_cli,metric_readiness,sleep_validation,step_motion_estimator}_tests.rs (active_device_id: None added to existing CapturedFrameBatchOptions construction sites)"
    - Rust/core/src/perf_budget.rs
metrics:
  duration_minutes: 13
  completed_date: "2026-06-04"
  tasks_completed: 3
  tasks_total: 3
  files_modified: 15
---

# Phase 09 Plan 02: FIX-01 — active_device_id Propagation into capture_sessions Summary

**One-liner:** `active_device_id` field added to batch import bridge args and `CapturedFrameBatchOptions`; `GooseStore::set_capture_session_device_id` writes it to `capture_sessions.active_device_id`; D-02 device_type separation confirmed by store-level regression test.

## What Was Built

### FIX-01 — Rust Side: active_device_id Propagation (Tasks 1 + 2)

**bridge.rs `CaptureImportFrameBatchArgs`:** Added `#[serde(default)] active_device_id: Option<String>`. When Swift passes `"active_device_id": "uuid-string"` in the bridge args JSON, it deserializes to `Some("uuid-string")`; when omitted, deserializes to `None` (backward compatible).

**bridge.rs `capture_import_frame_batch_bridge`:** Passes `active_device_id: args.active_device_id.as_deref()` into `CapturedFrameBatchOptions` so the value flows from the bridge args down through the import chain.

**capture_import.rs `CapturedFrameBatchOptions`:** Added `pub active_device_id: Option<&'a str>` field. The existing `parser_version: &'a str` already gave the struct a lifetime, so the new field uses the same lifetime without introducing lifetime complexity.

**capture_import.rs `import_captured_frame_batch_with_output_options_in_transaction`:** After the frame import loop, when `options.active_device_id` is `Some(device_id)`:
- Collect distinct `capture_session_id` values from the frame batch via `BTreeSet`
- For each session_id, call `store.set_capture_session_device_id(session_id, device_id)`
- The store method uses `WHERE active_device_id IS NULL` so repeated imports of the same batch are idempotent

**store.rs `GooseStore::set_capture_session_device_id`:** New public method. Issues `UPDATE capture_sessions SET active_device_id = ?2 WHERE session_id = ?1 AND active_device_id IS NULL`. Returns `true` when the row was updated, `false` when already set or session not found.

**All existing `CapturedFrameBatchOptions` construction sites** (14 files) updated to include `active_device_id: None` for backward compatibility.

### D-02 Confirmation — Upload Bridge No-JOIN Verification (Task 3)

The `upload_get_recent_decoded_streams_bridge` was confirmed to filter HR frames via `frame.device_type == "HR_MONITOR"` (bridge.rs line 3194) — no JOIN to `capture_sessions` exists or was introduced. `grep -n 'JOIN capture_sessions' Rust/core/src/bridge.rs` returns empty.

A new regression test `upload_device_type_filter_hr_frames_are_stored_separate_from_goose_frames` added to `capture_import_tests.rs`:
- Imports one `DeviceType::HrMonitor` frame and one `DeviceType::Goose` frame
- Queries `store.decoded_frames_between` to retrieve both
- Asserts `device_type == "HR_MONITOR"` for the HR frame and `device_type == "GOOSE"` for the Goose frame
- Confirms the separation mechanism exists at the store layer, which the upload bridge relies upon

The existing tests in `bridge_tests.rs` (`bridge_hr_monitor_upload_stream_contains_bpm_and_rr`, `bridge_hr_monitor_upload_stream_device_id_deferred`) cover the upload bridge end-to-end and were not duplicated here per plan.

## Tasks

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | Add failing tests for active_device_id persistence (RED) | 4f95d32 | Rust/core/tests/capture_import_tests.rs |
| 2 | FIX-01: thread active_device_id from bridge args into capture_sessions | 7256a38 | Rust/core/src/bridge.rs, Rust/core/src/capture_import.rs, Rust/core/src/store.rs, Rust/core/src/perf_budget.rs, 10 test files |
| 3 | D-02 regression: device_type separation HR vs Goose | 81ea7b3 | Rust/core/tests/capture_import_tests.rs |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan 01 commits missing from worktree**

- **Found during:** Pre-execution setup
- **Issue:** This worktree was created from commit `0c6ff4b` (before Plan 01 ran). The Plan 01 commits (`8645088`, `fa9b41f`, `71686d6`) were present in the local `main` branch but not in the worktree. Plan 02 depends on Plan 01 (`bridge.rs` changes).
- **Fix:** Cherry-picked the three Plan 01 commits into the worktree branch before starting Plan 02 tasks.
- **Commits:** `4f48e29`, `c05e960`, `d822a29` (cherry-picks of Plan 01 work)

**2. [Rule 1 - Bug] Plan's line-400 reference points to `import_capture_sqlite`, not the batch import path**

- **Found during:** Task 2 analysis
- **Issue:** The plan specified "at line 400: change `active_device_id: None` to `options.active_device_id`". Line 400 of `capture_import.rs` is in `import_capture_sqlite`, which uses `CaptureSqliteImportOptions` (not `CapturedFrameBatchOptions`). The batch import path (`import_captured_frame_batch_with_output_options_in_transaction`) never called `start_capture_session`. The must_haves requirement ("capture batch import supplies active_device_id → session stores non-NULL device id") required a different implementation.
- **Fix:** Added `active_device_id` propagation AFTER the frame loop in `import_captured_frame_batch_with_output_options_in_transaction`: collect `capture_session_id`s from frames and call `GooseStore::set_capture_session_device_id`. Also added the `set_capture_session_device_id` store method to keep SQL private. The must_haves truths are fully satisfied.
- **Files modified:** `Rust/core/src/capture_import.rs`, `Rust/core/src/store.rs`

**3. [Rule 1 - Bug] device_type string value is "GOOSE" not "Goose" in stored rows**

- **Found during:** Task 3 test
- **Issue:** The D-02 regression test asserted `device_type == "Goose"` but `store::device_type_name(DeviceType::Goose)` returns `"GOOSE"` (uppercase). Test failed on first run.
- **Fix:** Corrected assertion to `"GOOSE"`. One-line fix, no architectural change.
- **Files modified:** `Rust/core/tests/capture_import_tests.rs`

## Verification Results

```
cargo test --test capture_import_tests -- device_id   → 2 passed; 0 failed (FIX-01 tests)
cargo test --test capture_import_tests                → 12 passed; 0 failed (all capture tests)
cargo test                                            → all suites pass; 0 failures
grep -n 'JOIN capture_sessions' Rust/core/src/bridge.rs → empty (D-02 deferral honored)
grep -n 'active_device_id' Rust/core/src/bridge.rs   → shows args field + as_deref pass-through
grep -n 'active_device_id' Rust/core/src/capture_import.rs → shows options field + update loop
```

## Threat Model Coverage

| Threat | Disposition | Verified |
|--------|-------------|---------|
| T-09-04: NULL active_device_id makes captured data untraceable | mitigate | FIX-01 test passes: Some("test-uuid-1234") stored; None path stays NULL |
| T-09-05: active_device_id disclosure | accept | CoreBluetooth UUID is random, app-scoped, stored locally only |
| T-09-06: malformed active_device_id | accept | serde deserializes as Option<String>; stored as opaque TEXT |

## Known Stubs

None — all functionality is fully wired at the Rust layer. The Swift call site (passing `active_device_id` in `capture.import_frame_batch` args from `CaptureFrameWriteQueue`) is out of scope for this plan (Plan 09-03 covers Swift side).

## Threat Flags

None — no new network endpoints, auth paths, or file access patterns introduced beyond what is in the plan's threat model.

## Self-Check: PASSED

- FOUND: .planning/phases/09-ble-stability-data-integrity/09-02-SUMMARY.md
- FOUND: commit 4f95d32 (test: RED — active_device_id tests)
- FOUND: commit 7256a38 (feat: FIX-01 implementation)
- FOUND: commit 81ea7b3 (test: D-02 regression)
- Tests: cargo test — all suites ok; 0 failures
- grep JOIN capture_sessions bridge.rs → empty (D-02 honored)
