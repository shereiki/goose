# Phase 10: HR Monitor Scan/Connect UI — Research

**Researched:** 2026-06-04
**Domain:** SwiftUI, CoreBluetooth, iOS navigation (MoreRoute)
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01 — Screen placement:** New `MoreRoute` case `.hrMonitor` → `HRMonitorView` accessible at More > HR Monitor. Does NOT touch the existing WHOOP `DeviceView` or `ConnectionView`. New entry in `MoreRouteModels.swift` and `MoreView.swift` destination.

**D-02 — Visual style:** `HRMonitorView` follows the `DeviceView` visual pattern: header with device name or scan status, scrollable content below. Not a plain List — same visual language as the WHOOP device screen.

**D-03 — Screen states:** Two mutually exclusive states:
- **Scanning state** (no HR monitor connected): shows live list of discovered devices by RSSI, scan starts automatically on `onAppear`, stops on `onDisappear`.
- **Connected state** (HR monitor connected): shows HR live BPM, device name, disconnect button, and reconnect state indicator. No scan list visible.

**D-04 — Scan lifecycle:** Scan starts automatically when `HRMonitorView` appears (`onAppear`) — no manual Scan button required. Scan stops on `onDisappear`.
**D-04b:** If `hrConnectionState == "connected"` on appear, skip scan entirely and go directly to connected state.

**D-05 — Connection UX:** Tapping a device in the scan list shows a **sheet** with device name and a "Connect" button. The user confirms before initiating the connection.
**D-06:** After the user confirms in the sheet, a `ProgressView` (spinner) appears inline on the list item for the device being connected. The list remains visible while connecting.

**D-07 — Connected state content:** When connected, `HRMonitorView` shows:
- Live HR (BPM) from `ble.liveHeartRateBPM` — existing published property
- Device name from `hrMonitorManager.connectedDeviceName`
- `hrReconnectState` string if not idle (surfacing reconnect backoff status from Phase 9)
- "Disconnect" button — calls `ble.stopHRMonitorScan()` and cancels connection

### Claude's Discretion

- **State propagation:** `GooseBLEHRMonitorManager.discoveredHRDevices` is currently a plain `var` (not `@Published`). The planner should decide whether to: (a) add `@Published var discoveredHRDevices` to `GooseBLEClient` mirroring the manager's array (promoted state pattern), or (b) make `GooseBLEHRMonitorManager` conform to `ObservableObject`. Pattern (a) is consistent with how `GooseBLEClient` publishes all BLE state — recommended.
- **HR monitor disconnect:** Implementation detail of cancelling the CBPeripheral connection and clearing `hrConnectionState` / `hrPeripheral` in `GooseBLEHRMonitorManager`. No user preference required.
- **`@Published var isHRMonitorConnected`:** Convenience property on `GooseBLEClient` computing from `hrMonitorManager.hrConnectionState == "connected"`. Claude can add this if it simplifies the SwiftUI view logic.

### Deferred Ideas (OUT OF SCOPE)

- HR monitor integration in the onboarding flow — good future enhancement once HR monitor UX is stable, but widens Phase 10 scope. Note for v3.0+ backlog item.
- Automatic reconnect to a "remembered" HR monitor — out of scope for Phase 10; Phase 11 will determine if an independent capture session requires remembered device behavior.
- `bt-button-open-settings.md` — Bluetooth button in `ConnectionView` — low-priority improvement unrelated to Phase 10; remains in backlog.
- `2026-06-03-remote-server-test-and-import-actions.md` — More tab UI work unrelated to HR monitor scan; remains in backlog.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| WEAR-04 | User can view a scan list of nearby HR monitors (device name + RSSI) and initiate a scan from the app | `HRMonitorScanList` backed by `ble.discoveredHRDevices` (promoted `@Published`); scan auto-starts on `onAppear` via `ble.startHRMonitorScan()` |
| WEAR-05 | User can tap a device in the scan list to connect the HR monitor | Sheet on row tap (D-05); `ble.connectHRMonitor(device)` called on confirm; inline `ProgressView` while connecting; view switches to connected panel on `hrConnectionState == "connected"` |
</phase_requirements>

---

## Summary

Phase 10 is a **pure SwiftUI UI phase** — all BLE logic already exists in `GooseBLEHRMonitorManager` and the `GooseBLEClient` extension methods (`startHRMonitorScan`, `stopHRMonitorScan`, `connectHRMonitor`). The work is wiring that existing BLE layer into a new `HRMonitorView` screen that follows the `DeviceView` visual pattern already established in the codebase.

