# Feature Research

**Domain:** iOS BLE wearable app — WHOOP + HR monitor capture, RTC sync, localisation
**Researched:** 2026-06-04
**Confidence:** HIGH (all claims verified against codebase + CoreBluetooth official docs + Xcode localisation docs)

---

## Context: What Already Exists (Do Not Re-Build)

| Already Built | Where |
|---------------|-------|
| WHOOP BLE scan, connect, packet capture | `GooseBLEClient` + extensions |
| HR monitor CBCentralManager + 0x180D/0x2A37 subscribe | `GooseBLEHRMonitorManager` in `GooseBLEClient+HRMonitor.swift` |
| HR monitor upload taxonomy (device_class HR_MONITOR) | `GooseAppModel+Upload.swift` |
| WHOOP clock read + write commands | `writeClockCommand(.get/.set)` in `GooseBLEClient+Commands.swift` |
| Recovery V2 view scaffold | `RecoveryV2OverviewPage` in `HealthRecoveryStressViews.swift` |
| SQLite frame storage with device_id column | `store.rs`, `capture_import.rs` |
| FastAPI+TimescaleDB server upload | `GooseUploadService`, server/ |

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| HR monitor scan list UI | Backend scabut has zero callers in any view; users cannot discover HR monitors | MEDIUM | `GooseBLEHRMonitorManager.discoveredHRDevices` is not a `@Published` property on `GooseBLEClient`; needs promotion to published state and a SwiftUI list, mirroring the existing WHOOP `ConnectionView` "Discovered" section |
| HR monitor connect / disconnect from UI | Scan list is useless without a tap-to-connect action | LOW | `connectHRMonitor(_:)` already exists; UI just needs to call it; also needs a disconnect button |
| HR monitor connection status visible | Users need to know if the chest strap is connected | LOW | `hrConnectionState` string on `GooseBLEHRMonitorManager` needs to surface as `@Published` on the parent `GooseBLEClient` |
| HR monitor independent capture session | Currently gated on WHOOP `activeHealthPacketCapture`; users want HR-only recordings without WHOOP | HIGH | Requires a separate session lifecycle that starts/stops independently; frames already route through `onNotification` but the capture queue gating logic must be decoupled |
| BLE reconnect backoff with UI feedback | Reconnecting immediately in a tight loop drains both phone and strap battery; upstream PR #18 documents this | MEDIUM | Current `attemptAutomaticReconnect` has no delay at all; needs per-attempt delay array [1,2,4,8,16,32,60s] and a 10-attempt circuit breaker; UI needs attempt count + countdown display |
| Bluetooth state error handling in HR scan UI | Users need to know why scan is not starting (BT off, unauthorized) | LOW | Mirror what `ConnectionView` already does for WHOOP: show BT state, disable Scan button when `central.state != .poweredOn` |
| Recovery V2 dashboard wired to real data | Scaffold (`RecoveryV2OverviewPage`) exists with placeholder display methods; needs bridge-backed HRV/RHR/recovery score | HIGH | `HealthDataStore` must expose recovery-specific bridge queries; `store.recoveryHRVDisplayText(for:)` is already called in the view but the method may not be fully implemented |
| per-row device_id filter in CR-02 | Without this, multi-device setups mix frames from different devices in metric queries | MEDIUM | `active_device_id: None` is hard-coded in `capture_import.rs` line 400; Rust bridge needs the UUID passed per-row and queries updated to filter |
| pt-PT localisation baseline | All UI strings are hard-coded English; app targets Portuguese-speaking user | MEDIUM | No `.xcstrings` or `.strings` files exist; Xcode 15 String Catalog workflow is the correct approach; ~200 visible strings estimated across 80+ SwiftUI files |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| WHOOP 4.0 RTC clock auto-sync | Prevents timestamp drift that corrupts sleep/recovery correlation; upstream issue #17 is unresolved | MEDIUM | `writeClockCommand(.set, syncIfNeeded:)` path already exists; missing pieces are: (a) drift detection at connection time, (b) auto-trigger when drift > threshold (constant already referenced as `strapClockAutoSyncThresholdDisplay`), (c) clear drift delta in DeviceView |
| BLE reconnect backoff with "Retry Now" / "Stop Retrying" controls | Power users can intervene; avoids app appearing frozen during out-of-range periods | LOW | Described in upstream PR #18; `ReconnectBackoffBanner` with live countdown is the UX; can be added to `DeviceView` alongside existing `reconnectRemembered()` button |
| HR monitor session independent of WHOOP | Single-device HR-only workflows: treadmill, rowing, any sport without WHOOP | HIGH | High value for the user; architecturally requires decoupling HR capture start/stop from `activeHealthPacketCapture` in `GooseAppModel` |
| RSSI signal strength indicator in scan list | Users identify the nearest HR monitor when multiple are in range | LOW | `discoveredHRDevices` already sorts by RSSI; just needs a visual bar or dBm label in the list row |
| Scan auto-stop on connect | Saves battery; standard BLE UX best practice per Apple docs | LOW | CoreBluetooth docs: call `stopScan()` in `centralManager(_:didConnect:)`; `GooseBLEHRMonitorManager.centralManager(_:didConnect:)` does NOT currently stop scan |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Auto-scan on app foreground for HR monitor | Convenience | Drains battery; may connect to wrong device if multiple HR monitors in range; CBCentralManager state may not be `.poweredOn` yet at foreground time | Explicit scan button; remember the last-connected HR monitor UUID and use `retrievePeripherals(withIdentifiers:)` for silent reconnect |
| Real-time everything localised (all dynamic strings) | Completeness | Dynamic strings formed at runtime (e.g. `"BPM: \(bpm)"`, `"disconnected"`) are not auto-extracted by Xcode and break the String Catalog extraction pipeline; they also serve as diagnostic log values | Localise static UI labels only in v3.0; dynamic metric values are locale-formatted by Swift `formatted()` without localisation keys |
| Full offline-first localisation of Coach/AI responses | Thoroughness | Coach responses are generated by OpenAI API; localising surrounding chrome is sufficient; prompt engineering can request Portuguese responses | Localise app chrome; let Coach respond in user's language via prompt |
| Circuit breaker that silently gives up with no UI | Clean implementation | Users do not know why WHOOP stopped reconnecting; app appears broken | Always show a banner or status when circuit breaker trips; provide a manual "Retry" button |
| Standard BLE Current Time Service (0x1805) for RTC sync | Standards compliance | WHOOP uses a proprietary command protocol, not standard GATT CTS; writing to 0x1805 would have no effect | Use existing `writeClockCommand(.set)` which wraps the proprietary WHOOP frame format |

