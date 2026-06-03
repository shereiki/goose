---
phases: [6, 7, 8]
reviewers: [codex]
reviewed_at: 2026-06-03T00:00:00Z
plans_reviewed:
  - .planning/phases/06-whoop-gen4-ios-support/06-P01-PLAN.md
  - .planning/phases/06-whoop-gen4-ios-support/06-P02-PLAN.md
  - .planning/phases/06-whoop-gen4-ios-support/06-P03-PLAN.md
  - .planning/phases/07-android-port-foundations-ci/07-01-PLAN.md
  - .planning/phases/07-android-port-foundations-ci/07-02-PLAN.md
  - .planning/phases/07-android-port-foundations-ci/07-03-PLAN.md
  - .planning/phases/07-android-port-foundations-ci/07-04-PLAN.md
  - .planning/phases/08-additional-wearables-e2e/08-P01-PLAN.md
  - .planning/phases/08-additional-wearables-e2e/08-P02-PLAN.md
  - .planning/phases/08-additional-wearables-e2e/08-P03-PLAN.md
skipped_reviewers:
  - name: gemini
    reason: GEMINI_API_KEY not configured
  - name: claude
    reason: self-skip (running inside Claude Code, excluded for independence)
---

# Cross-AI Plan Review — Phases 6-8

## Codex Review

### Summary

Overall, the plans are coherent and mostly well-sequenced. Phase 6 is the strongest: it directly addresses the Gen4 support goal, includes a critical Rust/Swift device-type mismatch fix, and creates the `WearableDescriptor` abstraction needed by later phases. Phase 7 is reasonable but carries integration risk around Android cross-compilation, JNI string/error handling, and CI reproducibility. Phase 8 is directionally good, but it has the highest ambiguity: the HR monitor plan mixes "device type" and "device name" semantics, reuses WHOOP storage paths in ways that may obscure future extensibility, and needs tighter test coverage around upload payloads and non-WHOOP notification routing.

### Strengths

- Clear dependency structure: Phase 8 correctly depends on Phase 6's `WearableDescriptor` and `rustDeviceType` abstraction.
- Good removal of Gen5-specific naming: renaming `supportsV5*` to `supportsHistoricalSync` reduces future wearable coupling.
- Strong Gen4 bug identification: fixing Rust `parse_device_type` to accept `"GEN4"` is essential and should be prioritized early.
- Good architectural choice to derive generation during BLE scan from advertised service UUIDs instead of later guessing from connection state.
- JNI plan uses the correct `extern "system"` ABI and Rust 2024-compatible `#[unsafe(no_mangle)]`.
- Android dependency gating for `tungstenite` is appropriate and reduces mobile build surface area.
- Server CI with a real TimescaleDB container is valuable and better than mocking database behavior for integration tests.
- Phase 8 correctly avoids repurposing the WHOOP central manager and acknowledges Swift extension stored-property limits.
- HR parser test plan covers the right low-level protocol surface, including RR interval conversion and malformed data.

### Concerns

- **HIGH:** Phase 6 test plan creates the first Swift unit test target in Wave 3, after behavioral changes in Waves 1 and 2. That means the riskiest iOS refactor lands before the test infrastructure exists. Consider moving minimal Swift test-target creation into P01 or splitting it into an earlier enabling task.

- **HIGH:** Upload payload behavior is under-tested across phases. Phase 6 requires verifying `device_generation: "4.0"` for Gen4 captures, but P03 only mentions Swift descriptor/type tests and Rust bridge tests. The actual `GooseUploadService` payload construction needs direct tests.

- **HIGH:** Phase 8's upload semantics are inconsistent: success criteria say upload identifies HR monitor data with a distinct `device_type`, while key decisions say `device_type` equals the BLE-advertised device name. That loses the class-level distinction unless another field carries `"HR_MONITOR"`.

- **HIGH:** Mapping `parse_device_type("HR_MONITOR")` to `DeviceType::Goose` may work short-term but weakens the "additional wearables extensibility" claim. It risks making downstream storage, analytics, and debugging treat HR data as native Goose/WHOOP-like data.

- **MEDIUM:** Generation derived from advertised service UUID prefix needs fallback behavior. Plans should define what happens when both Gen4 and Gen5 UUIDs are advertised, no known UUID is advertised, or CoreBluetooth returns service UUIDs late/incompletely.

- **MEDIUM:** `WearableDescriptor.isCommandCharacteristic(_:)` needs exact UUID normalization rules. Prefix matching can be fragile if UUIDs appear in short form, lowercase/uppercase, full 128-bit form, or Apple-normalized form.

- **MEDIUM:** Connected generation propagation may be stale if the app reconnects to a previously discovered peripheral without a fresh scan result. The model should define whether generation is stored with the peripheral identity, passed through connection state, or recomputed.

- **MEDIUM:** The Rust bridge remains synchronous and must not be called from `@MainActor`. Plans touching notification ingestion and upload should explicitly preserve background dispatch, especially in Phase 8 where HR notifications may arrive frequently.

- **MEDIUM:** JNI error handling says "return error JSON or null_mut()" but does not define which failures return which shape. Android callers need a stable contract for invalid input, UTF conversion failure, bridge failure, and allocation failure.

- **MEDIUM:** Android CI depends on `cargo-ndk`, NDK r29, and host lockfile compatibility. `cargo build --all-targets --locked` on host does not prove Android target dependencies are locked unless the Android job also uses `--locked`.

