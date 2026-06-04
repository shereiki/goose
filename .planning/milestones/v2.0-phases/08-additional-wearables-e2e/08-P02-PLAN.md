---
phase: "08"
plan: "08-P02"
title: "iOS BLE HR Monitor Extension + WearableDescriptor.genericHRMonitor + Notification Routing"
wave: 1
depends_on: []
files_modified:
  - GooseSwift/GooseBLETypes.swift
  - GooseSwift/GooseBLEClient+HRMonitor.swift
  - GooseSwift/GooseAppModel+NotificationPipeline.swift
  - GooseSwiftTests/GooseBLETypesTests.swift
autonomous: true
requirements:
  - WEAR-02
---

<objective>
Implement the iOS BLE layer for standard HR monitors (0x180D Heart Rate Service):
(1) Add `WearableDescriptor.genericHRMonitor` static instance to `GooseBLETypes.swift`, AND fix the
empty-prefix bug in `WearableDescriptor.isCommandCharacteristic` / `isCommandUUID` in the SAME task
(review MEDIUM-1 — the guard must land with the empty-prefix descriptor, not be discovered later).
(2) Extend `GooseNotificationEvent.rustDeviceType` to return `"HR_MONITOR"` for 0x2A37 characteristics,
using normalized (lowercased, hyphen-stripped) UUID comparison so both short (`2A37`) and full 128-bit
(`00002A37-0000-1000-8000-00805F9B34FB`) forms are matched (review MEDIUM-2).
(3) Create `GooseBLEClient+HRMonitor.swift` — a new extension file with a dedicated second
`CBCentralManager` for scanning 0x180D devices (separate from WHOOP scan), manual connect, and
characteristic subscription on 0x2A37. HR notifications MUST be delivered to `onNotification?` on a
background queue, never inline on `@MainActor` (review MEDIUM-3).
(4) Fix `GooseAppModel+NotificationPipeline.swift` so 0x2A37 notifications bypass WHOOP `0xaa` frame
reassembly and are stored via the existing capture pipeline.

Purpose: Deliver the iOS BLE acquisition path for standard HR monitors (WEAR-02) without contaminating
WHOOP connection state, and harden the descriptor/UUID-matching primitives flagged in cross-AI review.
Output: A working dedicated HR-monitor scan/connect/notify flow plus the `genericHRMonitor` descriptor
and hardened `WearableDescriptor` matching helpers.
</objective>

<must_haves>
  <truths>
    - WEAR-02: `GooseBLEClient+HRMonitor.swift` exists with `startHRMonitorScan()` and `stopHRMonitorScan()` methods that scan for `CBUUID(string: "180D")`
    - `GooseNotificationEvent.rustDeviceType` returns `"HR_MONITOR"` for the 0x2A37 characteristic in BOTH short form (`"2A37"`) and full 128-bit form (`"00002A37-0000-1000-8000-00805F9B34FB"`), case-insensitively
    - `WearableDescriptor.genericHRMonitor` static instance exists in `GooseBLETypes.swift` with `serviceUUIDPrefix: "180d"` and `commandCharacteristicPrefix: ""`
    - `WearableDescriptor.isCommandCharacteristic` and `isCommandUUID` return `false` when `commandCharacteristicPrefix` is empty (review MEDIUM-1 — guard lands in P02-T01)
    - All UUID prefix comparisons in `WearableDescriptor` use `.lowercased()` consistently (review MEDIUM-2)
    - 0x2A37 notifications from connected HR monitor devices are delivered to `onNotification?` callback on a BACKGROUND queue (never inline on `@MainActor` — review MEDIUM-3)
    - WHOOP scan state, `activePeripheral`, and `connectionState` are NOT modified by HR monitor scanning or connection
    - HR monitor scan uses a separate `CBCentralManager` instance — the WHOOP central is not repurposed
    - HR monitor connection is manual only — no auto-connect logic
  </truths>
  <artifacts>
    - path: "GooseSwift/GooseBLEClient+HRMonitor.swift"
      provides: "Dedicated HR monitor scan/connect/notify with separate CBCentralManager"
    - path: "GooseSwift/GooseBLETypes.swift"
      provides: "genericHRMonitor descriptor + HR_MONITOR rustDeviceType + empty-prefix guard"
  </artifacts>
  <key_links>
    - from: "GooseBLEClient+HRMonitor.swift (GooseBLEHRMonitorManager)"
      to: "GooseBLEClient.onNotification"
      via: "background-queue callback with GooseNotificationEvent(characteristicUUID: 2A37)"
  </key_links>
