---
phase: 6
reviewers: [internal-critic]
reviewed_at: 2026-06-03T21:25:32Z
plans_reviewed:
  - 06-P01-PLAN.md
  - 06-P02-PLAN.md
  - 06-P03-PLAN.md
reviewer_note: >
  Only the claude CLI was detected on this system. Running inside Claude Code (SELF_CLI=claude),
  so the claude CLI is skipped for independence. Review performed as a structured internal
  adversarial critique using direct codebase inspection to validate every assumption in the plans.
  All findings are grounded in actual file reads, not speculation.
---

# Cross-AI Plan Review — Phase 6: WHOOP Gen4 iOS Support

## Internal Adversarial Review

**Reviewer:** Internal critic (Claude Code session, adversarial mode)
**Method:** Direct codebase inspection cross-referenced against plan assumptions

---

### Summary

The three-plan structure is well-organised and the critical `"GEN4"` Rust bridge bug discovery
(parse_device_type not accepting the Swift-emitted string) is the most valuable finding in P01 —
this would have been a silent data-loss bug in production. The wave ordering is correct (types
first, UI second, tests third). However, there are several concrete issues that need addressing
before execution, ranging from a HIGH severity correctness bug in the `connectedDeviceGeneration`
propagation approach to MEDIUM issues around WearableDescriptor scope reduction and a missing
disconnect reset path.

---

### Strengths

- **Critical bug correctly identified and planned** — P01-T04b catches that Swift sends `"GEN4"`
  but Rust only accepted `"GEN_4"`. This was a genuine silent data-loss bug. The fix is minimal
  and the Rust test (P03-T04) verifies it end-to-end.
- **Wave ordering is correct** — types/guards (W1) → UI (W2) → tests (W3) respects the compile-time
  dependency chain without unnecessary serialisation.
- **All 5 requirements mapped** — GEN4-01 through GEN4-05 each have a clear owner plan and
  verifiable acceptance criteria.
- **Concrete line references** — Most tasks include actual file line numbers verified against the
  codebase, which reduces executor ambiguity significantly.
- **Xcode test target plan is realistic** — P03-T01 provides both Xcode-UI and manual pbxproj
  paths, acknowledging that automated pbxproj editing is fragile.
- **`shouldUseCommandCharacteristic` addressed** — The preference-ordering logic for characteristic
  selection is correctly updated in P01-T02 rather than left as a latent bug.

---

### Concerns

#### HIGH — P01-T05: Wrong propagation mechanism for `connectedDeviceGeneration`

**Finding:** The plan says "follow the existing pattern where `GooseAppModel` listens to
`ble.$connectionState.sink`". This pattern does **not exist** in the codebase. `GooseAppModel`
does not use Combine. It uses a closure callback: `ble.onConnectionStateChange = { [weak self]
state in Task { @MainActor in self?.handleBLEConnectionStateChange(state) } }`. The correct hook
point is `handleBLEConnectionStateChange(_:)` in `GooseAppModel+Lifecycle.swift`.

**Risk:** If the executor follows the plan literally and tries to add a `$connectionState.sink`,
it will either (a) introduce an unnecessary `AnyCancellable` store that has no precedent in the
codebase, or (b) fail to compile because there's no `import Combine` and no cancellables
storage. Either way, `connectedDeviceGeneration` won't be set correctly.

**Fix required:** P01-T05 must say "In `GooseAppModel+Lifecycle.swift`, inside
`handleBLEConnectionStateChange(_:)`, set `connectedDeviceGeneration` when `state == "ready"`
and clear it in the `guard state == "ready" else` branch."

---

#### HIGH — P01-T01: `WearableDescriptor` shape is a subset of what CONTEXT.md Decision 1 specifies

**Finding:** CONTEXT.md Decision 1 defines `WearableDescriptor` with 4 fields:
`serviceUUIDs: [CBUUID]`, `commandCharacteristicPrefix: String`,
`notificationCharacteristicPrefixes: [String]`, `rustDeviceType: String`. The P01 plan delivers
only 2 fields: `serviceUUIDPrefix: String` and `commandCharacteristicPrefix: String`.

**Risk:** Phase 8 (Additional Wearables) depends explicitly on `WearableDescriptor` for routing
notification frames. The `rustDeviceType` field in particular was in CONTEXT.md precisely to
enable Phase 8's `rustDeviceType` derivation to move from `GooseNotificationEvent`'s heuristic
to the descriptor. Delivering a 2-field stub means Phase 8 will need to retrofit the shape,
losing the Phase 6 forward-compatibility benefit that justified the extra work.

