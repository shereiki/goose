---
phase: "06"
plan: "06-P02"
title: "UI Generation Labels + Onboarding Copy"
wave: 2
depends_on:
  - "06-P01"
files_modified:
  - GooseSwift/DeviceView.swift
  - GooseSwift/ConnectionView.swift
  - GooseSwift/OnboardingStepViews.swift
  - GooseSwift/OnboardingModels.swift
autonomous: true
requirements:
  - GEN4-03
  - GEN4-04
---

<objective>
Add generation labels ("Gen 4" / "Gen 5") to the device scan list and connected device view,
update the device scan row in onboarding to show generation, and update onboarding copy
to explicitly mention WHOOP 4.0 support alongside WHOOP 5.0.
Depends on Plan 06-P01 which adds `GooseDiscoveredDevice.generation` and
`GooseAppModel.connectedDeviceGeneration`.
</objective>

<must_haves>
  <truths>
    - GEN4-03: The onboarding connect step title or subtitle explicitly mentions "WHOOP 4.0" (or "4.0 and 5.0"), not just "WHOOP"
    - GEN4-04: The connected device view in DeviceView shows a generation label "Gen 4" or "Gen 5" when a device is connected
    - D-05: The scan list row in DeviceView shows generation as a subtitle replacing the raw UUID
    - D-06: The onboarding scan list row shows generation instead of only "RSSI N"
    - D-07: ConnectionView scan list also shows generation information
  </truths>
</must_haves>

