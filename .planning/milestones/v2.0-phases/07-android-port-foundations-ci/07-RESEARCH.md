# Phase 7: Android Port Foundations + CI — Research

**Phase:** 07 — Android Port Foundations + CI
**Requirements:** ANDROID-01, ANDROID-02, ANDROID-03, CI-01
**Researched:** 2026-06-03

---

## Executive Summary

Phase 7 has four work streams that are fully independent of each other:

1. **Cargo.toml changes** — cfg-gate `tungstenite`, add `jni` crate for Android only
2. **bridge.rs JNI shim** — thin `#[cfg(target_os = "android")]` module wrapping existing C FFI
3. **CI: Android job** — add to `rust-core-ci.yml` using `cargo-ndk 4.1.2` + NDK r29
4. **CI: Server pytest** — new `server-ci.yml` running `server/ingest/tests/` with real TimescaleDB

No new Rust logic is required. The JNI shim is purely a calling-convention adapter around the existing `goose_bridge_handle_json` function. The `cdylib` crate type is already declared — Android just adds a cross-compile target.

---

## 1. JNI Shim Architecture

### 1.1 The `jni` Crate

The standard Rust JNI crate is `jni` (crates.io). Key facts:

- Current stable version: `jni = "0.21"` — compatible with Rust edition 2024 and MSRV 1.94
- Must be added as **Android-only** dep: `[target.'cfg(target_os = "android")'.dependencies]`
- Provides `JNIEnv`, `JString`, `JClass`, `jstring` types needed for the shim

**Cargo.toml addition:**
```toml
[target.'cfg(target_os = "android")'.dependencies]
jni = { version = "0.21", default-features = false }
```

`default-features = false` drops the `invocation` feature (which tries to load libjvm and is unnecessary for a library target).

### 1.2 JNI Function Naming Convention

JNI mangles Java method names to C symbol names using the rule:
`Java_<package_underscores>_<ClassName>_<methodName>`

For `com.goose.core.GooseBridge.handle(String) → String`:
- Symbol: `Java_com_goose_core_GooseBridge_handle`
- Input: `JString` (MUTF-8 encoded Java string)
- Output: `jstring` (heap-allocated Java string returned via `env.new_string()`)

The JNI shim does NOT re-implement logic — it:
1. Converts `JString` → Rust `&str` (via `env.get_string()`)
2. Calls `handle_bridge_request_json(&request_str)` (the existing internal function)
3. Converts the returned `String` → `jstring` (via `env.new_string()`)

This means the shim cannot panic (JVM crashes on Rust panics crossing the FFI boundary). Error handling must use `env.throw_new()` or return an error-encoded JSON string via `new_string()`.

### 1.3 MUTF-8 String Handling Policy

Java strings are MUTF-8 (Modified UTF-8), not standard UTF-8. The `jni` crate's `get_string()` method returns a `JavaStr` that implements `Deref<Target = str>`, handling the conversion transparently for ASCII-compatible content.

**Policy decision (for ADR):**
- Use `env.get_string(&input)` → MUTF-8 → Rust `&str`. This is safe because all bridge requests are JSON (ASCII-subset), so MUTF-8 and UTF-8 are identical.
- If `get_string` fails (null, invalid encoding): return an error JSON via `env.new_string("{\"ok\":false,\"error\":\"invalid_utf8\"}")` rather than panicking or throwing.
- Never call `env.throw_new()` in the shim — return error JSON instead, consistent with the existing bridge error protocol.

### 1.4 JNI Module Structure in bridge.rs

The shim goes at the bottom of `bridge.rs` inside a `#[cfg(target_os = "android")]` module:

```rust
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
        let request = match env.get_string(&request_json) {
            Ok(s) => s.to_string_lossy().into_owned(),
            Err(_) => {
                return env
                    .new_string("{\"ok\":false,\"error\":\"jni_string_error\"}")
                    .map(|s| s.into_raw())
                    .unwrap_or(std::ptr::null_mut());
            }
        };
        let response = super::handle_bridge_request_json(&request);
        env.new_string(response)
            .map(|s| s.into_raw())
            .unwrap_or(std::ptr::null_mut())
    }
}
```

Note: The module uses `super::handle_bridge_request_json` — this is the internal string-in/string-out function already used by `goose_bridge_handle_json`. It is not `pub` currently; the plan must make it accessible from the submodule (either `pub(super)` or move the module inline).

**Critical check:** Verify `handle_bridge_request_json` is directly callable. Looking at bridge.rs, the function is `fn handle_bridge_request_json(request: &str) -> String` — it's `pub(crate)` or private. The JNI module inside `bridge.rs` can call it directly as `super::handle_bridge_request_json`.

---

## 2. Cargo Configuration

### 2.1 tungstenite cfg-gate

Current state: `tungstenite = "0.28"` is in `[dependencies]` (unconditional).

