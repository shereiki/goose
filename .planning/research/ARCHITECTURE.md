# Architecture Research

**Domain:** iOS BLE wearable app with Rust core — v3.0 feature integration
**Researched:** 2026-06-04
**Confidence:** HIGH (all findings from direct source inspection)

## Standard Architecture

### System Overview

```
┌────────────────────────────────────────────────────────────────┐
│                        SwiftUI Views (@MainActor)               │
│  HomeDashboardView  HealthMetricFamilyStrainViews  MoreTabView  │
│  RecoveryV2OverviewPage (existing skeleton)                     │
│  [NEW] HRMonitorScanView                                        │
└───────────────────────────┬────────────────────────────────────┘
                            │ @EnvironmentObject / @ObservedObject
┌───────────────────────────▼────────────────────────────────────┐
│   GooseAppModel (@MainActor coordinator)                        │
│   @Published state — observed by all views                      │
│   Extension files: +HealthCapture, +NotificationPipeline,       │
│   +ActivityRecording, +Upload, +OvernightRun, +Lifecycle        │
│   [MODIFY] +NotificationPipeline — remove WHOOP-session gate    │
│   [NEW]    +HRMonitorSession — independent HR capture session   │
└────────┬───────────────────────────────────┬───────────────────┘
         │                                   │
┌────────▼───────────┐           ┌───────────▼─────────────────┐
│  GooseBLEClient     │           │  HealthDataStore             │
│  (ObservableObject) │           │  (@MainActor, ObservableObj) │
│  +Commands          │           │  +ActivitySnapshots          │
│  +CentralDelegate   │           │  +Trends                     │
│  +HRMonitor         │           │  +CoachSummaries             │
│  [MODIFY] backoff   │           │  [NEW] +RecoveryV2           │
│  [MODIFY] RTC sync  │           └────────────┬────────────────┘
│  hrMonitorManager   │                        │
│  (GooseBLEHRMonitor │           ┌────────────▼────────────────┐
│   Manager — exists) │           │  GooseRustBridge (stateless) │
└────────┬────────────┘           │  JSON-over-FFI               │
         │ coreBluetoothQueue     │  metrics.daily_recovery_*    │
┌────────▼────────────┐           │  [FIX] device_id namespace   │
│  CoreBluetooth      │           └────────────┬────────────────┘
│  CBCentralManager x2│                       │ synchronous FFI
│  (WHOOP + HR monitor)│          ┌────────────▼────────────────┐
└─────────────────────┘           │  Rust libgoose_core (SQLite) │
                                  │  capture_import.rs           │
                                  │  store.rs                    │
                                  │  [FIX] CR-02 device_id query │
                                  └─────────────────────────────┘
```

### Component Responsibilities (v3.0 scope)

| Component | Current Responsibility | v3.0 Change |
|-----------|----------------------|-------------|
| `GooseBLEClient` | WHOOP BLE central; notification routing; command writes | Add backoff state vars + `scheduleReconnectWithBackoff()`; add `sendRTCSyncIfNeeded()` called from `processDiscoveredCharacteristics` for Gen4 only |
| `GooseBLEClient+CentralDelegate` | `didDisconnectPeripheral` fires immediate reconnect | Replace immediate reconnect with `scheduleReconnectWithBackoff()` |
| `GooseBLEHRMonitorManager` | HR scan/connect/notify (no scan UI caller, no independent session, no disconnect backoff) | Add `didDisconnectPeripheral` backoff; expose `@Published discoveredHRDevices` forwarding via owner |
| `GooseAppModel` | Central coordinator; owns `activeHealthPacketCapture` | Add `activeHRMonitorCapture`, `hrMonitorCaptureStatus`, `hrMonitorCaptureFrameCount` `@Published` vars |
| `GooseAppModel+NotificationPipeline` | `importCapturedFrames` gated on `activeHealthPacketCapture != nil` (line 170) | Split gate: WHOOP frames keep existing gate; HR frames check `activeHRMonitorCapture != nil` independently |
| `GooseAppModel+HRMonitorSession` (NEW) | — | Start/stop independent HR capture session; wire `startHRMonitorScan()` / `connectHRMonitor()` |
| `HealthDataStore+RecoveryV2` (NEW) | — | Bridge calls for `metrics.daily_recovery_metrics`; publish `@Published recoveryV2Metrics` |
| `HealthRecoveryStressViews` | Skeleton Recovery V2 UI with placeholder timeline and insights sections | Wire timeline, insights sections to bridge-backed `HealthDataStore+RecoveryV2` data |
| Rust `store.rs` | `device_id` column exists; per-row filter was reverted to no-op in v2.0 | Fix `active_device_id` namespace so per-row `device_id` matches the session's `active_device_id` |
| `Localizable.xcstrings` (NEW) | No localisation infrastructure exists | Add String Catalog to `GooseSwift/` target; add pt-PT strings for all v3.0 UI text |

