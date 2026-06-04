# Phase 7: Android Port Foundations + CI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 07-android-port-foundations-ci
**Areas discussed:** JNI naming, CI Android organization, Server CI (CI-01)

---

## JNI Naming

| Option | Description | Selected |
|--------|-------------|----------|
| com.goose.core | Neutral, aligns with Rust crate concept → Java_com_goose_core_GooseBridge_handle | ✓ |
| com.goose.android | Explicit Android layer naming | |
| io.goose.core | Alternative open-source convention | |

**User's choice:** `com.goose.core`
**Notes:** Selected recommended option; no additional notes.

| Class Option | Description | Selected |
|-------------|-------------|----------|
| GooseBridge | Mirrors iOS GooseRustBridge pattern — cross-platform consistency | ✓ |
| GooseCore | Matches crate name | |
| Bridge | Simple, generic | |

**User's choice:** `GooseBridge`
**Notes:** Selected recommended option; mirrors iOS naming convention.

---

## CI Android Organization

| Option | Description | Selected |
|--------|-------------|----------|
| Novo android-ci.yml | Separate file, trigger on Rust/core/** | |
| Adicionar ao rust-core-ci.yml | Extra job in existing file | ✓ |

**User's choice:** Add to existing `rust-core-ci.yml`
**Notes:** Keeps Rust CI consolidated in fewer files.

| Gate Option | Description | Selected |
|------------|-------------|----------|
| Bloquear merge | Blocking — aligns with ANDROID-01 | ✓ |
| Advisory | Non-blocking | |

**User's choice:** Blocking merge
**Notes:** Consistent with the requirement that Android build must pass on CI.

---

## Server CI (CI-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Novo server-ci.yml | Separate workflow triggered on server/** | ✓ |
| Adicionar ao rust-core-ci.yml | Add to existing Rust CI | |

**User's choice:** New `server-ci.yml`
**Notes:** Separate concerns — server CI is Python/Docker, distinct from Rust CI.

| Gate Option | Description | Selected |
|------------|-------------|----------|
| Bloquear merge | Blocking — aligns with CI-01 | ✓ |
| Advisory | Non-blocking | |

**User's choice:** Blocking merge
**Notes:** CI-01 requirement explicitly states "failures block merge".

---

## Claude's Discretion

- Exact mechanism for `panic = "abort"` Android profile override (`.cargo/config.toml` vs `Cargo.toml`)
- `cargo-ndk` caching strategy in CI
- ADR prose style and depth beyond mandatory sections

## Deferred Ideas

- x86_64-linux-android and armv7-linux-androideabi targets (rusqlite bundled bugs)
- Full Android app UI — v3+ milestone
- JNI test harness for the shim
- Kotlin/Java Android client library