</must_haves>

<threat_model>
  <threats>
    <threat id="T-08-02" severity="medium">
      HR monitor scan could discover and accidentally connect to other non-HR BLE devices if the scan filter is too broad. Mitigation: HR monitor central scans exclusively for `[CBUUID(string: "180D")]`; only peripherals advertising exactly this service UUID are shown in the HR monitor device list.
    </threat>
    <threat id="T-08-03" severity="low">
      Malformed BLE device names used as device_type in upload could contain PII or excessively long strings. Mitigation: device name sanitization (trim whitespace, cap to 64 chars, fallback to "unknown_hr_monitor") is applied before passing to the capture pipeline.
    </threat>
    <threat id="T-08-06" severity="medium">
      Empty `commandCharacteristicPrefix` makes `hasPrefix("")` return `true`, so `genericHRMonitor` would falsely classify EVERY characteristic as a command characteristic — risking accidental writes to a read-only HR sensor. Mitigation: `isCommandCharacteristic`/`isCommandUUID` guard against empty prefix and return `false` (P02-T01).
    </threat>
  </threats>
</threat_model>

<tasks>

  <task id="P02-T01" type="execute">
    <title>Add WearableDescriptor.genericHRMonitor, fix empty-prefix guard, and extend rustDeviceType with normalized UUID matching in GooseBLETypes.swift</title>
    <read_first>
      - GooseSwift/GooseBLETypes.swift (full file — current WearableDescriptor struct + extension, its isCommandCharacteristic/isCommandUUID methods, and the GooseNotificationEvent.rustDeviceType computed property)
      - .planning/phases/08-additional-wearables-e2e/08-CONTEXT.md (D-07: WearableDescriptor.genericHRMonitor pattern; D-09: rustDeviceType = "HR_MONITOR")
      - .planning/phases/08-additional-wearables-e2e/08-PATTERNS.md (Pattern: WearableDescriptor Static Instance; Pattern: rustDeviceType computed property extension)
      - .planning/phases/08-additional-wearables-e2e/08-REVIEWS.md (MEDIUM-1 empty-prefix bug; MEDIUM-2 UUID normalization)
      - .planning/phases/06-whoop-gen4-ios-support/06-P03-SUMMARY.md (confirms isCommandUUID was added to WearableDescriptor — check exact current signatures before editing)
    </read_first>
    <action>
      In `GooseSwift/GooseBLETypes.swift`, make THREE changes. (Review MEDIUM-1 requires the empty-prefix
      guard to land HERE, in the same task that introduces the empty-prefix descriptor — do NOT defer it.)

      1. Add the `genericHRMonitor` static instance in `extension WearableDescriptor`, after the existing
         `.whoopGen4` instance. Use exactly `serviceUUIDPrefix: "180d"` (lowercased) and
         `commandCharacteristicPrefix: ""` (empty string — HR monitors are read-only notify devices with
         no command characteristic). Add a comment noting it describes Standard Bluetooth Heart Rate
         Service 0x180D / HR Measurement 0x2A37.

      2. Add an empty-prefix guard to BOTH `WearableDescriptor.isCommandCharacteristic(_:)` and
         `WearableDescriptor.isCommandUUID(_:)`. Each method must, as its first statement, return `false`
         when `commandCharacteristicPrefix.isEmpty` (`guard !commandCharacteristicPrefix.isEmpty else { return false }`).
         Rationale: `"".hasPrefix("")` evaluates to `true`, so without this guard `genericHRMonitor` would
         classify every characteristic as a command characteristic and risk writing to a read-only sensor.
         Also confirm both methods normalize the candidate UUID with `.lowercased()` before the `hasPrefix`
         comparison (the stored `serviceUUIDPrefix`/`commandCharacteristicPrefix` literals are already
         lowercase). If either method currently compares without `.lowercased()`, fix it (review MEDIUM-2).

      3. Update the `GooseNotificationEvent.rustDeviceType` computed property to add an `"HR_MONITOR"`
         branch. Order: first the GEN4 check (`characteristicUUID.lowercased().hasPrefix("610800")` → `"GEN4"`),
         then the HR monitor check, otherwise `"GOOSE"`. The HR monitor check MUST match both the short
         form and the full 128-bit form, case-insensitively. Compute a normalized form once:
         `let normalizedUUID = characteristicUUID.replacingOccurrences(of: "-", with: "").lowercased()`
         then return `"HR_MONITOR"` when `normalizedUUID == "2a37"` OR `normalizedUUID.hasPrefix("00002a37")`.
         This handles `"2A37"`, `"2a37"`, and `"00002A37-0000-1000-8000-00805F9B34FB"`. Do not break the
         existing GEN4/GOOSE behavior.
    </action>
    <acceptance_criteria>
      - `GooseBLETypes.swift` contains `static let genericHRMonitor = WearableDescriptor(serviceUUIDPrefix: "180d", commandCharacteristicPrefix: "")`
      - `WearableDescriptor.isCommandCharacteristic` contains `guard !commandCharacteristicPrefix.isEmpty else { return false }`
      - `WearableDescriptor.isCommandUUID` contains `guard !commandCharacteristicPrefix.isEmpty else { return false }`
      - `grep -c "commandCharacteristicPrefix.isEmpty" GooseSwift/GooseBLETypes.swift` returns 2
      - `GooseNotificationEvent.rustDeviceType` returns `"HR_MONITOR"` for both `"2A37"` and `"00002A37-0000-1000-8000-00805F9B34FB"` (verified by tests in P02-T04)
      - `GooseNotificationEvent.rustDeviceType` still returns `"GEN4"` for `610800`-prefixed UUIDs and `"GOOSE"` for all other UUIDs
      - Swift build succeeds (no compile errors introduced)
    </acceptance_criteria>
  </task>

  <task id="P02-T02" type="execute">
    <title>Create GooseBLEClient+HRMonitor.swift with dedicated scan/connect/notify for 0x180D (background-queue notification dispatch)</title>
    <read_first>
      - GooseSwift/GooseBLEClient+UserActions.swift (startScan/stopScan patterns — lines 13–145)
      - GooseSwift/GooseBLEClient.swift (lines 1–120 for class properties; lines 367–420 for UUID constants; standardHeartRateServiceID, standardHeartRateMeasurementID; the coreBluetoothQueue / notificationIngestQueue used for off-main-thread work)
      - GooseSwift/GooseBLEClient+CentralDelegate.swift (CBCentralManagerDelegate pattern for scanning and connecting)
      - GooseSwift/GooseBLEClient+PeripheralDelegate.swift (CBPeripheralDelegate — how notifications are subscribed and received; confirm WHOOP notifications are NOT delivered inline on @MainActor)
      - .planning/phases/08-additional-wearables-e2e/08-CONTEXT.md (D-07: separate scan mode; D-08: manual-only connection; D-09: notification routing)
      - .planning/phases/08-additional-wearables-e2e/08-RESEARCH.md (F-05: separate CBCentralManager; F-09: connection state separation)
      - .planning/phases/08-additional-wearables-e2e/08-PATTERNS.md (Pattern: BLE Extension File)
      - .planning/phases/08-additional-wearables-e2e/08-REVIEWS.md (MEDIUM-3: HR notifications must NOT route through @MainActor inline)
    </read_first>
    <action>
      Create `GooseSwift/GooseBLEClient+HRMonitor.swift`. File header: `import CoreBluetooth`,
      `import Foundation`, `import OSLog`, blank line, then the extension and helper class.

      Because Swift extensions cannot add stored properties to a class, use a file-level helper class
      `final class GooseBLEHRMonitorManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate`
      declared in this file, and add a single stored property `let hrMonitorManager = GooseBLEHRMonitorManager()`
      to `GooseBLEClient.swift` (alongside existing `let`-declared collaborators). The
      `extension GooseBLEClient` in this file exposes public delegating methods.

      `GooseBLEHRMonitorManager` properties (all `internal`, NOT `private`, so P03-T02 can read connection
      state for manual upload): `var central: CBCentralManager?`, `var discoveredHRDevices: [GooseDiscoveredDevice] = []`,
      `var hrPeripheral: CBPeripheral?`, `var hrConnectionState: String = "disconnected"`,
      `var connectedDeviceName: String?`, and `weak var owner: GooseBLEClient?`.

      `GooseBLEHRMonitorManager` behavior:
      1. `func start(queue: DispatchQueue)` — initializes `CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.goose.swift.hr-monitor"])`. The `queue` passed in is `GooseBLEClient`'s existing background CoreBluetooth queue — so all delegate callbacks run off the main thread (review MEDIUM-3).
      2. `func startScan()` — `central?.scanForPeripherals(withServices: [CBUUID(string: "180D")], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])`.
      3. `func stopScan()` — `central?.stopScan()`.
      4. `centralManager(_:didDiscover:advertisementData:rssi:)` — derive a sanitized device name: take `peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "unknown_hr_monitor"`, `.trimmingCharacters(in: .whitespacesAndNewlines)`, cap to 64 chars via `.prefix(64).description`, and replace empty-after-trim with `"unknown_hr_monitor"`. Append/update a `GooseDiscoveredDevice(id: peripheral.identifier, name: sanitizedName, rssi: RSSI.intValue, generation: "hr_monitor")` in `discoveredHRDevices` (dedupe by id, sort by RSSI descending). Publish to the UI on the main thread only for the discovered-list update (`DispatchQueue.main.async { ... self.owner?.objectWillChange.send() }`) — this is a UI-state hop, NOT the data path.
      5. `func connect(_ device: GooseDiscoveredDevice)` — find the peripheral by `device.id`, set `connectedDeviceName = device.name`, call `central?.connect(peripheral, options: nil)`. Manual only — no auto-reconnect.
      6. `centralManager(_:didConnect:)` — set `hrConnectionState = "connected"`, `hrPeripheral = peripheral`, `peripheral.delegate = self`, `peripheral.discoverServices([CBUUID(string: "180D")])`.
      7. `peripheral(_:didDiscoverServices:)` — for each service whose UUID matches 180D, `peripheral.discoverCharacteristics([CBUUID(string: "2A37")], for: service)`.
      8. `peripheral(_:didDiscoverCharacteristicsFor:)` — for the 0x2A37 characteristic, `peripheral.setNotifyValue(true, for: characteristic)`.
      9. `peripheral(_:didUpdateValueFor:error:)` for 0x2A37 — this callback already runs on the background CoreBluetooth queue (because the CBCentralManager was created with that queue in step 1). Build `GooseNotificationEvent(deviceID: peripheral.identifier, serviceUUID: "180D", characteristicUUID: "2A37", value: characteristic.value ?? Data(), capturedAt: Date())` and call `owner?.onNotification?(event)` DIRECTLY on this background queue — do NOT wrap it in `DispatchQueue.main.async` and do NOT call it from a `@MainActor` context (review MEDIUM-3; HR notifications can arrive at high frequency and must stay off the main actor, matching how WHOOP notifications are handled). Separately, for live HR display, call `owner?.handleStandardHeartRate(characteristic.value ?? Data(), characteristic: characteristic, capturedAt: Date())` (this existing method already performs its own main-thread hop for published UI state).
      10. `centralManager(_:didDisconnectPeripheral:error:)` — set `hrConnectionState = "disconnected"`, `hrPeripheral = nil`.

      `extension GooseBLEClient` public methods in this file:
      - `func startHRMonitorScan()` — set `hrMonitorManager.owner = self`, `hrMonitorManager.start(queue: <the existing background CoreBluetooth queue property on GooseBLEClient>)`, `hrMonitorManager.startScan()`, then `record(source: "ble.hr_monitor", title: "scan.start")`.
      - `func stopHRMonitorScan()` — `hrMonitorManager.stopScan()`, `record(source: "ble.hr_monitor", title: "scan.stop")`.
      - `func connectHRMonitor(_ device: GooseDiscoveredDevice)` — `hrMonitorManager.connect(device)`, `record(source: "ble.hr_monitor", title: "connect.requested", body: device.name)`.

      In `GooseBLEClient.swift`, add the single stored property `let hrMonitorManager = GooseBLEHRMonitorManager()`.
    </action>
    <acceptance_criteria>
      - `GooseSwift/GooseBLEClient+HRMonitor.swift` exists
      - File contains `final class GooseBLEHRMonitorManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate`
      - File contains `extension GooseBLEClient` with `startHRMonitorScan()`, `stopHRMonitorScan()`, `connectHRMonitor(_:)`
      - `startHRMonitorScan()` (via the manager) scans for `CBUUID(string: "180D")` — not `whoopServices`
      - The 0x2A37 `didUpdateValueFor` handler calls `owner?.onNotification?(event)` directly on the background CoreBluetooth queue and is NOT wrapped in `DispatchQueue.main.async`: `grep -A12 "didUpdateValueFor" GooseSwift/GooseBLEClient+HRMonitor.swift | grep -c "DispatchQueue.main.async" ` returns 0 for the onNotification call site
      - `GooseBLEHRMonitorManager` exposes `hrPeripheral`, `hrConnectionState`, and `connectedDeviceName` as `internal` (non-private) properties
      - `GooseBLEClient.swift` has `let hrMonitorManager = GooseBLEHRMonitorManager()` stored property
      - Swift build succeeds with no compile errors
    </acceptance_criteria>
  </task>

  <task id="P02-T03" type="execute">
    <title>Fix GooseAppModel+NotificationPipeline.swift to handle "HR_MONITOR" rustDeviceType (bypass 0xaa reassembly)</title>
    <read_first>
      - GooseSwift/GooseAppModel+NotificationPipeline.swift (lines 783–844: gooseFrames implementation; the 0xaa frame-start search logic)
      - GooseSwift/GooseAppModel+NotificationPipeline.swift (lines 704–714: notificationIngestResult — calls gooseFrames; confirm it is `nonisolated`/off-main as in current code)
      - .planning/phases/08-additional-wearables-e2e/08-RESEARCH.md (F-03: HR GATT bytes are NOT 0xaa-delimited WHOOP frames; standard GATT bytes will be dropped)
      - .planning/phases/08-additional-wearables-e2e/08-CONTEXT.md (D-09: HR monitor notifications routed via rustDeviceType = "HR_MONITOR")
      - .planning/phases/08-additional-wearables-e2e/08-REVIEWS.md (MEDIUM-3: keep this path off @MainActor)
    </read_first>
    <action>
      The `gooseFrames(in:event:)` function searches for `0xaa` start bytes; for standard 0x2A37 HR
      notifications the raw bytes are a GATT measurement payload, never `0xaa`-framed, so they would be
      dropped as zero frames.

      In `notificationIngestResult(for:)`, add an early-return branch BEFORE the WHOOP reassembly call:
      when `event.rustDeviceType == "HR_MONITOR"`, treat the entire notification value as a single frame.
      Compute `let frameHex = event.value.hexString`; if `frameHex.isEmpty`, return a
      `NotificationIngestResult` with `frames: []` and all byte counters zero; otherwise return a
      `NotificationIngestResult` whose `frames` array contains exactly one `NotificationFrame(hex: frameHex)`
      with `bufferedBytes: 0`, `expectedBytes: nil`, `droppedBytes: 0`, `usedBufferedData: false`. Leave the
      existing non-HR_MONITOR path (the `gooseFrames(in:event:)` reassembly) completely unchanged. Do not
      add a `@MainActor` annotation — this function must remain off the main actor so high-frequency HR
      notifications never block the main thread (review MEDIUM-3).
    </action>
    <acceptance_criteria>
      - `GooseAppModel+NotificationPipeline.swift` `notificationIngestResult(for:)` contains an `if event.rustDeviceType == "HR_MONITOR"` early-return branch
      - The HR_MONITOR branch returns a `NotificationIngestResult` with exactly one `NotificationFrame` containing the hex of the raw 0x2A37 bytes (or zero frames when the value is empty)
      - The WHOOP path (non-HR_MONITOR) is unchanged
      - `notificationIngestResult(for:)` is NOT annotated `@MainActor` (remains `nonisolated`/off-main as before)
      - Swift build succeeds with no compile errors
    </acceptance_criteria>
  </task>

  <task id="P02-T04" type="execute">
    <title>Add Swift unit tests for genericHRMonitor, empty-prefix guard, and normalized rustDeviceType matching</title>
    <read_first>
      - GooseSwiftTests/GooseBLETypesTests.swift (existing test file for rustDeviceType and WearableDescriptor — from Phase 6 P03)
      - GooseSwift/GooseBLETypes.swift (current state after T01 — genericHRMonitor, empty-prefix guard, normalized HR_MONITOR rustDeviceType)
      - .planning/phases/06-whoop-gen4-ios-support/06-P03-SUMMARY.md (GooseSwiftTests target setup — bundle ID, TEST_HOST)
      - .planning/phases/08-additional-wearables-e2e/08-REVIEWS.md (MEDIUM-1 guard verification; MEDIUM-2 short vs full UUID forms)
    </read_first>
    <action>
      The empty-prefix guard itself is added in P02-T01 (production code). This task adds the tests that
      PROVE the guard and the normalized UUID matching. In `GooseSwiftTests/GooseBLETypesTests.swift`, add
      test methods to the existing test class:

      1. `test_genericHRMonitor_serviceUUIDPrefix` — assert `WearableDescriptor.genericHRMonitor.serviceUUIDPrefix == "180d"`.
      2. `test_genericHRMonitor_commandCharacteristicPrefix_empty` — assert `WearableDescriptor.genericHRMonitor.commandCharacteristicPrefix == ""`.
      3. `test_genericHRMonitor_isCommandUUID_returnsFalseForAnyUUID` — assert `WearableDescriptor.genericHRMonitor.isCommandUUID(CBUUID(string: "2A37")) == false` AND `WearableDescriptor.genericHRMonitor.isCommandUUID(CBUUID(string: "FD4B0002-...")) == false` (proves the empty-prefix guard from MEDIUM-1).
      4. `test_whoopGen4_isCommandUUID_stillMatchesCommandPrefix` — sanity check that the guard did NOT break the populated case: assert `WearableDescriptor.whoopGen4.isCommandUUID(CBUUID(string: "61080002-..."))` returns `true` for the Gen4 command UUID.
      5. `test_rustDeviceType_2A37_short_returnsHRMonitor` — `GooseNotificationEvent` with `characteristicUUID: "2A37"`, assert `rustDeviceType == "HR_MONITOR"`.
      6. `test_rustDeviceType_2a37_lowercase_returnsHRMonitor` — `characteristicUUID: "2a37"`, assert `"HR_MONITOR"`.
      7. `test_rustDeviceType_2A37_full128bit_returnsHRMonitor` — `characteristicUUID: "00002A37-0000-1000-8000-00805F9B34FB"`, assert `"HR_MONITOR"` (proves MEDIUM-2 full-form matching).
      8. `test_rustDeviceType_610800_stillReturnsGEN4` — `characteristicUUID: "61080003-..."`, assert `"GEN4"`.
      9. `test_rustDeviceType_fd4b_stillReturnsGOOSE` — `characteristicUUID: "fd4b0003-..."`, assert `"GOOSE"`.

      Use the existing test class and helper patterns already present in the file (do not create a new file
      or target). For the full Gen4/Goose command UUID literals, copy the exact prefixes used by
      `whoopGen4`/`whoopGen5` from `GooseBLETypes.swift`.
    </action>
    <acceptance_criteria>
      - `GooseSwiftTests/GooseBLETypesTests.swift` contains at least 7 new test methods for Phase 8 additions
      - Tests include a full-128-bit-form assertion: `characteristicUUID: "00002A37-0000-1000-8000-00805F9B34FB"` → `rustDeviceType == "HR_MONITOR"`
      - Tests include `genericHRMonitor.isCommandUUID(...)` returning `false` and `whoopGen4.isCommandUUID(...)` returning `true`
      - Swift build succeeds; test target compiles and the new tests pass
    </acceptance_criteria>
  </task>

