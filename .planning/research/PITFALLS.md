# Pitfalls Research

**Domain:** v3.0 feature additions to existing iOS BLE + Rust core app — HR monitor scan UI, independent HR capture, CR-02 device_id filter, Recovery V2 dashboard, pt-PT localisation, WHOOP 4.0 RTC sync, BLE reconnect backoff
**Researched:** 2026-06-04
**Confidence:** HIGH — all pitfalls derived from direct code inspection of the live codebase (GooseBLEClient, GooseBLEClient+HRMonitor, GooseBLEClient+CentralDelegate, GooseBLEClient+Commands, HealthDataStore, bridge.rs, store.rs) plus known v2.0 revert history (CR-02 namespace mismatch, WEAR-02 partial state).

---

## Critical Pitfalls

Mistakes that cause data loss, silent misrouting, rewrites, or App Store rejection.

---

### Pitfall 1: Two CBCentralManager instances sharing one DispatchQueue — delegate callbacks are serialised, not parallelised

**What goes wrong:**
`GooseBLEClient` creates its `CBCentralManager` on `coreBluetoothQueue` (a private `.utility` DispatchQueue). `GooseBLEHRMonitorManager.start(queue:)` is called with the same `coreBluetoothQueue`. Both managers share a single serial queue. This means a slow delegate callback from the WHOOP manager (e.g., a heavy `didDiscover` path that calls `objectWillChange.send()` with a `DispatchQueue.main.async`) blocks the HR monitor delegate from receiving its next notification, and vice versa. Under normal conditions this is benign; under high HR notification frequency (1 Hz from 0x2A37) combined with a WHOOP historical sync (which fires many delegate callbacks in sequence), the shared queue becomes a bottleneck and HR notifications are delayed or queued beyond the next BLE connection event deadline.

**Why it happens:**
`GooseBLEHRMonitorManager.start(queue:)` was written to accept any queue and was handed `coreBluetoothQueue` for convenience (the WHOOP manager already uses it). Sharing a queue is not forbidden by CoreBluetooth, but it creates a hidden serialisation dependency between two independent BLE sessions.

**How to avoid:**
Give `GooseBLEHRMonitorManager` its own dedicated `DispatchQueue` (e.g., `com.goose.swift.corebluetooth.hr`). Isolate WHOOP and HR monitor delegate execution. The HR monitor `didUpdateValueFor` callback explicitly documents "do NOT hop to @MainActor" — this discipline is correct, but the queue isolation must also be correct to make it effective.

**Warning signs:**
- HR notifications arrive in bursts with multi-second gaps during a WHOOP historical sync.
- `didDiscover` for HR monitor is logged only after a WHOOP historical sync command completes.
- Instruments shows both CBCentralManager delegates competing on the same queue.

**Phase to address:** WEAR-02 (HR scan UI and independent capture) — create the dedicated HR monitor queue when wiring up `startHRMonitorScan()`.

---

### Pitfall 2: `discoveredHRDevices` and `hrConnectionState` are plain `var` properties on a non-`@Published`, non-`@MainActor` class — UI reads them from the wrong thread

**What goes wrong:**
`GooseBLEHRMonitorManager` is a plain `NSObject` subclass with `var discoveredHRDevices: [GooseDiscoveredDevice] = []` and `var hrConnectionState: String = "disconnected"`. These are mutated on the CoreBluetooth queue (inside delegate callbacks) and read from SwiftUI views (on the main thread) via `ble.hrMonitorManager.discoveredHRDevices`. There is no synchronisation. The current code does send `objectWillChange.send()` from `DispatchQueue.main.async`, which causes the view to re-render — but the actual array read happens on the main thread immediately after, while the CoreBluetooth queue may simultaneously be mutating it (e.g., `discoveredHRDevices.sort`). This is a data race.

**Why it happens:**
`GooseBLEHRMonitorManager` was written as a helper object that forwards to `owner?.objectWillChange.send()`. The `@Published` wrapper is on `GooseBLEClient`, not on the manager. Developers assume that because `objectWillChange.send()` is dispatched to main, the data is safe to read on main — but the array mutation happens on the BT queue before the `DispatchQueue.main.async` block fires; the read may race with a subsequent mutation on the BT queue if two scan results arrive close together.

**How to avoid:**
Either: (a) make `GooseBLEHRMonitorManager` publish its state through `@Published` properties on `GooseBLEClient` proper (array mutations happen on BT queue, then a `DispatchQueue.main.async` block copies the snapshot to `@Published` properties owned by `GooseBLEClient`), or (b) protect the array with an `NSLock` (consistent with how `notificationContextLock` is used elsewhere in the codebase). Option (a) is architecturally cleaner and matches the existing `liveHeartRateBPM` pattern.

**Warning signs:**
- SwiftUI list of discovered HR devices occasionally shows duplicates or missing entries that resolve on the next scroll.
- Thread Sanitiser reports a data race on `discoveredHRDevices` during a heavy scan session.
- `discoveredHRDevices` is accessed directly in a SwiftUI `ForEach` via `ble.hrMonitorManager.discoveredHRDevices`.

