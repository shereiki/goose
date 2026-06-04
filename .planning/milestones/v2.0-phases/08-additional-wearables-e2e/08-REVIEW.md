---
phase: 08-additional-wearables-e2e
reviewed: 2026-06-04T10:00:00Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - GooseSwift.xcodeproj/project.pbxproj
  - GooseSwift/GooseAppModel+NotificationPipeline.swift
  - GooseSwift/GooseAppModel+Upload.swift
  - GooseSwift/GooseBLEClient.swift
  - GooseSwift/GooseBLEClient+HRMonitor.swift
  - GooseSwift/GooseBLETypes.swift
  - GooseSwift/GooseUploadService.swift
  - GooseSwift/HealthDataStore.swift
  - GooseSwift/HealthDataStore+Snapshots.swift
  - GooseSwiftTests/GooseBLETypesTests.swift
  - GooseSwiftTests/GooseUploadServiceTests.swift
  - Rust/core/src/bridge.rs
  - Rust/core/src/heart_rate_gatt_protocol.rs
  - Rust/core/src/lib.rs
  - Rust/core/src/openwhoop_reference.rs
  - Rust/core/src/protocol.rs
  - Rust/core/src/store.rs
  - Rust/core/tests/heart_rate_gatt_protocol_tests.rs
findings:
  critical: 3
  warning: 4
  info: 3
  total: 10
status: issues_found
---

# Phase 08: Code Review Report

**Reviewed:** 2026-06-04T10:00:00Z
**Depth:** standard
**Files Reviewed:** 17
**Status:** issues_found

## Summary

Phase 08 adds HR monitor (standard GATT 0x2A37) support to the BLE stack and wires the new device
class into the upload pipeline. The Rust `heart_rate_gatt_protocol` parser and its test suite are
clean and correct. The `GooseBLETypes`, `WearableDescriptor`, and `GooseNotificationEvent.rustDeviceType`
additions are correct and well-covered by tests.

Three blockers surface:

1. **`GooseUploadService` has an unsynchronised data race on `pendingBatchCount` and
   `lastUploadTimestamp`** — the comment claiming cooperative-pool protection is wrong; `upload()`
   increments `pendingBatchCount` on the caller's actor while `performUpload` decrements it on a
   detached task.

2. **The `upload.get_recent_decoded_streams` Rust bridge silently ignores the `device_id`
   argument** — the filter body is an empty comment block. Two simultaneous uploads (WHOOP + HR
   monitor) both query the full time-window without isolation; each upload payload may carry the
   other device's frames.

3. **`chrono_from_unix` in `bridge.rs` performs `secs as u64` on an `i64`** — casting a negative
   seconds value (pre-1970 timestamp) in Rust is a wrapping cast in release builds and a panic in
   debug builds. In iOS context, `sinceTimestamp` can be negative only if `lastUploadAt` is
   somehow corrupted, but the code should be defensive.

Four warnings cover a cross-thread read of `GooseBLEHRMonitorManager` state from `@MainActor`,
the `DispatchSemaphore.wait()` on a `URLSession.shared.dataTask` blocking the global queue thread,
the truncated-energy/RR-silenced bug in the GATT parser, and the `GooseAppModel._didRunHealthCheck`
static being accessed on `@MainActor` without actor annotation.

---

## Critical Issues

### CR-01: Data race on `GooseUploadService.pendingBatchCount` and `lastUploadTimestamp`

**File:** `GooseSwift/GooseUploadService.swift:32-124`

**Issue:** `upload()` (called from `@MainActor` callers) mutates `pendingBatchCount += 1` on line 32
synchronously on whatever actor the caller holds. `performUpload` runs on a `Task.detached`
(unstructured, cooperative-pool thread) and decrements `pendingBatchCount` at multiple return
points (lines 40, 45, 49, 66, 82, 93, 124) and sets `lastUploadTimestamp` on line 119. Neither
variable is protected by a lock or actor isolation. The class is marked `@unchecked Sendable`,
and the comment on line 17 says _"Protected by Swift's cooperative thread pool — only mutated
from upload tasks"_, which is factually wrong: `upload()` mutates `pendingBatchCount` before
creating the task, from the caller's context. Concurrent uploads (WHOOP + HR monitor) can issue
overlapping increments and decrements without synchronisation, producing an incorrect counter and
potentially a torn read in `publishStatus()`.

