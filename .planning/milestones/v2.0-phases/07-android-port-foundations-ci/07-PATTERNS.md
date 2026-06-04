# Phase 7: Android Port Foundations + CI — Pattern Map

**Phase:** 07 — Android Port Foundations + CI
**Created:** 2026-06-03

---

## Files to Create/Modify

| File | Role | Action |
|------|------|--------|
| `Rust/core/Cargo.toml` | Build config | Move tungstenite to cfg-gate; add jni dep |
| `Rust/core/src/bridge.rs` | Core library | Add `#[cfg(target_os = "android")] pub mod android` at bottom |
| `.github/workflows/rust-core-ci.yml` | CI | Add `android-build:` job |
| `.github/workflows/server-ci.yml` | CI | Create new workflow |
| `docs/ADR-android-jni.md` | Docs | Create ADR |

---

## Pattern: Cargo Target-Specific Dependency

**Role:** Exclude `tungstenite` from Android targets; add `jni` only for Android.

**Closest analog:** `Rust/core/Cargo.toml` existing `[dependencies]` block.

**Pattern to replicate:**
```toml
# BEFORE (in [dependencies]):
tungstenite = "0.28"

# AFTER — move to non-Android platform section:
[target.'cfg(not(target_os = "android"))'.dependencies]
tungstenite = "0.28"

# New Android-only section:
[target.'cfg(target_os = "android")'.dependencies]
jni = { version = "0.21", default-features = false }
```

**Key constraint:** `default-features = false` on `jni` drops the `invocation` feature (which tries to link `libjvm.so` — unnecessary for a library target).

---

## Pattern: cfg-Gated Rust Module in bridge.rs

**Role:** JNI shim module that wraps the existing C FFI bridge for Android.

**Closest analog:** The existing C FFI functions at `Rust/core/src/bridge.rs:2685–2727`:

```rust
// EXISTING PATTERN (C FFI):
#[unsafe(no_mangle)]
pub unsafe extern "C" fn goose_bridge_handle_json(request_json: *const c_char) -> *mut c_char {
    // ... calls handle_bridge_request_json() internally
}

// NEW PATTERN (JNI, cfg-gated):
#[cfg(target_os = "android")]
pub mod android {
    use jni::objects::{JClass, JString};
    use jni::sys::jstring;
    use jni::JNIEnv;

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_com_goose_core_GooseBridge_handle(
        mut env: JNIEnv,
        _class: JClass,
        request_json: JString,
    ) -> jstring {
        // Calls super::handle_bridge_request_json (the same internal function)
    }
}
```

**Key differences from C FFI:**
- `extern "system"` not `extern "C"` (JNI ABI on Android)
- Input: `JString` not `*const c_char`
- Output: `jstring` (owned Java string heap reference) not `*mut c_char`
- No `unsafe` on the function signature (JNI env methods handle memory safety)
- Must NOT panic — return error JSON string on failure

---

## Pattern: GitHub Actions Job in Existing Workflow

**Role:** Add Android cross-compile job to `rust-core-ci.yml`.

**Closest analog:** The existing `build-test:` job in `.github/workflows/rust-core-ci.yml`:

```yaml
# EXISTING JOB STRUCTURE:
jobs:
  build-test:
    name: Build, test, and lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Rust toolchain
        run: rustup toolchain install stable --profile minimal
      - name: Cache cargo ...
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            Rust/core/target
          key: ${{ runner.os }}-cargo-${{ hashFiles('Rust/core/Cargo.lock') }}
      - name: Build
        run: cargo build --all-targets --locked

# NEW JOB (sibling, same trigger):
  android-build:
    name: Android cross-compile (aarch64)
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: Rust/core
    steps:
      - uses: actions/checkout@v4
      - name: Set up Rust toolchain
        run: |
          rustup toolchain install stable --profile minimal
          rustup target add aarch64-linux-android
      - name: Set up Android NDK r29
        uses: nttld/setup-ndk@v1
        with:
          ndk-version: r29
          add-to-path: true
      - name: Cache cargo registry
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
          key: ${{ runner.os }}-cargo-android-${{ hashFiles('Rust/core/Cargo.lock') }}
      - name: Install cargo-ndk
        run: cargo install cargo-ndk --version 4.1.2 --locked
      - name: Build for aarch64-linux-android
        run: cargo ndk -t arm64-v8a build --release --lib
```