## Recommended Project Structure (v3.0 additions)

```
GooseSwift/
├── GooseBLEClient.swift                   # Add: backoff state vars (reconnectAttemptCount,
│                                          #   reconnectBackoffWorkItem); @Published discoveredHRDevices
├── GooseBLEClient+Commands.swift          # Add: scheduleReconnectWithBackoff(), sendRTCSyncIfNeeded()
├── GooseBLEClient+CentralDelegate.swift   # Modify: didDisconnectPeripheral uses backoff
├── GooseBLEClient+HRMonitor.swift         # Modify: didDisconnectPeripheral adds HR backoff
├── GooseAppModel.swift                    # Add: activeHRMonitorCapture, @Published HR session vars
├── GooseAppModel+HRMonitorSession.swift   # NEW: start/stop independent HR session
├── GooseAppModel+NotificationPipeline.swift  # Modify: decouple HR gate from WHOOP gate (line 170)
├── HealthDataStore+RecoveryV2.swift       # NEW: bridge-backed recovery metrics for V2 dashboard
├── HealthRecoveryStressViews.swift        # Modify: wire timeline/insights/trends sections
├── HRMonitorScanView.swift                # NEW: SwiftUI scan/connect sheet for HR monitors
├── Localizable.xcstrings                  # NEW: String Catalog (Xcode 15+ format)

Rust/core/src/
├── store.rs                               # Fix: device_id namespace in per-row filter query
├── capture_import.rs                      # Verify: HrMonitor branch uses correct device_id format
```

## Architectural Patterns

### Pattern 1: Extension file per concern on GooseBLEClient / GooseAppModel

**What:** Large classes (GooseBLEClient, GooseAppModel) are split into focused extension files. Each extension owns one coherent slice of behaviour. All extensions share state on the parent class.

**When to use:** Every new capability in v3.0. Do not add methods to the main `.swift` files; create a new `+Feature.swift` extension file.

**Trade-offs:** State lives on the parent class (good for cohesion); extension count grows (acceptable, already 10+ on GooseBLEClient).

**Example for HRMonitorSession:**
```swift
// GooseAppModel+HRMonitorSession.swift
extension GooseAppModel {
  func startHRMonitorCapture() {
    guard activeHRMonitorCapture == nil else { return }
    activeHRMonitorCapture = ActiveHRMonitorCapture(sessionID: UUID().uuidString)
    ble.startHRMonitorScan()
    hrMonitorCaptureStatus = "Scanning..."
  }

  func stopHRMonitorCapture() {
    guard activeHRMonitorCapture != nil else { return }
    ble.stopHRMonitorScan()
    activeHRMonitorCapture = nil
    hrMonitorCaptureStatus = "Stopped"
  }
}
```

### Pattern 2: Independent capture session for HR monitor

**What:** `activeHRMonitorCapture: ActiveHRMonitorCapture?` on `GooseAppModel` mirrors the existing `activeHealthPacketCapture` pattern. The notification pipeline checks both independently.

**When to use:** HR monitor frames must persist to SQLite regardless of whether a WHOOP session is active.