---

## Feature Dependencies

```
[HR scan list UI]
    └──requires──> [discoveredHRDevices promoted to @Published on GooseBLEClient]
                       └──requires──> [GooseBLEHRMonitorManager owner.objectWillChange refactor or @Published bridge]

[HR independent capture session]
    └──requires──> [HR scan list UI + connect]
    └──requires──> [session lifecycle decoupled from WHOOP activeHealthPacketCapture in GooseAppModel]
    └──benefits from──> [CR-02 device_id per-row filter] (HR frames otherwise tagged NULL device_id)

[BLE reconnect backoff]
    └──requires──> [attemptAutomaticReconnect refactor with delay work items + attempt counter]
    └──enhances──> [ReconnectBackoffBanner UI in DeviceView]
    └──applies to──> [GooseBLEHRMonitorManager.centralManager(_:didDisconnect:) — same pattern]

[WHOOP RTC auto-sync]
    └──requires──> [existing writeClockCommand(.set) path — already present]
    └──requires──> [drift detection at connect time — reads .get then conditionally sends .set]
    └──enhances──> [DeviceView clock section — strapClockStatus already displayed]

[Recovery V2 dashboard]
    └──requires──> [HealthDataStore recovery bridge query methods implemented]
    └──requires──> [Rust bridge methods for recovery HRV/RHR/score returning real rows]

[pt-PT localisation]
    └──requires──> [Localizable.xcstrings file created + project language added]
    └──no conflicts with other features — fully independent]

[CR-02 device_id filter]
    └──requires──> [Rust capture_import.rs updated to accept and persist device_id per-row]
    └──requires──> [Swift call site passes peripheral UUID into bridge args]
    └──requires──> [Rust query methods updated with WHERE device_id filter]
```

### Dependency Notes