The most significant non-trivial technical decision is **state promotion**: `discoveredHRDevices` and `hrConnectionState` currently live as plain `var` properties on `GooseBLEHRMonitorManager` (not `@Published`). SwiftUI cannot reactively observe them. The CONTEXT.md recommends Pattern (a): add `@Published var discoveredHRDevices` and a promoted `@Published var hrConnectionState` (or use `@Published var isHRMonitorConnected`) to `GooseBLEClient` itself, mirroring the manager's values via the existing `objectWillChange.send()` mechanism. This is the same pattern used for all other BLE state in this codebase.

A secondary gap: `hrConnectionState` in the manager only ever takes values `"disconnected"` and `"connected"` — the `"connecting"` intermediate state is never set. The `connect(_:)` method calls `central?.connect(peripheral, options: nil)` but does not update `hrConnectionState` to `"connecting"` before the `didConnect` callback fires. The UI-SPEC requires the `"connecting"` state for the header and inline ProgressView. This state must be set in `connect(_:)` before the CBCentral call.

**Primary recommendation:** Promote `discoveredHRDevices` and `hrConnectionState` as `@Published` properties on `GooseBLEClient` (Pattern a), add `"connecting"` state in `GooseBLEHRMonitorManager.connect(_:)`, then build `HRMonitorView` as a new SwiftUI file wiring exclusively to `model.ble`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| BLE scan lifecycle (start/stop) | BLE layer (`GooseBLEHRMonitorManager`) | UI trigger via `ble.startHRMonitorScan()` on `onAppear` | CoreBluetooth work must not run on `@MainActor` |
| Discovered device list | `GooseBLEClient` `@Published` (promoted) | Rendered by `HRMonitorScanList` | All published state for views lives on `GooseBLEClient` |
| Connection state tracking | `GooseBLEHRMonitorManager` | `@Published` mirror on `GooseBLEClient` | CBCentralManagerDelegate callbacks are on the BLE queue; mirror dispatches to main |
| Live BPM display | `GooseBLEClient.liveHeartRateBPM` (existing `@Published`) | `HRMonitorConnectedPanel` reads it | `handleStandardHeartRate` already publishes on main |
| Navigation routing | `MoreRouteModels.swift` enum + `MoreView.swift` destination | — | Established pattern; add `.hrMonitor` case |
| Sheet presentation | `HRMonitorView` view-local `@State` | — | `selectedDevice: GooseDiscoveredDevice?` drives `.sheet` |
| Connecting device tracking | `HRMonitorView` view-local `@State` | — | `connectingDeviceID: UUID?` drives inline `ProgressView` |
| Disconnect action | `GooseBLEHRMonitorManager` (cancel peripheral + reset state) | Called via disconnect button action | CBCentral cancel must run through the manager |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 26.0 SDK | Declarative UI — `HRMonitorView` and all sub-views | Sole UI framework for this project (CLAUDE.md) |
| CoreBluetooth | iOS 26.0 SDK | BLE scan/connect — already encapsulated in `GooseBLEHRMonitorManager` | Already integrated; UI only calls extension methods |
| Foundation | iOS 26.0 SDK | `UUID`, `Date` | Universal in project |

No new third-party packages. This phase uses only Apple system frameworks.

**Installation:** No installation step required.

---

## Package Legitimacy Audit

Not applicable — this phase introduces zero external packages. Only Apple system frameworks are used.

---

## Architecture Patterns

### System Architecture Diagram

```
User → More tab → NavigationLink(.hrMonitor)
  → HRMonitorView (observes model.ble via @ObservedObject)
      ├── onAppear → ble.startHRMonitorScan()
      │     └── GooseBLEHRMonitorManager.startScan()
      │           └── CBCentralManager.scanForPeripherals(180D)
      │
      ├── State 1 (BT unavailable): static error message
      │
      ├── State 2 (scanning): HRMonitorScanList
      │     └── ForEach(ble.discoveredHRDevices)  ← @Published promoted from manager
      │           └── HRMonitorDeviceRow (tap → sheet)
      │                 └── sheet: HRMonitorDeviceSheet
      │                       └── "Connect" → ble.connectHRMonitor(device)
      │                             └── GooseBLEHRMonitorManager.connect(device)
      │                                   ├── hrConnectionState = "connecting"  ← GAP TO FIX
      │                                   └── CBCentralManager.connect(peripheral)
      │
      ├── State 3 (connecting): scan list + inline ProgressView on connecting row
      │     ble.hrConnectionState == "connecting"
      │     connectingDeviceID: UUID? set in view-local @State
      │
      └── State 4 (connected): HRMonitorConnectedPanel
            ├── reads ble.liveHeartRateBPM (existing @Published)
            ├── reads ble.hrConnectionState (promoted @Published)
            ├── reads ble.hrReconnectState (existing @Published)
            └── "Disconnect" → cancel peripheral + clear state → returns to State 2
```

