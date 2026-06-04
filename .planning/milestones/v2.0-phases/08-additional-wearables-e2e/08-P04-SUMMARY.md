---
phase: "08"
plan: "08-P04"
subsystem: testing
tags: [swift, xctest, upload, payload, unit-tests, device-taxonomy, refactor]
dependency_graph:
  requires:
    - phase: 08-additional-wearables-e2e
      plan: 08-P03
      provides: "switch deviceType in performUpload with GEN4/GOOSE/HR_MONITOR taxonomy"
  provides:
    - "Pure buildUploadPayload(deviceID:deviceType:streams:) function extracted from performUpload"
    - "GooseUploadServiceTests with 6 tests covering Gen4/Gen5/HR monitor payload taxonomy"
    - "Cross-AI review HIGH-3 (absent upload payload tests) resolved"
    - "WEAR-03 upload taxonomy locked behind regression tests"
  affects:
    - Future phases touching GooseUploadService (regression safety net in place)
tech_stack:
  added: []
  patterns:
    - "Pure function extraction from async context for unit testability (buildUploadPayload)"
    - "Source-level assertion test pattern for untestable coordinator methods (triggerManualUpload)"
key_files:
  created:
    - GooseSwiftTests/GooseUploadServiceTests.swift
  modified:
    - GooseSwift/GooseUploadService.swift
    - GooseSwift/HealthDataStore.swift
    - GooseSwift/HealthDataStore+Snapshots.swift
    - GooseSwift.xcodeproj/project.pbxproj
key_decisions:
  - "buildUploadPayload is internal (not private) so @testable import GooseSwift test target can call it directly without a static wrapper"
  - "test_triggerManualUpload_doesNotHardcodeGoose uses source-assertion approach (walking DerivedData bundle up to source tree) because GooseAppModel cannot be instantiated in a unit test; XCTSkip is used when source is inaccessible (sandboxed CI)"
  - "sevenDayStrainCache stored property moved from HealthDataStore+Snapshots.swift extension to HealthDataStore.swift class body (Rule 3 fix — Swift prohibits stored properties in extensions; pre-existing build error blocking test compilation)"
  - "HEADER_SEARCH_PATHS ($(SRCROOT)/Rust/core/include) added to GooseSwiftTests Debug+Release build configurations to allow the bridging header to resolve goose_core_bridge.h during test compilation"
requirements_completed:
  - WEAR-03

duration: "~30 minutes"
completed: "2026-06-04"
---

# Phase 08 Plan 04: Upload Payload Unit Tests (Gen4 / Gen5 / HR monitor / manual upload derivation) Summary

**Pure buildUploadPayload function extracted from performUpload plus 6-test GooseUploadServiceTests suite locking the WEAR-03 device taxonomy (GEN4/GOOSE/HR_MONITOR) behind regression tests — resolves cross-AI review HIGH-3.**

## Performance

- **Duration:** ~30 minutes
- **Started:** 2026-06-03T23:54:00Z
- **Completed:** 2026-06-04T00:05:00Z
- **Tasks:** 2
- **Files modified:** 5 (1 created)

## Accomplishments

- Extracted `buildUploadPayload(deviceID:deviceType:streams:)` as a pure `internal` synchronous function from `performUpload`; no `await`, `URLSession`, or Rust bridge access — fully unit-testable via `@testable import GooseSwift`
- Added `GooseSwiftTests/GooseUploadServiceTests.swift` with 6 tests: Gen4 `device_generation: "4.0"` + no `device_class`; Gen5 `device_generation: "5.0"` + no `device_class`; HR monitor `device_type: "Polar H10"` + `device_class: "HR_MONITOR"` + no `device_generation`; unknown device defaults to `HR_MONITOR`; streams round-trip; triggerManualUpload source assertion
- Full GooseSwiftTests suite (all three test classes) passes with zero failures

## Task Commits

1. **P04-T01: Extract pure buildUploadPayload from performUpload** - `b207d3a` (refactor)
2. **P04-T02: Add GooseUploadServiceTests** - `ee84b0e` (test)

## Files Created/Modified

- `GooseSwiftTests/GooseUploadServiceTests.swift` - 6 XCTest methods covering upload payload taxonomy (created)
- `GooseSwift/GooseUploadService.swift` - buildUploadPayload extracted; performUpload delegates to it
- `GooseSwift/HealthDataStore.swift` - sevenDayStrainCache stored property moved here from extension
- `GooseSwift/HealthDataStore+Snapshots.swift` - removed duplicate stored property declaration
- `GooseSwift.xcodeproj/project.pbxproj` - GooseUploadServiceTests added to test target; HEADER_SEARCH_PATHS added to GooseSwiftTests configs