**Phase to address:** WEAR-02 — introduce the synchronisation pattern before wiring the scan UI to avoid shipping a latent race.

---

### Pitfall 3: `startHRMonitorScan()` has no caller and `GooseBLEHRMonitorManager.central` starts as `nil` — calling `startScan()` before `start(queue:)` is a silent no-op

**What goes wrong:**
`GooseBLEHRMonitorManager.startScan()` calls `central?.scanForPeripherals(...)`. If `central` is `nil` (i.e., `start(queue:)` has not been called yet), this is a silent no-op — no error, no log, no scan. The `start(queue:)` guard (`guard central == nil else { return }`) means `start` is idempotent, but calling `startScan()` before `start()` simply does nothing. A UI button that calls `startHRMonitorScan()` → `hrMonitorManager.startScan()` would appear to work (no crash) but produce zero discovered devices.

**Why it happens:**
`start(queue:)` initialises the `CBCentralManager`, which triggers `centralManagerDidUpdateState`. The manager is only ready to scan after `.poweredOn` is received — which is asynchronous. The current implementation in `GooseBLEClient.startHRMonitorScan()` calls `start(queue:)` and `startScan()` in sequence, but `startScan()` fires before `centralManagerDidUpdateState(.poweredOn)` is received. On first launch this always produces a silent no-op scan.

**How to avoid:**
Implement the standard CoreBluetooth pattern: call `scanForPeripherals` only inside `centralManagerDidUpdateState` when `central.state == .poweredOn`, using a stored `pendingScan: Bool` flag set by `startScan()`. This is already done for the WHOOP manager via `startupReconnectAttempted`. Apply the identical pattern to `GooseBLEHRMonitorManager`.

**Warning signs:**
- `startHRMonitorScan()` is called and returns without error but no devices appear in the list.
- No `"scan.start"` CoreBluetooth system log entry appears in Console.app for the HR manager.
- `hrMonitorManager.central?.isScanning` is `false` immediately after `startHRMonitorScan()`.

**Phase to address:** WEAR-02 — the very first thing to implement before any UI is the `centralManagerDidUpdateState` → scan flow.

---

### Pitfall 4: HR monitor frames currently gated on `onNotification` which is only wired during WHOOP capture — independent HR capture requires a separate write path

**What goes wrong:**
In `GooseBLEHRMonitorManager.peripheral(_:didUpdateValueFor:)`, the HR notification is delivered via `owner?.onNotification?(event)`. The `onNotification` closure on `GooseBLEClient` is set in `GooseAppModel+NotificationPipeline.swift` and feeds into `CaptureFrameWriteQueue`, which requires an active `capture_session_id`. If a WHOOP session is not active, `captureSessionID` on `CaptureFrameWriteQueue` is `nil`, and frames are not persisted. The HR monitor cannot independently persist data.

**Why it happens:**
The HR monitor was wired into the existing `onNotification` pipeline in v2.0 as the fastest path to get E2E data flow working. The `CaptureFrameWriteQueue` was designed for WHOOP capture sessions, not for a continuously-running HR monitor that operates independently of WHOOP.

**How to avoid:**
Introduce a separate `CaptureFrameWriteQueue` instance (or a lighter `HRFrameWriteQueue`) for the HR monitor that uses a permanent session identifier (not gated on user-initiated capture). Alternatively, give `GooseBLEHRMonitorManager` its own `onHRNotification` closure distinct from `onNotification`, and route it to a standalone SQLite write path in Rust. The HR monitor's 0x2A37 frames are structurally simpler (already parsed by `heart_rate_gatt_protocol.rs`) and do not need the full WHOOP frame reassembly pipeline.

**Warning signs:**
- HR monitor shows live heart rate (via `handleStandardHeartRate`) but no frames appear in `decoded_frames` after disconnecting WHOOP.
- `captureSessionID` is `nil` when the HR monitor is active but no WHOOP session is running.
- HR data disappears from the server after a WHOOP session ends even though the HR monitor remains connected.

**Phase to address:** WEAR-02 — define the independent write path before implementing the capture session decoupling.

---

### Pitfall 5: CR-02 device_id filter — the namespace mismatch that caused the v2.0 revert

**What goes wrong:**
In `upload_get_recent_decoded_streams_bridge`, the `device_id` argument passed from Swift is `ble.activeDeviceIdentifier?.uuidString` — a CoreBluetooth `peripheral.identifier` UUID (e.g., `"A1B2C3D4-..."`). The `decoded_frames` table stores `device_model TEXT NOT NULL` (the sanitised BLE device name, e.g., `"WHOOP 5B1234"`) and `active_device_id TEXT` (also the CoreBluetooth UUID when passed). The `ble_raw_notifications` table stores `device_id TEXT` (the CoreBluetooth UUID) and `active_device_name TEXT` (the BLE device name).

