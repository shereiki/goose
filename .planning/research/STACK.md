# Stack Research — Goose v3.0

**Domain:** iOS wearable app (SwiftUI + Rust core), WHOOP BLE + HR monitor UX
**Researched:** 2026-06-04
**Confidence:** HIGH — all findings verified against live codebase and Context7 Apple docs

---

## Scope

This document covers only the NEW capabilities in v3.0. Existing validated stack
(CoreBluetooth GATT, Rust FFI bridge, rusqlite, FastAPI server) is not re-researched.

---

## Core Technologies (new v3.0 usage)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| CoreBluetooth — `writeValue(_:for:type:)` | iOS 26.0 (already in SDK) | WHOOP 4.0 RTC clock sync write | Already used for WHOOP 5.0 clock sync; identical API path. `CBCharacteristicWriteType.withResponse` gives delegate callback via `peripheral(_:didWriteValueFor:error:)` for error detection. No new import or dependency. |
| CoreBluetooth — `CBCentralManager.isScanning` + `scanForPeripherals` | iOS 26.0 (already in SDK) | HR monitor scan list UI state | `isScanning` is a published-observable Bool; `GooseBLEHRMonitorManager.discoveredHRDevices` is already populated by `centralManager(_:didDiscover:advertisementData:rssi:)`. Only the SwiftUI view layer is missing. |
| SwiftUI `List` / `ForEach` + `@ObservedObject` | iOS 26.0 (already in project) | HR monitor scan list + connect UI | Pattern already exists in `ConnectionView.swift` (WHOOP scan list). Reuse `GooseDiscoveredDevice` (already `Identifiable`) and the `hrMonitorManager.discoveredHRDevices` array. No new framework. |
| Xcode String Catalog (`.xcstrings`) | Xcode 15+ / iOS 17+ | pt-PT localisation | Apple's current-generation localisation format. Replaces `.strings` files. Xcode auto-extracts strings from `Text("…")` literals and `String(localized:)` on build. Single source of truth — no separate `.strings` per language. `knownRegions` in `project.pbxproj` currently only has `en` + `Base`; adding `pt-PT` is a project setting change + catalog entry. |
| `DispatchQueue.main.asyncAfter` (Foundation) | iOS 26.0 (already in SDK) | BLE reconnect exponential backoff + circuit breaker | No external dependency. Pattern: on `didDisconnect`, increment attempt counter, compute `min(pow(2, attempt) * baseDelay, maxDelay)`, schedule reconnect via `asyncAfter`. Cancel pending work item on manual disconnect. Reset counter on successful `ready` state. |
| rusqlite `params!` macro — optional WHERE clause | 0.37 (already in Cargo.toml) | CR-02 per-row `device_id` filter | No new crate. The fix requires adding `device_id` to the `decoded_frames` table (via schema migration) or resolving it through `raw_evidence → capture_sessions.active_device_id` (JOIN). Then pass `device_id: Option<&str>` to `decoded_frames_between` and gate the `WHERE` clause. |

---

## Supporting Libraries (no new additions needed)

| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| rusqlite | 0.37 (bundled) | SQLite query changes for CR-02 device_id filter | Already in `Cargo.toml`; only query/schema changes needed |
| serde / serde_json | 1.0 | `UploadGetRecentDecodedStreamsArgs` already has `device_id: String` field | Already in `Cargo.toml` |
| Foundation `DispatchWorkItem` | iOS 26.0 | Cancel in-flight backoff timer on manual disconnect | Already used for `clockCommandTimeoutWorkItem` — reuse the same pattern |

**No new Swift packages, no new Rust crates, no new server dependencies are required for v3.0.**

---

## Feature-by-Feature Stack Decisions

### HR Monitor Scan/Connect UI

**What exists:** `GooseBLEHRMonitorManager` (in `GooseBLEClient+HRMonitor.swift`) fully implements
`didDiscover`, `discoveredHRDevices` array (sorted by RSSI), and `connect(_:)`. `startHRMonitorScan()`
exists on `GooseBLEClient` but has no UI caller.

