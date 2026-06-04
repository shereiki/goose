---
phase: "06"
plan: "06-P01"
title: "WearableDescriptor + Command Guard Fix + Generation Field"
wave: 1
depends_on: []
files_modified:
  - GooseSwift/GooseBLETypes.swift
  - GooseSwift/GooseBLEClient.swift
  - GooseSwift/GooseBLEClient+Commands.swift
  - GooseSwift/GooseBLEClient+Parsing.swift
  - GooseSwift/GooseBLEClient+CentralDelegate.swift
  - GooseSwift/GooseBLEClient+HistoricalCommands.swift
  - GooseSwift/GooseBLEClient+UserActions.swift
  - GooseSwift/GooseAppModel.swift
  - Rust/core/src/bridge.rs
autonomous: true
requirements:
  - GEN4-01
  - GEN4-02
---

<objective>
Introduce `WearableDescriptor` value type, fix the `supportsV5*` command guards to accept Gen4's
`61080002-` prefix (unblocking all WHOOP 4.0 commands), add a `generation: String` field to
`GooseDiscoveredDevice` derived at scan time from the advertised BLE service UUID, and propagate
the generation to `GooseAppModel`.
</objective>

<must_haves>
  <truths>
    - GEN4-01: After this plan, a Gen4 device connecting via `61080002-` command characteristic receives `supportsHistoricalSync == true`, `supportsAlarmCommands == true`, `supportsClockCommands == true`, `supportsSensorCommands == true`
    - GEN4-02: `GooseDiscoveredDevice` has a `generation: String` field populated from advertised service UUID at scan time ("4.0" for `61080001-*`, "5.0" for `fd4b0001-*`, "unknown" otherwise)
    - D-01: `WearableDescriptor` struct exists in `GooseBLETypes.swift` with static `.whoopGen4` and `.whoopGen5` instances and `isCommandCharacteristic(_:)` method
    - D-02: All `supportsV5*` computed property names are renamed to remove `V5` (4 renames)
    - D-03: `isV5CommandCharacteristic` is removed; replaced by `activeDescriptor?.isCommandCharacteristic`
    - D-04: `GooseAppModel` has `@Published var connectedDeviceGeneration: String?` set when device connects
    - D-08: Rust `parse_device_type` in `bridge.rs` accepts `"GEN4"` (no underscore) so Swift's `rustDeviceType` value is correctly handled
  </truths>
</must_haves>

