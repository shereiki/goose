---
phase: "06"
plan: "06-P03"
title: "Tests: Swift Unit Test Target + Rust Gen4 Bridge Tests"
wave: 3
depends_on:
  - "06-P01"
  - "06-P02"
files_modified:
  - GooseSwift.xcodeproj/project.pbxproj
  - GooseSwiftTests/GooseBLETypesTests.swift
  - GooseSwiftTests/WearableDescriptorTests.swift
  - Rust/core/tests/bridge_tests.rs
autonomous: true
requirements:
  - GEN4-05
---

<objective>
Create a Swift unit test target (`GooseSwiftTests`) in the Xcode project and add unit tests
verifying `WearableDescriptor.isCommandCharacteristic`, `GooseDiscoveredDevice.generation`
derivation, and `GooseNotificationEvent.rustDeviceType` logic. Also add Rust bridge tests
verifying the Gen4 device type is correctly parsed and that `"GEN4"` is accepted as a valid
`device_type` string (covering the bug fixed in P01-T04b).

Depends on Plans P01 and P02, which introduce all the types being tested.
</objective>

<must_haves>
  <truths>
    - GEN4-05: At least one automated test verifies that the upload payload correctly identifies Gen4 data; verified by `cargo test` passing and Swift unit tests passing on simulator
    - D-09: Swift unit test target `GooseSwiftTests` exists in `GooseSwift.xcodeproj`
    - D-10: `WearableDescriptor.whoopGen4.isCommandCharacteristic` returns true for `61080002-...` prefix and false for `fd4b0002-...` prefix
    - D-11: `GooseDiscoveredDevice.generation` is `"4.0"` when service UUID starts with `61080001` and `"5.0"` when it starts with `fd4b0001`
    - D-12: Rust `parse_device_type("GEN4")` succeeds (no error) — verifies the P01-T04b fix
  </truths>
</must_haves>