**Current gate (to be split) — GooseAppModel+NotificationPipeline.swift line 170:**
```swift
// CURRENT: HR frames dropped unless a WHOOP session is open
guard activeHealthPacketCapture != nil || activeActivityPersistence != nil else { return }

// AFTER: independent per-device-type gate
let isHRFrame = event.serviceUUID == "180D"
if isHRFrame {
  guard activeHRMonitorCapture != nil else { return }
} else {
  guard activeHealthPacketCapture != nil || activeActivityPersistence != nil else { return }
}
```

**Trade-offs:** Minimal code delta; does not affect the WHOOP capture path at all.

### Pattern 3: Exponential backoff on BLE disconnect

**What:** State vars on `GooseBLEClient` track attempt count and compute delay. `scheduleReconnectWithBackoff()` replaces the immediate `connect(peripheral, reason:)` call in `didDisconnectPeripheral`. Circuit breaker fires at 10 attempts.

**When to use:** Both WHOOP central delegate (`GooseBLEClient+CentralDelegate`) and HR monitor delegate (`GooseBLEHRMonitorManager`) need this. The WHOOP backoff is added to `GooseBLEClient+Commands.swift`. The HR monitor backoff is a parallel, simpler version inside `GooseBLEHRMonitorManager`.

**State to add to `GooseBLEClient`:**
```swift
var reconnectAttemptCount: Int = 0
var reconnectBackoffWorkItem: DispatchWorkItem?
static let reconnectMaxAttempts = 10
static let reconnectBaseInterval: TimeInterval = 1.0
static let reconnectMaxInterval: TimeInterval = 60.0
```

**Delay formula:** `min(baseInterval * pow(2.0, Double(attempt)), maxInterval)`

**Reset:** `reconnectAttemptCount = 0` inside `didConnect` on successful connection.

**Important:** HR monitor backoff state must live on `GooseBLEHRMonitorManager` directly, not on `GooseBLEClient` via `owner`. WHOOP reconnect cycles and HR monitor reconnect cycles are independent.

### Pattern 4: Rust bridge call from HealthDataStore extension

**What:** All bridge-backed data queries live in `HealthDataStore+*.swift` extensions. Each extension calls `bridge.request(method: "metrics.*", args: [...])` on a background queue, then publishes results as `@Published` state on `@MainActor`.

**Constraint:** `GooseRustBridge.request()` is synchronous. Never call from `@MainActor` directly; dispatch to a background queue first.

**When to use:** `HealthDataStore+RecoveryV2.swift` follows the exact pattern already established in `HealthDataStore+PacketInputs.swift` (lines 134-256).

**Example:**
```swift
// HealthDataStore+RecoveryV2.swift
func refreshRecoveryV2Metrics() {
  let db = Self.defaultDatabasePath()
  let bridge = self.bridge
  Task.detached(priority: .utility) { [weak self] in
    guard let self else { return }
    let result = try? bridge.request(
      method: "metrics.daily_recovery_metrics",
      args: ["database_path": db, "start_time_unix_ms": ..., "end_time_unix_ms": ...]
    )
    await MainActor.run { self.recoveryV2Metrics = Self.parseRecoveryMetrics(result) }
  }
}
```

### Pattern 5: WHOOP 4.0 RTC sync on connect

**What:** Call `writeClockCommand(.get, syncIfNeeded: true)` when `connectionState` transitions to `"ready"` and `activeDescriptor == .whoopGen4`. The existing `writeClockCommand` infrastructure already handles read-then-sync logic (in `GooseBLEClient+HistoricalHandlers.swift` lines 194-207) — RTC sync on connect only needs a caller.

**When to use:** Hook into `processDiscoveredCharacteristics` (end of function, after `updateConnectionState("ready")`) in `GooseBLEClient+Commands.swift`.

**Trade-off:** Adding the call directly after `updateConnectionState("ready")` is cleanest; avoids a cross-type callback. Use `DispatchQueue.main.asyncAfter(deadline: .now() + 1)` to avoid colliding with in-flight GATT discovery.

### Pattern 6: String Catalogs for pt-PT localisation

**What:** Xcode 15+ String Catalog (`.xcstrings`) is the current standard. A single `Localizable.xcstrings` file in the `GooseSwift/` target replaces the older `.strings`/`.stringsdict` per-locale system. The catalog holds all locales in one JSON file with source-language strings as keys.

