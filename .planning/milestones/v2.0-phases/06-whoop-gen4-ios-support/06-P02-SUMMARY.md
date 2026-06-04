---
phase: "06"
plan: "06-P02"
subsystem: ui-gen4
tags: [gen4, ui, onboarding, device-view]
requires:
  - 06-P01 (GooseDiscoveredDevice.generation, GooseAppModel.connectedDeviceGeneration)
provides:
  - Generation labels in DeviceView scan list and connected device header
  - Generation label in ConnectionView scan list
  - Generation info in onboarding device row
  - WHOOP 4.0 copy in onboarding connect step
affects:
  - GooseSwift/DeviceView.swift
  - GooseSwift/ConnectionView.swift
  - GooseSwift/OnboardingStepViews.swift
  - GooseSwift/OnboardingModels.swift
tech-stack:
  added: []
  patterns:
    - generationMajorVersion helper converts "4.0" -> "4", "5.0" -> "5", "unknown" -> "?"
key-files:
  created: []
  modified:
    - GooseSwift/DeviceView.swift
    - GooseSwift/ConnectionView.swift
    - GooseSwift/OnboardingStepViews.swift
    - GooseSwift/OnboardingModels.swift
key-decisions:
  - DeviceView scan list replaces UUID subtitle with "Gen N · RSSI dBm" format
  - Connected device header shows "Gen N" label when generation is known (not "unknown")
  - OnboardingModels connect title updated to "Connect your WHOOP (4.0 or 5.0)"
  - Onboarding default body copy updated to mention WHOOP 4.0 and 5.0 explicitly
requirements-completed:
  - GEN4-03
  - GEN4-04
duration: "7 min"
completed: "2026-06-03"
---

# Phase 06 Plan 02: UI Generation Labels + Onboarding Copy Summary

Added "Gen 4" / "Gen 5" generation labels throughout the device UI: scan list rows in DeviceView and ConnectionView now show "Gen N · RSSI dBm" instead of raw UUID; the connected device header shows "Gen N" under the device name; the onboarding scan row shows generation prefix alongside RSSI; and the onboarding connect step now explicitly mentions "WHOOP 4.0 or 5.0" in both the title and body copy.

**Duration:** 7 min | **Start:** 2026-06-03T21:27:46Z | **End:** 2026-06-03T21:29:47Z | **Tasks:** 4 | **Files:** 4

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| P02-T01 | DeviceView scan list: Gen N · RSSI dBm label | 620aa49 |
| P02-T02 | DeviceConnectionHeader: generation label under device name | 9385e24 |
| P02-T03 | ConnectionView scan list: generation label | d422d32 |
| P02-T04 | Onboarding scan row + WHOOP 4.0 copy | 279aa69 |

## Deviations from Plan

None - plan executed exactly as written.

## Verification

- `device.generation` used in DeviceView scan list and header PASS
- `model.connectedDeviceGeneration` passed to DeviceConnectionHeader PASS
- `device.id.uuidString` no longer in DeviceView scan list (count=0) PASS
- "4.0" string in OnboardingModels.swift and OnboardingStepViews.swift PASS

## Self-Check: PASSED

Ready for 06-P03 (Swift unit tests + Rust bridge tests).