<tasks>

  <task id="P02-T01" type="execute">
    <title>Update DeviceView scan list row — replace UUID subtitle with generation + RSSI</title>
    <read_first>
      - GooseSwift/DeviceView.swift (lines 555-615 for DiscoveredDeviceList / ForEach scan list rows)
      - GooseSwift/GooseBLETypes.swift (after P01: GooseDiscoveredDevice with generation field)
    </read_first>
    <action>
      In `DeviceView.swift`, inside the `DiscoveredDeviceList` private struct's `ForEach(ble.discoveredDevices)` block
      (around lines 564-590), find the `VStack` that contains:
      ```swift
      Text(device.name)  // primary — keep as-is
      Text(device.id.uuidString)  // secondary — replace this line
      ```
      Replace `Text(device.id.uuidString)` with:
      ```swift
      Text("Gen \(generationMajorVersion(device.generation)) · \(device.rssi) dBm")
        .font(.system(size: 12, weight: .semibold, design: .default))
        .foregroundStyle(mutedText)
        .lineLimit(1)
      ```
      Add a private helper function `generationMajorVersion` in the `DiscoveredDeviceList` extension or at file scope:
      ```swift
      private func generationMajorVersion(_ generation: String) -> String {
        // "4.0" -> "4", "5.0" -> "5", "unknown" -> "?"
        generation == "unknown" ? "?" : String(generation.prefix(1))
      }
      ```
      Keep existing `.font(.system(size: 12, weight: .semibold, design: .default))` and `.foregroundStyle(mutedText)` style constants unchanged.
    </action>
    <acceptance_criteria>
      - `DeviceView.swift` scan list row no longer contains `device.id.uuidString`
      - `DeviceView.swift` scan list row contains `device.generation` referenced via the subtitle
      - A `generationMajorVersion` helper converts "4.0" → "4", "5.0" → "5", "unknown" → "?"
      - The subtitle text format is "Gen N · N dBm" (verifiable by reading the Text literal)
    </acceptance_criteria>
  </task>

  <task id="P02-T02" type="execute">
    <title>Add generation label to connected device view in DeviceView</title>
    <read_first>
      - GooseSwift/DeviceView.swift (lines 203-243 for DeviceConnectionHeader struct; lines 310-325 for DeviceDetailStack rows)
      - GooseSwift/GooseAppModel.swift (after P01: @Published var connectedDeviceGeneration: String?)
    </read_first>
    <action>
      In `DeviceView.swift`, update `DeviceConnectionHeader` to show the generation label.

      Option A (preferred — minimal change): Add an optional `generation: String?` parameter to
      `DeviceConnectionHeader`. In the `VStack(alignment: .leading, spacing: 7)` body, after
      `Text(deviceName.uppercased())`, conditionally show:
      ```swift
      if let gen = generation, gen != "unknown" {
        Text("Gen \(gen.prefix(1))")
          .font(deviceLabelFont)
          .foregroundStyle(secondaryText)
      }
      ```
      Pass `model.connectedDeviceGeneration` to the `DeviceConnectionHeader` call at line 29
      (inside the parent `DeviceContentView` struct where `ble.activeDeviceName` is passed).
      The parent already receives `model` via `@EnvironmentObject`.

      Add the parameter to `DeviceConnectionHeader` as:
      ```swift
      let generation: String?  // nil when disconnected
      ```
      Update the call site at line 29-34 to pass:
      ```swift
      DeviceConnectionHeader(
        connected: deviceConnected,
        statusText: connectionHeadline,
        deviceName: ble.activeDeviceName,
        lastSync: lastSyncSummary,
        generation: model.connectedDeviceGeneration
      )
      ```

      The `model` is accessible via `@EnvironmentObject private var model: GooseAppModel` which
      already exists on `DeviceContentView` (the parent struct) — confirm by reading the file.
    </action>
    <acceptance_criteria>
      - `DeviceConnectionHeader` has a `generation: String?` parameter
      - When generation is "4.0" or "5.0", a `Text("Gen N")` label appears in the header VStack
      - When generation is nil or "unknown", no generation label appears
      - `DeviceConnectionHeader(...)` call site passes `model.connectedDeviceGeneration`
      - `.foregroundStyle(secondaryText)` is used for the generation label (consistent with existing label style)
    </acceptance_criteria>
  </task>

  <task id="P02-T03" type="execute">
    <title>Update ConnectionView scan list row to show generation</title>
    <read_first>
      - GooseSwift/ConnectionView.swift (lines 68-90 for the ForEach(ble.discoveredDevices) block in the "Discovered" section)
      - GooseSwift/GooseBLETypes.swift (after P01: GooseDiscoveredDevice with generation field)
    </read_first>
    <action>
      In `ConnectionView.swift`, inside the "Discovered" section's `ForEach(ble.discoveredDevices)` block,
      find the `VStack(alignment: .leading)` that contains:
      ```swift
      Text(device.name)
      Text(device.id.uuidString)
        .font(.caption)
        .foregroundStyle(.secondary)
      ```
      Replace `Text(device.id.uuidString)` with:
      ```swift
      Text("Gen \(device.generation == "unknown" ? "?" : String(device.generation.prefix(1))) · \(device.rssi) dBm")
        .font(.caption)
        .foregroundStyle(.secondary)
      ```
      Keep the surrounding `HStack`, `Spacer()`, and `Text("\(device.rssi)")` (RSSI is shown
      separately in ConnectionView — either remove the duplicate RSSI Text or keep both as is).
      Since ConnectionView is a debug/advanced view, simplicity is acceptable.
    </action>
    <acceptance_criteria>
      - `ConnectionView.swift` ForEach scan row no longer uses `device.id.uuidString` as a visible label
      - `ConnectionView.swift` scan row shows `device.generation` in the subtitle
    </acceptance_criteria>
  </task>

  <task id="P02-T04" type="execute">
    <title>Update onboarding scan row to show generation and update connect step copy</title>
    <read_first>
      - GooseSwift/OnboardingStepViews.swift (lines 576-615 for the device row struct; lines 260-290 for connect step subtitle strings)
      - GooseSwift/OnboardingModels.swift (lines 24-25 for the connect step title)
      - GooseSwift/GooseBLETypes.swift (after P01: GooseDiscoveredDevice.generation)
    </read_first>
    <action>
      1. **Onboarding scan row** (around line 589): In the `VStack(alignment: .leading, spacing: 2)`
         that shows `Text(device.name)` and `Text("RSSI \(device.rssi)")`, replace
         `Text("RSSI \(device.rssi)")` with:
         ```swift
         let genLabel = device.generation == "unknown" ? "" : "Gen \(device.generation.prefix(1)) · "
         Text("\(genLabel)RSSI \(device.rssi)")
           .font(.subheadline)
           .foregroundStyle(.secondary)
         ```

      2. **Connect step title** in `OnboardingModels.swift` (line 25):
         Change `"Connect your WHOOP"` to `"Connect your WHOOP (4.0 or 5.0)"`.
         Alternatively, keep the title and update the subtitle/body copy.

      3. **Connect step subtitle strings** in `OnboardingStepViews.swift` (around lines 272-288):
         Update the default body text from:
         `"Take the strap off your wrist, keep it nearby, then start pairing."`
         to:
         `"Supports WHOOP 4.0 and WHOOP 5.0. Take the strap off your wrist, keep it nearby, then start pairing."`
         And/or update the "Pair your WHOOP strap" fallback label to "Pair your WHOOP (4.0 or 5.0)".

      Focus: ensure at least one user-visible string in the onboarding connect flow explicitly
      mentions "4.0" or "WHOOP 4.0". The exact wording is at implementer's discretion.
    </action>
    <acceptance_criteria>
      - `OnboardingStepViews.swift` onboarding scan row shows device.generation in the subtitle text
      - At least one string in `OnboardingModels.swift` or `OnboardingStepViews.swift` contains "4.0" referring to WHOOP generation
      - No compile errors from changed `GooseDiscoveredDevice` usage (generation field is accessed correctly)
    </acceptance_criteria>
  </task>

</tasks>

<verification>
  1. `grep -n "device.generation\|connectedDeviceGeneration" GooseSwift/DeviceView.swift` — must show generation used in both scan list and header
  2. `grep -n "4.0" GooseSwift/OnboardingStepViews.swift GooseSwift/OnboardingModels.swift` — must return at least one result referencing WHOOP 4.0
  3. `grep -n "device.id.uuidString" GooseSwift/DeviceView.swift` — should return zero results (UUID replaced by generation label)
  4. Xcode build of GooseSwift scheme for simulator succeeds without compile errors
  5. Manual UI review: scan list in DeviceView shows "Gen 4 · -NN dBm" or "Gen 5 · -NN dBm" format in simulator (verify by checking the layout code, no hardware needed)
</verification>

<success_criteria>
  - DeviceView scan list shows "Gen 4" or "Gen 5" alongside RSSI, replacing raw UUID
  - Connected device view shows "Gen 4" or "Gen 5" label under the device name
  - Onboarding connect step copy mentions WHOOP 4.0 in at least one user-visible string
  - Onboarding scan row shows generation information alongside device name
  - No regression in existing UI layout (verified by reading the modified code and confirming structure)
</success_criteria>
