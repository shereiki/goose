# Phase 6: WHOOP Gen4 iOS Support — Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Task Boundary

Expose WHOOP Gen4 (4.0) support in the iOS app layer. The Rust core already fully supports Gen4
(DeviceType::Gen4, 4-byte header, CRC8, UUID 61080001-8D6D-82B8-614A-1C8CB0F8DCC6).
The upload already sends `device_generation: "4.0"` for Gen4 devices.
The BLE scan already includes both Gen4 and Gen5 service UUIDs in `whoopServices`.

What's missing (iOS app layer only):
1. Command capability guards block all Gen4 commands — `supportsV5*` only accepts `fd4b0002` prefix
2. `GooseDiscoveredDevice` has no `generation` field
3. No generation label in device scan list or connected device view
4. Onboarding copy doesn't mention WHOOP 4.0
5. No test verification of the Gen4 upload path

**This is an untested version (no physical WHOOP 4.0 hardware).** Ship with a note in the PR/release
asking Gen4 users to report bugs. Target for upstream PR to b-nnett/goose after validation.

</domain>

<decisions>
## Implementation Decisions

### 1. Command Guard Fix Approach: Fix + WearableDescriptor

Introduce a `WearableDescriptor` value type in `GooseBLETypes.swift` that centralises
all per-device UUID arrays and name checks. Use it to resolve the command guard.

```swift
struct WearableDescriptor {
  let serviceUUIDs: [CBUUID]
  let commandCharacteristicPrefix: String
  let notificationCharacteristicPrefixes: [String]
  let rustDeviceType: String
  func isCommandCharacteristic(_ c: CBCharacteristic) -> Bool {
    c.uuid.uuidString.lowercased().hasPrefix(commandCharacteristicPrefix)
  }
}
```

Rationale: The current codebase has 4 separate UUID arrays scattered across `GooseBLEClient.swift`
(`whoopServices`, `commandCharacteristicIDs`, `notificationCharacteristicIDs`,
`debugMenuCharacteristicIDs`). `WearableDescriptor` centralises these per device family,
which makes Phase 8 (second wearable) significantly cleaner. +2h now saves -8h in Phase 8.

### 2. supportsV5* Rename

Rename all `supportsV5*` computed properties to remove the `V5` reference, since Gen4 supports
the same logical commands:
- `supportsV5HistoricalSync` → `supportsHistoricalSync`
- `supportsV5AlarmCommands` → `supportsAlarmCommands`
- `supportsV5ClockCommands` → `supportsClockCommands`
- `supportsV5SensorCommands` → `supportsSensorCommands`
- `isV5CommandCharacteristic` → resolved via `WearableDescriptor.isCommandCharacteristic`

### 3. Generation Derivation: At Scan Time from Service UUID

`GooseDiscoveredDevice` gets a new `generation: String` field (e.g. `"4.0"` or `"5.0"`).
Derived at scan time from the advertised service UUID:
- Service UUID starts with `61080001` → `"4.0"` (Gen4)
- Service UUID starts with `fd4b0001` → `"5.0"` (Gen5)
- Unknown → `"unknown"` (fallback, should not occur for WHOOP devices)

Available before connecting — the label "Gen 4" can appear in the scan list.

### 4. Generation Propagation

Three propagation points:
- `GooseDiscoveredDevice.generation` (scan-time, from service UUID)
- `GooseAppModel.connectedDeviceGeneration: String?` (@Published, set when device connects)
- `GooseNotificationEvent.rustDeviceType` (already "GEN4" for Gen4 — upload already correct, no change needed)

### 5. Gen4 Name Recognition: Trust isWhoopName() with a Code Comment

`isWhoopName()` does a case-insensitive substring search for "whoop". Assume WHOOP 4.0 devices
advertise with "WHOOP" in their Bluetooth device name (not confirmed on hardware).

Add a code comment: `// Gen4 device name assumed to contain "whoop" — not validated on hardware.`

If a Gen4 device doesn't match, the workaround is to connect via identifier from the device list.
This is noted in the release notes as a known limitation.

### 6. UI: Subtitle Text, Both Contexts