**When to use:** No localisation infrastructure currently exists. Adding `Localizable.xcstrings` is zero-disruption. Existing hardcoded strings become candidates for extraction in phases.

**Scope for v3.0:** Only new strings introduced by v3.0 features need to be localised immediately (HRMonitorScanView strings, Recovery V2 section headers, RTC sync status strings). Existing UI strings can be extracted incrementally.

## Data Flow

### HR Monitor Independent Capture Flow (new)

```
User taps "Start HR Monitor Capture"
    |
GooseAppModel.startHRMonitorCapture()         [@MainActor]
    |
ble.startHRMonitorScan()                      [-> coreBluetoothQueue via hrMonitorManager]
    | user selects device from HRMonitorScanView
GooseAppModel.connectHRMonitor(device)        [@MainActor]
    |
GooseBLEHRMonitorManager.didUpdateValue(0x2A37)  [coreBluetoothQueue]
    | owner.onNotification?(event)  [serviceUUID = "180D"]
GooseAppModel.handleNotification(event)       [coreBluetoothQueue -> notificationIngestQueue]
    | serviceUUID == "180D" -> check activeHRMonitorCapture
importCapturedFrames(frames, event)           [notificationIngestQueue]
    |
CaptureFrameWriteQueue.enqueue(rows)          [captureFrameRowBuildQueue -> SQLite]
```

### BLE Reconnect Backoff Flow (new, both WHOOP and HR monitor)

```
didDisconnectPeripheral(peripheral, error)    [@MainActor, dispatched from coreBluetoothQueue]
    |
reconnectAttemptCount += 1
if reconnectAttemptCount > maxAttempts -> updateReconnectState("circuit open"); return
    |
delay = min(base * 2^attempt, maxInterval)    [exponential]
scheduleReconnectWithBackoff(peripheral, delay)
    | DispatchQueue.main.asyncAfter(delay)
connect(peripheral, reason: "auto.backoff.\(attempt)")
    | on successful connect
reconnectAttemptCount = 0                     [reset in didConnect]
```

### WHOOP 4.0 RTC Sync Flow (new)

```
processDiscoveredCharacteristics(...)         [main thread via dispatchCoreBluetoothDelegateToMainIfNeeded]
    | commandCharacteristic found
updateConnectionState("ready")
    | if activeDescriptor == .whoopGen4
scheduleRTCSyncIfNeeded()                     [DispatchQueue.main.asyncAfter(+1s)]
    |
writeClockCommand(.get, syncIfNeeded: true)   [existing path -> auto-syncs if offset > 5s]
```

### CR-02 device_id Filter Fix (Rust side)

```
capture_import.rs import_captured_frame_batch()
    | for HrMonitor frames, CapturedFrameInput.device_id = peripheral.identifier.uuidString
store.rs start_capture_session() sets active_device_id
    | PROBLEM: active_device_id in capture session uses a different namespace/format
    |          than per-row device_id from Swift, causing filter to never match
Fix: align device_id format in capture session with per-row device_id
     (both must use the same UUID string format, with or without dashes)
```

### Recovery V2 Data Flow (new)

```
HealthDataStore.refreshRecoveryV2Metrics()    [background Task]
    |
GooseRustBridge.request("metrics.daily_recovery_metrics", args: [db, date_range])
    |
Rust bridge.rs -> daily_recovery_metrics_bridge() -> store.daily_recovery_metrics_between()
    |
await MainActor.run { self.recoveryV2Metrics = parsed }
    |
HealthRecoveryStressViews observes @Published recoveryV2Metrics
    | timeline, insights, trends sections populated
```

## Integration Points

### Existing Components — Modified