**Fix:** Either make `GooseUploadService` a Swift `actor` (dropping `@unchecked Sendable`), or
guard all accesses to `pendingBatchCount`/`lastUploadTimestamp`/`lastSyncedCount` behind an
`NSLock` (matching the existing pattern in `GooseAppModel`):

```swift
// Option A — actor (preferred)
actor GooseUploadService {
  // All methods become automatically isolated; callers use `await`.
}

// Option B — NSLock guard (minimal change)
private let stateLock = NSLock()

func upload(deviceID: UUID, deviceType: String, sinceTimestamp: Date) {
  stateLock.lock()
  pendingBatchCount += 1
  stateLock.unlock()
  Task.detached(priority: .utility) { [weak self] in
    await self?.performUpload(deviceID: deviceID, deviceType: deviceType, sinceTimestamp: sinceTimestamp)
  }
}

// Wrap every pendingBatchCount and lastUploadTimestamp access in stateLock.lock()/unlock().
```

---

### CR-02: `upload.get_recent_decoded_streams` ignores `device_id` — mixed-device data in upload payload

**File:** `Rust/core/src/bridge.rs:3063-3070`

**Issue:** The `device_id` filter body is an empty comment block:

```rust
if !args.device_id.is_empty() {
    // The evidence_id encodes device identity via the capture session.
    // For now we rely on the time-window filter (since_ts). …
}
```

When both a WHOOP and an HR monitor are connected and `triggerManualUpload` fires (or both call
`triggerUpload` in close succession), two separate upload tasks query `decoded_frames_between` with
the same `since_ts`. Because the local SQLite can contain frames from any previously active device
within that time window, each upload payload may contain frames from the wrong device. The server
would then receive WHOOP-type HR rows attributed to the HR monitor UUID or vice versa, corrupting
the server's per-device stream history.

**Fix:** Implement device-ID filtering in the loop body. The `evidence_id` already embeds the
device UUID in the `ios.<UUID>.<ms>.<index>.<hex>` format used by `captureEvidenceID`:

```rust
if !args.device_id.is_empty() {
    let device_prefix = format!("ios.{}.", args.device_id.to_lowercase());
    if !frame.evidence_id.to_lowercase().starts_with(&device_prefix) {
        continue;
    }
}
```

Alternatively, add a `device_id` column to the `decoded_frames` schema and filter at the SQL
level. Either approach is acceptable; the empty filter body must not ship.

---

### CR-03: `chrono_from_unix` casts negative `i64` to `u64` — wraps in release, panics in debug

**File:** `Rust/core/src/bridge.rs:3164-3166`

**Issue:**
```rust
let secs = ts as i64;
let nanos = ((ts - secs as f64) * 1_000_000_000.0) as u32;
let dt = std::time::UNIX_EPOCH + std::time::Duration::new(secs as u64, nanos);
```

`secs as u64` when `secs` is negative is a **wrapping cast** in release builds (producing an
astronomically large `u64`) and **panics** in debug builds due to Rust's overflow checks on
`Duration::new`. In practice `since_ts` is derived from `Date().addingTimeInterval(-30)` or
`Date().addingTimeInterval(-24 * 3600)`, both positive on any real iOS device. However, if
`lastUploadAt` were ever read as a corrupt value from `UserDefaults`, a negative `since_ts` would
propagate here and cause either silent wrong results (release) or a bridge crash (debug).

**Fix:**
```rust
fn chrono_from_unix(ts: f64) -> String {
    // Guard against pre-epoch timestamps; clamp to epoch.
    let ts = ts.max(0.0);
    let secs = ts as u64;
    let nanos = ((ts - secs as f64) * 1_000_000_000.0).max(0.0) as u32;
    let dt = std::time::UNIX_EPOCH + std::time::Duration::new(secs, nanos);
    // … rest unchanged
}
```

---

## Warnings

### WR-01: Cross-thread read of `GooseBLEHRMonitorManager` mutable state from `@MainActor`

**File:** `GooseSwift/GooseAppModel+Upload.swift:37-43`

