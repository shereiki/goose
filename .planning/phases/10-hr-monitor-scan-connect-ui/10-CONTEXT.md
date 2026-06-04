# Phase 10: HR Monitor Scan/Connect UI - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the user-facing UI to discover and connect nearby HR monitors (Bluetooth Heart Rate profile, 0x180D). The user opens a new "HR Monitor" screen in More tab, sees a live list of discovered devices, taps a device to connect, and views the connected device's HR and status. Completes WEAR-04 (scan list) and WEAR-05 (tap-to-connect).

No capture session logic (WEAR-06 is Phase 11). No onboarding changes. No server changes.

</domain>

<decisions>
## Implementation Decisions

### D-01 — Screen placement

- **D-01:** New `MoreRoute` case `.hrMonitor` → `HRMonitorView` accessible at More > HR Monitor. Does NOT touch the existing WHOOP `DeviceView` or `ConnectionView`. New entry in `MoreRouteModels.swift` and `MoreView.swift` destination.

### D-02 — Visual style

- **D-02:** `HRMonitorView` follows the `DeviceView` visual pattern: header with device name or scan status, scrollable content below. Not a plain List — same visual language as the WHOOP device screen.

### D-03 — Screen states

The screen has two mutually exclusive states:
- **Scanning state** (no HR monitor connected): shows live list of discovered devices by RSSI, scan starts automatically on `onAppear`, stops on `onDisappear`.
- **Connected state** (HR monitor connected): shows HR live BPM, device name, disconnect button, and reconnect state indicator. No scan list visible.

### D-04 — Scan lifecycle

- **D-04:** Scan starts automatically when `HRMonitorView` appears (`onAppear`) — no manual Scan button required. Scan stops on `onDisappear`.
- **D-04b:** If `hrConnectionState == "connected"` on appear, skip scan entirely and go directly to connected state.

### D-05 — Connection UX

- **D-05:** Tapping a device in the scan list shows a **sheet** with device name and a "Connect" button. The user confirms before initiating the connection.
- **D-06:** After the user confirms in the sheet, a `ProgressView` (spinner) appears inline on the list item for the device being connected. The list remains visible while connecting.

### D-07 — Connected state content

When connected, `HRMonitorView` shows:
- Live HR (BPM) from `ble.liveHeartRateBPM` — existing published property
- Device name from `hrMonitorManager.connectedDeviceName`
- `hrReconnectState` string if not idle (surfacing reconnect backoff status from Phase 9)
- "Disconnect" button — calls `ble.stopHRMonitorScan()` and cancels connection

### Claude's Discretion

- **State propagation:** `GooseBLEHRMonitorManager.discoveredHRDevices` is currently a plain `var` (not `@Published`). The planner should decide whether to: (a) add `@Published var discoveredHRDevices` to `GooseBLEClient` mirroring the manager's array (promoted state pattern), or (b) make `GooseBLEHRMonitorManager` conform to `ObservableObject`. Pattern (a) is consistent with how `GooseBLEClient` publishes all BLE state — recommended.
- **HR monitor disconnect:** Implementation detail of cancelling the CBPeripheral connection and clearing `hrConnectionState` / `hrPeripheral` in `GooseBLEHRMonitorManager`. No user preference required.
- **`@Published var isHRMonitorConnected`:** Convenience property on `GooseBLEClient` computing from `hrMonitorManager.hrConnectionState == "connected"`. Claude can add this if it simplifies the SwiftUI view logic.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/REQUIREMENTS.md` — WEAR-04 and WEAR-05 requirement definitions with acceptance criteria
- `.planning/ROADMAP.md` §Phase 10 — Success criteria (4 numbered items) and phase boundaries

### Existing HR Monitor BLE Implementation (the foundation to build on)
- `GooseSwift/GooseBLEClient+HRMonitor.swift` — `GooseBLEHRMonitorManager` full class + `GooseBLEClient` extensions: `startHRMonitorScan()`, `stopHRMonitorScan()`, `connectHRMonitor(_:)`; `discoveredHRDevices`, `hrConnectionState`, `connectedDeviceName`
- `GooseSwift/GooseBLEClient.swift` lines 7–36 — all `@Published` properties; note `hrReconnectState` (line 24) is the reconnect status string from Phase 9
- `GooseSwift/GooseBLETypes.swift` lines 52–57 — `GooseDiscoveredDevice` struct: `id: UUID`, `name: String`, `rssi: Int`, `generation: String`

### Navigation & Routing (where new screen plugs in)
- `GooseSwift/MoreRouteModels.swift` — `MoreRoute` enum; add `.hrMonitor` case here
- `GooseSwift/MoreView.swift` — `destination(for:)` switch; add `.hrMonitor` → `HRMonitorView()`

### Reference UI Pattern (DeviceView style to replicate)
- `GooseSwift/DeviceView.swift` — target visual pattern: `DeviceConnectionHeader`, `DeviceStatusTabs`, scroll + background; follow same structure for `HRMonitorView`

### Scan List Pattern (existing WHOOP scan list for reference)
- `GooseSwift/ConnectionView.swift` lines 97–121 — existing "Discovered" section rendering `discoveredDevices` with RSSI; HR monitor list should follow the same row layout

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GooseBLEHRMonitorManager.startScan()` / `stopScan()` / `connect(_:)` — full BLE logic already implemented; the UI just needs to call these
- `GooseBLEClient.startHRMonitorScan()` / `stopHRMonitorScan()` / `connectHRMonitor(_:)` — extension methods already wired; UI calls these via `model.ble`
- `GooseDiscoveredDevice` (id, name, rssi, generation) — Identifiable + Equatable; can be used directly in `ForEach` for the scan list
- `ble.liveHeartRateBPM: Int?` — existing `@Published` property, updated by `handleStandardHeartRate` called from HR monitor notifications
- `ble.hrReconnectState: String` — `@Published` reconnect status string from Phase 9 (e.g., "reconnecting (attempt 3/10)", "failed after 10 attempts")
- `DeviceConnectionHeader` — existing SwiftUI view for the header (device name, status text, last sync); can be repurposed or mimicked for HR monitor header
- `.gooseListBackground()` — existing view modifier for consistent list background