| Component | What Changes | Threading Constraint |
|-----------|-------------|---------------------|
| `GooseBLEClient` (main file) | Add backoff state vars; add `@Published discoveredHRDevices: [GooseDiscoveredDevice]` forwarded from manager | `@Published` on `@MainActor`; safe via `objectWillChange.send()` dispatch already in manager |
| `GooseBLEClient+CentralDelegate` | `didDisconnectPeripheral` delegates reconnect to `scheduleReconnectWithBackoff()` instead of immediate `connect()` | Already dispatches to main; backoff `DispatchWorkItem` scheduled on `DispatchQueue.main` |
| `GooseBLEClient+HRMonitor` | `GooseBLEHRMonitorManager.didDisconnectPeripheral` adds HR backoff; `didDiscover` updates forwarded `@Published` array | HR manager runs on `coreBluetoothQueue`; `DispatchQueue.main.async` for UI state |
| `GooseBLEClient+Commands` | Add `scheduleReconnectWithBackoff()`, `sendRTCSyncIfNeeded()` | Both called from main thread; schedule main-thread work items |
| `GooseAppModel` | Add `activeHRMonitorCapture`, `hrMonitorCaptureStatus`, `hrMonitorCaptureFrameCount` `@Published` vars | All `@Published` on `@MainActor` — no threading concern |
| `GooseAppModel+NotificationPipeline` | Split `importCapturedFrames` gate at line 170 | No threading change; same queue path |
| `HealthRecoveryStressViews` | Wire timeline/insights sections to bridge data from `HealthDataStore+RecoveryV2` | `@ObservedObject store` already on view; no new threading |
| Rust `store.rs` | Fix per-row `device_id` namespace in the capture import query | Pure Rust; no threading implication for Swift |

### New Components

| Component | Depends On | Used By |
|-----------|-----------|---------|
| `GooseAppModel+HRMonitorSession.swift` | `GooseBLEClient.hrMonitorManager`, `activeHRMonitorCapture` on `GooseAppModel` | `HRMonitorScanView`, `GooseAppModel+NotificationPipeline` |
| `HRMonitorScanView.swift` | `GooseAppModel` (`@EnvironmentObject`), `GooseBLEClient.discoveredHRDevices` (`@Published`) | Health tab or dedicated BLE sheet |
| `HealthDataStore+RecoveryV2.swift` | `GooseRustBridge`, `metrics.daily_recovery_metrics` bridge method | `HealthRecoveryStressViews` |
| `Localizable.xcstrings` | Xcode 15 build toolchain | All new v3.0 views |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `GooseAppModel` <-> `GooseBLEHRMonitorManager` | `ble.hrMonitorManager.*` direct calls; forwarded `@Published discoveredHRDevices` on `GooseBLEClient` for UI observation | `hrMonitorManager` itself is not `@Published`; forward discovered devices list to `GooseBLEClient` |
| `GooseAppModel+HRMonitorSession` <-> `GooseAppModel+NotificationPipeline` | Shared `activeHRMonitorCapture` var on `GooseAppModel` | Both extensions run on `@MainActor`; no lock needed |
| `HealthDataStore+RecoveryV2` <-> `HealthRecoveryStressViews` | `@Published recoveryV2Metrics` on `HealthDataStore` | Follow same pattern as `packetInputReports` |
| Swift <-> Rust (`device_id` fix) | CR-02 fix is Rust-only; Swift side already passes `peripheral.identifier.uuidString` | Verify format consistency: UUID string with dashes in both capture session start and per-row insert |

## Anti-Patterns

### Anti-Pattern 1: Binding `GooseBLEHRMonitorManager.discoveredHRDevices` directly in SwiftUI

**What people do:** Bind `ble.hrMonitorManager.discoveredHRDevices` directly in a SwiftUI `ForEach`.

**Why it's wrong:** `GooseBLEHRMonitorManager` is not an `ObservableObject`. Mutations call `objectWillChange.send()` on the owning `GooseBLEClient`, not on `GooseBLEHRMonitorManager`. A direct array reference in SwiftUI will not trigger view updates.

**Do this instead:** Add `@Published var discoveredHRDevices: [GooseDiscoveredDevice] = []` to `GooseBLEClient`, updated from the manager's `didDiscover` callback. `GooseBLEClient` is already an `@ObservedObject` in views.

### Anti-Pattern 2: Calling `GooseRustBridge.request()` from `@MainActor`

