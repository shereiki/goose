---
phase: "08"
plan: "08-P04"
title: "Upload Payload Unit Tests (Gen4 / Gen5 / HR monitor device_class / manual upload device-type derivation)"
wave: 3
depends_on: ["08-P03"]
files_modified:
  - GooseSwift/GooseUploadService.swift
  - GooseSwiftTests/GooseUploadServiceTests.swift
autonomous: true
requirements:
  - WEAR-03
---

<objective>
Addresses cross-AI review HIGH-3: `GooseUploadService` payload construction currently has ZERO unit
tests, which the reviewer flagged as HIGH risk. This plan extracts the payload-building logic from the
`async`/network-coupled `performUpload` into a pure, synchronously-testable function and adds unit tests
that pin the upload taxonomy decided in P03:

- Gen4 device type → payload has `device_generation: "4.0"` and NO `device_class` key
- Gen5 device type (`"GOOSE"`) → payload has `device_generation: "5.0"` and NO `device_class` key
- HR monitor device type (e.g., `"Polar H10"`) → payload has `device_type: "Polar H10"` AND `device_class: "HR_MONITOR"`, and NO `device_generation` key
- `triggerManualUpload()` derives the device type from the active connection — it never hardcodes `"GOOSE"`

These are pure unit tests on the payload dictionary; they do NOT require a live server, BLE hardware, or
the Rust bridge.

Purpose: Lock the WEAR-03 upload taxonomy behind regression tests so future edits cannot silently
reintroduce the Gen5 fallback or drop `device_class`.
Output: A pure `buildUploadPayload(...)` function plus `GooseUploadServiceTests.swift` covering all four
review-mandated cases.
</objective>

<must_haves>
  <truths>
    - HIGH-3: `GooseUploadService` exposes a pure payload-construction function (no network, no async, no bridge) that is unit-testable
    - A unit test asserts Gen4 (`deviceType == "GEN4"`) payload contains `device_generation == "4.0"` and contains NO `device_class` key
    - A unit test asserts Gen5 (`deviceType == "GOOSE"`) payload contains `device_generation == "5.0"` and contains NO `device_class` key
    - A unit test asserts HR monitor (`deviceType == "Polar H10"`) payload contains `device_type == "Polar H10"` AND `device_class == "HR_MONITOR"` AND NO `device_generation` key
    - A test verifies `triggerManualUpload()` does not pass a hardcoded `"GOOSE"` device type when no WHOOP device is active (the derivation logic is exercised, not a literal)
    - `performUpload` calls the extracted `buildUploadPayload(...)` — behavior of the live upload path is unchanged
  </truths>
  <artifacts>
    - path: "GooseSwiftTests/GooseUploadServiceTests.swift"
      provides: "Unit tests for upload payload taxonomy"
    - path: "GooseSwift/GooseUploadService.swift"
      provides: "Pure buildUploadPayload function extracted for testability"
  </artifacts>
  <key_links>
    - from: "GooseUploadService.performUpload"
      to: "GooseUploadService.buildUploadPayload"
      via: "extracted pure function call"
  </key_links>
</must_haves>

<threat_model>
  <threats>
    <threat id="T-08-08" severity="low">
      Extracting payload construction could accidentally change the live upload payload shape. Mitigation: `buildUploadPayload` returns the exact same dictionary `performUpload` built before; the Gen4/Gen5 cases are asserted to be byte-equivalent (same keys, same `streams` structure) by the new tests, and `performUpload` is changed only to delegate to the extracted function.
    </threat>
  </threats>
</threat_model>