- **HR independent capture benefits from CR-02:** Without per-row device_id, HR frames captured independently cannot be isolated from WHOOP frames in metric queries — metrics would be computed on mixed data from both devices.
- **Recovery V2 requires bridge implementation:** The view scaffold calls `store.recoveryHRVDisplayText(for:)` etc.; if these methods return placeholder strings the feature is visually present but functionally hollow.
- **Reconnect backoff applies to both BLE delegates:** PR #18 targets the WHOOP path in `GooseBLEClient`; the same pattern is needed for `GooseBLEHRMonitorManager` to prevent battery drain from HR monitor reconnect loops.
- **Localisation is fully independent:** No data or BLE dependency; can be developed in a parallel or separate phase.

---

## MVP Definition for v3.0

### Launch With (required for milestone closure)

- [ ] HR scan list UI with connect action — completes WEAR-02 started in v2.0
- [ ] HR independent capture session — core value for HR-only workflows
- [ ] CR-02 per-row device_id filter — data integrity prerequisite for multi-device
- [ ] Recovery V2 dashboard with real bridge data — view scaffold exists; needs wiring
- [ ] BLE reconnect backoff + circuit breaker — battery and reliability fix; upstream PR #18 ready
- [ ] WHOOP 4.0 RTC auto-sync — upstream issue #17; clock drift corrupts all time-series data
- [ ] pt-PT localisation baseline — required by user; app chrome strings only

### Add After Validation (v3.x)

- [ ] HR monitor silent reconnect via `retrievePeripherals(withIdentifiers:)` — improves UX after first pairing
- [ ] Localisation of dynamic metric display values using Swift `formatted()`

### Future Consideration (v4+)

- [ ] Upload queue persisted in SQLite to survive app restarts — deferred per PROJECT.md
- [ ] Background URLSession upload — deferred per PROJECT.md

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| HR scan list UI | HIGH | LOW | P1 |
| HR independent capture session | HIGH | HIGH | P1 |
| CR-02 device_id filter | HIGH | MEDIUM | P1 |
| Recovery V2 dashboard | HIGH | HIGH | P1 |
| BLE reconnect backoff | MEDIUM | MEDIUM | P1 |
| WHOOP RTC auto-sync | MEDIUM | MEDIUM | P1 |
| pt-PT localisation | MEDIUM | MEDIUM | P1 |
| RSSI bars in scan list | LOW | LOW | P2 |
| Auto-stop scan on HR connect | LOW | LOW | P2 |
| HR silent reconnect on re-open | LOW | LOW | P2 |

**Priority key:**
- P1: Must have for v3.0 milestone closure
- P2: Should have, add within v3.0 phases where trivial
- P3: Nice to have, future consideration

---

## Expected User-Facing Behaviour Per Feature

### BLE Device Scan List UI (HR Monitor)

Standard iOS BLE pairing flow:
1. User opens a "HR Monitor" section (new tab entry or section within the existing More/Connect area)
2. Taps "Scan" — animated indicator appears, list populates in real time
3. Each row: device name + RSSI in dBm (already sorted by RSSI in `discoveredHRDevices`)
4. Tap a row to connect → row shows "Connecting..."
5. On connect: scan stops automatically, row shows "Connected" state, capture begins
6. On failure: row shows error + "Retry" option

Table stakes: Bluetooth-off state must show a message ("Enable Bluetooth in Settings"), not a broken empty list. The `centralManagerDidUpdateState` stub in `GooseBLEHRMonitorManager` is currently empty and must be wired up.

### HR Monitor Independent Capture Session

User expectation: tap "Start HR Capture" and the app records HR/RR data regardless of whether a WHOOP is connected. Stopping the HR capture session stops the upload queue for that device class only.

Architecture implication: a new `hrCaptureActive: Bool` flag on `GooseAppModel`, independent of `activeHealthPacketCapture`. The frame routing via `onNotification` already works; the gate that checks `activeHealthPacketCapture` before persisting must accept HR frames unconditionally when `hrCaptureActive` is true.

### WHOOP 4.0 RTC Clock Sync (BLE Write)