Required change — move to non-Android only:
```toml
[target.'cfg(not(target_os = "android"))'.dependencies]
tungstenite = "0.28"
```

**Risk:** Any existing code that uses `tungstenite` must also be wrapped in `#[cfg(not(target_os = "android"))]`. Check: `tungstenite` is used by the debug WebSocket server (`src/debug_ws.rs`). This module must be cfg-gated too. The import in `bridge.rs` of any `debug_ws` types must also be cfg-gated.

**Action required in plan:** Verify all `use crate::debug_ws::*` imports in bridge.rs and tag them `#[cfg(not(target_os = "android"))]` as well.

### 2.2 panic = "abort" for Android

**Current state:** `[profile.release]` in Cargo.toml already has `panic = "abort"`.

This means the release profile ALREADY aborts on panic for ALL targets including Android. **No additional configuration is needed.**

However, `cargo ndk` by default builds in release mode, so this is already satisfied. For debug builds (not used in CI), panic would be `unwind` (the Rust default) — this is acceptable for CI which only checks the release/build.

**If `.cargo/config.toml` is used** to force `panic = "abort"` for all Android profiles:
```toml
[target.aarch64-linux-android]
rustflags = []

[profile.release]
panic = "abort"
```

But this is redundant given the existing Cargo.toml profile. The ADR should note this is already satisfied by the global release profile.

### 2.3 cargo-ndk Installation

`cargo-ndk 4.1.2` is a cargo subcommand installed via:
```bash
cargo install cargo-ndk --version 4.1.2 --locked
```

`--locked` ensures reproducible builds using the locked Cargo.lock of cargo-ndk itself.

For CI, this can be cached using the `cargo install` cache key pattern or installed fresh (takes ~60-90s). Given CI simplicity preference, install fresh without cache.

---

## 3. Android CI Job Design

### 3.1 NDK Setup on GitHub Actions

`ubuntu-latest` (ubuntu-24.04) has pre-installed Android SDK/NDK tooling. The pre-installed NDK version varies by runner image — typically r27 or r28 as of 2026. NDK r29 must be explicitly installed.

**Recommended approach:** Use the `nttld/setup-ndk` action (maintained, supports exact NDK version):
```yaml
- uses: nttld/setup-ndk@v1
  with:
    ndk-version: r29
    add-to-path: true
```

Alternative: Use `android-actions/setup-android` with `ndk` component. The `nttld/setup-ndk` is simpler and more focused.

After NDK setup, set `ANDROID_NDK_HOME` which `cargo-ndk` reads automatically.

### 3.2 Full Android Job in rust-core-ci.yml

The new job runs sequentially after the existing `build-test` job (not parallel — saves cost) OR runs as a separate independent job (both approaches work; independent job is faster). 

Given the phase decision D-08 (add to existing file), the new job is a sibling of `build-test`:

```yaml
android-build:
  name: Android cross-compile (aarch64)
  runs-on: ubuntu-latest
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
        restore-keys: |
          ${{ runner.os }}-cargo-android-
          
    - name: Install cargo-ndk
      run: cargo install cargo-ndk --version 4.1.2 --locked
      
    - name: Build for aarch64-linux-android
      working-directory: Rust/core
      run: cargo ndk -t arm64-v8a build --release --lib
```

**Notes:**
- `--lib` builds only the library target (not the binaries) — binaries cannot cross-compile to Android because they depend on linux host syscalls in some cases
- `--release` uses the release profile (which has `panic = "abort"` already)
- The `nttld/setup-ndk@v1` action sets `ANDROID_NDK_HOME` automatically

**BLOCKER consideration:** The binary targets (`[[bin]]` entries) in Cargo.toml may fail to cross-compile if they use platform-specific code. Using `--lib` avoids this entirely. If the plan uses `cargo ndk ... build` without `--lib`, it will try to build all targets including binaries and potentially fail.

---

## 4. Server CI Design

### 4.1 Triggering

```yaml
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
```

### 4.2 Docker Socket Availability on ubuntu-latest

Docker daemon is available on `ubuntu-latest` GitHub Actions runners without any special setup. The `conftest.py` uses `subprocess.run(["docker", "run", ...])` directly, which works as-is. No `services:` block or `docker-compose` is needed.

**Port binding:** `conftest.py` uses `-P` (random ephemeral port), then queries `docker port <name> 5432/tcp` to get the actual port. This works correctly on GHA runners.

**Timing:** `conftest.py` has a 60-second readiness timeout with 1-second polling. On GHA ubuntu-latest, TimescaleDB typically starts in 15-30 seconds. No additional wait steps needed.

### 4.3 Python Setup

`ubuntu-latest` ships Python 3.12. The tests need:
- `psycopg[binary]` (from requirements.txt)
- `fastapi`, `uvicorn`, `httpx` (from requirements.txt)
- `neurokit2`, `numpy`, `scipy`, `scikit-learn`, `pandas` (from requirements.txt)
- `pytest>=8`, `httpx>=0.27` (from requirements-dev.txt)