**Fix required:** Add `rustDeviceType: String` to `WearableDescriptor` in P01-T01. Set it to
`"GEN4"` for `.whoopGen4` and `"GOOSE"` for `.whoopGen5`. This is a one-line addition per
instance that preserves Phase 8 extensibility. The `notificationCharacteristicPrefixes` field
is optional for Phase 6 but `rustDeviceType` is the key forward-compatibility hook.

---

#### MEDIUM — P01-T05: Missing `activeDescriptor = nil` on disconnect (acceptance criteria mismatch)

**Finding:** The acceptance criteria says `activeDescriptor` is reset to nil in
`GooseBLEClient+CentralDelegate.swift` `didDisconnectPeripheral`. The action block is correct
in describing this. However, the plan also shows `commandCharacteristic` being reset on
disconnect, but it doesn't specify *where* `commandCharacteristic = nil` actually happens — so
the executor needs to find it independently. The plan should reference the exact method name:
`centralManager(_:didDisconnectPeripheral:error:)`.

**Risk:** Low, but if the executor misses the disconnect reset, `activeDescriptor` from a
previous Gen4 session would persist into the next connection, potentially mis-labelling a Gen5
device as Gen4 if reconnection happens with a different device.

**Fix:** Add the specific method name to the action block: "In
`GooseBLEClient+CentralDelegate.swift`, in `centralManager(_:didDisconnectPeripheral:error:)`,
set `activeDescriptor = nil` alongside `commandCharacteristic = nil`."

---

#### MEDIUM — P02-T04: Onboarding title change may break UI snapshot tests or UI layout

**Finding:** Changing `"Connect your WHOOP"` to `"Connect your WHOOP (4.0 or 5.0)"` in
`OnboardingModels.swift` adds ~20 characters to a title used in an onboarding flow with
potentially fixed-width layout constraints. The plan doesn't verify the title fits without
truncation in the smallest supported screen size (iPhone SE, 320pt wide). The project targets
iOS 26.0, but SE-class devices remain supported.