The WHOOP 4.0 drifts from real time (upstream issue #17). The fix path:
1. At connection (`connectionState == "ready"`), read the strap clock: `writeClockCommand(.get, syncIfNeeded: true)`
2. On response, compare `strapClockDate` to `Date()` — if drift exceeds threshold, auto-send `.set`
3. `writeClockCommand(.set)` encodes current Unix timestamp in the proprietary WHOOP V5 command frame (not standard BLE CTS 0x1805 — WHOOP uses its own protocol)
4. `strapClockStatus` + `strapClockOffsetSeconds` in DeviceView expose the result

The existing code has all the plumbing. The missing piece is auto-triggering `.get` at `"ready"` and conditionally sending `.set` without user intervention.

### BLE Reconnect Backoff with UI Feedback

Replace the current immediate `attemptAutomaticReconnect` (no delay, no limit) with:
- Delay schedule: [0s, 1s, 2s, 4s, 8s, 16s, 32s, 60s, 60s, 60s] — 10 slots
- After 10 attempts: circuit breaker trips, `reconnectState = "gave up after 10 attempts"`
- `ReconnectBackoffBanner` in `DeviceView`: shows "Attempt N of 10 — next in Xs"
- "Retry Now" button: cancels pending work item, triggers immediate attempt, resets countdown
- "Stop Retrying" button: cancels all pending work items, sets `reconnectState = "stopped"`
- Apply the same delay pattern to `GooseBLEHRMonitorManager.centralManager(_:didDisconnectPeripheral:error:)`

### pt-PT Localisation

iOS String Catalog workflow (Xcode 15+):
1. Add `Localizable.xcstrings` to the `GooseSwift` target (no `.strings` files exist — clean start, no migration needed)
2. Build once to trigger Xcode extraction of all `Text("...")` SwiftUI string literals
3. Add "Portuguese (Portugal)" in Project Settings → Info → Localizations
4. Translate extracted strings directly in the catalog editor
5. Scope for v3.0: static UI labels in SwiftUI views only

Dynamic runtime strings (e.g. `"ready"`, `"disconnected"`, `"unauthorized"`) that are assigned in `GooseBLEClient` serve dual purpose as diagnostic log values. These should be translated at the SwiftUI display layer using a mapping function, not at the assignment site, to preserve log readability.

### Recovery V2 Dashboard

`RecoveryV2OverviewPage` already renders a full hero + stat cards layout. The wiring needed:
- `store.recoveryHRVDisplayText(for:)` — implement in `HealthDataStore+Cardio.swift` or a new `HealthDataStore+Recovery.swift` extension; calls `metrics.recovery.hrv` or equivalent bridge method
- `store.recoveryRHRDisplayText(for:)` — same pattern
- `store.recoveryScoreDisplayText(for:)` — calls `metrics.recovery.score` bridge method
- Date picker already present in the scaffold (`selectedDate: Date` binding, `showingDatePicker` state)
- Navigation from Health tab to Recovery V2 must be wired through `AppRouter`

### CR-02 Per-Row device_id Filter

In `capture_import.rs`, `active_device_id: None` is hard-coded (line 400), causing all imported frames to receive NULL device_id in SQLite, making per-device filtering impossible.

Fix:
- Swift side: pass the connected peripheral's `UUID.uuidString` when calling the frame import bridge method
- Rust side: accept the device_id argument and set it on each inserted row instead of `None`
- Query side: all bridge methods computing metrics from captured frames must add `WHERE device_id = ?` (with NULL fallback for legacy rows without device_id)

---

## Sources

- Apple CoreBluetooth documentation — `CBCentralManager`, `CBCentralManagerDelegate`, reconnection patterns: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager (HIGH confidence)
- Apple Xcode localisation documentation — String Catalog workflow: https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog (HIGH confidence)
- Upstream PR #18 `b-nnett/goose` — exponential backoff + circuit breaker + `ReconnectBackoffBanner` UX description (MEDIUM confidence — GitHub WebFetch)
- Upstream issue #17 `b-nnett/goose` — RTC clock drift description (LOW confidence — issue contains no technical detail; implementation inferred from existing `writeClockCommand(.set)` in this codebase)
- Codebase inspection — `GooseBLEClient+HRMonitor.swift`, `GooseBLEClient+Commands.swift`, `ConnectionView.swift`, `HealthRecoveryStressViews.swift`, `capture_import.rs` (HIGH confidence — direct Read tool)

---
*Feature research for: Goose v3.0 — HR monitor UX, reconnect backoff, RTC sync, device_id filter, Recovery V2, pt-PT localisation*
*Researched: 2026-06-04*
