---
phase: 7
slug: android-port-foundations-ci
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-03
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | cargo test (Rust), pytest 8+ (server Python) |
| **Config file** | `Rust/core/Cargo.toml` (Rust), `server/ingest/requirements-dev.txt` (Python) |
| **Quick run command** | `cd Rust/core && cargo check --target aarch64-linux-android 2>&1 \| tail -5` |
| **Full suite command** | `cd Rust/core && cargo ndk -t arm64-v8a build --release --lib && nm -D target/aarch64-linux-android/release/libgoose_core.so \| grep Java_` |
| **Estimated runtime** | ~180 seconds (first build with NDK), ~60s (cached) |

---

## Sampling Rate

- **After every task commit:** Run `cd Rust/core && cargo check --locked` (native, fast host check)
- **After every plan wave:** Run full Android build: `cargo ndk -t arm64-v8a build --release --lib`
- **Before `/gsd-verify-work`:** Full suite must pass including CI workflow linting (`actionlint` optional)
- **Max feedback latency:** 180 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | ANDROID-02 | — | N/A | compile | `cd Rust/core && cargo check --locked` | ✅ | ⬜ pending |
| 07-01-02 | 01 | 1 | ANDROID-01 | — | N/A | compile | `cd Rust/core && cargo ndk -t arm64-v8a build --release --lib` | ✅ | ⬜ pending |
| 07-02-01 | 02 | 2 | ANDROID-02 | — | N/A | compile | `cd Rust/core && cargo ndk -t arm64-v8a build --release --lib` | ✅ | ⬜ pending |
| 07-02-02 | 02 | 2 | ANDROID-01 | — | N/A | symbol | `nm -D Rust/core/target/aarch64-linux-android/release/libgoose_core.so \| grep Java_com_goose_core_GooseBridge_handle` | ✅ | ⬜ pending |
| 07-03-01 | 03 | 1 | ANDROID-01 | — | N/A | file-exists | `test -f .github/workflows/rust-core-ci.yml && grep -q 'android-build' .github/workflows/rust-core-ci.yml` | ✅ | ⬜ pending |
| 07-04-01 | 04 | 1 | CI-01 | — | N/A | file-exists | `test -f .github/workflows/server-ci.yml && grep -q 'pytest' .github/workflows/server-ci.yml` | ✅ | ⬜ pending |
| 07-04-02 | 04 | 1 | ANDROID-03 | — | N/A | file-exists | `test -f docs/ADR-android-jni.md && grep -q 'cdylib' docs/ADR-android-jni.md` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

No Wave 0 required. This phase adds infrastructure files (CI workflows, Cargo config, ADR) and modifies existing Rust source. The existing Rust test infrastructure covers the host-side logic; Android compilation is validated by the CI job itself.

Existing infrastructure covers all phase requirements: `cargo check` / `cargo ndk build` are the validation primitives.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GitHub Actions android-build job passes on PR to main | ANDROID-01 | Requires GHA runner with NDK — cannot run locally without NDK r29 | Open a PR, observe the `android-build` job status in Actions tab |
| GitHub Actions server pytest job passes on PR to main | CI-01 | Requires GHA runner with Docker daemon — local Docker is optional | Open a PR, observe the `pytest` job status in Actions tab |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
