---
phase: 9
reviewers: [codex]
reviewed_at: "2026-06-04T17:33:16Z"
plans_reviewed:
  - 09-01-PLAN.md
  - 09-02-PLAN.md
  - 09-03-PLAN.md
  - 09-04-PLAN.md
skipped_reviewers:
  claude: self-CLI (running inside Claude Code — skipped for independence)
  gemini: GEMINI_API_KEY not set in environment
---

# Cross-AI Plan Review — Phase 9: BLE Stability & Data Integrity

## Codex Review

## Summary

The four plans are generally strong: they are traceable to Phase 9 requirements, scoped to known files, sequenced to reduce merge conflicts, and include validation hooks. The biggest risks are in the Swift reconnection design, especially preserving correct retry semantics, cancellation, queue discipline, and UI control coverage. The Rust plans are cleaner and lower risk, though the panic test strategy needs tightening so it does not rely on accidental panics or test-only behavior that could distort production code.

## 09-01-PLAN.md — FFI Panic Safety + Storage Compaction Bridge

### Strengths

- Clear separation of FIX-04 and FIX-05 Rust-side plumbing.
- Correctly identifies that `panic = "unwind"` is required for `catch_unwind` to work.
- Keeps compaction algorithm unchanged and only exposes it through the bridge.
- Includes tests for both panic handling and compaction no-op behavior.
- Good threat model: app-crash DoS and storage growth are the right risks.

### Concerns

- **HIGH:** Panic test trigger is underspecified. "Trigger the panic with an unwrap/expect path or explicit test-only panic" may lead to brittle tests or production-only test hooks.
- **MEDIUM:** `bridge_error("unknown", "panic", message)` may lose the real request ID even when the request was already parsed. This is acceptable if the panic happens before parsing, but if the request ID is available, preserving it would be better.
- **MEDIUM:** The plan does not explicitly verify that unwinding cannot cross the FFI boundary. The closure should include all Rust work that may panic and return a C string only inside the caught path.
- **LOW:** `grep -c 'panic = "abort"'` returning 0 may be too broad if comments or unrelated profiles exist later.

### Suggestions

- Add a deterministic test-only bridge method behind `#[cfg(test)]` or a test-only helper that panics inside dispatch, rather than relying on malformed args accidentally reaching an unwrap.
- If possible, parse/extract `request_id` before dispatch and use it in the panic response.
- Add a normal-request regression test through `goose_bridge_handle_json` to prove non-panicking calls still work.
- Ensure returned C strings from the FFI test are freed with the existing free helper to avoid leaks in tests.

### Risk Assessment

**LOW-MEDIUM.** The implementation is localized and technically sound, but the panic test design needs to be deterministic and not depend on incidental panics.

---

## 09-02-PLAN.md — active_device_id Propagation

### Strengths

- Correctly treats `active_device_id` as session-scoped, not frame-scoped.
- Preserves backward compatibility with omitted `active_device_id`.
- Explicitly avoids the deferred JOIN-based upload filter work.
- Good sequencing after 09-01 because both touch `bridge.rs`.
- Test plan checks both supplied and omitted device ID paths.

### Concerns

- **MEDIUM:** This plan alone does not fully satisfy "HR monitor frames written to the database contain a non-NULL `device_id` matching the connected HR monitor device." It fixes `capture_sessions.active_device_id`, but the roadmap wording also mentions `ble_raw_notifications.device_id`. The plan acknowledges those are different paths, but the success criterion may still be interpreted more strictly.
- **MEDIUM:** The plan says "HR monitor frames' session rows carry…" in success criteria, which narrows the requirement. If stakeholders expect `ble_raw_notifications.device_id` for live HR frames, this will be a mismatch.
- **LOW:** Test coverage around upload filtering is optional/conditional. Given CR-02 history, a small explicit regression test would be valuable.

### Suggestions

- Clarify whether `ble_raw_notifications.device_id` is also populated by the FIX-01 fix, or only `capture_sessions.active_device_id`.
- Tighten acceptance language: "active_device_id" vs "device_id in ble_raw_notifications."
- Add a focused upload-filter regression test for the existing device_type filter path.

### Risk Assessment

**LOW-MEDIUM.** The fix is targeted and the Rust changes are well-understood, but the acceptance criteria could be misread. Clarifying the scope of FIX-01 prevents confusion during verification.

---

## 09-03-PLAN.md — ReconnectBackoff + WHOOP Reconnect + Swift Integration

### Strengths

- Good decomposition of `ReconnectBackoff` into a reusable value type.
- Correctly identifies the existing `autoReconnectInFlight` pattern to replace.
- Compaction is wired at both required points (launch and per-write).
- Includes a human-verify checkpoint for BLE reconnect behavior.
- Detailed task actions with concrete file references.

### Concerns

- **HIGH:** Reconnect cancellation semantics are underspecified. `DispatchQueue.asyncAfter` closures cannot be cancelled directly. If Stop is tapped or reconnect succeeds while a `asyncAfter` is pending, a stale reconnect may fire. Plan 03 does not specify generation tokens or `DispatchWorkItem`.
- **HIGH:** The first-attempt timing is ambiguous. If `baseDelay` is 1s, it is unclear whether the first attempt fires immediately (attempt 0 before delay) or after 1s. The acceptance criteria do not specify this.
- **MEDIUM:** `@Published var reconnectState` mutation from a BLE queue is a data race unless explicitly dispatched to main. The plan states Task @MainActor but does not specify this for all state mutation sites.
- **MEDIUM:** Active device ID propagation relies on `GooseAppModel` setting `activeDeviceID` on the queue at connect/disconnect. The plan does not specify which exact delegate callback triggers this, leaving room for a race.
- **LOW:** `cargo build` is not meaningful validation for Swift edits. It only proves Rust still builds.

