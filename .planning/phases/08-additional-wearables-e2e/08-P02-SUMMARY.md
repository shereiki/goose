---
phase: 08-additional-wearables-e2e
plan: "08-P02"
subsystem: ble
tags: [swift, corebluetooth, ble, heart-rate, gatt, whoop, ios]

# Dependency graph
requires:
  - phase: 06-whoop-gen4-ios-support
    provides: "WearableDescriptor abstraction, rustDeviceType heuristic, GooseDiscoveredDevice.generation field"
provides:
  - "WearableDescriptor.genericHRMonitor static instance (serviceUUIDPrefix: 180d, empty commandCharacteristicPrefix)"
  - "Empty-prefix guard in isCommandCharacteristic/isCommandUUID — prevents hasPrefix(\"\") matching everything"
  - "Normalized rustDeviceType HR_MONITOR for 0x2A37 in short, lowercase, and full 128-bit UUID forms"
  - "GooseBLEHRMonitorManager: dedicated CBCentralManager scanning 0x180D, manual connect, background-queue 0x2A37 notifications"
  - "GooseBLEClient.startHRMonitorScan/stopHRMonitorScan/connectHRMonitor public API"
  - "notificationIngestResult HR_MONITOR bypass (skips 0xaa WHOOP reassembly)"
  - "Swift unit tests for all of the above (9 new test methods)"
affects:
  - 08-P03 (upload integration reads hrMonitorManager.hrConnectionState and connectedDeviceName)
  - 08-P04 (e2e verification builds on this BLE layer)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GooseBLEHRMonitorManager: file-local helper class pattern for Swift extension stored properties on GooseBLEClient"
    - "Separate CBCentralManager per device family — WHOOP central and HR monitor central are independent"
    - "Background-queue notification dispatch: CBCentralManager created with coreBluetoothQueue so 0x2A37 callbacks never touch @MainActor"
    - "rustDeviceType normalization: replacingOccurrences(of: \"-\", with: \"\").lowercased() for UUID comparison"

key-files:
  created:
    - GooseSwift/GooseBLEClient+HRMonitor.swift
    - GooseSwiftTests/GooseBLETypesTests.swift (9 new test methods appended)
  modified:
    - GooseSwift/GooseBLETypes.swift
    - GooseSwift/GooseBLEClient.swift
    - GooseSwift/GooseAppModel+NotificationPipeline.swift
    - GooseSwift.xcodeproj/project.pbxproj

key-decisions:
  - "Empty-prefix guard lands in P02-T01 — same task that introduces the empty-prefix descriptor, not deferred (MEDIUM-1)"
  - "HR notifications delivered via owner?.onNotification?(event) directly on CoreBluetooth background queue — no main-thread hop (MEDIUM-3)"
  - "GooseBLEHRMonitorManager properties are internal (not private) so P03-T02 can read hrConnectionState and connectedDeviceName for upload"
  - "Device name sanitization: trim whitespace + cap to 64 chars + fallback to unknown_hr_monitor (T-08-03 threat mitigation)"
  - "notificationIngestResult HR_MONITOR branch returns single NotificationFrame with raw hex bytes; empty value returns frames: [] (not an error)"

patterns-established:
  - "Pattern: WearableDescriptor with empty commandCharacteristicPrefix for read-only notify-only devices; isCommandCharacteristic/isCommandUUID return false via guard"
  - "Pattern: file-local helper class (GooseBLEHRMonitorManager) to hold CBCentralManager stored properties for a GooseBLEClient extension"

requirements-completed:
  - WEAR-02

# Metrics
duration: 6min
completed: 2026-06-03
---

# Phase 8 Plan 02: iOS BLE HR Monitor Extension + WearableDescriptor.genericHRMonitor + Notification Routing Summary

**WearableDescriptor.genericHRMonitor descriptor, empty-prefix guard, normalized HR_MONITOR rustDeviceType, and dedicated 0x180D BLE scan/connect/notify flow with background-queue dispatch — completing the WEAR-02 iOS acquisition path**

## Performance

- **Duration:** 6 min
- **Started:** 2026-06-03T22:27:40Z
- **Completed:** 2026-06-03T22:33:25Z
- **Tasks:** 4 (+ 1 chore commit for Xcode project registration)
- **Files modified:** 6