**What people do:** Call bridge methods inline in a `HealthDataStore` method that runs on `@MainActor`.

**Why it's wrong:** `goose_bridge_handle_json` blocks the calling thread. On `@MainActor`, this freezes the UI.

**Do this instead:** `Task.detached(priority: .utility)` or `DispatchQueue.global().async`. Publish results back via `await MainActor.run { self.property = ... }`. See `HealthDataStore+PacketInputs.swift` lines 134-256 for the established pattern.

### Anti-Pattern 3: Storing backoff state on `GooseBLEClient` and reading it from `GooseBLEHRMonitorManager` via `owner`

**What people do:** Use one `reconnectAttemptCount` on `GooseBLEClient` for both WHOOP and HR monitor reconnect cycles.

**Why it's wrong:** WHOOP and HR monitor reconnect cycles are independent. A WHOOP reconnect failure must not exhaust the HR monitor circuit breaker.

**Do this instead:** Add separate `hrReconnectAttemptCount: Int` and `hrReconnectBackoffWorkItem: DispatchWorkItem?` directly to `GooseBLEHRMonitorManager`. WHOOP backoff state lives on `GooseBLEClient`.

### Anti-Pattern 4: Adding HR monitor capture session state to `GooseBLEClient`

**What people do:** Add `@Published var hrMonitorCaptureStatus` to `GooseBLEClient`.

**Why it's wrong:** Capture session lifecycle is `GooseAppModel`'s responsibility. `GooseBLEClient` owns BLE connectivity; `GooseAppModel` owns session state.

**Do this instead:** Add capture session state (`activeHRMonitorCapture`, `hrMonitorCaptureStatus`, `hrMonitorCaptureFrameCount`) to `GooseAppModel`. Add only connectivity state (`discoveredHRDevices`, `hrConnectionState`) to `GooseBLEClient`.

## Build Order (Suggested)

### Step 1: CR-02 device_id Fix (Rust, isolated)

**Rationale:** Pure Rust change. Zero Swift impact. Fixing it first means all subsequent testing with HR monitor capture produces correct per-device storage. Unblocks meaningful integration testing.

**Files:** `Rust/core/src/store.rs`, `Rust/core/src/capture_import.rs`
**Risk:** LOW — SQL query fix; existing Rust integration tests cover capture import

### Step 2: BLE Reconnect Backoff — WHOOP + HR Monitor

**Rationale:** Infrastructure change that touches both `GooseBLEClient+CentralDelegate` and `GooseBLEHRMonitorManager`. Must be done before HR monitor scan UI is wired (otherwise reconnect behaviour is undefined after user connects an HR monitor and it drops). Does not depend on any other v3.0 feature.

**Files:** `GooseBLEClient.swift` (add state vars), `GooseBLEClient+Commands.swift` (add `scheduleReconnectWithBackoff()`), `GooseBLEClient+CentralDelegate.swift` (hook in backoff), `GooseBLEClient+HRMonitor.swift` (HR manager `didDisconnectPeripheral`)
**Risk:** MEDIUM — changes live reconnect path; requires real-device testing

### Step 3: HR Monitor Scan/Connect UI + Independent Capture Session

**Rationale:** Depends on Step 2 (backoff) being stable. Adds `HRMonitorScanView`, wires `startHRMonitorScan()`, adds `GooseAppModel+HRMonitorSession`, and modifies `GooseAppModel+NotificationPipeline` to decouple the capture gate. These sub-tasks are tightly coupled; implement together.

**Sub-tasks (sequential within step):**
1. Add `@Published discoveredHRDevices` forwarding on `GooseBLEClient`
2. Add `activeHRMonitorCapture` + `@Published` status vars on `GooseAppModel`
3. Create `GooseAppModel+HRMonitorSession.swift`
4. Modify `GooseAppModel+NotificationPipeline.swift` gate at line 170
5. Create `HRMonitorScanView.swift`

**Files:** `GooseBLEClient.swift`, `GooseAppModel.swift`, `GooseAppModel+HRMonitorSession.swift` (new), `GooseAppModel+NotificationPipeline.swift`, `HRMonitorScanView.swift` (new)
**Risk:** MEDIUM — modifies notification pipeline (hot path for all BLE frames)