**Issue:** `triggerManualUpload` runs on `@MainActor` and reads `hrManager.hrConnectionState`,
`hrManager.hrPeripheral`, and `hrManager.connectedDeviceName` (lines 38-39). These properties
belong to `GooseBLEHRMonitorManager`, a plain `NSObject` with no actor isolation. Its delegate
callbacks (`didConnect`, `didDisconnectPeripheral`) mutate those same properties on
`coreBluetoothQueue` (the queue passed to `CBCentralManager`). Swift's actor checker does not
enforce isolation on `NSObject` subclasses, so this cross-queue read is undetected at compile time
but constitutes a data race under Swift Concurrency's memory model.

**Fix:** Gate `GooseBLEHRMonitorManager`'s mutable fields behind a lock, or capture the relevant
values inside a `DispatchQueue.sync` on `coreBluetoothQueue` before reading them on `@MainActor`:

```swift
// In triggerManualUpload, snapshot HR monitor state on the BLE queue:
var hrSnapshot: (connectionState: String, peripheralID: UUID?, deviceName: String?)?
ble.coreBluetoothQueue.sync {
  let m = ble.hrMonitorManager
  guard m.hrConnectionState != "disconnected" else { return }
  hrSnapshot = (m.hrConnectionState, m.hrPeripheral?.identifier, m.connectedDeviceName)
}
if let snap = hrSnapshot, let peripheralID = snap.peripheralID {
  let hrDeviceType = snap.deviceName ?? "unknown_hr_monitor"
  uploadService.upload(deviceID: peripheralID, deviceType: hrDeviceType, sinceTimestamp: sinceTimestamp)
}
```

---

### WR-02: `DispatchSemaphore.wait()` on a global queue thread in `runHealthCheck`

**File:** `GooseSwift/GooseAppModel+Upload.swift:81-108`

**Issue:** `runHealthCheck` dispatches to `DispatchQueue.global(qos: .utility)` and then blocks
that thread with `semaphore.wait()` while awaiting a `URLSession.shared.dataTask` completion. This
permanently occupies one of the limited utility-pool threads for the entire network timeout
(up to 5 s). Under GCD's thread-width limits, blocking multiple global-pool threads simultaneously
can cause thread-pool exhaustion, stalling other utility-queue work items (including
`notificationIngestQueue`, which shares `qos: .utility`). The pattern is explicitly flagged as
incorrect in Apple's concurrency guidance.

**Fix:** Replace with an async `URLSession` call from within a Swift `Task`:

```swift
private func runHealthCheck(serverURLString: String) {
  guard let url = URL(string: serverURLString + "/healthz") else {
    Task { @MainActor in self.serverReachable = false }
    return
  }
  var request = URLRequest(url: url)
  request.timeoutInterval = 5
  Task { [weak self] in
    guard let self else { return }
    let isReachable: Bool
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      isReachable = (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
      isReachable = false
    }
    await MainActor.run { self.serverReachable = isReachable }
  }
}
```

---

### WR-03: GATT parser silently drops RR intervals when energy-expended field is truncated

**File:** `Rust/core/src/heart_rate_gatt_protocol.rs:56-76`

**Issue:** When the `energy_expended` flag (bit 3) is set but the data is truncated (fewer than
`offset + 2` bytes remain), the code sets `offset = data.len()` at line 63:

```rust
} else {
    // Truncated — advance past and set None
    offset = data.len();
    None
}
```

The RR-intervals loop that follows (line 72–76) immediately evaluates `data.len() >= offset + 2`,
which becomes `data.len() >= data.len() + 2` — always false. Any RR interval bytes that are
actually present after the truncated energy field are silently discarded. For a device that sets
bit 3 (energy present) and bit 4 (RR intervals present) but sends a partial payload, the parser
will return an empty `rr_intervals_ms` vec even though RR data is present in the buffer. This
affects HRV computation correctness.

No existing test covers this case (the test suite has a truncated-16-bit-HR test and a
truncated-energy test only up to the HR byte, not the combined flags=0x18 scenario).

**Fix:**
```rust
} else {
    // Truncated energy field — do NOT advance offset to data.len();
    // leave offset unchanged so the RR loop can still consume any trailing bytes.
    None
}
```