## Accomplishments
- Added `WearableDescriptor.genericHRMonitor` with `serviceUUIDPrefix: "180d"` and `commandCharacteristicPrefix: ""`, plus the empty-prefix guard in both `isCommandCharacteristic` and `isCommandUUID` (MEDIUM-1 cross-AI review finding) that prevents `hasPrefix("")` from matching every characteristic
- Extended `GooseNotificationEvent.rustDeviceType` with normalized UUID comparison matching `"2A37"`, `"2a37"`, and `"00002A37-0000-1000-8000-00805F9B34FB"` → `"HR_MONITOR"` (MEDIUM-2)
- Created `GooseBLEClient+HRMonitor.swift` with `GooseBLEHRMonitorManager` class: separate `CBCentralManager` scanning exclusively for `CBUUID("180D")`, manual-only connect, 0x2A37 subscription, and notification dispatch directly on the background CoreBluetooth queue (MEDIUM-3 — never `@MainActor` inline)
- Added HR_MONITOR bypass in `notificationIngestResult(for:)` that skips the WHOOP 0xaa frame reassembly and passes the raw GATT bytes through as a single `NotificationFrame` — `nonisolated` annotation preserved
- Added 9 Swift unit tests covering `genericHRMonitor` descriptor properties, empty-prefix guard correctness, and short/lowercase/full-128-bit 0x2A37 UUID normalization

## Task Commits

Each task was committed atomically:

1. **P02-T01: WearableDescriptor.genericHRMonitor + empty-prefix guard + rustDeviceType HR_MONITOR** - `4d5a613` (feat)
2. **P02-T02: GooseBLEClient+HRMonitor.swift + GooseBLEClient.hrMonitorManager property** - `46c8d3f` (feat)
3. **P02-T03: notificationIngestResult HR_MONITOR bypass** - `f56cfab` (feat)
4. **P02-T04: Swift unit tests** - `7077bdb` (test)
5. **Xcode project registration for GooseBLEClient+HRMonitor.swift** - `4b087ef` (chore)

## Files Created/Modified

- `GooseSwift/GooseBLETypes.swift` — added `genericHRMonitor` static instance, empty-prefix guard in `isCommandCharacteristic`/`isCommandUUID`, normalized `HR_MONITOR` branch in `rustDeviceType`
- `GooseSwift/GooseBLEClient+HRMonitor.swift` — new file: `GooseBLEHRMonitorManager` class + `GooseBLEClient` extension with `startHRMonitorScan`, `stopHRMonitorScan`, `connectHRMonitor`
- `GooseSwift/GooseBLEClient.swift` — added `let hrMonitorManager = GooseBLEHRMonitorManager()` stored property
- `GooseSwift/GooseAppModel+NotificationPipeline.swift` — added `HR_MONITOR` early-return branch in `notificationIngestResult(for:)`
- `GooseSwiftTests/GooseBLETypesTests.swift` — 9 new test methods for Phase 8 P02 additions
- `GooseSwift.xcodeproj/project.pbxproj` — registered `GooseBLEClient+HRMonitor.swift` in PBXBuildFile, PBXFileReference, PBXGroup, and Sources build phase

## Decisions Made

- Empty-prefix guard lands in P02-T01 (same commit that introduces the empty-prefix descriptor), not deferred to a later task — consistent with MEDIUM-1 review requirement
- HR notifications are dispatched via `owner?.onNotification?(event)` directly on the CoreBluetooth background queue — the `CBCentralManager` is initialised with `coreBluetoothQueue` so callbacks never execute on `@MainActor` (MEDIUM-3)
- `GooseBLEHRMonitorManager` properties (`hrPeripheral`, `hrConnectionState`, `connectedDeviceName`) are `internal` (not `private`) so P03 can read them for upload identity without exposing a public API
- Device name sanitization applied in `didDiscover`: trim whitespace, cap to 64 chars, replace empty-after-trim with `"unknown_hr_monitor"` (T-08-03 threat mitigation)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added GooseBLEClient+HRMonitor.swift to Xcode project.pbxproj**
- **Found during:** Post-T02 verification
- **Issue:** The new Swift file was not registered in `GooseSwift.xcodeproj/project.pbxproj`; Xcode would not compile it without the PBXFileReference, PBXBuildFile, PBXGroup, and Sources build phase entries
- **Fix:** Inserted 4 entries in `project.pbxproj` using IDs `D20000000000000000000058` (file reference) and `D10000000000000000000058` (build file), following the existing sequential ID pattern
- **Files modified:** `GooseSwift.xcodeproj/project.pbxproj`
- **Verification:** `grep "GooseBLEClient+HRMonitor" GooseSwift.xcodeproj/project.pbxproj` returns 4 lines
- **Committed in:** `4b087ef` (chore commit after T04)

---

**Total deviations:** 1 auto-fixed (Rule 3 — blocking build issue)
**Impact on plan:** Necessary for compilation. No scope creep.

## Issues Encountered

None beyond the Xcode project registration deviation documented above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- WEAR-02 iOS BLE acquisition path complete: scan → connect → notify → `onNotification?` callback on background queue
- P03 can read `ble.hrMonitorManager.hrConnectionState`, `ble.hrMonitorManager.connectedDeviceName`, and `ble.hrMonitorManager.discoveredHRDevices` to drive the upload payload
- No blockers for P03 or P04

## Self-Check: PASSED

All files exist, all commits found, all plan verification checks pass.

---
*Phase: 08-additional-wearables-e2e*
*Completed: 2026-06-03*