Show `"Gen 4"` / `"Gen 5"` as a subtitle (`.caption` or `.footnote`) under the device name:
- **Scan list row**: `DeviceName\nGen 4 · –65 dBm` (generation · RSSI)
- **Connected device view**: `Gen 4 · Connected` as secondary text

No new component needed. Pattern matches the existing `.foregroundStyle(.secondary)` text pattern
throughout the app.

### 7. Test Strategy (No Hardware)

Unit tests only — no hardware required:
- Test `rustDeviceType` returns `"GEN4"` for `61080002-...` characteristic UUIDs
- Test `WearableDescriptor.isCommandCharacteristic` returns true for `61080002-...` prefix
- Test `GooseDiscoveredDevice.generation` derivation from service UUID
- Test `GooseAppModel.connectedDeviceGeneration` is set correctly on device connect

### 8. Release Notes + Upstream PR

Include a **"Gen4 support — untested build"** note in the PR/commit description and any GitHub
release notes:
> "WHOOP 4.0 (Gen4) support added. No physical Gen4 hardware was available for testing.
> If you have a WHOOP 4.0, please test and report issues at [repo issues]. Known limitation:
> device name detection relies on Bluetooth-advertised name containing 'WHOOP' — report if your
> Gen4 doesn't appear in the scan list."

After user validation, submit as a PR to upstream `b-nnett/goose` (deferred — after Phase 6 ships
and gets real-world validation).

</decisions>

<specifics>
## Specific Implementation Notes

**Files to modify:**
- `GooseSwift/GooseBLETypes.swift` — add `WearableDescriptor`, add `generation` to `GooseDiscoveredDevice`
- `GooseSwift/GooseBLEClient.swift` — use `WearableDescriptor` for scan/connect UUID arrays
- `GooseSwift/GooseBLEClient+Commands.swift` — rename `supportsV5*` guards, use descriptor
- `GooseSwift/GooseAppModel.swift` — add `@Published var connectedDeviceGeneration: String?`
- `GooseSwift/GooseBLEClient+Parsing.swift` — derive generation from service UUID at scan time
- Onboarding views — add copy mentioning WHOOP 4.0

**Key guard fix location:** `GooseBLEClient+Commands.swift:147-165`
Current: `isV5CommandCharacteristic` checks `fd4b0002` prefix only
After: resolved via `WearableDescriptor.isCommandCharacteristic` which accepts both prefixes

**WearableDescriptor instances:**
- `WearableDescriptor.whoopGen5` — serviceUUID: `fd4b0001`, commandPrefix: `fd4b0002`, notifPrefixes: `["fd4b"]`
- `WearableDescriptor.whoopGen4` — serviceUUID: `61080001`, commandPrefix: `61080002`, notifPrefixes: `["610800"]`

**Research refs used:**
- `.planning/research/ARCHITECTURE.md` — integration points and file list
- `.planning/research/FEATURES.md` — Gen4 codebase state (80% done)
- `.planning/research/PITFALLS.md` — `supportsV5*` blockage, device name risks

</specifics>

<canonical_refs>
## Canonical References

- `GooseSwift/GooseBLEClient+Commands.swift` — `supportsV5*` guard definitions (lines 147-165)
- `GooseSwift/GooseBLETypes.swift` — `GooseDiscoveredDevice`, `GooseNotificationEvent.rustDeviceType`
- `GooseSwift/GooseBLEClient.swift` — `whoopServices`, UUID arrays, `isWhoopName()`
- `.planning/research/ARCHITECTURE.md` — integration points for Gen4 iOS layer
- `.planning/research/PITFALLS.md` — Pitfall #2 (supportsV5* blockage)
- `.planning/REQUIREMENTS.md` — GEN4-01 to GEN4-05

</canonical_refs>

<deferred>
## Deferred Ideas

- Upstream PR to b-nnett/goose — after Phase 6 ships and gets real-world Gen4 validation
- Gen4 hardware validation — needed before upstream PR submission
- Explicit Gen4 device name patterns — if `isWhoopName()` proves insufficient on real hardware
</deferred>