**What is missing:** A SwiftUI view that renders `hrMonitorManager.discoveredHRDevices` as a `List`,
with a "Scan" / "Stop" button and a "Connect" button per row. The `GooseBLEHRMonitorManager` is not
`ObservableObject` — it triggers `owner?.objectWillChange.send()` on the parent `GooseBLEClient`.
The UI should observe `GooseBLEClient` (already `@ObservedObject` in existing views) and access
`ble.hrMonitorManager.discoveredHRDevices` directly.

**Pattern to follow:** `ConnectionView.swift` lines 65–100 (WHOOP `discoveredDevices` list).

**Stack call:** No new API. Use `@ObservedObject var ble: GooseBLEClient`, `ForEach(ble.hrMonitorManager.discoveredHRDevices)`, `ble.startHRMonitorScan()` / `ble.stopHRMonitorScan()` / `ble.connectHRMonitor(_:)`.

---

### HR Monitor Independent Capture Session

**Problem:** HR frames are currently routed through `onNotification?` only when
`activeHealthPacketCapture` is active (WHOOP session gate).

**Fix:** The `GooseBLEHRMonitorManager.peripheral(_:didUpdateValueFor:)` already fires unconditionally
and calls `owner?.onNotification?`. The gate is upstream in `GooseAppModel`. Add a separate
`@Published var hrCaptureActive: Bool` and `hrCaptureSessionID: String?` to `GooseAppModel` that
controls whether HR frames get persisted, independent of the WHOOP capture path.

**Stack:** No new API. Pattern follows existing `healthPacketCaptureSessionID` / `healthPacketCaptureStatus`.

---

### CR-02 Per-Row `device_id` Filter (Rust/SQLite)

**Root cause (from code comment at `bridge.rs:3065`):** The `device_id` field in
`UploadGetRecentDecodedStreamsArgs` is a CoreBluetooth `peripheral.identifier` UUID string. The
`decoded_frames` table has `device_type` (e.g., `"WHOOP_GEN5"`) but no `device_id` column.
`raw_evidence` has no `device_id` either. `capture_sessions.active_device_id` holds it but
`decoded_frames` is linked via `raw_evidence.capture_session_id → capture_sessions`.

**Fix options (choose one):**

Option A — JOIN path (no schema change): Change `decoded_frames_between` to LEFT JOIN
`raw_evidence → capture_sessions` and filter `WHERE capture_sessions.active_device_id = ?`.
Available immediately; no migration needed.

Option B — Denormalise (schema migration): Add `device_id TEXT` column to `decoded_frames`,
populate on insert via the active session, add `CREATE INDEX IF NOT EXISTS idx_decoded_frames_device_id`.
More performant at scale; requires a schema version bump.

**Recommendation:** Option A first (minimal risk), then Option B if performance matters. The existing
rusqlite migration infrastructure (`goose_schema_migrations` table in `store.rs`) supports this.

**Stack:** `rusqlite 0.37` `params!` with `Option<&str>` — pattern already used throughout `store.rs`.
Named parameters (`":device_id"`) or positional `?N` both work; the codebase uses positional.

---

### Recovery V2 Dashboard

**What exists:** `RecoveryV2OverviewPage` view struct is already in `HealthRecoveryStressViews.swift`
and calls `store.recoveryHRVDisplayText(for:)` (defined in `HealthDataStore+CoachSummaries.swift`).
Bridge methods `metrics.daily_recovery_metrics`, `metrics.goose_recovery_v0`,
`metrics.recovery_sensor_daily_rollup`, `metrics.recovery_sensor_discovery` all exist in `bridge.rs`.

**What is missing:** The `HealthDataStore` extension for per-date `daily_recovery_metrics` bridging
(RHR, HRV, recovery score per `selectedDate`) and the routing of `RecoveryV2OverviewPage` into the
Health tab navigator. Verified: `daily_recovery_metrics_bridge` in `bridge.rs` exists and calls
`store.daily_recovery_metrics_between(start, end)` in `store.rs`.

**Stack:** No new bridge methods. Add a `HealthDataStore+Recovery.swift` extension that calls
`metrics.daily_recovery_metrics` with a ±12h window around `selectedDate`. Pattern follows
`HealthDataStore+Sleep.swift`.

---

### pt-PT Localisation (String Catalogs)