Add a test:
```rust
#[test]
fn test_energy_truncated_rr_still_parsed() {
    // flags=0x18: energy present (bit 3) + RR present (bit 4), 8-bit HR
    // HR=70, energy truncated (only 1 byte), RR=0x0400 (1000 ms)
    let data = [0x18u8, 70, 0xE8, 0x00, 0x04]; // energy only 1 byte then RR
    // With the fix, hr=70, rr=[1000.0], energy=None
    let result = parse_hr_measurement(&data).unwrap();
    assert_eq!(result.hr_bpm, 70);
    // Current code fails this: rr_intervals_ms is empty
    assert_eq!(result.rr_intervals_ms.len(), 1);
}
```

---

### WR-04: `GooseAppModel._didRunHealthCheck` static accessed without actor isolation

**File:** `GooseSwift/GooseAppModel+Upload.swift:9, 64, 72, 76`

**Issue:** `_didRunHealthCheck` is declared as `private static var _didRunHealthCheck = false`
inside `GooseAppModel`, which is a `@MainActor final class`. Static stored properties of a
`@MainActor` class are **not** automatically `@MainActor` isolated in Swift — they are
`nonisolated` unless explicitly annotated. `checkServerHealth` and `triggerHealthCheckIfNeeded`
both read and write `GooseAppModel._didRunHealthCheck` on `@MainActor` (since they are instance
methods), but the Swift compiler does not enforce this: the static is accessible from any
isolation context, creating a potential future regression if ever called from a non-MainActor
context (e.g., a background task that calls `checkServerHealth` via a `Task.detached`).

**Fix:** Annotate the static explicitly:

```swift
@MainActor private static var _didRunHealthCheck = false
```

---

## Info

### IN-01: `hkSleepScore` comment disagrees with implementation

**File:** `GooseSwift/HealthDataStore+Snapshots.swift:324`

**Issue:** The comment on line 324 documents the score mapping as:
`// Maps: <5h=20, 5h=40, 6h=60, 7h=80, 7.5h=90, 8h+=95, >9h=85 (too long).`

The actual `switch` returns different values:
```
case ..<4:    return 15   // comment says "<5h=20"
case 4..<5:   return 30   // comment says nothing for 4–5h
case 5..<6:   return 50   // comment says "5h=40"
```

The comment describes a previous or intended scoring, not what the code computes. Users and
reviewers who rely on the comment will be misled about what score values to expect.

**Fix:** Update the comment to match the code, or vice versa if the comment describes the
intended mapping.

---

### IN-02: `test_triggerManualUpload_doesNotHardcodeGoose` is a brittle source-level assertion

**File:** `GooseSwiftTests/GooseUploadServiceTests.swift:91-121`

**Issue:** The test reads the source file `GooseAppModel+Upload.swift` from disk and performs a
string search for `deviceType: "GOOSE"`. This is a source-scanning approach that:
- Silently skips on CI sandboxes (caught by `XCTSkip` but not reported as failure)
- Breaks if the file moves or is renamed
- Cannot detect equivalent patterns that use a variable intermediate (e.g., `let t = "GOOSE"; … deviceType: t`)
- Produces a false pass if the constant string appears in a comment

The assertion is also checking a condition that is trivially satisfied today but provides no
protection against future regressions in derived logic.

**Fix:** Extract the device-type derivation from `triggerManualUpload` into a `static func` that
`@testable import GooseSwift` can call directly with a mock descriptor, then test the function's
return value instead of the source text.

---

### IN-03: `upload.get_recent_decoded_streams` emits always-empty `rr`, `battery`, `spo2`, `skin_temp`, `resp`, `gravity` arrays

**File:** `Rust/core/src/bridge.rs:3049-3055, 3146-3155`

**Issue:** Six of the eight stream arrays are declared as `let` (`rr`, `battery`, `spo2`,
`skin_temp`, `resp`, `gravity`) with no code path that appends to them. They are always included
in the response JSON as empty arrays. The Swift upload payload (line 79 in `GooseUploadService`)
skips the upload only when ALL eight are empty; since `hr` and `events` can be non-empty,
the upload proceeds and the server receives six empty arrays on every call. This wastes bandwidth
and server processing for fields that will never be populated until the Rust extractor is extended.

**Fix (immediate):** Change the always-empty arrays to be conditionally omitted from the JSON
response, or document clearly in the Rust function docstring which fields are currently
unimplemented. This is an info-level item because the empty arrays are functionally harmless for
the server, but they communicate false intent.

---

_Reviewed: 2026-06-04T10:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