### Established Patterns
- All `@Published` state mutations via `@MainActor`; BLE callbacks dispatch back with `Task { @MainActor in ... }` or `DispatchQueue.main.async`
- `GooseBLEHRMonitorManager` updates `discoveredHRDevices` and calls `owner?.objectWillChange.send()` on main — views observing `GooseBLEClient` will re-render
- Extension files: new HR monitor view logic → `GooseSwift/HRMonitorView.swift` (new file); state propagation additions → `GooseSwift/GooseBLEClient.swift` or a new extension

### Integration Points
- `MoreRoute.hrMonitor` (new case) → `HRMonitorView()` in `MoreView.destination(for:)` → triggers scan via `ble.startHRMonitorScan()` in `onAppear`
- `HRMonitorView` observes `model.ble` (`@ObservedObject`) for `discoveredHRDevices`, `hrConnectionState`, `hrReconnectState`, `liveHeartRateBPM`
- `GooseBLEClient` needs a promoted `@Published var discoveredHRDevices: [GooseDiscoveredDevice]` that mirrors `hrMonitorManager.discoveredHRDevices` (currently non-published)

</code_context>

<specifics>
## Specific Ideas

- The connected-state view should look like `DeviceView` with a header showing the HR monitor's device name and live BPM prominently.
- Scan list rows should show device name + RSSI (e.g., "Polar H10 · -72 dBm") — same pattern as the WHOOP scan list in `ConnectionView.swift` lines 108–116.
- Sheet on device tap: minimal — device name, RSSI label, and one "Connect" button. No extra info needed.
- After disconnect, screen returns to scanning state (auto-scan restarts).

</specifics>

<deferred>
## Deferred Ideas

- HR monitor integration in the onboarding flow (the user raised this idea — good future enhancement once HR monitor UX is stable, but it would widen Phase 10 scope and Phase 11 depends on Phase 10 being done first). Note for a v3.0+ backlog item.
- Automatic reconnect to a "remembered" HR monitor (same as WHOOP's `rememberedDeviceDescription` pattern) — out of scope for Phase 10; Phase 11 will determine if an independent capture session requires remembered device behavior.

### Reviewed Todos (not folded)
- `bt-button-open-settings.md` — "Botão Request Bluetooth deve abrir definições do sistema" — low-priority improvement in `ConnectionView` unrelated to Phase 10; remains in backlog.
- `2026-06-03-remote-server-test-and-import-actions.md` — "Add Test and Import actions to Remote Server settings" — More tab UI work unrelated to HR monitor scan; remains in backlog.

</deferred>

---

*Phase: 10-HR Monitor Scan/Connect UI*
*Context gathered: 2026-06-04*