**Key differences from build-test:**
- Adds `rustup target add aarch64-linux-android`
- Adds NDK setup step (`nttld/setup-ndk@v1`)
- Installs `cargo-ndk 4.1.2`
- Runs `cargo ndk -t arm64-v8a build --release --lib` (not `cargo build --all-targets`)
- Does NOT include `cargo test` (no Android runtime for tests)
- Cache key uses `cargo-android-` prefix to avoid collision with x86_64 cache

---

## Pattern: GitHub Actions Python Pytest Workflow

**Role:** New `server-ci.yml` for server pytest suite with real TimescaleDB.

**Closest analog:** `.github/workflows/rust-core-ci.yml` overall structure (workflow file structure, checkout, cache, run steps).

**Unique pattern:** `conftest.py` manages Docker container lifecycle via `subprocess.run(["docker", "run", ...])` — NOT via GHA `services:` block. Docker daemon available by default on `ubuntu-latest`.

```yaml
# NEW FILE: .github/workflows/server-ci.yml
name: Server CI

on:
  push:
    branches: ["main"]
    paths:
      - "server/**"
      - ".github/workflows/server-ci.yml"
  pull_request:
    paths:
      - "server/**"
      - ".github/workflows/server-ci.yml"
  workflow_dispatch:

defaults:
  run:
    working-directory: server/ingest

jobs:
  pytest:
    name: Server pytest suite
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Cache pip
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('server/ingest/requirements-dev.txt') }}
          restore-keys: ${{ runner.os }}-pip-
      - name: Install dependencies
        run: pip install -r requirements-dev.txt
      - name: Verify Docker is available
        run: docker info
      - name: Run pytest
        run: pytest tests/ -v --tb=short
```

---

## Pattern: ADR Document

**Role:** Architecture Decision Record at `docs/ADR-android-jni.md`.

**Closest analog:** No existing ADRs in `docs/`. Use standard Nygard format.

```markdown
# ADR: Android JNI Architecture for Goose Core

**Status:** Accepted
**Date:** 2026-06-03
**Deciders:** tigercraft4

## Context

The Goose Rust core already produces a `cdylib` (`.so`) for general shared-library use...

## Decision

Use the existing `cdylib` crate type with a thin `#[cfg(target_os = "android")]` JNI shim
in `bridge.rs`, rather than creating a separate crate or using raw `extern "system"` without
the `jni` crate...

## Consequences

### Positive
- Zero new Rust logic — JNI shim is purely a calling-convention adapter
- cdylib already present — Android just adds a new compilation target
- jni crate 0.21 handles MUTF-8 transparently for JSON (ASCII-compatible)

### Negative / Trade-offs
- Only aarch64-linux-android is supported (x86_64, armv7 excluded due to rusqlite bundled bugs)
- Future JNI tests require an Android emulator or device

## Appendix: Future Android App Path

The ADR keeps the door open for a full Android app by:
1. Establishing the Java package namespace `com.goose.core`
2. Using `GooseBridge` class name matching the iOS `GooseRustBridge` pattern
3. Producing a proper `.so` via cdylib — standard Android AAR packaging
...
```

---

## Integration Points

- `super::handle_bridge_request_json` — the JNI shim's target function; located in `Rust/core/src/bridge.rs` as a private `fn`; accessible from a submodule inside the same file via `super::`
- `debug_ws` module — uses `tungstenite`; must be cfg-gated with `#[cfg(not(target_os = "android"))]` if it's imported at the bridge.rs module level
- `server/ingest/tests/conftest.py` — defines `timescale_dsn` and `clean_db` fixtures; CI only needs `pytest tests/ -v`