The mismatch: the filter tried to compare `device_id` (UUID string) against `device_model` (name string). These two fields are in different namespaces — a UUID never equals a device name. Any filter of the form `WHERE device_model = ?` with a UUID argument returns zero rows. The v2.0 revert replaced the filter with the time-window-only approach (`since_ts`).

**Why it happens:**
The schema evolved over multiple phases. `decoded_frames` was designed with `device_model` (name-based identity) while the upload bridge was designed with `device_id` (UUID-based identity). No single place in the codebase maps UUID → device name at storage time for `decoded_frames`. The upload query cannot join the two without a schema normalisation step.

**How to avoid:**
Fix at the schema level, not the query level. Option A: add `active_device_id TEXT` to `decoded_frames` (store the CoreBluetooth UUID alongside `device_model`) as a migration, then filter `WHERE active_device_id = ?`. Option B: pass `device_model` (the name) from Swift to the upload bridge and filter by name. Option A is more robust because names are not stable (user can rename a Bluetooth device). The migration must include a `CREATE INDEX IF NOT EXISTS decoded_frames_device_id ON decoded_frames(active_device_id)` to keep the filter performant.

**Warning signs:**
- `upload_get_recent_decoded_streams_bridge` returns frames for all devices even when `device_id` is set.
- `SELECT COUNT(*) FROM decoded_frames WHERE device_model = 'A1B2C3D4-...'` returns zero.
- The filter was re-implemented without a schema migration step.

**Phase to address:** CR-02 — before writing any filter logic, define which column carries the UUID and add the migration.

---

### Pitfall 6: Recovery V2 bridge queries are synchronous and called from `@MainActor` — blocks the main thread

