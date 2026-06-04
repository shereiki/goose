---
status: partial
phase: 08-additional-wearables-e2e
source: [08-VERIFICATION.md]
started: 2026-06-03T23:17:11Z
updated: 2026-06-03T23:17:11Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. End-to-End HR Monitor Data Flow (Physical BLE Device)
expected: Server receives data with device_class: "HR_MONITOR" and device_type matching the advertised BLE device name after connecting a real 0x180D HR monitor and triggering manual upload
result: [pending]

### 2. WHOOP + HR Monitor Scan Isolation (Dual Connection)
expected: WHOOP connection state completely unaffected while HR monitor scan runs simultaneously; both devices deliver data concurrently
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