**Risk:** Low probability of actual breakage since SwiftUI wraps text by default, but worth
noting. More importantly, the plan gives the executor significant discretion ("exact wording is
at implementer's discretion") — this may result in inconsistent phrasing across the 5+ onboarding
string call sites (lines 261, 267, 270, 272, 288).

**Fix:** Pin the minimum change: specify exactly which one string must contain "4.0" (the
body/subtitle at line 288, not the title at line 25) to minimise layout risk while satisfying
GEN4-03.

---

#### MEDIUM — P03-T02: `WearableDescriptor.isCommandCharacteristic` is untestable as written

**Finding:** The test plan acknowledges `CBCharacteristic` can't be instantiated in unit tests,
and proposes testing `commandCharacteristicPrefix` directly instead. But it then suggests adding
`func isCommandUUID(_ uuid: CBUUID) -> Bool` as an alternative. The plan must commit to one
approach, not offer both — an executor may implement the main plan (testing the prefix directly)
while the `isCommandUUID` alternative is left in dead code.

**If the HIGH finding about `WearableDescriptor` missing `rustDeviceType` is fixed, then
`isCommandUUID` becomes the clean testable surface.** The test plan should definitively say:
"Add `func isCommandUUID(_ uuid: CBUUID) -> Bool` to `WearableDescriptor` and test that
method, not the `isCommandCharacteristic(_ c: CBCharacteristic)` method directly."

---

#### LOW — P01-T02: `shouldUseCommandCharacteristic` with nil `activeDescriptor` returns `false`

**Finding:** The proposed body of `shouldUseCommandCharacteristic` when `activeDescriptor` is
nil returns `false`. This means: if `processDiscoveredCharacteristics` is called before
`activeDescriptor` is set (e.g., from a cached service path), the first command characteristic
discovered will be rejected and `commandCharacteristic` will never be set. 

The original code accepted the first valid characteristic unconditionally: `guard let current =
commandCharacteristic else { return true }`. The new code returns `false` when `activeDescriptor`
is nil even with no current characteristic. The plan sets `activeDescriptor` at the same time as
`commandCharacteristic` (P01-T05), but `shouldUseCommandCharacteristic` is called *before*
`commandCharacteristic` is set — it's called to *decide* whether to set it.

**Fix:** Keep `guard let current = commandCharacteristic else { return true }` — if no command
characteristic is set yet, always accept the candidate. Only apply the descriptor-based preference
logic when a characteristic is already set and we're evaluating a replacement.

---

#### LOW — P03-T01: `autonomous: true` on Xcode pbxproj edit is over-optimistic

**Finding:** The test target creation task (P03-T01) has `autonomous: true` but the action
recommends "Option A — Xcode UI (preferred if running with Xcode)". An automated executor cannot
use the Xcode UI. The fallback (manual pbxproj edit) is complex, fragile, and frequently breaks
on minor version differences in Xcode's pbxproj format.

**Fix:** Set `autonomous: false` on P03-T01, or alternatively change the approach to use
`xcodebuild` to add the test target via a Swift Package or use `swift package init --type
library` + merge strategy.

---

#### LOW — P02-T01: UUID removed from scan list may hurt debugging

**Finding:** The plan removes `device.id.uuidString` from the scan list row in DeviceView,
replacing it with the generation label. The UUID is useful for debugging Bluetooth issues
(connecting by identifier, cross-referencing OS Bluetooth logs). DeviceView is primarily the
diagnostic screen — its power-user audience benefits from the raw UUID.

**Suggestion:** Keep the UUID as a tertiary `.caption2` line beneath the generation label, or
move it to an onLongPress tooltip/popover. This is a UX question, not a blocking issue.

---

### Suggestions

1. **Fix P01-T05 propagation mechanism** (HIGH) — Replace the `ble.$connectionState.sink`
   reference with `handleBLEConnectionStateChange(_:)` in `GooseAppModel+Lifecycle.swift`. This
   is the existing hook; add 3-4 lines there to set/clear `connectedDeviceGeneration`.

2. **Add `rustDeviceType: String` to `WearableDescriptor`** (HIGH) — One additional field
   preserving Phase 8 forward-compatibility. Add `"GEN4"` and `"GOOSE"` to the static instances.

3. **Fix `shouldUseCommandCharacteristic` nil guard** (LOW) — Restore `guard let current =
   commandCharacteristic else { return true }` before the descriptor-based logic.

4. **Set `autonomous: false` on P03-T01** (LOW) — Xcode test target creation cannot be
   automated without Xcode.app.

5. **Pin onboarding string change to body copy, not title** (MEDIUM) — Change line 288 body
   string to mention "4.0", avoid changing the shorter title to prevent layout issues.

6. **Commit to `isCommandUUID` test approach in P03-T02** (MEDIUM) — Remove the "or alternatively"
   hedging; specify `isCommandUUID` as the testable surface.

---

### Risk Assessment

**Overall risk: MEDIUM**

The plans are well-researched and the critical Rust bug fix is correct. The HIGH severity issues
are both correctness bugs that would survive code review but cause silent failures at runtime:

- The `connectedDeviceGeneration` won't update because the propagation uses a non-existent
  Combine pattern — the generation label will always be nil/missing in the connected device view.
- The narrowed `WearableDescriptor` shape will require a rework in Phase 8 rather than the
  promised "Phase 8 significantly cleaner" benefit.

Neither HIGH issue would cause a crash or data loss, but both would make Phase 6 feel incomplete
to users (no generation label when connected) and create technical debt for Phase 8.

The LOW `shouldUseCommandCharacteristic` issue is a potential regression: on a cached GATT
path (device reconnects without re-discovery), `commandCharacteristic` may never be set because
`shouldUseCommandCharacteristic` returns `false` for all candidates when `activeDescriptor` is
nil at the moment of evaluation. This could break Gen5 devices in the reconnection path.

---

## Consensus Summary

### Agreed Strengths

- Rust `"GEN4"` alias bug fix is the most impactful finding and is correctly planned
- Wave structure and dependency ordering are sound
- Requirements-to-plan mapping is complete (5/5 GEN4 requirements covered)

### Agreed Concerns

- **P01-T05 propagation mechanism is wrong** — `ble.$connectionState.sink` does not exist; the
  correct hook is `handleBLEConnectionStateChange(_:)` in GooseAppModel+Lifecycle.swift
- **`WearableDescriptor` is smaller than CONTEXT.md specifies** — missing `rustDeviceType` field
  reduces Phase 8 extensibility value
- **`shouldUseCommandCharacteristic` nil guard removal** — risks breaking Gen5 reconnection
- **P03-T01 `autonomous: true`** — manual pbxproj editing cannot be automated safely

### Divergent Views

None — this was a single-reviewer session. The above concerns represent one systematic pass
through all three plans with direct codebase verification.