<tasks>

  <task id="P01-T01" type="execute">
    <title>Add WearableDescriptor to GooseBLETypes.swift</title>
    <read_first>
      - GooseSwift/GooseBLETypes.swift (current struct definitions and import pattern)
      - .planning/phases/06-whoop-gen4-ios-support/06-CONTEXT.md (Decision 1: WearableDescriptor shape)
      - .planning/phases/06-whoop-gen4-ios-support/06-PATTERNS.md (WearableDescriptor pattern section)
    </read_first>
    <action>
      In `GooseBLETypes.swift`, after the existing imports block and before the `GooseLogLevel` enum, add:

      1. `struct WearableDescriptor` with stored properties:
         - `let serviceUUIDPrefix: String` — lowercased first 8 chars of service UUID
         - `let commandCharacteristicPrefix: String` — lowercased first 8 chars of command UUID
         and method:
         - `func isCommandCharacteristic(_ c: CBCharacteristic) -> Bool` — returns `c.uuid.uuidString.lowercased().hasPrefix(commandCharacteristicPrefix)`

      2. Static instances as `extension WearableDescriptor`:
         - `.whoopGen5` — serviceUUIDPrefix: `"fd4b0001"`, commandCharacteristicPrefix: `"fd4b0002"`
         - `.whoopGen4` — serviceUUIDPrefix: `"61080001"`, commandCharacteristicPrefix: `"61080002"`

      3. Update `GooseDiscoveredDevice` struct: add `let generation: String` after `rssi: Int`.
         (Memberwise init is synthesised — callers must be updated in P01-T04.)
    </action>
    <acceptance_criteria>
      - `GooseBLETypes.swift` contains `struct WearableDescriptor` with `isCommandCharacteristic(_ c: CBCharacteristic) -> Bool`
      - `WearableDescriptor.whoopGen4.commandCharacteristicPrefix == "61080002"` (verifiable by reading the static property)
      - `WearableDescriptor.whoopGen5.commandCharacteristicPrefix == "fd4b0002"` (verifiable by reading the static property)
      - `GooseDiscoveredDevice` has `let generation: String` field
      - `import CoreBluetooth` is present at the top of `GooseBLETypes.swift` (already exists — verify it stays)
    </acceptance_criteria>
  </task>

  <task id="P01-T02" type="execute">
    <title>Add activeDescriptor to GooseBLEClient and replace isV5CommandCharacteristic</title>
    <read_first>
      - GooseSwift/GooseBLEClient.swift (lines 1-60 for @Published properties; lines 840-870 for canSync* properties)
      - GooseSwift/GooseBLEClient+Commands.swift (lines 145-180 for supportsV5* and isV5CommandCharacteristic; lines 163-174 for shouldUseCommandCharacteristic)
      - GooseSwift/GooseBLETypes.swift (after P01-T01: WearableDescriptor definition)
    </read_first>
    <action>
      In `GooseBLEClient.swift`:
      1. Add `private var activeDescriptor: WearableDescriptor?` as a stored property in the class body (after `var commandCharacteristic: CBCharacteristic?`).

      In `GooseBLEClient+Commands.swift` (lines 145-174), make these changes:
      2. Remove `func isV5CommandCharacteristic(_ characteristic: CBCharacteristic) -> Bool` entirely.
      3. Replace the four `supportsV5*` computed properties with renamed versions:
         - `supportsV5HistoricalSync` → `supportsHistoricalSync`
         - `supportsV5AlarmCommands` → `supportsAlarmCommands`
         - `supportsV5ClockCommands` → `supportsClockCommands`
         - `supportsV5SensorCommands` → `supportsSensorCommands`
         Each body becomes: `commandCharacteristic.map { activeDescriptor?.isCommandCharacteristic($0) == true } == true`
      4. Update `shouldUseCommandCharacteristic(_:)` (line 167-174):
         Replace the body from using `isV5CommandCharacteristic` to:
         ```swift
         guard commandCharacteristicIDs.contains(characteristic.uuid) else { return false }
         guard let current = commandCharacteristic else { return true }
         // Prefer command characteristic matching active descriptor; if no descriptor, accept first found
         if let desc = activeDescriptor {
           return desc.isCommandCharacteristic(characteristic) && !desc.isCommandCharacteristic(current)
         }
         return false
         ```
      5. Update the four in-line guard call sites in the same file that reference the old `supportsV5*` names:
         - Line 209: `supportsV5ClockCommands` → `supportsClockCommands`
         - Line 302: `supportsV5AlarmCommands` → `supportsAlarmCommands`
         - Line 393: `supportsV5SensorCommands` → `supportsSensorCommands`
         - Line 906: `supportsV5SensorCommands` → `supportsSensorCommands`
         - Line 927: `supportsV5HistoricalSync` → `supportsHistoricalSync`
    </action>
    <acceptance_criteria>
      - `GooseBLEClient+Commands.swift` contains no occurrences of `supportsV5` or `isV5CommandCharacteristic`
      - `GooseBLEClient.swift` contains `private var activeDescriptor: WearableDescriptor?`
      - `supportsHistoricalSync`, `supportsAlarmCommands`, `supportsClockCommands`, `supportsSensorCommands` all exist as computed `var` on the extension
      - Each renamed property body references `activeDescriptor?.isCommandCharacteristic`
    </acceptance_criteria>
  </task>

  <task id="P01-T03" type="execute">
    <title>Update remaining supportsV5* call sites in GooseBLEClient.swift, HistoricalCommands, UserActions</title>
    <read_first>
      - GooseSwift/GooseBLEClient.swift (lines 840-900 for canSync* computed properties and supportsV5* guard at line 898)
      - GooseSwift/GooseBLEClient+HistoricalCommands.swift (line 26)
      - GooseSwift/GooseBLEClient+UserActions.swift (line 60)
    </read_first>
    <action>
      In `GooseBLEClient.swift`, update all `supportsV5*` references:
      - Line 849: `supportsV5HistoricalSync` → `supportsHistoricalSync`
      - Line 853: `supportsV5SensorCommands` → `supportsSensorCommands`
      - Line 861: `supportsV5AlarmCommands` → `supportsAlarmCommands`
      - Line 867: `supportsV5ClockCommands` → `supportsClockCommands`
      - Line 898: `supportsV5AlarmCommands` → `supportsAlarmCommands`

      In `GooseBLEClient+HistoricalCommands.swift`:
      - Line 26: `supportsV5HistoricalSync` → `supportsHistoricalSync`

      In `GooseBLEClient+UserActions.swift`:
      - Line 60: `supportsV5SensorCommands` → `supportsSensorCommands`
    </action>
    <acceptance_criteria>
      - `grep -rn "supportsV5" GooseSwift/` returns zero results
      - `grep -rn "isV5Command" GooseSwift/` returns zero results
      - `GooseBLEClient.swift` `canSyncHistorical` references `supportsHistoricalSync`
      - `GooseBLEClient+HistoricalCommands.swift` guard references `supportsHistoricalSync`
      - `GooseBLEClient+UserActions.swift` guard references `supportsSensorCommands`
    </acceptance_criteria>
  </task>

  <task id="P01-T04" type="execute">
    <title>Add generation(from:) helper and populate GooseDiscoveredDevice.generation at scan time</title>
    <read_first>
      - GooseSwift/GooseBLEClient+Parsing.swift (lines 302-345 for whoopIdentityEvidence, isWhoopService, isWhoopName patterns)
      - GooseSwift/GooseBLEClient+CentralDelegate.swift (lines 95-135 for scan delegate where GooseDiscoveredDevice is created)
      - GooseSwift/GooseBLETypes.swift (after P01-T01: GooseDiscoveredDevice with generation field)
    </read_first>
    <action>
      In `GooseBLEClient+Parsing.swift`, add a new static helper function after `isWhoopService`:
      ```
      static func generation(from serviceUUIDs: [CBUUID]) -> String
      ```
      Logic: return `"4.0"` if any UUID uuidString lowercased starts with `"61080001"`;
      return `"5.0"` if any starts with `"fd4b0001"`; else return `"unknown"`.
      Add a comment: `// Gen4 service UUID prefix 61080001-, Gen5 prefix fd4b0001-`

      In `GooseBLEClient+CentralDelegate.swift`, update the `GooseDiscoveredDevice` initialiser
      call at line 119 to include `generation: Self.generation(from: advertisedServices)`.
      The `advertisedServices` variable is already computed at line 103 in the same method.
    </action>
    <acceptance_criteria>
      - `GooseBLEClient+Parsing.swift` contains `static func generation(from serviceUUIDs: [CBUUID]) -> String`
      - The function returns `"4.0"` for `[CBUUID(string: "61080001-8D6D-82B8-614A-1C8CB0F8DCC6")]`
      - The function returns `"5.0"` for `[CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")]`
      - `GooseBLEClient+CentralDelegate.swift` `GooseDiscoveredDevice(...)` call includes `generation:` parameter
      - Build compiles without error (no missing memberwise init argument)
    </acceptance_criteria>
  </task>

  <task id="P01-T04b" type="execute">
    <title>Fix Rust parse_device_type to accept "GEN4" (no underscore) — critical bug fix</title>
    <read_first>
      - Rust/core/src/bridge.rs (lines 7955-7970 for parse_device_type function)
      - GooseSwift/GooseBLETypes.swift (rustDeviceType computed var that returns "GEN4")
    </read_first>
    <action>
      In `Rust/core/src/bridge.rs`, update `parse_device_type` (line 7958) to add `"GEN4"` as an accepted alias:
      ```rust
      "GEN4" | "GEN_4" | "Gen4" | "gen4" => Ok(DeviceType::Gen4),
      ```
      This fixes a critical silent bug: the Swift `GooseNotificationEvent.rustDeviceType` returns
      `"GEN4"` for Gen4 notifications, but the Rust bridge only accepted `"GEN_4"` / `"Gen4"` / `"gen4"`.
      Every Gen4 frame parse call was returning an error and frames were being silently dropped.

      Run `cargo test --manifest-path Rust/core/Cargo.toml` to confirm no regressions.
    </action>
    <acceptance_criteria>
      - `Rust/core/src/bridge.rs` `parse_device_type` match arm contains `"GEN4"` as a valid alias
      - `cargo test --manifest-path Rust/core/Cargo.toml` exits 0
      - The match arm `"GEN4" | "GEN_4" | "Gen4" | "gen4" => Ok(DeviceType::Gen4)` is present
    </acceptance_criteria>
  </task>

  <task id="P01-T05" type="execute">
    <title>Set activeDescriptor on connect and publish connectedDeviceGeneration in GooseAppModel</title>
    <read_first>
      - GooseSwift/GooseBLEClient+Commands.swift (lines 835-900 for processDiscoveredCharacteristics where commandCharacteristic is set)
      - GooseSwift/GooseBLEClient+CentralDelegate.swift (lines 155-210 for didConnect delegate)
      - GooseSwift/GooseAppModel.swift (lines 1-100 for @Published properties and ble reference)
      - GooseSwift/GooseBLETypes.swift (after P01-T01: WearableDescriptor static instances)
    </read_first>
    <action>
      In `GooseBLEClient+Commands.swift`, inside `processDiscoveredCharacteristics` at the point
      where `commandCharacteristic = characteristic` is assigned (line 846):
      Also set `activeDescriptor` based on the characteristic UUID prefix:
      ```swift
      commandCharacteristic = characteristic
      activeDescriptor = characteristic.uuid.uuidString.lowercased().hasPrefix("61080002")
        ? .whoopGen4 : .whoopGen5
      ```
      Add a log `record(source: "ble", title: "wearable_descriptor.set", body: "...")` line
      after the assignment using the existing `record(source:title:body:)` pattern.

      In `GooseBLEClient+CentralDelegate.swift`, inside `centralManager(_:didDisconnectPeripheral:error:)`,
      reset `activeDescriptor = nil` where other state is reset (follow the pattern of resetting
      `commandCharacteristic = nil`).

      In `GooseAppModel.swift`, add `@Published var connectedDeviceGeneration: String?`
      after the existing `@Published` block.

      In `GooseAppModel.swift`, observe the BLE connection state and propagate the generation.
      Follow the existing pattern where `GooseAppModel` listens to `ble.$connectionState.sink`:
      When `connectionState == "ready"`, set:
      ```swift
      connectedDeviceGeneration = ble.discoveredDevices
        .first(where: { $0.id == ble.activeDeviceIdentifier })?.generation
      ```
      When `connectionState == "disconnected"` or `"connect failed"`, set `connectedDeviceGeneration = nil`.
    </action>
    <acceptance_criteria>
      - `GooseBLEClient+Commands.swift` `processDiscoveredCharacteristics` sets `activeDescriptor` when `commandCharacteristic` is assigned
      - `activeDescriptor` is reset to `nil` on disconnect in `GooseBLEClient+CentralDelegate.swift`
      - `GooseAppModel.swift` contains `@Published var connectedDeviceGeneration: String?`
      - `GooseAppModel.swift` sets `connectedDeviceGeneration` from the connected device's generation on BLE ready state
      - `GooseAppModel.swift` sets `connectedDeviceGeneration = nil` on disconnect
    </acceptance_criteria>
  </task>