### Recommended Project Structure

```
GooseSwift/
├── HRMonitorView.swift          (NEW — all HR monitor UI sub-views)
├── GooseBLEClient.swift         (ADD 2 @Published lines)
├── GooseBLEClient+HRMonitor.swift  (EDIT — set "connecting" state; mirror promoted @Published; add disconnect helper)
├── MoreRouteModels.swift        (EDIT — add .hrMonitor case)
└── MoreView.swift               (EDIT — add .hrMonitor destination)
```

### Pattern 1: Published State Promotion (Pattern A)

**What:** Mirror `GooseBLEHRMonitorManager` plain `var` fields as `@Published` properties on `GooseBLEClient` so SwiftUI views can reactively observe them.

**When to use:** Always — this is the established pattern for all BLE state in this codebase. `GooseBLEHRMonitorManager` already calls `owner?.objectWillChange.send()` from the main queue when `discoveredHRDevices` changes; promoting to `@Published` is cleaner and symmetric.

**Implementation (GooseBLEClient.swift — add 2 lines adjacent to existing @Published declarations):**
```swift
// Source: established codebase pattern (GooseBLEClient.swift lines 7–36)
@Published var discoveredHRDevices: [GooseDiscoveredDevice] = []
@Published var hrConnectionState: String = "disconnected"
```

**Mirroring in GooseBLEClient+HRMonitor.swift** — replace `objectWillChange.send()` with direct assignment of the promoted properties inside the manager's callbacks (must happen on main thread):
```swift
// Inside GooseBLEHRMonitorManager.centralManager(_:didDiscover:...) — replace existing objectWillChange.send():
DispatchQueue.main.async { [weak self] in
  self?.owner?.discoveredHRDevices = self?.discoveredHRDevices ?? []
}
```

### Pattern 2: View Observes GooseBLEClient via @ObservedObject

**What:** `HRMonitorView` receives `model.ble` as `@ObservedObject` — the same pattern as `DeviceContentView` and `ConnectionContentView`.

**When to use:** All views that need to react to BLE state.

```swift
// Source: DeviceView.swift pattern [VERIFIED: codebase]
struct HRMonitorView: View {
  @EnvironmentObject private var model: GooseAppModel
  var body: some View {
    HRMonitorContentView(ble: model.ble)
      .environmentObject(model)
  }
}

private struct HRMonitorContentView: View {
  @ObservedObject var ble: GooseBLEClient
  @State private var connectingDeviceID: UUID?
  @State private var selectedDevice: GooseDiscoveredDevice?
  // ...
}
```

### Pattern 3: Scan Lifecycle on onAppear/onDisappear

**What:** Start scan automatically on view appear, stop on disappear — D-04 requirement.

```swift
// Source: CONTEXT.md D-04 + DeviceView.swift .task pattern [VERIFIED: codebase]
.onAppear {
  guard ble.hrConnectionState != "connected" else { return }  // D-04b
  ble.startHRMonitorScan()
}
.onDisappear {
  ble.stopHRMonitorScan()
}
```

### Pattern 4: Device Row with Sheet Presentation

**What:** Tapping a device row sets `selectedDevice` which triggers `.sheet(item:)`.

```swift
// Source: CONTEXT.md D-05, UI-SPEC Connection Sheet [VERIFIED: codebase]
HRMonitorDeviceRow(device: device, isConnecting: connectingDeviceID == device.id)
  .onTapGesture { selectedDevice = device }

.sheet(item: $selectedDevice) { device in
  HRMonitorDeviceSheet(device: device) {
    ble.connectHRMonitor(device)
    connectingDeviceID = device.id
  }
  .presentationDetents([.height(220)])
  .presentationDragIndicator(.visible)
}
```

### Pattern 5: Color and Font Token Reuse

**What:** All visual constants are `private let` file-scope definitions mirroring DeviceView.swift — not imported from a shared module. Each file that uses them declares its own identical `private let` copies.