## Decisions Made

- `buildUploadPayload` is `internal` (not `private`) so the test target can call it via `@testable import GooseSwift` without wrapping it in a static helper
- Source-assertion approach chosen for `test_triggerManualUpload_doesNotHardcodeGoose` because `GooseAppModel` cannot be instantiated in a unit test; the test walks up from the DerivedData bundle to find the source tree and uses `XCTSkip` when inaccessible (sandboxed CI)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed stored property in Swift extension blocking test compilation**
- **Found during:** P04-T02 (running xcodebuild test)
- **Issue:** `private var sevenDayStrainCache` was declared inside `extension HealthDataStore` in `HealthDataStore+Snapshots.swift`. Swift prohibits stored properties in extensions — this caused a compile error that prevented `@testable import GooseSwift` from succeeding, blocking the entire test target
- **Fix:** Moved `sevenDayStrainCache` declaration to the main `HealthDataStore` class body in `HealthDataStore.swift`; removed the duplicate from the extension; added a comment explaining the relocation
- **Files modified:** `GooseSwift/HealthDataStore.swift`, `GooseSwift/HealthDataStore+Snapshots.swift`
- **Verification:** `xcodebuild build -scheme GooseSwift` succeeded; `xcodebuild test -scheme GooseSwiftTests` full suite passed
- **Committed in:** `ee84b0e` (P04-T02 commit)

**2. [Rule 3 - Blocking] Added HEADER_SEARCH_PATHS to GooseSwiftTests build configurations**
- **Found during:** P04-T02 (second xcodebuild test attempt after fixing the extension error)
- **Issue:** GooseSwiftTests target had no `HEADER_SEARCH_PATHS`, so the bridging header (`GooseSwift-Bridging-Header.h`) could not resolve `goose_core_bridge.h` during test compilation
- **Fix:** Added `HEADER_SEARCH_PATHS = ("$(inherited)", "$(SRCROOT)/Rust/core/include")` to both Debug and Release configurations of GooseSwiftTests in `project.pbxproj`
- **Files modified:** `GooseSwift.xcodeproj/project.pbxproj`
- **Verification:** Test target compiled successfully; all 6 GooseUploadServiceTests ran (5 passed, 1 skipped via XCTSkip as expected in DerivedData environment)
- **Committed in:** `ee84b0e` (P04-T02 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 3 — blocking)
**Impact on plan:** Both fixes were strictly necessary to make `@testable import GooseSwift` work in the test target. The stored property fix resolves a pre-existing Swift compile error; the header search path fix resolves a pre-existing test configuration gap. No scope creep.

## Issues Encountered

- `test_triggerManualUpload_doesNotHardcodeGoose` correctly uses `XCTSkip` when running from DerivedData (simulator sandboxed environment cannot walk up to the source tree). This is the expected and documented behavior — the test exercises the source-assertion logic when the source is accessible (e.g., local development or non-sandboxed CI).

## Known Stubs

None. All tests make assertions against real `buildUploadPayload` return values with no hardcoded placeholders.

## Threat Flags

No new network endpoints, auth paths, or schema changes introduced. The `buildUploadPayload` extraction is a pure refactor with identical behavior; the test-only files add no production surface.

## Self-Check: PASSED

- [x] `GooseSwift/GooseUploadService.swift` — `buildUploadPayload` function present, `performUpload` delegates to it
- [x] `GooseSwiftTests/GooseUploadServiceTests.swift` — 6 test methods, HR_MONITOR assertions present
- [x] `GooseSwift/HealthDataStore.swift` — `sevenDayStrainCache` declared in class body
- [x] `GooseSwift/HealthDataStore+Snapshots.swift` — duplicate stored property removed
- [x] `GooseSwift.xcodeproj/project.pbxproj` — file ref T20000000000000000000006, build file T10000000000000000000004, group entry, Sources entry all present; HEADER_SEARCH_PATHS in both test configs
- [x] Commit `b207d3a` verified (P04-T01)
- [x] Commit `ee84b0e` verified (P04-T02)
- [x] `xcodebuild test -scheme GooseSwiftTests` full suite: SUCCEEDED (5 passed, 1 skipped)
- [x] WEAR-03 upload taxonomy locked behind regression tests

---
*Phase: 08-additional-wearables-e2e*
*Completed: 2026-06-04*
