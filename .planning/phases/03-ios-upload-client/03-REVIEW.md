---
phase: 03
status: issues
depth: standard
reviewed_at: 2026-06-03
files_reviewed:
  - GooseSwift/GooseUploadService.swift
  - GooseSwift/GooseAppModel+Upload.swift
  - GooseSwift/GooseAppModel+NotificationPipeline.swift
  - GooseSwift/GooseAppModel.swift
  - Rust/core/src/bridge.rs
---

# Code Review — Phase 03: iOS Upload Client

## Summary

5 files reviewed. 2 Warning findings, 3 Info findings. No Critical or blocking issues. The core architecture is sound — threading model is correct, guards are complete, payload contract matches the server.

---

## Findings

### WARNING — Rust: `lastNotificationEvent` written from `notificationIngestQueue`, read from `@MainActor`

**File:** `GooseSwift/GooseAppModel+NotificationPipeline.swift` line 165, `GooseAppModel.swift` line 179  
**Severity:** Warning

`lastNotificationEvent` is set inside `importCapturedFrames`, which is called from `handleNotificationIngestResult`, which is dispatched back to `@MainActor` via `DispatchQueue.main.async`. The read in `handleCaptureFrameWriteResult` is also on `@MainActor`. So in practice reads and writes both happen on the main actor — this is safe.

However, `importCapturedFrames` is also reachable without the `DispatchQueue.main.async` wrapper: `handleNotificationIngestResultWithoutCapture` calls `parseNotificationFrames` directly from `notificationIngestQueue` (a background queue). If a future code path calls `importCapturedFrames` off `@MainActor`, the `lastNotificationEvent` write would race with the `handleCaptureFrameWriteResult` read.

**Recommended fix:** Mark `lastNotificationEvent` with a comment noting it is only read/written on `@MainActor`, or annotate it `@MainActor var` (which the class already is) and add a MARK for clarity. No code change strictly required given current call paths, but worth a defensive comment.

---

### WARNING — Rust: `chrono_from_unix` has a variable shadowing bug — `h` computed correctly but `h % 24` is always the same as `h` for valid timestamps

**File:** `Rust/core/src/bridge.rs` — `chrono_from_unix` function  
**Severity:** Warning

```rust
let h = total_secs / 3600;
// ...
format!("{year:04}-{month:02}-{day:02}T{h:02}:{m:02}:{s:02}.{ms:03}Z", h = h % 24)
```

`h` is computed as `total_secs / 3600` which gives the total hours elapsed since epoch (e.g., ~490,000). The format string then uses `h % 24` which gives the hour-of-day correctly. **This is actually correct** — `h % 24` produces 0-23.

However, `days_since_epoch` is computed as `total_secs / 86400`, which correctly strips hours. And `h % 24` correctly gives the hour component within the day. So the output is valid.

The real issue: the `nanos` variable computed on line 2 of the function is unused beyond `dt`, and `dt.duration_since(UNIX_EPOCH)` re-derives from scratch — making the `nanos`/`dt` computation pointless (it discards sub-millisecond precision by computing `elapsed` from `total_secs` and `ms = elapsed.subsec_millis()`). The function could be simplified to operate purely on `total_secs` and `(ts.fract() * 1000.0) as u32`.

**Recommended fix (minor, non-blocking):**
```rust
fn chrono_from_unix(ts: f64) -> String {
    let total_secs = ts as u64;
    let ms = ((ts.fract()) * 1000.0) as u32;
    let h = (total_secs / 3600) % 24;
    let m = (total_secs % 3600) / 60;
    let s = total_secs % 60;
    let (year, month, day) = days_to_ymd((total_secs / 86400) as u32);
    format!("{year:04}-{month:02}-{day:02}T{h:02}:{m:02}:{s:02}.{ms:03}Z")
}
```

---

### INFO — Swift: `upload` public method increments `pendingBatchCount` on `uploadQueue` but before the async block executes; count is not observable until the async block runs

**File:** `GooseSwift/GooseUploadService.swift` line 30-34  
**Severity:** Info

```swift
func upload(...) {
    uploadQueue.async { [weak self] in
        guard let self else { return }
        self.pendingBatchCount += 1  // ← incremented inside async block
        self.performUpload(...)
    }
}
```

`pendingBatchCount` is incremented inside the `async` block. If the caller reads `onStatusUpdate` immediately after `upload()` returns (before the block executes), the count will not yet reflect the pending batch. For a Phase 4 UI that shows "uploading…" this could cause a brief display gap (count stays 0 until the queue runs).

**Recommended fix:** Increment synchronously before the `async` if a live display is needed, or keep as-is and document the timing. Given `uploadQueue.qos = .utility` this is generally imperceptible. Non-blocking.

---

### INFO — Rust: empty `if` block for `device_id` filtering is dead code

**File:** `Rust/core/src/bridge.rs` — `upload_get_recent_decoded_streams_bridge`  
**Severity:** Info

```rust
if !args.device_id.is_empty() {
    // The evidence_id encodes device identity via the capture session.
    // For now we rely on the time-window filter...
}
```

The block contains only comments — no code. While the comment is useful documentation, an empty `if` block will generate a Clippy warning (`clippy::if_let_else` or similar depending on version). Cargo's existing 6 warnings are pre-existing, but this adds one more.

**Recommended fix:** Either remove the empty block and put the comment as a standalone doc comment before the loop, or replace with `let _ = &args.device_id; // used in payload only`.

---

### INFO — Swift: `onStatusUpdate` closure captures `self` weakly but assigns to `@MainActor` properties without `Task { @MainActor in ... }`

**File:** `GooseSwift/GooseAppModel+Upload.swift` lines 7-11  
**Severity:** Info

```swift
uploadService.onStatusUpdate = { [weak self] status in
    // Called on @MainActor via DispatchQueue.main.async in GooseUploadService
    self?.uploadLastTimestamp = status.lastUploadTimestamp
    self?.uploadPendingBatchCount = status.pendingBatchCount
}
```

The closure is called via `DispatchQueue.main.async` in `GooseUploadService.publishStatus()`, so it does reach the main thread. However, the Swift compiler cannot verify this statically — the `@MainActor` annotation on `onStatusUpdate` is a closure type annotation (a promise to the caller), not an enforcement mechanism on the caller's dispatch. The `@MainActor` annotation on the property type `(@MainActor (GooseUploadStatus) -> Void)?` means the Swift compiler will verify that the closure *body* can only access `@MainActor`-isolated state, but the dispatch to main is the responsibility of `GooseUploadService`. This pattern is used elsewhere in the codebase (`captureFrameWriteQueue.enqueue`), so it is consistent with the project conventions.

No change required — consistent with project patterns. Documenting for awareness.

---

## Verdict

**No Critical issues.** All findings are Warning or Info level. The implementation is architecturally sound:
- Threading model: correct — Rust bridge calls never on @MainActor
- Security: Bearer token never logged, read from Keychain at call time (not cached in memory beyond the call)
- Payload: matches server DecodedBatch contract exactly
- Guards: all three pre-conditions checked before any network I/O

The Warning about `chrono_from_unix` being slightly over-engineered (dead `nanos`/`dt` variables) is cosmetic and does not affect correctness. The timestamp output is valid.