**What goes wrong:**
`HealthDataStore` is `@MainActor`. The existing `refreshBridgeCatalogs()` and `runPacketInputs()` correctly dispatch to `packetInputQueue` before calling `bridge.requestValue(...)`. However, a naive Recovery V2 implementation that adds new metric queries directly inside a `@MainActor` function (e.g., inside a view's `.onAppear` or inside a `@MainActor func refresh()`) calls the synchronous Rust bridge on the main thread. The bridge documentation in `CLAUDE.md` explicitly states: "Never call from `@MainActor` with expensive methods; always dispatch to a background queue first." A metric aggregation over 30 days of `decoded_frames` can take 200–500 ms.

**Why it happens:**
The `HealthDataStore.bridge` property is accessible from any `@MainActor` context. There is no compile-time enforcement preventing a `@MainActor` function from calling `bridge.request(...)` directly. The correct dispatch pattern (background queue → main async for state mutation) is established in existing extensions but not enforced architecturally.

**How to avoid:**
Every new bridge query in Recovery V2 must follow the established pattern: (1) capture `let bridge = self.bridge` and `let databasePath = self.databasePath` on `@MainActor`, (2) `packetInputQueue.async { let result = bridge.request(...) ... DispatchQueue.main.async { self.recoveryV2State = result } }`. Never call `bridge.request(...)` directly inside a `Task { @MainActor in ... }` block.

**Warning signs:**
- Adding `try bridge.request(method: "metrics.recovery_v2_*", args: ...)` directly inside a `@MainActor func` without a background queue dispatch.
- UI freezes for 200+ ms when navigating to the Recovery V2 dashboard.
- Instruments shows the main thread blocked in `goose_bridge_handle_json` during dashboard load.

**Phase to address:** Recovery V2 dashboard phase — enforce the background-dispatch rule as a phase acceptance criterion, not an afterthought.

---

### Pitfall 7: pt-PT localisation — zero existing infrastructure, 310 hardcoded string literals in SwiftUI views

**What goes wrong:**
The app has no localisation infrastructure: no `.xcstrings` file, no `.lproj` directories, zero `NSLocalizedString` / `String(localized:)` calls. All 310+ `Text("...")`, `Label("...", ...)`, and `Button("...")` literals are raw English strings. SwiftUI's `Text("Literal string")` initialiser uses `LocalizedStringKey` by default — which means SwiftUI will attempt to look up the literal in a string catalog when one exists. Without a string catalog, SwiftUI renders the raw literal. Adding a string catalog later is safe (fallback = raw literal), but the scale is large: extracting 310+ strings from 80 SwiftUI files is significant mechanical work.

The specific pitfall: Xcode's "Export Localizations" and String Catalog migration tool generates a `.xcstrings` file from the project, but it does not handle strings that are constructed programmatically (e.g., `"Score: \(score)"` or `ble.connectionState`). Those require manual `String(localized:)` wrapping. Status strings like `"disconnected"`, `"connecting"`, `"reconnecting after disconnect"` are set in Swift code (not in SwiftUI `Text`), so they are not auto-extracted. If these status strings remain untranslated, the UI will show English status text alongside Portuguese UI labels — a jarring mixed-language experience.

**Why it happens:**
The app was built for a single-user personal use case. Localisation was never a goal. The `@Published` string properties (`connectionState`, `reconnectState`, `strapClockStatus`, etc.) are set via raw English literals scattered across 15+ files and fed directly to SwiftUI views via `LabeledContent("...", value: ble.connectionState)`. These do not go through `LocalizedStringKey`.

**How to avoid:**
Phase the migration: (1) Create the `.xcstrings` file and run Xcode's String Catalog extraction to cover all static `Text("...")` literals automatically. (2) Separately, audit all `@Published var` string properties that are displayed in views and convert them to localisation-safe patterns — either enum-based status (with a `localizedDescription` computed property) or explicit `String(localized: "...", bundle: .main)` at the assignment site. Do not attempt to do both in the same phase — the static literal extraction is mechanical and safe; the dynamic string conversion is architectural and risky.

**Warning signs:**
- Xcode shows a new `.xcstrings` file in the project but status labels (`connectionState`, `historicalSyncStatus`, etc.) still show English text in the pt-PT UI.
- `LabeledContent("Reconnect", value: ble.reconnectState)` with `reconnectState = "reconnecting after disconnect"` — the label is translated but the value is not.
- `Text(ble.catalogStatus)` is not in the String Catalog because it is not a literal.

**Phase to address:** pt-PT localisation phase — split into two sub-phases: static catalog extraction first, dynamic string conversion second.

---

### Pitfall 8: WHOOP 4.0 RTC sync — writing the SET_TIME command before the command characteristic is confirmed as writable causes a silent failure

**What goes wrong:**
`writeClockCommand(_:syncIfNeeded:)` has six guards before writing: `!isHistoricalSyncing`, `pendingClockCommand == nil`, `pendingAlarmCommand == nil`, `activePeripheral != nil && commandCharacteristic != nil`, `connectionState == "ready"`, and `supportsClockCommands`. The `connectionState == "ready"` guard is the critical one: it transitions from `"discovering"` only after `processDiscoveredCharacteristics` runs and finds the command characteristic. If the auto-sync logic attempts RTC sync immediately after `didConnect` (but before `discoverServices` → `discoverCharacteristics` completes), all six guards are evaluated with `commandCharacteristic == nil` and the command is silently discarded with `failClockCommand(...)`. No retry is scheduled.

**Why it happens:**
WHOOP 4.0 RTC sync is triggered by comparing the strap clock reading against wall time. The read itself (`ClockCommandKind.get`) is sent after `connectionState == "ready"`. But developers implementing the auto-sync feature (send a SET_TIME immediately after connect if the clock is drifted) may trigger the SET_TIME before the read completes, or schedule it in `centralManager(_:didConnect:)` before the GATT discovery cycle finishes.

**How to avoid:**
Always sequence RTC sync as: (1) wait for `connectionState == "ready"`, (2) send GET clock command, (3) in `HistoricalHandlers.handleClockResponse`, if `abs(offset) > threshold`, send SET clock command. Never send SET_TIME directly from the `didConnect` callback. The existing `writeClockCommand` guard on `connectionState == "ready"` is correct — the risk is bypassing it by using a DispatchWorkItem scheduled from `didConnect` with a fixed delay (e.g., `asyncAfter(deadline: .now() + 2.0)`) that may or may not clear the GATT discovery window.

**Warning signs:**
- `strapClockStatus = "Clock command needs active WHOOP command characteristic."` logged during the GATT discovery window.
- SET_TIME is sent from `centralManager(_:didConnect:)` or `centralManagerDidUpdateState` instead of from `handleClockResponse`.
- `asyncAfter` used to work around GATT timing instead of waiting for `connectionState == "ready"`.

**Phase to address:** WHOOP 4.0 RTC sync phase — define the sequencing contract (GET → response → SET if needed) in the phase plan before writing code.

---

### Pitfall 9: BLE reconnect backoff — `DispatchWorkItem` cancel race when a new connection arrives before the backoff timer fires

**What goes wrong:**
The reconnect backoff will schedule a `DispatchWorkItem` on `coreBluetoothQueue` after a failed connection attempt. The pattern exists elsewhere in the codebase (`historicalCommandTimeoutWorkItem`, `clockCommandTimeoutWorkItem`) but with a bug-prone pattern: if `connect(peripheral:reason:)` is called manually by the user while a backoff timer is pending, the timer is not cancelled before the manual connection proceeds. When the timer fires, it calls `connect(...)` a second time on a peripheral that is already in the `.connecting` state. CoreBluetooth silently ignores the duplicate `connect` call, but `autoReconnectInFlight` is set to `true` a second time, and `pendingConnectionReason` is overwritten.

For the HR monitor delegate, the pitfall is more severe: `GooseBLEHRMonitorManager` has no backoff state, no `reconnectWorkItem` property, and no `NSLock` protecting concurrent access from the two BT queues (WHOOP and HR). Adding backoff to the HR monitor without proper cancellation means a stale backoff timer from the HR manager fires on the HR BT queue while the WHOOP manager's disconnect handler is running on the WHOOP BT queue — these can concurrently mutate shared state on `GooseBLEClient` (e.g., `hrConnectionState`, `owner` reference).

**Why it happens:**
The existing reconnect code in `GooseBLEClient+CentralDelegate.swift` calls `connect(peripheral, reason: reconnectReason)` directly in `centralManager(_:didDisconnectPeripheral:)` without a delay. Backoff requires a delay — and delays require `DispatchWorkItem` management. The cancellation contract is easy to get wrong: the workItem must be cancelled (a) in `centralManager(_:didConnect:)`, (b) in `stopScan`, and (c) when the user manually disconnects. Missing any of these produces a spurious reconnect attempt after the condition was already resolved.

**How to avoid:**
Follow the existing `clockCommandTimeoutWorkItem` pattern exactly: store the workItem as a `var reconnectBackoffWorkItem: DispatchWorkItem?` on the relevant manager, cancel it at every state transition that resolves the disconnect, and use `[weak self]` in the workItem closure. For the HR monitor, the backoff workItem must be stored on `GooseBLEHRMonitorManager` (not on `GooseBLEClient`) to avoid cross-queue state access. Apply backoff to both managers independently — do not share state between them.

**Warning signs:**
- Two `"reconnect.requested"` log entries within milliseconds of each other after a manual user reconnect.
- `autoReconnectInFlight` is `true` after a successful connection (should be reset to `false` in `didConnect`).
- HR monitor reconnect fires after the user has already manually disconnected.

**Phase to address:** BLE reconnect backoff phase — implement WHOOP backoff first, then apply the same pattern to the HR monitor as a separate step.

---

### Pitfall 10: `GooseBLEHRMonitorManager` uses `owner?.objectWillChange.send()` but `hrMonitorManager` is not `@Published` on `GooseBLEClient` — SwiftUI does not observe it

**What goes wrong:**
`GooseBLEClient` is `ObservableObject`. `hrMonitorManager` is a plain `let` constant (not `@Published`). SwiftUI views that access `ble.hrMonitorManager.discoveredHRDevices` do not receive automatic invalidation when `discoveredHRDevices` changes — only when `objectWillChange.send()` fires on `GooseBLEClient`. The current code manually calls `owner?.objectWillChange.send()` from `DispatchQueue.main.async` to work around this. This is fragile: if `owner` is `nil` at the time the async block fires (e.g., `GooseBLEClient` was deallocated), the update is silently dropped. More importantly, any new state on `GooseBLEHRMonitorManager` (e.g., `hrConnectionState` changing from `"connected"` to `"disconnected"`) that is not manually accompanied by `objectWillChange.send()` will not update the UI.

**Why it happens:**
The manual `objectWillChange.send()` pattern was used to avoid refactoring `GooseBLEClient`. It works for the `discoveredHRDevices` list (which always fires the send) but is fragile for other state properties where a developer may mutate the property and forget the `owner?.objectWillChange.send()` call.

**How to avoid:**
Promote all HR monitor state that the UI needs to `@Published` properties on `GooseBLEClient` directly: `@Published var discoveredHRDevices: [GooseDiscoveredDevice] = []`, `@Published var hrConnectionState = "disconnected"`. Mutations happen on the BT queue, but assignments to `@Published` properties must be dispatched to `DispatchQueue.main.async`. Remove the manual `objectWillChange.send()` call from `GooseBLEHRMonitorManager`. This is the correct pattern already used for `liveHeartRateBPM` and `connectionState`.

**Warning signs:**
- HR device list updates in the SwiftUI view only when navigating away and back, not in real time during scan.
- `hrConnectionState == "connected"` but the UI still shows "disconnected" until the user taps a button.
- A new `@Published` property is added to `GooseBLEHRMonitorManager` without a corresponding `objectWillChange.send()`.

**Phase to address:** WEAR-02 — refactor observation model before wiring scan UI to avoid shipping broken reactivity.

---

## Moderate Pitfalls

---

### Pitfall 11: `CBCentralManagerOptionRestoreIdentifierKey` for the HR monitor will trigger `willRestoreState` on launch — handler is currently a no-op stub

**What goes wrong:**
`GooseBLEHRMonitorManager.start(queue:)` sets `CBCentralManagerOptionRestoreIdentifierKey: "com.goose.swift.hr-monitor"`. This opts the HR manager into CoreBluetooth state restoration. On next app launch (e.g., after a crash or background termination), CoreBluetooth will call `centralManager(_:willRestoreState:)` on `GooseBLEHRMonitorManager` with a dictionary containing the previously connected HR peripheral. The current implementation of `willRestoreState` is a stub: `// State restoration not required for manual-only HR monitor connections`. This comment is incorrect if the HR monitor is running an independent capture session that should survive app restart. If state restoration is ignored, the restored peripheral is leaked — it remains in CoreBluetooth's connection pool as a zombie peripheral that the app does not manage, and reconnecting to the same HR monitor on the next manual scan may fail with "already connected".

**Why it happens:**
The `CBCentralManagerOptionRestoreIdentifierKey` was added to follow the WHOOP manager pattern, but its implications (state restoration at launch) were not addressed. The stub comment implies a deliberate decision, but the consequences of ignoring restoration for an independent capture session were not considered.

**How to avoid:**
Either (a) remove `CBCentralManagerOptionRestoreIdentifierKey` from the HR manager (simpler — HR monitor is manual-connect, not background-kept), or (b) implement `willRestoreState` properly by inspecting the restored peripheral and reconnecting if it matches the last-connected HR device. Option (a) is correct if the HR monitor is always manually initiated.

**Warning signs:**
- After app restart, `centralManager.retrieveConnectedPeripherals(withServices: [CBUUID("180D")])` returns the previous HR device as already connected, but no `didConnect` callback fires.
- "Already connected" error when attempting `central.connect(peripheral)` for the HR monitor peripheral after launch.

**Phase to address:** WEAR-02 — decide restoration policy before release; removing the key is the safe default.

---

### Pitfall 12: CR-02 schema migration — adding `active_device_id` to `decoded_frames` must use `ALTER TABLE` not re-creation, or existing data is lost

**What goes wrong:**
`decoded_frames` already contains captures from v1.0, v2.0, and early v3.0. Any schema migration that uses `DROP TABLE + CREATE TABLE` to add `active_device_id TEXT` destroys all existing frames. SQLite's `ALTER TABLE ... ADD COLUMN` is the correct migration path. However, `open_bridge_store` runs schema initialisation every time the bridge is opened, using `CREATE TABLE IF NOT EXISTS` — which is idempotent for existing tables but does not add new columns. The migration must explicitly detect the missing column and run `ALTER TABLE decoded_frames ADD COLUMN active_device_id TEXT` before the bridge proceeds.

**Why it happens:**
The Rust store initialisation uses `CREATE TABLE IF NOT EXISTS` for all tables (correct). But `IF NOT EXISTS` means column additions are silently skipped if the table already exists. There is no column existence check in the current `open_bridge_store` path.

**How to avoid:**
Add a Rust migration step (before the existing `CREATE TABLE IF NOT EXISTS` block) that checks `PRAGMA table_info(decoded_frames)` and runs `ALTER TABLE decoded_frames ADD COLUMN active_device_id TEXT` if the column is absent. Then build an index on the new column. Test this migration against a real database from v2.0 (copy `goose.sqlite` from the device, apply migration, verify row count unchanged).

**Warning signs:**
- `decoded_frames` row count drops to zero after deploying the CR-02 fix.
- `open_bridge_store` does not include a `PRAGMA table_info` check for the new column.
- The migration is applied as a new `CREATE TABLE` statement rather than `ALTER TABLE`.

**Phase to address:** CR-02 — the migration test (v2.0 database → v3.0 schema) must be a phase entry criterion, not an exit criterion.

---

### Pitfall 13: Recovery V2 bridge methods called with a stale `databasePath` when the SQLite file has moved

**What goes wrong:**
`HealthDataStore.databasePath` is a `lazy var` — it is computed once on first access and cached. If the app is first launched in a state where the `ApplicationSupport/GooseSwift/` directory does not yet exist (e.g., a fresh install), `defaultDatabasePath()` creates the directory and returns the path. If the directory is later moved or the app is restored from a backup to a different container, `lazy var databasePath` still holds the old path. All new bridge calls use the old path, which no longer exists, and the Rust bridge returns `"database not found"` errors.

**Why it happens:**
The `lazy var` pattern is correct for avoiding repeated `FileManager` calls, but it does not handle container path changes (which happen on OS updates, iCloud Drive moves, or iTunes backup restores). The existing code is already affected by this for all bridge calls — Recovery V2 just adds more of them.

**How to avoid:**
Do not add new bridge calls without verifying the `databasePath` is still valid before each call family. In `HealthDataStore.refreshBridgeCatalogs()`, `runPacketInputs()`, and any new Recovery V2 method, add a pre-flight `FileManager.default.fileExists(atPath: databasePath)` check. If the file does not exist at the cached path, reset `databasePath` (clear the `lazy var` cache by using a stored optional and re-computing it if nil).

**Warning signs:**
- Bridge returns `"No such file or directory"` error after device restore from backup.
- `lazy var databasePath` is never invalidated in any error path.
- Recovery V2 dashboard shows "Error" immediately after a device migration.

**Phase to address:** Recovery V2 — add the pre-flight database existence check as part of the bridge call wrapper.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Manual `objectWillChange.send()` from `GooseBLEHRMonitorManager` | No `GooseBLEClient` refactoring | Fragile — new HR state properties require remembering to add the send; easy to miss | Never — promote to `@Published` on `GooseBLEClient` |
| Sharing `coreBluetoothQueue` between WHOOP and HR managers | Zero new queue objects | Hidden serialisation; HR notifications delayed during WHOOP sync bursts | Acceptable only if HR notification frequency is < 0.1 Hz; not acceptable at 1 Hz |
| `willRestoreState` stub on HR manager while retaining `RestoreIdentifierKey` | No code to write | Leaked zombie peripheral in CoreBluetooth connection pool after crash | Never — either implement or remove the key |
| Time-window-only filter (no `device_id`) for upload query | Simple, no schema migration | Cannot distinguish WHOOP from HR monitor frames in a two-device capture session | Acceptable only until a real two-device session is needed |
| Hardcoded English status strings in `@Published var` properties | Zero localisation work now | pt-PT UI shows mixed-language content; `"reconnecting after disconnect"` is in English | Never for any string that appears in a SwiftUI view |

---

## Integration Gotchas

| Integration Point | Common Mistake | Correct Approach |
|-------------------|----------------|------------------|
| Two CBCentralManager instances | Share `coreBluetoothQueue` | Give each manager its own dedicated serial queue |
| HR monitor scan UI | Call `startHRMonitorScan()` directly in button action | Implement `pendingScan` flag; start scan only in `centralManagerDidUpdateState(.poweredOn)` |
| CR-02 `device_id` filter | Compare UUID string against `device_model` (name) | Add `active_device_id` column to `decoded_frames`; filter by UUID-to-UUID |
| RTC SET_TIME command | Send from `didConnect` callback | Send only after `connectionState == "ready"` + GET clock response confirms drift |
| `HealthDataStore` bridge queries | Call `bridge.request(...)` inside `@MainActor` function | Dispatch to `packetInputQueue`, then `DispatchQueue.main.async` for state write |
| Localisation | Wrap only `Text("...")` literals | Also convert dynamic `@Published` strings (status, error messages) to localised enum cases |
| Reconnect backoff `DispatchWorkItem` | Forget to cancel on `didConnect` | Cancel workItem in `didConnect`, `stopScan`, and manual disconnect paths |
| SQLite migration for CR-02 | `CREATE TABLE IF NOT EXISTS` to add column | `PRAGMA table_info` check + `ALTER TABLE ADD COLUMN` for live databases |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Recovery V2 bridge query on `@MainActor` | 200–500 ms UI freeze on dashboard open | Dispatch all bridge calls to `packetInputQueue` | Immediately — first time the query runs over 30 days of data |
| HR monitor 0x2A37 notifications dispatched to `DispatchQueue.main` | Main thread saturated at 1 Hz; UI jank | Keep HR callbacks on the BT queue; only hop to main for `@Published` state writes | At 60 BPM (1 Hz) with a complex main thread |
| `discoveredHRDevices.sort` on BT queue while UI reads on main | Intermittent array corruption | NSLock or snapshot-to-main pattern | Whenever scan results arrive faster than the main thread processes them |
| `lazy var databasePath` pointing to deleted file | All bridge calls return "not found" | Pre-flight `fileExists` check; invalidate cached path on error | After device restore from backup |

---

## "Looks Done But Isn't" Checklist

- [ ] **HR scan UI:** `startHRMonitorScan()` is called and devices appear — verify scan also works after the app is backgrounded and foregrounded (state restoration or re-scan required).
- [ ] **HR independent capture:** HR frames appear in `decoded_frames` when WHOOP is not connected and no WHOOP capture session is active.
- [ ] **CR-02 filter:** `SELECT * FROM decoded_frames WHERE active_device_id = '<WHOOP UUID>'` returns only WHOOP frames, not HR monitor frames — verify after a mixed two-device session.
- [ ] **CR-02 migration:** Deploying v3.0 on a device with existing v2.0 data does not reduce `SELECT COUNT(*) FROM decoded_frames` — verify migration preserves rows.
- [ ] **Recovery V2 dashboard:** Dashboard loads without a perceptible freeze on a device with 30 days of capture data.
- [ ] **Recovery V2 bridge dispatch:** Instruments shows no `goose_bridge_handle_json` call on the main thread during dashboard load.
- [ ] **pt-PT localisation:** `LabeledContent("Reconnect", value: ble.reconnectState)` — the value `"reconnecting after disconnect"` is translated (not just the label key).
- [ ] **pt-PT localisation:** App Store Connect language metadata is set to Portuguese (Portugal) — adding pt-PT in code without updating App Store metadata means the locale is never activated for review.
- [ ] **RTC sync sequencing:** Clock SET_TIME is never logged before `connectionState == "ready"` appears in the log — verify via a GATT discovery timing test.
- [ ] **Reconnect backoff cancellation:** Connecting manually during a backoff delay does not produce two `"reconnect.requested"` log entries — verify with a simulated rapid connect/disconnect cycle.
- [ ] **HR monitor backoff isolation:** WHOOP disconnect does not trigger an HR monitor reconnect attempt — verify backoff workItems are stored per-manager.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| HR frames not persisted (gated on WHOOP session) | MEDIUM | Introduce independent write path; existing HR frames during WHOOP sessions are intact; future sessions covered |
| CR-02 migration drops existing frames | HIGH | Restore from `goose.sqlite` backup (if taken pre-migration); re-run historical sync; no recovery without backup |
| RTC SET_TIME sent before GATT ready — silent discard | LOW | Trigger manual clock sync from DeviceView; strap clock drift continues until manual fix |
| `databasePath` stale after backup restore | LOW | Delete app and reinstall; all captured data is lost unless user has a manual export |
| Mixed-language UI after partial pt-PT migration | LOW | Finish converting all `@Published` status strings; no data involved |
| Zombie peripheral from ignored `willRestoreState` | LOW | Remove `CBCentralManagerOptionRestoreIdentifierKey` from HR manager and redeploy |
| Reconnect backoff fires after manual connect | LOW | Cancel backoff workItem in `didConnect` (fix is one line); no data loss |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Shared BT queue serialisation (Pitfall 1) | WEAR-02 — HR scan UI | Instruments: two separate queues visible for WHOOP and HR managers |
| `discoveredHRDevices` data race (Pitfall 2) | WEAR-02 — HR scan UI | Thread Sanitiser passes during a scan session |
| `startScan` before `.poweredOn` silent no-op (Pitfall 3) | WEAR-02 — HR scan UI | Scan starts after Bluetooth state `.poweredOn` confirmed in log |
| HR frames gated on WHOOP session (Pitfall 4) | WEAR-02 — independent capture | HR frames in `decoded_frames` with WHOOP disconnected |
| CR-02 UUID vs name namespace mismatch (Pitfall 5) | CR-02 | `WHERE active_device_id = ?` returns correct rows |
| Recovery V2 bridge on `@MainActor` (Pitfall 6) | Recovery V2 dashboard | Instruments shows no bridge call on main thread |
| pt-PT dynamic string coverage (Pitfall 7) | pt-PT localisation | Zero English strings visible in pt-PT simulator run |
| RTC sync before GATT ready (Pitfall 8) | WHOOP 4.0 RTC sync | No `failClockCommand` log entry during GATT window |
| Reconnect backoff cancel race (Pitfall 9) | BLE reconnect backoff | Single `connect` call per disconnect event in log |
| `objectWillChange` fragility (Pitfall 10) | WEAR-02 — HR scan UI | All HR state changes reflected in UI without manual navigation |
| `willRestoreState` stub with RestoreIdentifierKey (Pitfall 11) | WEAR-02 | Remove key or implement handler; no zombie peripheral after restart |
| CR-02 schema migration destructiveness (Pitfall 12) | CR-02 | Row count unchanged after migration on v2.0 database |
| Stale `databasePath` lazy var (Pitfall 13) | Recovery V2 | Bridge returns data after simulated backup restore |

---

## Sources

- `GooseSwift/GooseBLEClient+HRMonitor.swift` — `GooseBLEHRMonitorManager` class; shared `coreBluetoothQueue`; `discoveredHRDevices` mutation on BT queue; `objectWillChange.send()` from `DispatchQueue.main.async`; `willRestoreState` stub
- `GooseSwift/GooseBLEClient.swift` — `coreBluetoothQueue` declaration (line 84); `hrMonitorManager` as plain `let` (line 92); `@Published var reconnectState` (line 23)
- `GooseSwift/GooseBLEClient+CentralDelegate.swift` — `centralManagerDidUpdateState` → `attemptAutomaticReconnect` pattern; `connect(peripheral, reason:)` called directly from `didDisconnectPeripheral` without backoff
- `GooseSwift/GooseBLEClient+Commands.swift` — `writeClockCommand` six-guard sequence (lines 206–234); `scheduleClockCommandTimeout` `DispatchWorkItem` pattern (line 286)
- `GooseSwift/HealthDataStore.swift` — `@MainActor` class (line 6); `lazy var databasePath` (line 54); `packetInputQueue` background dispatch pattern (lines 186–198)
- `Rust/core/src/bridge.rs` — CR-02 comment: `// CR-02: per-row device_id filtering is deferred to v3.0 multi-device tracking.` (lines 3065–3070); `#[allow(dead_code)] // device_id filter deferred to v3.0 (namespace mismatch: UUID vs BLE name)` (line 3022)
- `Rust/core/src/store.rs` — `decoded_frames` schema: `device_model TEXT NOT NULL`, `active_device_id TEXT` (lines 943, 1017); `ble_raw_notifications` schema: `device_id TEXT`, `active_device_name TEXT` (lines 1566–1567)
- Apple Developer Documentation — CoreBluetooth state restoration; `CBCentralManagerOptionRestoreIdentifierKey` semantics; background scanning requires `withServices:` non-nil
- Apple Developer Documentation — `CBCentralManager` initialisation is asynchronous; `centralManagerDidUpdateState` is the only safe place to start scanning
- CLAUDE.md architectural constraint — "Rust bridge is synchronous: `goose_bridge_handle_json` blocks the calling thread. Never call from `@MainActor` with expensive methods; always dispatch to a background queue first."

---
*Pitfalls research for: v3.0 Wearable UX, CI Hardening & RTC Sync*
*Researched: 2026-06-04*
