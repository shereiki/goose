---
status: complete
quick_id: 260603-s5w
slug: add-healthkitfullimporter-swift-to-goose
description: add HealthKitFullImporter.swift to GooseSwift.xcodeproj target membership
date: 2026-06-03
commit: f15a898
---

# Quick Task 260603-s5w: add HealthKitFullImporter.swift to Xcode target

## Result

Fixed build errors in `HealthDataStore+Sleep.swift` by registering `HealthKitFullImporter.swift`
in the Xcode project target.

## Root Cause

`HealthKitFullImporter.swift` was present on disk but not in `project.pbxproj` — the file had
no PBXFileReference, PBXBuildFile, PBXGroup, or PBXSourcesBuildPhase entries.

## Fix Applied

Added 4 entries to `GooseSwift.xcodeproj/project.pbxproj`:

| Entry type | UUID | Value |
|-----------|------|-------|
| PBXBuildFile | A10000000000000000000041 | HealthKitFullImporter.swift in Sources |
| PBXFileReference | A20000000000000000000041 | HealthKitFullImporter.swift |
| PBXGroup | A20000000000000000000041 | (next to HealthKitSleepImporter.swift) |
| PBXSourcesBuildPhase | A10000000000000000000041 | (next to HealthKitSleepImporter.swift) |

## Files Changed

| File | Action |
|------|--------|
| `GooseSwift.xcodeproj/project.pbxproj` | +4 lines |

## Commit

`f15a898` — fix: add HealthKitFullImporter.swift to GooseSwift target membership
