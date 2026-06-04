# Phase 7: Android Port Foundations + CI - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Cross-compile the Rust core to Android (`aarch64-linux-android` only), expose the existing C FFI API via a thin JNI wrapper module, document the architecture in an ADR, and run both the Rust CI (with the new Android job) and the server pytest suite on GitHub Actions.

**What this phase delivers:**
1. `cargo build --target aarch64-linux-android` (via `cargo-ndk 4.1.2`) passes on CI
2. A `#[cfg(target_os = "android")]` JNI shim in `bridge.rs` with `Java_com_goose_core_GooseBridge_*` function naming
3. `tungstenite` excluded on Android via Cargo target-specific dependency
4. `panic = "abort"` set for the Android release profile
5. `docs/ADR-android-jni.md` documenting the architecture choices
6. Android job added to `rust-core-ci.yml` (blocking merge)
7. New `server-ci.yml` workflow running server pytest suite against real TimescaleDB (blocking merge)

**Out of scope:** Full Android app UI, x86_64/armv7 Android targets (rusqlite bundled bugs), actual Android app packaging, Play Store distribution.

</domain>

<decisions>
## Implementation Decisions

### JNI Naming Convention
- **D-01:** Java package name: `com.goose.core`
- **D-02:** JNI class name: `GooseBridge` (mirrors iOS `GooseRustBridge` pattern)
- **D-03:** Resulting function naming: `Java_com_goose_core_GooseBridge_handle` for the main bridge entry point
- Rationale: `com.goose.core` is neutral and maps to the Rust crate concept; `GooseBridge` mirrors the iOS naming convention for cross-platform consistency

### Android Cargo Configuration
- **D-04:** Target: `aarch64-linux-android` only — `x86_64-linux-android` and `armv7-linux-androideabi` excluded due to open `rusqlite bundled` bugs
- **D-05:** `tungstenite` excluded via `[target.'cfg(not(target_os = "android"))'.dependencies]` in Cargo.toml (clean, declarative)
- **D-06:** `panic = "abort"` via `.cargo/config.toml` profile override for the Android target (or `[profile.release]` in Cargo.toml with a target-specific section) — Claude's discretion on exact mechanism
- **D-07:** `cargo-ndk 4.1.2` is the build tool; NDK version to match GitHub Actions ubuntu-latest available NDK (r29 per REQUIREMENTS.md ANDROID-01)

### CI Organization
- **D-08:** Android build: add a new job to the existing `rust-core-ci.yml` (not a separate file)
  - Trigger: already covers `Rust/core/**` paths
  - The new job runs `cargo ndk -t arm64-v8a build` and blocks merge on failure
- **D-09:** Server CI: new `server-ci.yml` workflow, separate file
  - Trigger: `server/**` and `.github/workflows/server-ci.yml` paths
  - Blocking: failures block merge (per CI-01 requirement)
  - Uses `ubuntu-latest` — Docker daemon already available; `conftest.py` spawns container via `docker run` directly (no `services:` needed)
  - Python setup + `pip install -r server/ingest/requirements-dev.txt` + `pytest server/ingest/tests/`
  - TimescaleDB image: `timescale/timescaledb:2.17.2-pg16` (matches `conftest.py` IMAGE constant)

### ADR Scope
- **D-10:** `docs/ADR-android-jni.md` must cover (per ANDROID-03): `cdylib`+JNI approach rationale, panic strategy, MUTF-8 string handling policy, `rusqlite bundled` target limitation (aarch64 only), what keeps the door open for a future Android app
- Audience: future contributors who want to build the Android app layer

### Claude's Discretion
- Exact mechanism for `panic = "abort"` Android override (`.cargo/config.toml` vs `Cargo.toml` profile)
- Whether to run `cargo ndk` install via `cargo install cargo-ndk --version 4.1.2` or cache it
- ADR prose style and depth beyond the mandatory sections above

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — ANDROID-01, ANDROID-02, ANDROID-03, CI-01 (full requirement text)

### Existing CI
- `.github/workflows/rust-core-ci.yml` — existing Rust build+test job to extend with Android job
- `.github/workflows/rust-core.yml` — separate MSRV/fmt workflow (reference only, do not modify)

### Rust Core Build
- `Rust/core/Cargo.toml` — existing `crate-type = ["rlib", "staticlib", "cdylib"]`, `tungstenite` dep, `rusqlite bundled` feature
- `Rust/core/src/bridge.rs` — main bridge file where JNI shim goes (inside `#[cfg(target_os = "android")]` module)

### Server Tests
- `server/ingest/tests/conftest.py` — uses `timescale/timescaledb:2.17.2-pg16`, `docker run` directly; no special Actions setup needed
- `server/ingest/requirements-dev.txt` — Python deps to install before pytest

### Prior Decisions
- `.planning/STATE.md` §Decisions — `cargo-ndk 4.1.2`, aarch64 only, tungstenite cfg-gated
- `.planning/PROJECT.md` — project constraints and tech stack

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Rust/core/src/bridge.rs` — the `goose_bridge_handle_json` / `goose_bridge_free_string` C FFI functions are the surface the JNI shim wraps; no new Rust logic needed, only new calling convention
- `.github/workflows/rust-core-ci.yml` — existing Ubuntu job structure to clone for the Android job

### Established Patterns
- `Cargo.toml` `[target.'cfg(...)'.dependencies]` pattern: not yet used but is the Cargo-idiomatic way to exclude platform-specific deps
- The existing `cdylib` crate type means the library already produces a `.so` for general use; Android just adds a new target for the same crate type

### Integration Points
- JNI shim in `bridge.rs` calls the existing `dispatch()` function (or `handle_json_request` equivalent) — no new logic, just JNI-compatible wrapper
- `server/ingest/tests/` pytest suite is self-contained with its own `conftest.py` fixture; CI only needs Python + Docker + pytest

</code_context>

<specifics>
## Specific Ideas

- JNI function signature pattern:
  ```rust
  #[cfg(target_os = "android")]
  pub mod jni {
      use jni::JNIEnv;
      use jni::objects::JString;
      use jni::sys::jstring;
      
      #[no_mangle]
      pub extern "system" fn Java_com_goose_core_GooseBridge_handle(
          env: JNIEnv,
          _class: jni::objects::JClass,
          request_json: JString,
      ) -> jstring { ... }
  }
  ```
- Server CI should use `working-directory: server/ingest` for pytest commands
- Android job in `rust-core-ci.yml` should install `cargo-ndk` and Android NDK, then run `cargo ndk -t arm64-v8a build`

</specifics>

<deferred>
## Deferred Ideas

- x86_64-linux-android and armv7-linux-androideabi targets — deferred until rusqlite bundled bug is fixed upstream
- Full Android app UI (ANDROID-V3-01) — v3+ milestone
- JNI test harness / Android unit tests for the JNI shim — could be added in a follow-up phase
- Kotlin/Java Android client library wrapping the JNI — v3+ milestone

</deferred>

---

*Phase: 7-android-port-foundations-ci*
*Context gathered: 2026-06-03*