**Current state:** Zero localisation files. `knownRegions = (en, Base)` in `project.pbxproj`.
51 existing `NSLocalizedString` / `String(localized:)` calls already localisation-ready.
SwiftUI `Text("…")` literals auto-extract to String Catalog on build.

**Recommended approach:** String Catalog (`.xcstrings`), not legacy `.strings`.

Rationale:
- Apple standard from Xcode 15 / iOS 17 onwards. Context7 Apple docs confirm auto-extraction from `Text("…")` literals on build.
- Single file per target (not one `.strings` per language per `.lproj` folder).
- Xcode 26.x String Catalog editor supports cut/copy/paste between languages, remove language, and pre-fill from existing language — confirmed in Xcode release notes.
- Migrating from `.strings` is one-way (`xcstrings` supersedes it); starting fresh with `.xcstrings` avoids the migration step entirely since the project has no existing `.strings`.

**Steps:**
1. File > New > File from Template > String Catalog → `Localizable.xcstrings` in `GooseSwift/` target.
2. Project editor > Info > Localizations > `+` → Portuguese (Portugal) `pt-PT`.
3. `knownRegions` in `project.pbxproj` gains `pt-PT`.
4. Product > Build — Xcode auto-populates catalog with all `Text("…")` literals and `String(localized:)` calls.
5. Translate entries in the catalog editor or export XLIFF for external translation.

**No external library needed.** Do NOT use `Localize-Swift` or similar packages — the project constraint forbids external iOS dependencies and the native String Catalog achieves the same result.

---

### WHOOP 4.0 RTC Clock Sync

**Current state:** `writeClockCommand(_:syncIfNeeded:)` already implements the full RTC write flow:
- Discovers command characteristic; Gen4 = `61080002`, Gen5 = `fd4b0002`.
- `ClockCommandKind.set(Date)` encodes timestamp as two LE `UInt32` (seconds + subseconds).
- `supportsClockCommands` gates on `activeDescriptor.isCommandCharacteristic(_:)` — so Gen4 command char is already gated correctly.
- UI button "Clock" in `DeviceView.swift` already calls `writeClockCommand(.get, syncIfNeeded: true)`.

**v3.0 task:** Confirm the Gen4 command numbers (`.get = 11`, `.set = 10`) match upstream issue #17's
documented protocol for WHOOP 4.0. If Gen4 uses different command numbers, add a `ClockCommandKind`
variant or check `activeDescriptor` before choosing command numbers. This is a verification + possible
one-line payload change, not a new API.

**Stack:** `CBPeripheral.writeValue(_:for:type:)` with `CBCharacteristicWriteType.withResponse`
(confirmed via Context7 Apple CoreBluetooth docs). The `peripheral(_:didWriteValueFor:error:)` delegate
already handles the response in `GooseBLEClient+HistoricalHandlers.swift`.

---

### BLE Reconnect Exponential Backoff + Circuit Breaker

**Current state:** On `didDisconnectPeripheral`, `connect(peripheral, reason:)` is called immediately
with no delay and no attempt limit. `reconnectState` is a `String` status label only.

**Implementation pattern (no new API):**

```swift
// New stored properties on GooseBLEClient
private var reconnectAttemptCount = 0
private static let reconnectMaxAttempts = 10
private static let reconnectBaseDelay: TimeInterval = 1.0
private static let reconnectMaxDelay: TimeInterval = 60.0
private var reconnectWorkItem: DispatchWorkItem?

// In didDisconnectPeripheral, replace immediate connect() with:
func scheduleReconnect(peripheral: CBPeripheral, reason: String) {
  guard reconnectAttemptCount < Self.reconnectMaxAttempts else {
    updateReconnectState("circuit open — \(reconnectAttemptCount) attempts exhausted")
    reconnectAttemptCount = 0
    return
  }
  let delay = min(
    pow(2.0, Double(reconnectAttemptCount)) * Self.reconnectBaseDelay,
    Self.reconnectMaxDelay
  )
  reconnectAttemptCount += 1
  let item = DispatchWorkItem { [weak self] in
    self?.connect(peripheral, reason: reason)
  }
  reconnectWorkItem = item
  DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
}
```

Reset `reconnectAttemptCount = 0` in the `ready` state handler.
Cancel `reconnectWorkItem` in `forgetRememberedDevice()` and on manual disconnect.

