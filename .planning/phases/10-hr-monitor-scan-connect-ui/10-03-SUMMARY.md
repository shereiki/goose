---
phase: 10-hr-monitor-scan-connect-ui
plan: "03"
subsystem: ui
tags: [swift, swiftui, navigation, more-tab, hr-monitor, routing]

# Dependency graph
requires:
  - phase: 10-hr-monitor-scan-connect-ui plan 02
    provides: "HRMonitorView — public SwiftUI view for HR monitor scan/connect screen"
provides:
  - "MoreRoute.hrMonitor — new enum case with complete switch coverage"
  - "MoreRouteStatus.hrMonitor — MoreStatusKind property for connection status"
  - "deviceRoutes includes .hrMonitor — HR Monitor entry in Device section"
  - "destination(for: .hrMonitor) -> HRMonitorView() — navigation wired"
  - "hrMonitor status argument in MoreDataStore.routeStatus(ble:model:)"
affects:
  - More tab Device section (HRMonitorView now navigable from More > HR Monitor)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MoreRoute enum extension pattern: all four switch arms + MoreRouteStatus property must be updated atomically"
    - "MoreDataStore routeStatus pattern: ble.hrConnectionState == 'connected' ? .ready : .pending"

key-files:
  created: []
  modified:
    - GooseSwift/MoreRouteModels.swift
    - GooseSwift/MoreView.swift
    - GooseSwift/MoreDataStore.swift

key-decisions:
  - "hrMonitor status uses ble.hrConnectionState == 'connected' ? .ready : .pending (RESEARCH Open Question 1 recommendation — ready only when fully connected)"
  - "No parameters passed to HRMonitorView() — it reads model.ble via @EnvironmentObject, same pattern as DeviceView()"

requirements-completed: [WEAR-04, WEAR-05]

# Metrics
duration: 3min
completed: 2026-06-04
---

# Phase 10 Plan 03: More Tab HR Monitor Navigation Wiring Summary

**MoreRoute.hrMonitor wired into More tab Device section with complete switch arms, MoreRouteStatus property, deviceRoutes inclusion, HRMonitorView destination, and connected/pending status driven by ble.hrConnectionState**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-06-04T22:52:00Z
- **Completed:** 2026-06-04T22:55:58Z
- **Tasks:** 2/2
- **Files modified:** 3

## Accomplishments

- Added `case hrMonitor` to `MoreRoute` enum immediately after `case device`
- Added exhaustive switch arms in all four computed properties: `title` ("HR Monitor"), `subtitle` ("Connect and view live heart rate from a Bluetooth HR monitor"), `systemImage` ("heart.circle"), `statusKeyPath` (`\.hrMonitor`)
- Updated `deviceRoutes` static array from `[.device]` to `[.device, .hrMonitor]`, making the HR Monitor entry appear in the Device section of the More tab
- Added `var hrMonitor: MoreStatusKind` to `MoreRouteStatus` struct after `var device`
- Added `case .hrMonitor: HRMonitorView()` to `destination(for:)` switch in `MoreView`, wiring navigation
- Added `hrMonitor: ble.hrConnectionState == "connected" ? .ready : .pending,` argument to `MoreRouteStatus(...)` initializer call in `MoreDataStore.routeStatus(ble:model:)`
- `cargo test` passed (9 tests, 0 failures) — Rust core unaffected

## Task Commits

1. **Task 1: Add MoreRoute.hrMonitor case, switch arms, status property, and deviceRoutes inclusion** - `ba34615` (feat)
2. **Task 2: Wire HRMonitorView destination and hrMonitor route status** - `6477826` (feat)

## Files Created/Modified

- `GooseSwift/MoreRouteModels.swift` — Added `case hrMonitor`, four switch arms (`title`, `subtitle`, `systemImage`, `statusKeyPath`), `var hrMonitor: MoreStatusKind` in `MoreRouteStatus`, and `.hrMonitor` in `deviceRoutes`
- `GooseSwift/MoreView.swift` — Added `case .hrMonitor: HRMonitorView()` to `destination(for:)` switch
- `GooseSwift/MoreDataStore.swift` — Added `hrMonitor: ble.hrConnectionState == "connected" ? .ready : .pending,` to `MoreRouteStatus(...)` call

## Decisions Made

- Status logic uses `ble.hrConnectionState == "connected" ? .ready : .pending` as recommended in RESEARCH Open Question 1. No `.blocked` or `.unavailable` states needed — the HR monitor entry is always accessible for scanning regardless of connection state, and `.ready` only when confirmed connected.
- `HRMonitorView()` takes no parameters — it reads `model.ble` via `@EnvironmentObject` injected by the parent `MoreView`, consistent with the `DeviceView()` pattern in the same switch.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. All four switch arms, the `MoreRouteStatus` property, the `deviceRoutes` inclusion, and the `MoreDataStore` argument were added atomically as required to prevent compile errors (Swift exhaustive switch + missing initializer argument).

## Known Stubs

None — all wiring is complete. `MoreRoute.hrMonitor` is fully integrated with status, navigation, and destination.

## Threat Flags

No new security surface introduced. Navigation is enum-driven (T-10-06: Swift compiler enforces exhaustive switches — all four arms added together; build fails closed if any is missing). No package installs (T-10-SC: Apple system frameworks only).

## End-to-End Path Status

The WEAR-04/WEAR-05 user path is now complete:
1. Plan 01: `@Published discoveredHRDevices` and `hrConnectionState` promoted to `GooseBLEClient`; `disconnectHRMonitor()` teardown wired
2. Plan 02: `HRMonitorView` with four-state machine, auto-scan lifecycle, tap-to-connect sheet, and connected panel
3. Plan 03 (this plan): `MoreRoute.hrMonitor` entry in Device section navigates to `HRMonitorView`

Hardware verification (deferred from Plan 02 Task 2 checkpoint) can now proceed: navigate to More > HR Monitor on a physical iPhone to exercise the full BLE scan/connect flow.

---
*Phase: 10-hr-monitor-scan-connect-ui*
*Completed: 2026-06-04*

## Self-Check: PASSED

- [x] `GooseSwift/MoreRouteModels.swift` has `case hrMonitor` (1 match)
- [x] `GooseSwift/MoreRouteModels.swift` has 4 `case .hrMonitor:` switch arms
- [x] `GooseSwift/MoreRouteModels.swift` has `var hrMonitor: MoreStatusKind`
- [x] `GooseSwift/MoreRouteModels.swift` has `deviceRoutes: [MoreRoute] = [.device, .hrMonitor]`
- [x] `GooseSwift/MoreView.swift` has `HRMonitorView()` (1 match)
- [x] `GooseSwift/MoreDataStore.swift` has `hrMonitor: ble.hrConnectionState == "connected" ? .ready : .pending`
- [x] Commits ba34615 and 6477826 present in git log
- [x] `cargo test` passed (9 tests, 0 failures)