</tasks>

<verification>
  1. `grep -rn "supportsV5\|isV5Command" GooseSwift/` — must return zero results
  0b. `grep -n '"GEN4"' Rust/core/src/bridge.rs` — must return the parse_device_type match arm
  2. `grep -n "supportsHistoricalSync\|supportsAlarmCommands\|supportsClockCommands\|supportsSensorCommands" GooseSwift/GooseBLEClient+Commands.swift` — must show all 4 renamed definitions
  3. `grep -n "WearableDescriptor" GooseSwift/GooseBLETypes.swift` — must show struct definition
  4. `grep -n "generation" GooseSwift/GooseBLETypes.swift` — must show `let generation: String` in `GooseDiscoveredDevice`
  5. `grep -n "connectedDeviceGeneration" GooseSwift/GooseAppModel.swift` — must show `@Published var`
  6. Xcode build of the GooseSwift scheme for simulator succeeds (no compile errors from renamed properties or missing memberwise init args)
</verification>

<success_criteria>
  - `WearableDescriptor` struct exists with `.whoopGen4` and `.whoopGen5` static instances
  - `isV5CommandCharacteristic` no longer exists anywhere in the codebase
  - All 4 `supportsV5*` properties renamed to `supportsV5`-less equivalents and accept both `fd4b0002` and `61080002` prefixes via `activeDescriptor`
  - `GooseDiscoveredDevice.generation` is populated with `"4.0"`, `"5.0"`, or `"unknown"` at scan time
  - `GooseAppModel.connectedDeviceGeneration` reflects the connected device's generation
  - All `canSyncHistorical`, `canSyncClock`, `canWriteAlarm`, `canWriteHighFrequencyHistorySync` computed properties work correctly for Gen4 devices
</success_criteria>
---

## ## PLANNING COMPLETE