```swift
// Source: DeviceView.swift lines 671–702 [VERIFIED: codebase]
private let deviceScreenBackground = GooseTheme.appBackground
private let devicePrimaryText = Color(uiColor: .label)
private let controlBackground = Color(uiColor: UIColor { traits in
  traits.userInterfaceStyle == .dark
    ? UIColor(red: 0.122, green: 0.161, blue: 0.188, alpha: 1)
    : UIColor.secondarySystemGroupedBackground
})
private let dividerColor = Color(uiColor: UIColor { traits in
  traits.userInterfaceStyle == .dark
    ? UIColor(red: 0.188, green: 0.220, blue: 0.251, alpha: 1)
    : UIColor.separator
})
private let secondaryText = Color(uiColor: UIColor { traits in
  traits.userInterfaceStyle == .dark
    ? UIColor(red: 0.627, green: 0.651, blue: 0.671, alpha: 1)
    : UIColor.secondaryLabel
})
private let mutedText = Color(uiColor: UIColor { traits in
  traits.userInterfaceStyle == .dark
    ? UIColor(red: 0.561, green: 0.584, blue: 0.600, alpha: 1)
    : UIColor.tertiaryLabel
})
private let connectedGreen = Color(red: 0.42, green: 0.84, blue: 0.30)
private let disconnectedRed = Color(red: 1.0, green: 0.27, blue: 0.23)
private let deviceLabelFont = Font.system(size: 15, weight: .black, design: .default)
private let deviceBodyFont = Font.system(size: 17, weight: .bold, design: .default)
```

### Anti-Patterns to Avoid

- **Calling `ble.hrMonitorManager` from a SwiftUI view directly:** The `hrMonitorManager` instance is an internal implementation detail. Views must only access the promoted `@Published` properties on `GooseBLEClient`. [VERIFIED: codebase pattern]
- **Calling `GooseRustBridge` from `HRMonitorView`:** This phase has no Rust bridge calls. HR BLE data is handled entirely in Swift. [VERIFIED: phase scope]
- **Adding a navigation button to trigger scan manually:** D-04 explicitly prohibits a manual Scan button — scan starts automatically.
- **Making `GooseBLEHRMonitorManager` conform to `ObservableObject` (Pattern b):** This is the alternative the CONTEXT.md does NOT recommend. Pattern (a) is preferred for consistency.
- **Using `.list` style for the scan list:** D-02 and UI-SPEC specify a custom `VStack`-based scroll view, not a `List`. `GooseListBackground` is a `ViewModifier` used in `MoreView` (which is a `List`), not in `DeviceView`-style screens.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| BLE scan/connect logic | Custom CBCentralManager in HRMonitorView | `ble.startHRMonitorScan()` / `connectHRMonitor(_:)` | Already implemented and tested in `GooseBLEClient+HRMonitor.swift` |
| RSSI sorting | Custom sort in SwiftUI | Existing sort in `GooseBLEHRMonitorManager.centralManager(_:didDiscover:)` | Manager already sorts `discoveredHRDevices` by RSSI descending on each update |
| Reconnect backoff UI | Custom reconnect state machine | `ble.hrReconnectState` (existing `@Published` from Phase 9) | Already delivers formatted strings like "reconnecting (attempt 3/10)" |
| Connection state machine | Custom state enum in view | `ble.hrConnectionState` string ("disconnected" / "connecting" / "connected") | Single string drives all 4 UI states |
| Sheet height and drag indicator | Custom `UIViewControllerRepresentable` | `.presentationDetents([.height(220)])` + `.presentationDragIndicator(.visible)` | Native SwiftUI modifiers available iOS 16+ |

**Key insight:** The BLE layer is complete. The UI is purely a rendering concern — no new BLE logic should be introduced.

---

## Critical Gap: "connecting" State Not Set

**The issue:** `GooseBLEHRMonitorManager.connect(_:)` calls `central?.connect(peripheral, options: nil)` without first setting `hrConnectionState = "connecting"`. The `didConnect` callback only fires after the OS completes the connection (can take 1–3 seconds). During this window, `hrConnectionState` remains `"disconnected"` — the UI-SPEC `"CONNECTING"` header state is never reached through the existing code path.