### Suggestions

- Split reconnect into explicit methods: `scheduleNextReconnect(reason:)`, `performReconnectAttempt()`, `cancelReconnectCycle()`.
- Add a reconnect generation/token: increment on Stop, success, manual retry; scheduled closures compare captured token before connecting.
- Use a typed reconnect state instead of parsing strings, e.g. enum/state fields plus a display string.
- Ensure the first attempt timing matches the requirement. If base delay is 1s, do not connect immediately unless explicitly intended.
- Log compaction results from `CaptureFrameWriteQueue` too, or route the report back to a logger if `compacted_rows > 0`.
- Make active device ID propagation precise: identify the exact connection callbacks and whether the queue should store WHOOP ID, HR ID, or the current capture source ID.

### Risk Assessment

**HIGH.** This is the riskiest plan. It touches stateful CoreBluetooth behavior, cancellation, UI state, and synchronous bridge calls. The reconnect description needs tightening before implementation.

---

## 09-04-PLAN.md — HR Monitor Backoff

### Strengths

- Correctly gives HR monitor its own `ReconnectBackoff` instance.
- Identifies the important edge case: capture the disconnected peripheral before clearing `hrPeripheral`.
- Keeps HR reconnect separate from WHOOP reconnect.
- Adds visible HR reconnect state to `ConnectionView`.
- Manual verification steps are concrete and relevant.

### Concerns

- **HIGH:** Same cancellation problem as Plan 03. Scheduled HR reconnect closures need a cancel/generation check, especially after successful reconnect or circuit-breaker failure.
- **HIGH:** Roadmap success criterion 4 says manual retry and stop buttons should restart/abort reconnection "at any time." Plan 04 explicitly does not add HR-specific Stop/Try Again controls. That may fail the phase success criteria if criterion 4 applies to both WHOOP and HR monitor.
- **MEDIUM:** The manager queue is not explicitly named. "Manager's BLE callback queue" needs to be tied to the actual queue used by its `CBCentralManager`.
- **MEDIUM:** `DispatchQueue asyncAfter on the manager's queue` is underspecified unless the manager stores that queue. If no queue property exists, implementation may accidentally use main/global.
- **MEDIUM:** `owner?.updateHRReconnectState(...)` from a background BLE queue must be safe and consistently main-actor dispatched.
- **LOW:** No handling is described for expected/manual disconnects versus unexpected disconnects. HR reconnect may trigger when the user intentionally disconnects.

### Suggestions

- Add `hrStopReconnect()` and `hrRetryReconnect()` or extend the existing buttons to control both active reconnect cycles.
- Add an HR reconnect generation/cancellation token.
- Track intentional disconnects and suppress automatic reconnect when the user manually disconnects.
- Store or reuse the exact dispatch queue that created the HR `CBCentralManager`; schedule all retry work there.
- Consider a unified reconnect-state model for WHOOP and HR so UI behavior is consistent.

### Risk Assessment

**MEDIUM-HIGH.** The plan is narrower than 09-03, but it inherits the same backoff/cancellation risks and may not fully satisfy the manual stop/retry criterion.

---

## Cross-Plan Concerns

- **HIGH:** Phase 9 success criterion 4 may not be fully met for HR monitor reconnect. The plans provide WHOOP Stop/Try Again, but HR monitor only gets a status row.
- **HIGH:** Reconnect cancellation semantics are not sufficiently specified. `asyncAfter` cannot be cancelled directly unless using `DispatchWorkItem` or a generation token.
- **MEDIUM:** The wave dependency ordering is conservative but partly artificial. 09-02 does not truly depend on 09-01 except for conflict avoidance. That is fine, but it could slow delivery.
- **MEDIUM:** The plans use human verification for Swift, which is realistic, but there is little automated protection for the backoff state machine.

---

## Consensus Summary

*(Single reviewer — no multi-reviewer consensus. Concerns reflect independent Codex analysis.)*

### Key Strengths

- Rust plans (09-01, 09-02) are well-scoped, traceable, and correctly sequenced.
- `ReconnectBackoff` value-type design is architecturally sound.
- Compaction wired at correct dual call sites (launch + per-write).
- Good use of canonical refs and existing patterns.

### Agreed Concerns (HIGH severity)

1. **Reconnect cancellation via `asyncAfter`** (Plans 03 + 04): scheduled closures can fire after Stop/success unless generation tokens or `DispatchWorkItem` are used. Must specify in plans before execution.
2. **HR monitor manual stop/retry missing** (Plan 04): success criterion 4 ("stop button to abort at any time") is ambiguous whether it covers HR monitor; likely yes, but Plan 04 doesn't implement it.
3. **Panic test strategy** (Plan 01): needs a deterministic `#[cfg(test)]` method rather than relying on malformed args hitting an unwrap.

### Divergent Views

N/A — single reviewer.

### Recommended Action

**Replan with `--reviews` to address HIGH concerns before execution**, specifically:
- Add cancellation token / `DispatchWorkItem` pattern to Plans 03 and 04
- Clarify whether HR stop/retry buttons are required (and add them if yes)
- Tighten panic test trigger to use a deterministic `#[cfg(test)]` bridge method