<tasks>

  <task id="P04-T01" type="execute">
    <title>Extract pure buildUploadPayload(deviceID:deviceType:streams:) from performUpload</title>
    <read_first>
      - GooseSwift/GooseUploadService.swift (full file — performUpload, lines ~38–100; the switch added in P03-T01 that branches on deviceType for device_generation vs device_type/device_class)
      - .planning/phases/08-additional-wearables-e2e/08-REVIEWS.md (HIGH-3: payload construction must be unit-tested)
      - .planning/phases/08-additional-wearables-e2e/08-P03-PLAN.md (P03-T01 — the exact device_class/device_generation taxonomy this function must produce)
    </read_first>
    <action>
      Refactor the payload construction in `GooseUploadService` so it lives in a pure, synchronous function
      with no `await`, no `URLSession`, and no Rust-bridge access:

      Add `func buildUploadPayload(deviceID: UUID, deviceType: String, streams: [String: Any]) -> [String: Any]`
      (or `static func` — choose static if it needs no instance state; it should not need any). The function
      reproduces EXACTLY the `switch deviceType` payload logic introduced in P03-T01:
      - `case "GEN4"`: `["device": [...], "streams": streams, "device_generation": "4.0"]`
      - `case "GOOSE"`: `["device": [...], "streams": streams, "device_generation": "5.0"]`
      - `default`: `["device": [...], "streams": streams, "device_type": deviceType, "device_class": "HR_MONITOR"]`
      The `device` sub-dictionary is `["id": deviceID.uuidString, "mac": NSNull(), "name": NSNull()]` exactly
      as today. No `device_generation` key in the default case; no `device_class` key in the WHOOP cases.

      In `performUpload`, replace the inline payload literal with a call:
      `let payload = buildUploadPayload(deviceID: deviceID, deviceType: deviceType, streams: ["hr": hr, "rr": rr, "events": events, "battery": battery, "spo2": spo2, "skin_temp": skinTemp, "resp": resp, "gravity": gravity])`.
      Keep the rest of `performUpload` (the `hasData` guard, `JSONSerialization`, the request, the retry
      loop) unchanged. Make `buildUploadPayload` at least `internal` (not `private`) so the test target can
      call it (the GooseSwiftTests target uses `@testable import GooseSwift` — confirm that import exists in
      the test target from Phase 6 setup; if `@testable` is used, `internal` is sufficient).
    </action>
    <acceptance_criteria>
      - `GooseUploadService.swift` contains a function `buildUploadPayload(deviceID:deviceType:streams:)` that returns `[String: Any]` and contains no `await`/`URLSession`/bridge calls
      - `performUpload` calls `buildUploadPayload(...)` and no longer builds the payload dictionary inline
      - The function is `internal` or `static` (callable from a `@testable import GooseSwift` test)
      - Gen4/Gen5 cases produce `device_generation` and no `device_class`; default case produces `device_type` + `device_class` and no `device_generation`
      - Swift build succeeds; live upload behavior is unchanged
    </acceptance_criteria>
  </task>

  <task id="P04-T02" type="execute">
    <title>Add GooseUploadServiceTests.swift covering Gen4, Gen5, HR monitor device_class, and manual-upload derivation</title>
    <read_first>
      - GooseSwift/GooseUploadService.swift (current state after P04-T01 — buildUploadPayload signature; GooseUploadService initializer args to confirm how to construct an instance, or whether buildUploadPayload is static)
      - GooseSwiftTests/GooseBLETypesTests.swift (existing test file — XCTest class pattern, imports, target conventions used in this project)
      - GooseSwift/GooseAppModel+Upload.swift (current state after P03-T02 — triggerManualUpload derivation logic to test)
      - .planning/phases/06-whoop-gen4-ios-support/06-P03-SUMMARY.md (GooseSwiftTests target: @testable import GooseSwift, TEST_HOST, bundle ID)
      - .planning/phases/08-additional-wearables-e2e/08-REVIEWS.md (HIGH-3: the four required upload payload assertions)
    </read_first>
    <action>
      Create `GooseSwiftTests/GooseUploadServiceTests.swift` with an `XCTestCase` subclass (use the same
      `import XCTest` + `@testable import GooseSwift` pattern as `GooseBLETypesTests.swift`). Construct the
      payload via the extracted function (instance or static per P04-T01) with an empty/minimal `streams`
      dictionary — payload-shape tests do not need real stream contents.

      Tests:
      1. `test_buildUploadPayload_gen4_hasGeneration4_noDeviceClass` — call with `deviceType: "GEN4"`; assert
         `payload["device_generation"] as? String == "4.0"`; assert `payload["device_class"] == nil`; assert
         `payload["device_type"] == nil`.
      2. `test_buildUploadPayload_gen5_goose_hasGeneration5_noDeviceClass` — `deviceType: "GOOSE"`; assert
         `payload["device_generation"] as? String == "5.0"`; assert `payload["device_class"] == nil`.
      3. `test_buildUploadPayload_hrMonitor_hasDeviceTypeAndDeviceClass_noGeneration` — `deviceType: "Polar H10"`;
         assert `payload["device_type"] as? String == "Polar H10"`; assert `payload["device_class"] as? String == "HR_MONITOR"`;
         assert `payload["device_generation"] == nil`.
      4. `test_buildUploadPayload_unknownDevice_defaultsToHrMonitorClass` — `deviceType: "Garmin HRM"`; assert
         `payload["device_class"] as? String == "HR_MONITOR"` and `payload["device_type"] as? String == "Garmin HRM"`.
      5. `test_buildUploadPayload_preservesStreams` — pass a `streams` dict with a known sentinel
         (e.g., `["hr": [42]]`) and assert the returned `payload["streams"]` round-trips the sentinel, proving
         the WHOOP `streams` structure is untouched.
      6. Manual-upload derivation: `test_triggerManualUpload_doesNotHardcodeGoose`. Because `triggerManualUpload`
         depends on `GooseAppModel`/BLE state that is hard to instantiate in a unit test, satisfy this with a
         SOURCE-LEVEL assertion test that reads `GooseSwift/GooseAppModel+Upload.swift` and asserts the
         `triggerManualUpload` body contains no unconditional `deviceType: "GOOSE"` literal — load the file via
         a path relative to the test bundle resource OR, if file access from the test bundle is awkward, instead
         write a behavioral test that exercises the derivation helper if P03-T02 extracted one. Prefer the
         behavioral test if a derivation helper exists; otherwise use the source-assertion test. Document which
         approach was used in a comment.

      Use `XCTAssertEqual`, `XCTAssertNil`, `XCTAssertNotNil`. For `[String: Any]` value extraction use
      `payload["key"] as? String` casts.
    </action>
    <acceptance_criteria>
      - `GooseSwiftTests/GooseUploadServiceTests.swift` exists with at least 5 test methods
      - Tests assert: Gen4 → `device_generation "4.0"` + no `device_class`; Gen5 → `device_generation "5.0"` + no `device_class`; HR monitor → `device_type` + `device_class "HR_MONITOR"` + no `device_generation`
      - A test covers `triggerManualUpload` not hardcoding `"GOOSE"` (behavioral if a helper exists, otherwise source-assertion)
      - `xcodebuild test` (GooseSwiftTests on iOS Simulator) runs the new tests and they pass
    </acceptance_criteria>
  </task>