**Fix required:** In `GooseBLEHRMonitorManager.connect(_:)`, set `hrConnectionState = "connecting"` (and mirror to owner's published property) before calling `central?.connect()`. This runs on the BLE callback queue, so mirror to main:

```swift
func connect(_ device: GooseDiscoveredDevice) {
  guard let peripheral = central?.retrievePeripherals(withIdentifiers: [device.id]).first else {
    return
  }
  connectedDeviceName = device.name
  hrConnectionState = "connecting"
  DispatchQueue.main.async { [weak self] in
    self?.owner?.hrConnectionState = "connecting"
  }
  central?.connect(peripheral, options: nil)
}
```

**Confidence:** HIGH — verified by reading `GooseBLEClient+HRMonitor.swift` lines 93–99 and 147. [VERIFIED: codebase]

---

## Critical Gap: Disconnect Implementation Missing

**The issue:** No dedicated disconnect method exists in `GooseBLEHRMonitorManager` or `GooseBLEClient` extensions. The CONTEXT.md D-07 says the Disconnect button calls `ble.stopHRMonitorScan()` and "cancels connection," but `stopHRMonitorScan()` only calls `central?.stopScan()` — it does not call `central?.cancelPeripheralConnection()` or reset `hrConnectionState`.

**Fix required:** Add a `disconnectHRMonitor()` method to `GooseBLEClient` (via extension in `GooseBLEClient+HRMonitor.swift`) that:
1. Stops the scan (`hrMonitorManager.stopScan()`)
2. Cancels the peripheral connection (`hrMonitorManager.central?.cancelPeripheralConnection(hrMonitorManager.hrPeripheral)`)
3. Stops the reconnect cycle (`hrMonitorManager.hrStopReconnect()`)
4. Resets `hrConnectionState` to `"disconnected"` and `connectedDeviceName` to nil

The `didDisconnectPeripheral` callback will fire after cancellation — the code there already sets `hrConnectionState = "disconnected"` and schedules reconnect. The disconnect flow must also cancel that reconnect schedule. `hrMonitorManager.hrStopReconnect()` already handles cancellation + resetting the backoff. The key addition is `cancelPeripheralConnection`.

**Confidence:** HIGH — verified by reading all methods in `GooseBLEClient+HRMonitor.swift`. [VERIFIED: codebase]

---

## Common Pitfalls

### Pitfall 1: Thread Safety on discoveredHRDevices

**What goes wrong:** `GooseBLEHRMonitorManager.discoveredHRDevices` is mutated on the BLE callback queue (CoreBluetooth queue). If `HRMonitorView` reads it directly from the manager (e.g., `ble.hrMonitorManager.discoveredHRDevices`) on the main thread without synchronisation, a data race occurs.

**Why it happens:** CBCentralManager callbacks run on the queue passed at creation (`coreBluetoothQueue`). The array is read by SwiftUI on the main thread.

**How to avoid:** Use Pattern (a) — promoted `@Published var discoveredHRDevices` on `GooseBLEClient`, always written from a `DispatchQueue.main.async` block inside the manager. Views read `ble.discoveredHRDevices`, never `ble.hrMonitorManager.discoveredHRDevices`.

**Warning signs:** Xcode thread sanitiser (TSan) will flag this as a data race if you access the array from both queues without promotion. [VERIFIED: codebase — STATE.md notes this as "HIGH severity pitfall"]

### Pitfall 2: MoreRouteStatus Missing hrMonitor Property

**What goes wrong:** `MoreRouteStatus` is a struct with one `MoreStatusKind` property per route. Adding `.hrMonitor` to `MoreRoute` without adding `var hrMonitor: MoreStatusKind` to `MoreRouteStatus` causes a compile error in `MoreDataStore` (which constructs `MoreRouteStatus`).

**Why it happens:** `MoreRoute.statusKeyPath` property must have a corresponding property in `MoreRouteStatus`.

**How to avoid:** Add both the `case .hrMonitor` to `MoreRoute` AND `var hrMonitor: MoreStatusKind` to `MoreRouteStatus` in `MoreRouteModels.swift`, plus update every switch exhaustion point.

**Warning signs:** Swift compiler "Switch must be exhaustive" error at build time. [VERIFIED: codebase — MoreRouteModels.swift lines 78–95 and 105–120]

### Pitfall 3: Switch Exhaustion in MoreRoute Properties

**What goes wrong:** `MoreRoute` has four computed properties with `switch self` — `title`, `subtitle`, `systemImage`, and `statusKeyPath`. Adding a new case without updating all four causes a compile error.

**How to avoid:** When adding `.hrMonitor`, update all four switch bodies:
- `title`: `"HR Monitor"`
- `subtitle`: `"Connect and view live heart rate from a Bluetooth HR monitor"`
- `systemImage`: `"heart.circle"`
- `statusKeyPath`: `\.hrMonitor` (requires `MoreRouteStatus` addition above)

[VERIFIED: codebase — MoreRouteModels.swift]

### Pitfall 4: deviceRoutes Static Array

**What goes wrong:** `MoreRoute.deviceRoutes` is `static let deviceRoutes: [MoreRoute] = [.device]`. If `.hrMonitor` is not added to this array, the new route will not appear in the "Device" section of `MoreView` (which renders `MoreRoute.deviceRoutes`).

**How to avoid:** Change to `static let deviceRoutes: [MoreRoute] = [.device, .hrMonitor]`.

[VERIFIED: codebase — MoreRouteModels.swift line 97 and MoreView.swift lines 45–47]

### Pitfall 5: DeviceConnectionHeader Has a "Last Sync" Column

**What goes wrong:** `DeviceConnectionHeader` in `DeviceView.swift` has a right-side `VStack` showing "LAST SYNC". If this view is reused directly for `HRMonitorHeader`, the "LAST SYNC" column appears incorrectly (no sync concept for HR monitors).

**How to avoid:** `HRMonitorHeader` must be a **new private struct** in `HRMonitorView.swift` that only renders the left `VStack` (status text + device name). It does not use or wrap `DeviceConnectionHeader`.

[VERIFIED: codebase — DeviceView.swift lines 204–248; UI-SPEC Header Design section]

### Pitfall 6: Sheet Not Dismissed After Connect Tap

**What goes wrong:** If the sheet uses `.sheet(isPresented:)` with a `@State var showSheet = false`, dismissing must be explicit. Using `.sheet(item:)` with `@State var selectedDevice: GooseDiscoveredDevice?` is safer — setting `selectedDevice = nil` dismisses the sheet automatically.

**How to avoid:** Use `.sheet(item: $selectedDevice)`. The "Connect" button action sets `selectedDevice = nil` (or calls the provided `dismiss()` environment value) after calling `ble.connectHRMonitor(device)`.

[VERIFIED: codebase — SwiftUI documentation pattern]

---

## Code Examples

### HRMonitorHeader (new private struct)

```swift
// Source: mirrors DeviceConnectionHeader (DeviceView.swift lines 204-248) but without right column
private struct HRMonitorHeader: View {
  let statusText: String
  let statusColor: Color
  let deviceDisplayName: String

  var body: some View {
    HStack(alignment: .bottom, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(statusText)
          .font(deviceLabelFont)
          .foregroundStyle(statusColor)
          .lineLimit(1)
        Text(deviceDisplayName.uppercased())
          .font(deviceBodyFont.weight(.black))
          .foregroundStyle(devicePrimaryText)
          .lineLimit(2)
          .minimumScaleFactor(0.78)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
```

### HRMonitorDeviceRow

```swift
// Source: ConnectionView.swift lines 102-117, adapted for DeviceView style
private struct HRMonitorDeviceRow: View {
  let device: GooseDiscoveredDevice
  let isConnecting: Bool

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(device.name)
          .font(deviceBodyFont.weight(.black))
          .foregroundStyle(devicePrimaryText)
        Text("\(device.rssi) dBm")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(mutedText)
      }
      Spacer(minLength: 16)
      if isConnecting {
        ProgressView()
          .scaleEffect(0.8)
          .tint(secondaryText)
          .accessibilityLabel("Connecting to \(device.name)")
      }
    }
    .padding(.vertical, 12)
    .contentShape(Rectangle())
    .accessibilityLabel("\(device.name), \(device.rssi) dBm")
  }
}
```

### MoreRouteModels.swift additions

```swift
// Source: MoreRouteModels.swift — add to MoreRoute enum
case hrMonitor

// title:
case .hrMonitor: "HR Monitor"

// subtitle:
case .hrMonitor: "Connect and view live heart rate from a Bluetooth HR monitor"

// systemImage:
case .hrMonitor: "heart.circle"

// statusKeyPath:
case .hrMonitor: \.hrMonitor

// deviceRoutes:
static let deviceRoutes: [MoreRoute] = [.device, .hrMonitor]

// MoreRouteStatus — add property:
var hrMonitor: MoreStatusKind
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual "Scan" button (WHOOP ConnectionView) | Auto-scan on `onAppear` (D-04) | Phase 10 design decision | Better UX — no extra tap required |
| Reading state from `hrMonitorManager` directly | `@Published` promoted state on `GooseBLEClient` | Phase 10 implementation | Thread-safe, SwiftUI-reactive |
| No `"connecting"` intermediate state | Must add `"connecting"` in `connect(_:)` | Phase 10 gap | Required for CONNECTING header and inline ProgressView |

**Missing in current code:**
- `"connecting"` state: Never set by any existing code path
- `disconnectHRMonitor()` method: No single method that stops scan + cancels peripheral + stops reconnect
- `@Published var discoveredHRDevices` on `GooseBLEClient`: Currently only a plain `var` on `GooseBLEHRMonitorManager`
- `@Published var hrConnectionState` on `GooseBLEClient`: Same gap

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ble.hrConnectionState` does not exist as a `@Published` property on `GooseBLEClient` — only as a plain `var` on `GooseBLEHRMonitorManager` | Critical Gap / State Promotion | If it already exists, the promotion task is a no-op — no harm done |
| A2 | `connect(_:)` does not set `"connecting"` state | Critical Gap: connecting state | If it is set elsewhere (e.g., an extension not read), the task adds a duplicate write — harmless but redundant |
| A3 | No Swift XCTest exists for `HRMonitorView` yet — test coverage for this UI is limited to manual/simulator testing | Validation Architecture | If tests exist in an unread file, Wave 0 is smaller |

**If this table is empty:** All claims were verified or cited. Three claims remain assumed because the full GooseBLEClient.swift was only partially read (80 lines of ~980+). Verified findings above are from direct file reading.

---

## Open Questions

1. **MoreDataStore routeStatus() — what status to emit for `.hrMonitor`?**
   - What we know: `routeStatus(ble:model:)` in `MoreDataStore` builds a `MoreRouteStatus` value with a `MoreStatusKind` per route. The `.device` route shows `.ready` when connected.
   - What's unclear: What should `.hrMonitor` show when no HR monitor is connected vs. connected? `.pending` (waiting for connection) or `.unavailable`?
   - Recommendation: Use `.ready` when `ble.hrConnectionState == "connected"`, `.pending` otherwise. Matches the `MoreStatusKind.pending` (clock icon, blue) semantics.

2. **Should `connectingDeviceID` be cleared on connection failure (no `didFailToConnect` observed)?**
   - What we know: `GooseBLEHRMonitorManager` implements `centralManager(_:didConnect:)` and `centralManager(_:didDisconnectPeripheral:)` but NOT `centralManager(_:didFailToConnect:)`.
   - What's unclear: If `connect()` fails, `hrConnectionState` may stay "connecting" indefinitely.
   - Recommendation: Add `centralManager(_:didFailToConnect:error:)` to `GooseBLEHRMonitorManager` that resets `hrConnectionState = "disconnected"`. View `connectingDeviceID` should be cleared by observing `hrConnectionState` returning to `"disconnected"`.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is code/config-only changes within the existing iOS app project. No new external tools, services, CLIs, runtimes, or databases are required.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (GooseSwiftTests target in GooseSwift.xcodeproj) |
| Config file | `GooseSwiftTests/Info.plist` |
| Quick run command | `xcodebuild test -project GooseSwift.xcodeproj -scheme GooseSwift -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:GooseSwiftTests` |
| Full suite command | same (only one test target exists) |

Note: Swift UI component tests cannot be run without Xcode simulator. Rust tests run separately via `cargo test` in `Rust/core/`.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WEAR-04 | Scan list populates from `discoveredHRDevices` | manual-only (BLE hardware/simulator required) | — | N/A |
| WEAR-05 | Tapping device triggers connection flow | manual-only (BLE hardware/simulator required) | — | N/A |
| WEAR-04 (unit) | `@Published var discoveredHRDevices` propagates updates | unit | `xcodebuild test … -only-testing:GooseSwiftTests/GooseBLETypesTests` | ❌ Wave 0 |
| WEAR-05 (unit) | `hrConnectionState` transitions "disconnected" → "connecting" → "connected" | unit | `xcodebuild test … -only-testing:GooseSwiftTests/HRMonitorStateTests` | ❌ Wave 0 |

Manual-only justification: CoreBluetooth scanning and connecting requires physical hardware or a BLE-capable simulator. The `GooseBLEHRMonitorManager` is a CBCentralManagerDelegate — mocking CBCentral would require significant test infrastructure not present in the project.

### Sampling Rate

- Per task commit: `cargo test` (Rust; Swift builds don't run per-task)
- Per wave merge: Build the GooseSwift target to verify compilation
- Phase gate: Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `GooseSwiftTests/HRMonitorStateTests.swift` — covers `hrConnectionState` transitions and `discoveredHRDevices` promotion

*(Existing `GooseBLETypesTests.swift` and `WearableDescriptorTests.swift` cover types used by this phase but do not cover the new state promotion or state transitions.)*

---

## Security Domain

`security_enforcement: true`, `security_asvs_level: 1`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes (device name) | `prefix(64)` already applied in `GooseBLEHRMonitorManager.centralManager(_:didDiscover:)` line 125 — device names are sanitised before storage in `discoveredHRDevices` |
| V6 Cryptography | no | — |
| V7 Error Handling | yes | Connection failures must not crash; `didFailToConnect` gap (Open Question 2) must be addressed |

### Known Threat Patterns for CoreBluetooth + SwiftUI

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious BLE device name (XSS-style injection) | Tampering | Already mitigated: `sanitizedName = String(rawName.prefix(64))` and whitespace trimming in manager |
| UI data race (BLE queue vs. main) | Spoofing / Denial of Service | Mitigated by Pattern (a): `@Published` promoted via `DispatchQueue.main.async` |
| Unbounded scan without stop | Denial of Service (battery) | `onDisappear` calls `stopHRMonitorScan()` |

No new security attack surface beyond what Phase 9 already handled. The only addition is promoting existing private state as `@Published` — no new data leaves the device, no new network surface, no new persistence.

---

## Project Constraints (from CLAUDE.md)

| Directive | Enforcement in Phase 10 |
|-----------|------------------------|
| No external Swift dependencies (URLSession only) | Confirmed — no new packages |
| Swift / SwiftUI for iOS | All new code in Swift/SwiftUI |
| No SPM root Package.swift | Not touched |
| 2-space indentation, K&R brace style | Apply to `HRMonitorView.swift` |
| `private` for internal state in `final class` types | `HRMonitorContentView` is a private struct; `connectingDeviceID` and `selectedDevice` are `@State private var` |
| PascalCase for types, camelCase for methods/properties | `HRMonitorView`, `HRMonitorHeader`, `connectingDeviceID` |
| `+` suffix extension files for functional areas | New additions to `GooseBLEClient+HRMonitor.swift`, not a new extension file |
| `@MainActor` for UI mutations; BLE callbacks dispatch to main | `DispatchQueue.main.async` in manager before setting owner's `@Published` properties |
| `GooseRustBridge` is synchronous — never call from `@MainActor` with expensive methods | Not applicable — this phase has no Rust bridge calls |
| All `@Published` state mutations via `@MainActor` | Promoted properties must be set via `DispatchQueue.main.async` from the BLE queue |

---

## Sources

### Primary (HIGH confidence)

- [VERIFIED: codebase] `GooseSwift/GooseBLEClient+HRMonitor.swift` — Full source of `GooseBLEHRMonitorManager` and extension methods; confirms missing "connecting" state, missing `disconnectHRMonitor()`, and `objectWillChange.send()` pattern
- [VERIFIED: codebase] `GooseSwift/GooseBLEClient.swift` (lines 1–110) — All `@Published` properties; confirms `hrReconnectState` exists at line 24; confirms `hrMonitorManager` is a plain stored property at line 93; confirms absence of `discoveredHRDevices` or `hrConnectionState` as `@Published`
- [VERIFIED: codebase] `GooseSwift/DeviceView.swift` — Source of truth for visual tokens (color, font constants, `DeviceConnectionHeader` struct) and `DeviceView` structural pattern
- [VERIFIED: codebase] `GooseSwift/MoreRouteModels.swift` — Complete `MoreRoute` enum; all switch arms that need updating; `MoreRouteStatus` struct; `deviceRoutes` static array
- [VERIFIED: codebase] `GooseSwift/MoreView.swift` — `destination(for:)` switch; exact insertion point for `.hrMonitor`
- [VERIFIED: codebase] `GooseSwift/GooseBLETypes.swift` — `GooseDiscoveredDevice` struct (id, name, rssi, generation)
- [VERIFIED: codebase] `GooseSwift/ConnectionView.swift` — Existing scan row pattern (lines 97–121); reference for RSSI display format
- [VERIFIED: codebase] `.planning/phases/10-hr-monitor-scan-connect-ui/10-CONTEXT.md` — All locked decisions and discretion items
- [VERIFIED: codebase] `.planning/phases/10-hr-monitor-scan-connect-ui/10-UI-SPEC.md` — Complete UI contract (hierarchy, spacing, typography, color, state machine, interaction flows, file contract)
- [VERIFIED: codebase] `GooseSwiftTests/GooseBLETypesTests.swift` — Existing test file; confirms XCTest infrastructure is present; shows test-writing conventions

### Secondary (MEDIUM confidence)

- [VERIFIED: codebase] `GooseSwift/GooseTheme.swift` — `GooseTheme.appBackground` adaptive color definition
- [VERIFIED: codebase] `.planning/STATE.md` — Confirms "discoveredHRDevices data race (BT queue vs. main thread) — HIGH severity pitfall to address in Phase 10"

### Tertiary (LOW confidence)

- None — all claims verified directly from codebase.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Apple-only frameworks; no third-party packages
- Architecture patterns: HIGH — directly derived from existing codebase files
- Critical gaps (connecting state, disconnect method): HIGH — verified by reading full `GooseBLEClient+HRMonitor.swift`
- Pitfalls: HIGH — verified from codebase structure (MoreRouteModels, DeviceView, STATE.md)
- Test infrastructure: HIGH — `GooseSwiftTests` directory and files confirmed

**Research date:** 2026-06-04
**Valid until:** Stable — no external dependencies, no third-party packages; valid until codebase changes