**Install command:** `pip install -r server/ingest/requirements-dev.txt` (which includes `-r requirements.txt`)

**`working-directory`:** Set to `server/ingest` for pytest to find the tests correctly.

### 4.4 Full server-ci.yml

```yaml
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

**Why no `services:` block:** `conftest.py` manages the container lifecycle itself. Using both `services:` AND the fixture would create two containers and conflict on port usage.

---

## 5. ADR Structure

### 5.1 docs/ Conventions

No existing ADRs are in `docs/`. No ADR format is enforced by project conventions (no `adr-tools`, no template file). The format should be a Markdown document with the standard Nygard-style sections: Status, Context, Decision, Consequences.

### 5.2 Required Content (from D-10)

`docs/ADR-android-jni.md` MUST cover:
1. Why `cdylib` + JNI shim rather than a separate crate
2. `panic` strategy (already `abort` in release profile)
3. MUTF-8 string handling policy
4. `rusqlite bundled` target limitation (aarch64 only — x86_64 and armv7 have open bugs)
5. What keeps the door open for a future Android app

### 5.3 Template Structure

```markdown
# ADR: Android JNI Architecture for Goose Core

**Status:** Accepted
**Date:** 2026-06-03
**Deciders:** tigercraft4

## Context
...

## Decision
...

## Consequences
...

## Appendix: Future Android App Path
...
```

---

## 6. Validation Architecture (Nyquist)

Since there is no Android runtime on CI, JNI correctness is validated by:

1. **Compilation gate:** `cargo ndk -t arm64-v8a build --release --lib` must exit 0 — proves the code compiles with `jni` crate and all cfg gates work
2. **Symbol presence:** The `aarch64-linux-android` `.so` must contain the `Java_com_goose_core_GooseBridge_handle` symbol (verifiable via `nm -D` or `readelf -Ws` on the output `.so`)
3. **Type-check coverage:** The existing test suite (runs on x86_64/linux, not Android) validates `handle_bridge_request_json` logic; the JNI shim is pure adapter code — logic validation is inherited
4. **cfg isolation check:** `cargo check --target aarch64-linux-android` should also pass as a lightweight check (alternative to full build)

**Sampling strategy for CI:**
- Primary: Full `cargo ndk build` (compilation is the proof)
- Secondary: `readelf -Ws target/aarch64-linux-android/release/libgoose_core.so | grep Java_com_goose_core` to confirm symbol export
- Not required: JVM integration test (out of scope, deferred per CONTEXT.md)

---

## 7. Risk Register

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Binary targets fail Android cross-compile | High | Use `--lib` flag to build library only |
| `tungstenite` has deep imports in `debug_ws.rs` that cascade | Medium | Audit all `debug_ws` imports in bridge.rs, cfg-gate them |
| `handle_bridge_request_json` is `fn` (not pub) and JNI module can't call it | Low | Module is inside bridge.rs — `super::handle_bridge_request_json` is accessible |
| NDK r29 unavailable via nttld/setup-ndk | Low | Fallback: install via `sdkmanager --install "ndk;29.0.13113456"` |
| Server pytest times out waiting for Docker | Low | 60-second timeout in conftest.py is generous for GHA |
| `jni` crate 0.21 API changes in future | Low | Pin version in Cargo.toml; lock via Cargo.lock |

---

## 8. File Change Map

| File | Change Type | What Changes |
|------|------------|-------------|
| `Rust/core/Cargo.toml` | Modify | Move `tungstenite` to non-Android cfg; add `jni` under Android cfg |
| `Rust/core/src/bridge.rs` | Modify | Add `#[cfg(target_os = "android")] pub mod android { ... }` at bottom |
| `Rust/core/src/debug_ws.rs` (or uses) | Potentially modify | May need `#[cfg(not(target_os = "android"))]` on the module or its uses |
| `.github/workflows/rust-core-ci.yml` | Modify | Add `android-build:` job |
| `.github/workflows/server-ci.yml` | Create | New workflow file |
| `docs/ADR-android-jni.md` | Create | New ADR document |

---

## RESEARCH COMPLETE

Phase 7 is well-scoped and technically straightforward. The planner should organize 3-4 plans:

1. **Cargo configuration plan** — Cargo.toml changes (tungstenite cfg-gate, jni dep), debug_ws cfg audit
2. **JNI shim plan** — bridge.rs android module, symbol verification step
3. **Android CI plan** — rust-core-ci.yml android-build job
4. **Server CI + ADR plan** — server-ci.yml + docs/ADR-android-jni.md

Wave structure: Plans 1 and 2 are sequential (Cargo changes before JNI code compiles); Plans 3 and 4 can be in the same wave as Plan 1 if files don't overlap (CI files are independent of Rust source). Preferred: Wave 1 = Plans 1+3+4, Wave 2 = Plan 2 (JNI shim, after Cargo changes land).
