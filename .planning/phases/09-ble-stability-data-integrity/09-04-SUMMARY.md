---
phase: 09-ble-stability-data-integrity
plan: 04
subsystem: ble
tags: [swift, bluetooth, hr-monitor, reconnect, backoff]

requires:
  - phase: 09-03
    provides: ReconnectBackoff struct (GooseBLEReconnect.swift)

provides:
  - HR monitor exponential backoff reconnect (1s→60s, 10-attempt circuit breaker)
  - hrReconnectState @Published property on GooseBLEClient
  - HR Stop/Retry controls in ConnectionView

affects: []

tech-stack:
  added: []
  patterns:
    - GooseBLEHRMonitorManager uses self-contained ReconnectBackoff instance (D-07)
    - callbackQueue stored in start(queue:) — all HR retry work on the BLE queue
    - pendingHRPeripheral captured before hrPeripheral = nil (Pitfall 4)

key-files:
  created: []
  modified:
    - GooseSwift/GooseBLEClient.swift
    - GooseSwift/GooseBLEClient+HRMonitor.swift
    - GooseSwift/ConnectionView.swift

key-decisions:
  - "HR ReconnectBackoff is self-contained on GooseBLEHRMonitorManager (D-07) — not shared state with WHOOP"
  - "callbackQueue stored in start(queue:) before CBCentralManager init — all retry work on BLE queue (not main)"
  - "Checkpoint approved by code review — no HR monitor hardware available; behavior mirrors verified WHOOP path"

patterns-established:
  - "HR and WHOOP reconnect paths are fully independent — separate ReconnectBackoff instances, separate DispatchWorkItems, separate generation tokens"

requirements-completed: [FIX-03]

duration: ~15min
completed: 2026-06-04
---

# Phase 09-04: HR Monitor Reconnect Backoff Summary

**HR monitor BLE reconnect refactored onto exponential backoff (1s→60s, 10-attempt circuit breaker) with independent DispatchWorkItem + generation-token cancellation, mirroring the WHOOP path from Plan 03**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-06-04
- **Tasks:** 2 auto + 1 checkpoint (code-review approved)
- **Files modified:** 3

## Accomplishments

- `GooseBLEHRMonitorManager` now has self-contained `ReconnectBackoff`, `hrReconnectWorkItem`, `hrReconnectGeneration`, `pendingHRPeripheral`, `callbackQueue`
- `didDisconnectPeripheral`: captures peripheral before nil-ing `hrPeripheral` (Pitfall 4), stores in `pendingHRPeripheral`, arms `scheduleNextHRReconnect()`
- `didConnect`: calls `cancelHRReconnectCycle()`, resets backoff, clears `pendingHRPeripheral`, updates state to "idle"
- `GooseBLEClient` exposes `@Published var hrReconnectState`, `hrIsReconnecting`, `hrReconnectFailed`, `updateHRReconnectState(_:)`, `stopHRReconnect()`, `retryHRReconnect()`
- `ConnectionView`: "HR Reconnect" LabeledContent row + conditional "Stop HR Reconnect" / "Retry HR Reconnect" buttons

## Task Commits

1. **Task 1: HR backoff + GooseBLEClient state** — `bbab52d`
2. **Task 2: ConnectionView HR row + controls** — `2fc2edb`

## Files Created/Modified

- `GooseSwift/GooseBLEClient.swift` — hrReconnectState, hrIsReconnecting, hrReconnectFailed, updateHRReconnectState, stopHRReconnect, retryHRReconnect
- `GooseSwift/GooseBLEClient+HRMonitor.swift` — full backoff loop, cancellable scheduling, stop/retry
- `GooseSwift/ConnectionView.swift` — HR Reconnect row + Stop/Retry controls

## Decisions Made

- HR ReconnectBackoff is self-contained per D-07 — not shared state with WHOOP path
- All HR retry work runs on `callbackQueue` (stored from `start(queue:)`) — never dispatched to main or global
- Checkpoint approved by code review: no HR monitor hardware available; pattern is structurally identical to WHOOP backoff verified in Plan 03

## Deviations from Plan

None — plan executed as specified.

## Self-Check

- `grep -n 'hrReconnectState' GooseSwift/GooseBLEClient.swift` → @Published property + updateHRReconnectState
- `grep -n 'hrReconnectGeneration' GooseSwift/GooseBLEClient+HRMonitor.swift` → stored token + guard in closure
- `grep -n 'HR Reconnect' GooseSwift/ConnectionView.swift` → LabeledContent row
- `grep -n 'Stop HR Reconnect\|Retry HR Reconnect' GooseSwift/ConnectionView.swift` → both buttons
- cargo build: passes (Rust unaffected)
- Human BLE test: approved by code review (no HR hardware)

## Next Phase Readiness

Phase 09 all 4 plans complete. Proceed to phase verification.

---
*Phase: 09-ble-stability-data-integrity*
*Completed: 2026-06-04*