</tasks>

<verification>
  1. `grep "func buildUploadPayload" GooseSwift/GooseUploadService.swift` — pure function present
  2. `grep -c "buildUploadPayload" GooseSwift/GooseUploadService.swift` — at least 2 (definition + call in performUpload)
  3. `ls GooseSwiftTests/GooseUploadServiceTests.swift` — test file exists
  4. `grep -c "func test_" GooseSwiftTests/GooseUploadServiceTests.swift` — at least 5
  5. `grep "HR_MONITOR" GooseSwiftTests/GooseUploadServiceTests.swift` — device_class assertion present
  6. GooseSwiftTests pass (Xcode test or xcodebuild test on iOS Simulator)
</verification>

<success_criteria>
  - [ ] Payload construction extracted into a pure, testable `buildUploadPayload` function
  - [ ] `performUpload` delegates to `buildUploadPayload`; live behavior unchanged
  - [ ] Unit tests cover Gen4 (`4.0`), Gen5 (`5.0`), HR monitor (`device_type` + `device_class: "HR_MONITOR"`)
  - [ ] A test confirms `triggerManualUpload()` does not hardcode `"GOOSE"`
  - [ ] GooseSwiftTests target compiles and the new tests pass
  - [ ] Cross-AI review HIGH-3 (absent upload payload tests) is resolved
</success_criteria>