</tasks>

<verification>
  1. `grep "genericHRMonitor" GooseSwift/GooseBLETypes.swift` — static instance present
  2. `grep "HR_MONITOR" GooseSwift/GooseBLETypes.swift` — rustDeviceType branch present
  3. `grep -c "commandCharacteristicPrefix.isEmpty" GooseSwift/GooseBLETypes.swift` — returns 2 (guard in both isCommandCharacteristic and isCommandUUID)
  4. `ls GooseSwift/GooseBLEClient+HRMonitor.swift` — extension file exists
  5. `grep "startHRMonitorScan\|stopHRMonitorScan\|connectHRMonitor" GooseSwift/GooseBLEClient+HRMonitor.swift` — public methods present
  6. `grep "HR_MONITOR" GooseSwift/GooseAppModel+NotificationPipeline.swift` — early-return branch present
  7. `grep "00002a37\|00002A37" GooseSwift/GooseBLETypes.swift` — full-form normalization present
  8. Swift build + GooseSwiftTests pass (Xcode test or xcodebuild test on iOS Simulator)
</verification>

<success_criteria>
  - [ ] `WearableDescriptor.genericHRMonitor` exists with correct UUIDs
  - [ ] `isCommandCharacteristic` and `isCommandUUID` have the empty-prefix guard (added in P02-T01, not deferred)
  - [ ] `GooseNotificationEvent.rustDeviceType` returns `"HR_MONITOR"` for short AND full-128-bit 0x2A37 forms, case-insensitively
  - [ ] `GooseBLEClient+HRMonitor.swift` exists with scan/connect/notify using a dedicated `CBCentralManager`
  - [ ] HR notifications are delivered to `onNotification?` on a background queue (never inline on @MainActor)
  - [ ] `GooseAppModel+NotificationPipeline.swift` passes HR_MONITOR raw bytes through without 0xaa reassembly, off the main actor
  - [ ] Swift unit tests cover genericHRMonitor, empty-prefix guard, and short/full/case-insensitive 0x2A37 matching
  - [ ] WEAR-02 requirement is fully satisfied
</success_criteria>