### Step 4: WHOOP 4.0 RTC Sync

**Rationale:** Depends on Step 2 (backoff) because the RTC sync call occurs at the `"ready"` connection state, which is in the same `processDiscoveredCharacteristics` code path modified for backoff. Isolated to Gen4 peripherals; no impact on WHOOP 5.0 sessions.

**Files:** `GooseBLEClient+Commands.swift` (add `sendRTCSyncIfNeeded()`; call from `processDiscoveredCharacteristics`)
**Risk:** LOW — uses existing `writeClockCommand(.get, syncIfNeeded: true)` infrastructure; Gen4-only guard

### Step 5: Recovery V2 Dashboard (bridge-backed data)

**Rationale:** Self-contained. `RecoveryV2OverviewPage` view skeleton already exists (`HealthRecoveryStressViews.swift`). Only needs `HealthDataStore+RecoveryV2.swift` to provide `@Published` data and the view wired to consume it. No dependencies on other v3.0 features.

**Files:** `HealthDataStore+RecoveryV2.swift` (new), `HealthRecoveryStressViews.swift` (wire timeline/insights sections)
**Risk:** LOW — additive; follows established bridge query pattern; bridge methods already exist in Rust

### Step 6: pt-PT Localisation

**Rationale:** Should be done last because it touches every new string introduced by Steps 3-5. Doing it after the UI is stable avoids re-running string extraction multiple times.

**Files:** `Localizable.xcstrings` (new, added to `GooseSwift/` target), pt-PT translations for all new v3.0 UI text
**Risk:** LOW — additive; does not change logic

## Scaling Considerations

This is a single-user personal device app. The following capacity concerns apply for v3.0:

| Concern | Current State | v3.0 Impact |
|---------|--------------|-------------|
| SQLite write throughput | Handled by `CaptureFrameWriteQueue` with batching | HR monitor adds a second concurrent write source; same queue, same DB — acceptable |
| `@Published` state mutations | GooseAppModel has 60+ @Published vars | Each new HR monitor var adds one more; no performance concern |
| BLE queue contention | Two `CBCentralManager` instances share `coreBluetoothQueue` | `GooseBLEHRMonitorManager` was already created with the same queue in v2.0; no change |
| Rust bridge synchrony | `goose_bridge_handle_json` blocks calling thread | No new synchronous calls added to hot paths; Recovery V2 query is on background queue |

## Sources

All findings from direct source inspection of the repository. No external references required.

- `GooseSwift/GooseBLEClient+HRMonitor.swift` — existing HR monitor manager; confirmed: no scan UI caller, no disconnect backoff in `didDisconnectPeripheral`
- `GooseSwift/GooseBLEClient+CentralDelegate.swift` — existing disconnect path (lines 228-283); immediate reconnect, no backoff
- `GooseSwift/GooseAppModel+NotificationPipeline.swift` — capture frame gate (line 170); gated on WHOOP `activeHealthPacketCapture` only
- `GooseSwift/GooseAppModel.swift` — `activeHealthPacketCapture` pattern (line 99); HR monitor mirrors this
- `GooseSwift/HealthDataStore+ActivitySnapshots.swift` — `dailyRecoveryMetrics()` bridge call pattern (lines 7-10)
- `GooseSwift/HealthDataStore+PacketInputs.swift` — background bridge query pattern (lines 134-256)
- `GooseSwift/HealthRecoveryStressViews.swift` — existing Recovery V2 skeleton with placeholder timeline and insights sections
- `Rust/core/src/capture_import.rs` — HrMonitor branch (line 637); `active_device_id: None` (line 400) is the CR-02 root cause
- `GooseSwift/GooseBLEClient.swift` — `ClockCommandKind.set(Date)` (line 462); `strapClockAutoSyncThresholdSeconds` (line 354); no backoff state vars present

---
*Architecture research for: Goose v3.0 — Wearable UX, CI Hardening & RTC Sync*
*Researched: 2026-06-04*