Apply the same pattern to `GooseBLEHRMonitorManager` for the HR monitor reconnect (upstream PR #18
says "apply to both WHOOP and HR monitor delegates").

**Stack:** `DispatchQueue.main.asyncAfter` + `DispatchWorkItem` — already used for `clockCommandTimeoutWorkItem`. No new import.

---

## Alternatives Considered

| Feature | Recommended | Alternative | Why Not |
|---------|-------------|-------------|---------|
| Localisation format | `.xcstrings` String Catalog | Legacy `.strings` + `.lproj` folders | `.strings` requires manual sync per language; `.xcstrings` auto-extracts from build. No migration path advantage since project has zero existing `.strings`. |
| CR-02 fix — JOIN path | SQL JOIN through `raw_evidence → capture_sessions` | Add `device_id` column to `decoded_frames` | JOIN is zero-migration-risk; denormalisation can come later as a schema migration if needed. |
| Backoff timer | `DispatchWorkItem` + `asyncAfter` | Combine `Timer.publish` or `AsyncStream` | `DispatchWorkItem` already used in project for timeouts; avoids introducing Combine or Swift Concurrency patterns inconsistent with existing code style. |
| HR scan UI | Extend existing `GooseBLEHRMonitorManager` + `GooseBLEClient` | New `ObservableObject` manager | `hrMonitorManager` already fires `owner?.objectWillChange.send()` — the parent BLE client is already observed. No duplication needed. |

---

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `Localize-Swift` or similar package | Project constraint: no external iOS dependencies | Native `.xcstrings` String Catalog |
| `RxBluetoothKit` / `SpeziBluetooth` | External dependency; existing CoreBluetooth code is complete | Native `CoreBluetooth` (`writeValue`, `scanForPeripherals`) |
| New Rust crates for device_id | `rusqlite 0.37` supports optional WHERE filtering with `params!` | Extend existing `decoded_frames_between` query |
| `goose_recovery_v1` / `goose_recovery_v2` Rust algorithm | Recovery V2 dashboard uses existing `metrics.daily_recovery_metrics` bridge — no new algorithm needed | Existing `daily_recovery_metrics_bridge` in `bridge.rs` |
| Combine or async/await for backoff | Inconsistent with project's `DispatchQueue`-based concurrency style | `DispatchWorkItem` + `asyncAfter` |

---

## Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| String Catalog (`.xcstrings`) | Xcode 15+ / iOS 17+ | Project targets iOS 26.0; fully supported |
| `CBCharacteristicWriteType.withResponse` | iOS 5+ | Available on all supported targets |
| `DispatchWorkItem` + `asyncAfter` | iOS 8+ | No compatibility concern |
| `rusqlite 0.37` | Already locked in `Cargo.lock` | No version change |
| `params!` optional binding | rusqlite 0.37 | `Option<&str>` works natively via `ToSql` impl |

---

## Sources

- `/websites/developer_apple_corebluetooth` (Context7) — `writeValue(_:for:type:)`, `CBCharacteristicWriteType`, `scanForPeripherals(withServices:options:)`, `centralManager(_:didDiscover:advertisementData:rssi:)` — HIGH confidence
- `/websites/developer_apple_xcode` (Context7) — String Catalog `.xcstrings`, `String(localized:)`, `Text` auto-extraction, `LocalizedStringResource`, Xcode 26.x new localisation features — HIGH confidence
- `/websites/rs_rusqlite_rusqlite` (Context7) — named parameters, `params!` macro, optional WHERE clause pattern — HIGH confidence
- Live codebase inspection — `GooseBLEClient+HRMonitor.swift`, `GooseBLEClient+Commands.swift`, `GooseBLEClient+CentralDelegate.swift`, `HealthRecoveryStressViews.swift`, `HealthDataStore+CoachSummaries.swift`, `Rust/core/src/bridge.rs` (CR-02 comment at line 3065), `Rust/core/src/store.rs` (`decoded_frames_between` query) — HIGH confidence

---

*Stack research for: Goose v3.0 — HR Monitor UX, RTC Sync, CR-02 fix, Recovery V2, pt-PT localisation, BLE backoff*
*Researched: 2026-06-04*
