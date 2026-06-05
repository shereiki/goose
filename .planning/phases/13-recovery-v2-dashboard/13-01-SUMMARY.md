---
phase: 13
plan: 01
subsystem: ios-ui
tags: [recovery, bridge, packet-scores, swiftui]
key-files:
  modified:
    - GooseSwift/HealthRecoveryStressViews.swift
decisions:
  - Follow same onAppear + onChange(packetImportRevision) pattern as HealthDashboardViews
  - ProgressView guard uses hasPrefix("Extracting") matching HealthDataStore+Snapshots status strings
metrics:
  duration: "5m"
  completed: "2026-06-05"
  tasks_completed: 1
  files_modified: 1
---

# Phase 13 Plan 01: Recovery V2 Dashboard Bridge Trigger Summary

**One-liner:** Wired `RecoveryV2OverviewPage` to call `runPacketScores()` on appear and on packet import, enabling bridge-backed recovery score, HRV, RHR, and trend population from real WHOOP data.

## What Was Built

`RecoveryV2OverviewPage` previously rendered a static score of 0 because no code ever called `store.runPacketScores()` — `packetScoreReports["recovery"]` was always empty.

Two additions to `GooseSwift/HealthRecoveryStressViews.swift`:

1. **ProgressView hero guard** — during extraction (`packetScoreStatus.hasPrefix("Extracting")`), the hero score gauge is replaced with a `ProgressView` tinted with `palette.accent`, giving visual feedback while scores compute.

2. **Lifecycle triggers** — `.onAppear` calls `loadBridgeCatalogsIfNeeded()` then `runPacketScores()`. `.onChange(of: model.packetImportRevision)` re-triggers `runPacketScores()` whenever new BLE packets arrive, keeping the displayed score live.

## Verification Results

| Check | Result |
|-------|--------|
| `runPacketScores\|loadBridgeCatalogsIfNeeded` count ≥ 2 | 3 |
| `packetImportRevision` count = 1 | 1 |
| `Extracting` count = 1 | 1 |
| `cargo test -p goose-core` | ok (9 passed, 0 failed) |

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | cdc0b1a | feat(13): trigger runPacketScores on Recovery V2 appear |

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- `GooseSwift/HealthRecoveryStressViews.swift` modified and committed
- Commit `cdc0b1a` exists in git log