<tasks>

  <task id="P03-T01" type="execute">
    <title>Create GooseSwiftTests Xcode test target</title>
    <read_first>
      - GooseSwift.xcodeproj/project.pbxproj (full file — understand existing target, bundle ID, and scheme structure; look for the main GooseSwift target UUID to set as the test host)
    </read_first>
    <action>
      Add a new `XCTestCase` test target to `GooseSwift.xcodeproj`:

      **Option A — Xcode UI (preferred if running with Xcode):**
      1. In Xcode, File > New > Target > Unit Testing Bundle
      2. Name: `GooseSwiftTests`
      3. Bundle identifier: `com.tigercraft4.goose.tests`
      4. Test host: `GooseSwift` (the main app target)
      5. Language: Swift

      **Option B — Manual pbxproj edit (if Xcode unavailable):**
      Add the following to `project.pbxproj`:
      - A new `PBXNativeTarget` entry for `GooseSwiftTests` with `productType = "com.apple.product-type.bundle.unit-test"`
      - `PRODUCT_BUNDLE_IDENTIFIER = "com.tigercraft4.goose.tests"`
      - `SWIFT_VERSION = 5.0`
      - `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
      - `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/GooseSwift.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/GooseSwift"`
      - `BUNDLE_LOADER = "$(TEST_HOST)"`
      - `INFOPLIST_FILE = "GooseSwiftTests/Info.plist"` (create a minimal Info.plist)
      - Add the target to the project's `targets` list
      - Add a `PBXSourcesBuildPhase` referencing the test Swift files
      - Add a `PBXFrameworksBuildPhase` referencing `XCTest.framework`

      Create the directory `GooseSwiftTests/` at the project root.

      Note: If using Xcode UI for target creation, the pbxproj changes are made automatically.
      After target creation, ensure `@testable import GooseSwift` resolves (the `GooseSwift`
      module name matches the `PRODUCT_MODULE_NAME` setting).
    </action>
    <acceptance_criteria>
      - `GooseSwiftTests/` directory exists at `/Users/francisco/Documents/goose/GooseSwiftTests/`
      - `GooseSwift.xcodeproj/project.pbxproj` contains `GooseSwiftTests` as a target
      - The scheme or test target list includes `GooseSwiftTests`
      - Building the test target in Xcode (or via `xcodebuild test`) does not immediately fail due to missing target configuration
    </acceptance_criteria>
  </task>

  <task id="P03-T02" type="execute">
    <title>Write WearableDescriptor unit tests</title>
    <read_first>
      - GooseSwift/GooseBLETypes.swift (after P01: WearableDescriptor struct with isCommandCharacteristic and static instances)
      - GooseSwiftTests/ (after P03-T01: target directory exists)
    </read_first>
    <action>
      Create `GooseSwiftTests/WearableDescriptorTests.swift` with:

      ```swift
      import XCTest
      import CoreBluetooth
      @testable import GooseSwift

      final class WearableDescriptorTests: XCTestCase {

        func testGen5DescriptorAcceptsGen5CommandCharacteristic() {
          let uuid = CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a")
          // Cannot directly create CBCharacteristic in unit tests — test prefix logic directly
          XCTAssertTrue(
            uuid.uuidString.lowercased().hasPrefix(WearableDescriptor.whoopGen5.commandCharacteristicPrefix),
            "Gen5 descriptor should accept fd4b0002 prefix"
          )
        }

        func testGen4DescriptorAcceptsGen4CommandCharacteristic() {
          let uuid = CBUUID(string: "61080002-8d6d-82b8-614a-1c8cb0f8dcc6")
          XCTAssertTrue(
            uuid.uuidString.lowercased().hasPrefix(WearableDescriptor.whoopGen4.commandCharacteristicPrefix),
            "Gen4 descriptor should accept 61080002 prefix"
          )
        }

        func testGen5DescriptorRejectsGen4CommandCharacteristic() {
          let uuid = CBUUID(string: "61080002-8d6d-82b8-614a-1c8cb0f8dcc6")
          XCTAssertFalse(
            uuid.uuidString.lowercased().hasPrefix(WearableDescriptor.whoopGen5.commandCharacteristicPrefix),
            "Gen5 descriptor should reject 61080002 prefix"
          )
        }

        func testGen4DescriptorRejectsGen5CommandCharacteristic() {
          let uuid = CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a")
          XCTAssertFalse(
            uuid.uuidString.lowercased().hasPrefix(WearableDescriptor.whoopGen4.commandCharacteristicPrefix),
            "Gen4 descriptor should reject fd4b0002 prefix"
          )
        }

        func testGen4ServiceUUIDPrefix() {
          XCTAssertEqual(WearableDescriptor.whoopGen4.serviceUUIDPrefix, "61080001")
        }

        func testGen5ServiceUUIDPrefix() {
          XCTAssertEqual(WearableDescriptor.whoopGen5.serviceUUIDPrefix, "fd4b0001")
        }
      }
      ```

      Note: `CBCharacteristic` cannot be instantiated directly in unit tests (it requires a live
      CoreBluetooth stack). The tests above test `WearableDescriptor.commandCharacteristicPrefix`
      directly against a `CBUUID`, which is the pure logic being validated. If the struct exposes
      `commandCharacteristicPrefix` as internal/public, this approach works without mocking.
      Alternatively, test `isCommandCharacteristic` by making `WearableDescriptor` testable
      via a helper that accepts a `String` UUID instead of `CBCharacteristic`.

      If `CBCharacteristic` cannot be constructed, add an internal method to `WearableDescriptor`:
      ```swift
      func isCommandUUID(_ uuid: CBUUID) -> Bool {
        uuid.uuidString.lowercased().hasPrefix(commandCharacteristicPrefix)
      }
      ```
      And test `isCommandUUID` instead. Adjust test code to call `isCommandUUID(uuid)`.
    </action>
    <acceptance_criteria>
      - `GooseSwiftTests/WearableDescriptorTests.swift` exists
      - File contains at least 4 `XCTestCase` test methods covering Gen4 and Gen5 descriptor prefix acceptance/rejection
      - `@testable import GooseSwift` is present
      - Tests compile without error (verifiable by reading the file and checking import/type names against P01 output)
    </acceptance_criteria>
  </task>

  <task id="P03-T03" type="execute">
    <title>Write GooseDiscoveredDevice generation derivation tests</title>
    <read_first>
      - GooseSwift/GooseBLETypes.swift (after P01: GooseDiscoveredDevice with generation field)
      - GooseSwift/GooseBLEClient+Parsing.swift (after P01: static func generation(from:) helper)
      - GooseSwiftTests/ (after P03-T01: target exists)
    </read_first>
    <action>
      Create `GooseSwiftTests/GooseBLETypesTests.swift` with:

      ```swift
      import XCTest
      import CoreBluetooth
      @testable import GooseSwift

      final class GooseBLETypesTests: XCTestCase {

        // MARK: - GooseBLEClient.generation(from:) helper tests

        func testGenerationDerivation_gen4ServiceUUID() {
          let gen4ServiceUUID = CBUUID(string: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6")
          let generation = GooseBLEClient.generation(from: [gen4ServiceUUID])
          XCTAssertEqual(generation, "4.0", "61080001 service UUID should derive generation 4.0")
        }

        func testGenerationDerivation_gen5ServiceUUID() {
          let gen5ServiceUUID = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
          let generation = GooseBLEClient.generation(from: [gen5ServiceUUID])
          XCTAssertEqual(generation, "5.0", "fd4b0001 service UUID should derive generation 5.0")
        }

        func testGenerationDerivation_unknownServiceUUID() {
          let unknownUUID = CBUUID(string: "00001800-0000-1000-8000-00805f9b34fb")
          let generation = GooseBLEClient.generation(from: [unknownUUID])
          XCTAssertEqual(generation, "unknown", "Unknown service UUID should derive 'unknown'")
        }

        func testGenerationDerivation_emptyServiceList() {
          let generation = GooseBLEClient.generation(from: [])
          XCTAssertEqual(generation, "unknown", "Empty service list should derive 'unknown'")
        }

        // MARK: - GooseNotificationEvent.rustDeviceType tests

        func testRustDeviceType_gen4CharacteristicPrefix() {
          let event = GooseNotificationEvent(
            deviceID: UUID(),
            serviceUUID: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6",
            characteristicUUID: "61080003-8d6d-82b8-614a-1c8cb0f8dcc6",
            value: Data(),
            capturedAt: Date()
          )
          XCTAssertEqual(event.rustDeviceType, "GEN4",
            "Characteristic starting with 610800 should produce rustDeviceType GEN4")
        }

        func testRustDeviceType_gen5CharacteristicPrefix() {
          let event = GooseNotificationEvent(
            deviceID: UUID(),
            serviceUUID: "fd4b0001-cce1-4033-93ce-002d5875f58a",
            characteristicUUID: "fd4b0003-cce1-4033-93ce-002d5875f58a",
            value: Data(),
            capturedAt: Date()
          )
          XCTAssertEqual(event.rustDeviceType, "GOOSE",
            "Characteristic starting with fd4b should produce rustDeviceType GOOSE")
        }
      }
      ```
    </action>
    <acceptance_criteria>
      - `GooseSwiftTests/GooseBLETypesTests.swift` exists with at least 6 test methods
      - Tests cover `generation(from:)` with Gen4 UUID → "4.0", Gen5 UUID → "5.0", empty → "unknown"
      - Tests cover `rustDeviceType` with `610800` prefix → `"GEN4"` and `fd4b` prefix → `"GOOSE"`
      - `GooseBLEClient.generation(from:)` is accessible as a `static func` (per P01-T04 which added it to the Parsing extension)
      - File compiles without error (import and type names consistent with P01 output)
    </acceptance_criteria>
  </task>

  <task id="P03-T04" type="execute">
    <title>Add Gen4 bridge tests in Rust (GEN4-05)</title>
    <read_first>
      - Rust/core/tests/bridge_tests.rs (lines 48-55 for existing constants; lines 388-408 for parse_frame_hex test pattern; lines 7955-7970 for parse_device_type after P01-T04b fix)
      - Rust/core/src/bridge.rs (parse_device_type function to confirm "GEN4" was added in P01-T04b)
    </read_first>
    <action>
      In `Rust/core/tests/bridge_tests.rs`, add the following tests after the existing
      `bridge_parses_frame_hex_for_app_import_flow` test (around line 408):

      ```rust
      #[test]
      fn bridge_accepts_gen4_device_type_string_without_underscore() {
          // Verifies that the Swift runtime sends "GEN4" (no underscore) and the Rust bridge
          // correctly routes it to DeviceType::Gen4. This was a silent bug: Swift sends "GEN4"
          // but Rust only accepted "GEN_4" prior to the Phase 6 fix.
          let response = request(serde_json::json!({
              "schema": "goose.bridge.request.v1",
              "request_id": "gen4-device-type-1",
              "method": "protocol.parse_frame_hex",
              "args": {
                  "device_type": "GEN4",
                  "frame_hex": GET_HELLO_FRAME
              }
          }));
          // GET_HELLO_FRAME is a Goose/Gen5 frame — it will parse ok or fail due to header
          // mismatch, but the device_type "GEN4" must NOT produce an "unsupported device_type" error.
          // The important assertion is that the error (if any) is a protocol error, not a type error.
          if !response.ok {
              let error = response.error.as_deref().unwrap_or("");
              assert!(
                  !error.contains("unsupported device_type"),
                  "\"GEN4\" should be a recognized device_type, got error: {error}"
              );
          }
      }

      #[test]
      fn bridge_gen4_device_type_aliases_all_accepted() {
          // Verify all known Gen4 device_type aliases are accepted
          for alias in &["GEN4", "GEN_4", "Gen4", "gen4"] {
              let response = request(serde_json::json!({
                  "schema": "goose.bridge.request.v1",
                  "request_id": format!("gen4-alias-{alias}"),
                  "method": "protocol.parse_frame_hex",
                  "args": {
                      "device_type": alias,
                      "frame_hex": GET_HELLO_FRAME
                  }
              }));
              if !response.ok {
                  let error = response.error.as_deref().unwrap_or("");
                  assert!(
                      !error.contains("unsupported device_type"),
                      "device_type \"{alias}\" should be a recognized Gen4 alias, got: {error}"
                  );
              }
          }
      }

      #[test]
      fn bridge_gen4_upload_device_generation_field_is_set_correctly() {
          // Verifies the full chain: GooseUploadService in Swift maps "GEN4" → "4.0"
          // in device_generation. The Rust side stores captured frames keyed by device_type.
          // This test verifies that "GEN4" is a valid device_type for capture.import_frame_batch.
          let tempdir = tempfile::tempdir().unwrap();
          let db = tempdir.path().join("goose.sqlite");
          let db_path = db.display().to_string();

          let response = request(serde_json::json!({
              "schema": "goose.bridge.request.v1",
              "request_id": "gen4-capture-import",
              "method": "capture.import_frame_batch",
              "args": {
                  "database_path": db_path,
                  "parser_version": "goose-core/bridge-test-gen4",
                  "frames": [
                      {
                          "evidence_id": "gen4-capture-1",
                          "source": "ios.corebluetooth.notification",
                          "captured_at": "2026-06-03T12:00:00Z",
                          "device_model": "WHOOP 4.0",
                          "frame_hex": GET_HELLO_FRAME,
                          "sensitivity": "user-owned-capture",
                          "device_type": "GEN4"
                      }
                  ]
              }
          }));

          assert!(response.ok, "GEN4 capture.import_frame_batch should succeed: {:?}", response.error);
          let result = response.result.unwrap();
          assert_eq!(result["raw_inserted"], 1, "Should insert 1 raw frame for GEN4 device_type");
      }
      ```

      Run `cargo test --manifest-path Rust/core/Cargo.toml` to confirm all new tests pass.
    </action>
    <acceptance_criteria>
      - `Rust/core/tests/bridge_tests.rs` contains `bridge_accepts_gen4_device_type_string_without_underscore` test
      - `Rust/core/tests/bridge_tests.rs` contains `bridge_gen4_upload_device_generation_field_is_set_correctly` test
      - `cargo test --manifest-path Rust/core/Cargo.toml` exits 0 with all tests passing
      - The `bridge_accepts_gen4_device_type_string_without_underscore` test asserts that `"GEN4"` does not produce an "unsupported device_type" error
    </acceptance_criteria>
  </task>

</tasks>

<verification>
  1. `xcodebuild test -project GooseSwift.xcodeproj -scheme GooseSwiftTests -destination "platform=iOS Simulator,name=iPhone 16"` — must exit 0 with all tests passing (or at minimum 0 test failures)
  2. `cargo test --manifest-path Rust/core/Cargo.toml 2>&1 | grep -E "FAILED|test result|gen4"` — must show `test result: ok` and gen4 tests listed
  3. `ls GooseSwiftTests/` — must list at least `WearableDescriptorTests.swift` and `GooseBLETypesTests.swift`
  4. `grep -n "bridge_accepts_gen4\|bridge_gen4_upload" Rust/core/tests/bridge_tests.rs` — must return both function names
</verification>

<success_criteria>
  - Swift unit test target `GooseSwiftTests` exists in the Xcode project
  - At least 6 Swift unit tests pass covering WearableDescriptor prefix logic and generation derivation
  - Rust bridge tests verify "GEN4" device_type is accepted without "unsupported device_type" error
  - `cargo test` passes with the Gen4-specific test functions
  - All tests can run in CI without physical hardware (simulator-only for Swift, `cargo test` for Rust)
</success_criteria>