- **MEDIUM:** Server CI triggered only on `server/**` may miss changes in shared config, Docker files, workflow files, or dependency lockfiles if those live outside `server/**`.

- **MEDIUM:** Phase 8's `notificationIngestResult` early-return for HR monitor raw bytes bypasses WHOOP frame reassembly, but the Rust ingestion path must know it is receiving 0x2A37 payloads, not WHOOP frames. The plan should explicitly name the Rust bridge request or parser path used.

- **LOW:** Updating onboarding copy and UI labels is straightforward, but snapshot/UI tests are not mentioned. Risk is modest, but generation label regressions could slip through.

- **LOW:** ADR plan is good, but "Nygard format covering all 5 mandatory sections" should specify exact sections expected by the repo to avoid style mismatch.

- **LOW:** `device_type` sanitization for HR monitor names should also handle empty-after-trim, control characters, and collision between multiple same-name monitors.

### Suggestions

- Move Swift test-target creation earlier — ideally into Phase 6 P01, then add focused tests alongside each implementation wave.

- Add direct upload payload tests for:
  - Gen4 produces `device_generation: "4.0"`.
  - Gen5 produces `device_generation: "5.0"`.
  - HR monitor does not silently become Gen5.
  - Manual upload derives the active connection type correctly.

- Define a canonical device taxonomy:
  - `rustDeviceType`: parser/storage routing value, e.g. `"GEN4"`, `"GOOSE"`, `"HR_MONITOR"`.
  - `device_generation`: WHOOP generation only, e.g. `"4.0"`, `"5.0"`, absent/null for HR.
  - `device_type` or `device_model`: uploaded class/model/name, with clear semantics.
  - `device_name`: sanitized advertised BLE name.

- Prefer adding a real Rust `DeviceType::HrMonitor` if feasible. If not, document the temporary `DeviceType::Goose` mapping and add a migration note.

- Make UUID matching exact after normalization where possible. Use descriptor-owned normalized UUID sets instead of broad prefix checks, except where the protocol genuinely requires prefix families.

- Add tests for ambiguous and missing BLE advertised service UUIDs:
  - Gen4 UUID only.
  - Gen5 UUID only.
  - Unknown UUID.
  - Multiple known UUIDs.
  - Case-insensitive and full/short UUID forms.

- Specify stale-generation handling for reconnects. Safest: persist discovered metadata with peripheral identifier during the session, clear deliberately on disconnect/reset.

- In Phase 7, make Android CI run with `--locked` and consider adding a minimal symbol check to confirm the JNI function is exported from `libgoose_core.so`.

- Define JNI response behavior precisely: return JSON error strings for logical/bridge errors, return `null_mut()` only when a Java string cannot be allocated or input cannot be read safely.

- Expand server CI triggers to include `.github/workflows/server-ci.yml`, Docker Compose files, dependency lockfiles, and migration files.

- For Phase 8, add parser-level malformed input tests: 0x2A37 length handling, RR interval truncation, energy-expended flag without enough bytes, conflicting sensor contact bits.

- Add at least one integration-style test that feeds an HR notification through the Swift routing layer and verifies the resulting Rust bridge request uses `"HR_MONITOR"`.

### Risk Assessment

**Overall risk: MEDIUM.**

The plans are well-structured and likely to achieve the stated goals if implemented carefully. The main risks are integration risks at boundaries: BLE UUID normalization, Swift-to-Rust type naming, upload payload semantics, synchronous Rust bridge usage, Android JNI contracts, and CI reproducibility. Phase 6 is medium-low risk with good payoff. Phase 7 is medium risk because Android cross-compilation and JNI often fail on toolchain details. Phase 8 is medium-high risk unless the device taxonomy and upload semantics are tightened before implementation.

---

## Consensus Summary

A single reviewer (Codex) completed the review. Gemini was unavailable (API key not configured).

### Key Findings

The plans are architecturally sound. The `WearableDescriptor` abstraction in Phase 6 is a genuinely good design decision that pays dividends in Phase 8. The Gen4 bug fix (Rust `parse_device_type` not accepting `"GEN4"`) is a critical catch that would have caused silent frame drops in production.

### Critical Concerns (require action before executing)

1. **Swift test target created after the riskiest code** — P01 introduces the biggest refactor (`supportsV5*` rename across 7 files + WearableDescriptor); the test target only arrives in P03. Consider at minimum extracting the test target creation as a Task 0 in P01.

2. **Phase 8 upload semantics are ambiguous** — `device_type` in the upload payload sometimes means "HR_MONITOR" (a device class) and sometimes means the device name ("Polar H10"). The server needs to distinguish wearable class from model. Resolve this before implementation.

3. **HR_MONITOR mapped to DeviceType::Goose** — This is technically functional but semantically misleading. Either add `DeviceType::HrMonitor` to the Rust enum (small change) or document explicitly that the Goose storage path is intentionally shared and add a comment in the enum definition.

4. **Upload payload tests absent** — `GooseUploadService` payload construction is not unit-tested in any phase. Codex flagged this as HIGH risk.

### Agreed Strengths

- Dependency ordering between phases is correct and explicit
- `supportsV5*` → generation-agnostic rename is the right call
- Gen4 Rust bug fix is well-identified and well-placed
- Separate `CBCentralManager` for HR monitors avoids state contamination
- Server CI with real TimescaleDB is the right approach

### Divergent Views

No second reviewer to compare against. If Gemini access is restored, re-run to get a second opinion on the Phase 8 device taxonomy concern.

---

*To incorporate feedback:* `/gsd-plan-phase 8 --reviews`
