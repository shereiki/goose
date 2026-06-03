# Requirements: v2.0 Multi-Device & Platform Foundations

**Milestone:** v2.0
**Status:** Active
**Last updated:** 2026-06-03

## User Stories

### WHOOP Gen4 Support
As a user with a WHOOP 4.0 device, I want to connect it to the Goose app and have full data capture and upload functionality, so that I can use the same experience as a WHOOP 5.0 user.

### Android Port Foundations
As a developer, I want the Rust core to compile for Android targets and have documented JNI integration patterns, so that a future Android app can consume the same health data pipeline.

### Additional Wearables
As a user with a standard Bluetooth heart rate monitor, I want to connect it to the Goose app and have my HR and RR data captured and uploaded to my server, so that I can track data from non-WHOOP devices.

### CI Coverage
As a developer, I want the server pytest suite to run on CI, so that server regressions are caught automatically.

---

## Requirements

### WHOOP Gen4 — iOS App Layer

> The Rust core already fully supports Gen4 (DeviceType::Gen4, 4-byte header, CRC8, UUID 61080001-8D6D-82B8-614A-1C8CB0F8DCC6). Both service UUIDs are already in the BLE scan. The upload already sends `device_generation: "4.0"`. What is missing is the iOS app layer: command capability guards, device generation exposure, onboarding copy, and UI labelling.

- [ ] **GEN4-01**: User with WHOOP 4.0 can connect the device and have all command capabilities available (historical sync, overnight mode) — the `supportsV5*` guards in `GooseBLEClient+Commands.swift` must correctly handle the Gen4 command characteristic UUID prefix (`61080002-...`)
- [ ] **GEN4-02**: `GooseDiscoveredDevice` exposes a `generation` field (e.g. `"4.0"` or `"5.0"`) derived from the advertised BLE service UUID at connect time, and propagates it through the app model
- [ ] **GEN4-03**: Onboarding UI mentions WHOOP 4.0 support alongside WHOOP 5.0 (text and/or device recognition)
- [ ] **GEN4-04**: Device view shows a generation label ("Gen 4" or "Gen 5") when a WHOOP device is connected
- [ ] **GEN4-05**: Upload payload contains `device_generation: "4.0"` for Gen4 captures; verified by a unit or integration test

### Android Port Foundations

> `crate-type = ["cdylib"]` is already declared in Cargo.toml. No full Android app — only the Rust core cross-compilation, a thin JNI shim, and an ADR.

- [ ] **ANDROID-01**: `cargo build --target aarch64-linux-android` produces a library (`libgoose_core.so`) without errors; verified on CI (GitHub Actions) with `cargo-ndk` and Android NDK r29
- [ ] **ANDROID-02**: A thin JNI wrapper module (`#[cfg(target_os = "android")]`) in `bridge.rs` exposes the existing C FFI API as JNI-callable functions (`Java_*` naming convention); `tungstenite` WebSocket module excluded on Android via `cfg` guard; `panic = "abort"` overridden for Android target profile
- [ ] **ANDROID-03**: Architecture Decision Record at `docs/ADR-android-jni.md` documents: why `cdylib` + JNI shim over a separate crate, `panic` strategy, MUTF-8 string handling policy, `rusqlite bundled` target limitation (aarch64 only), and the overall choices that keep the door open for a future Android app

### Additional Wearables — Standard HR GATT

> The standard Heart Rate Service UUID (`0x180D`) is already defined in `GooseBLEClient.swift`. The 0x2A37 format is fully public (Bluetooth SIG). This track validates that the Rust core + BLE pipeline architecture is extensible.

- [ ] **WEAR-01**: Rust module `Rust/core/src/heart_rate_gatt_protocol.rs` parses the standard 0x2A37 HR Measurement characteristic format (HR value + optional RR intervals), with integration tests covering the standard encoding variants
- [ ] **WEAR-02**: iOS BLE client scans for and connects standard 0x180D Heart Rate Service devices; frames are routed through the existing notification pipeline using the `rustDeviceType` heuristic extended for the new device class
- [ ] **WEAR-03**: Upload payload correctly identifies HR monitor data separately from WHOOP data (distinct `device_type` or `device_generation` value); `GooseUploadService` device-type mapping extended to handle all device classes without the silent WHOOP Gen5 fallback

### CI Coverage

- [ ] **CI-01**: Server pytest suite (`server/ingest/tests/`) runs on GitHub Actions on push/PR to `main`; uses a real TimescaleDB container (matching the existing `conftest.py` pattern); failures block merge

---

## Future Requirements (v3+)

- Upload queue persisted in SQLite to survive app restarts (UPLD-V2-01)
- Background URLSession for upload when the app is suspended (UPLD-V2-02)
- Sync cursor/watermark for incremental uploads (UPLD-V2-03)
- HR/RR/SpO2 charts on iOS dashboard (DASH-V2-01)
- PRs back to upstream b-nnett/goose with fork fixes (UPSTREAM-V2-01)
- Third wearable support + generic `Wearable` protocol abstraction (WEAR-V3-01)
- Full Android app UI (ANDROID-V3-01)

---

## Out of Scope (v2.0)

- Server-side data analysis, dashboards, or alerts
- Advanced authentication (OAuth, 2FA) — Bearer token is sufficient
- Full Android application — architecture foundations only
- Background URLSession for iOS upload
- Third wearable device support
- Polar PMD proprietary ECG service (WEAR-02 targets standard HR GATT only)

---

## Definition of Done

- All active requirements have passing tests or verifiable evidence
- Gen4: a physical WHOOP 4.0 connects and data flows to server (or Simulator BLE mock passes)
- Android: CI workflow for `aarch64-linux-android` passes on GitHub Actions
- Wearables: standard 0x180D device connects and HR data appears in TimescaleDB
- Server pytest CI: workflow passes on push to main

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GEN4-01 | Phase 6 | Pending |
| GEN4-02 | Phase 6 | Pending |
| GEN4-03 | Phase 6 | Pending |
| GEN4-04 | Phase 6 | Pending |
| GEN4-05 | Phase 6 | Pending |
| ANDROID-01 | Phase 7 | Pending |
| ANDROID-02 | Phase 7 | Pending |
| ANDROID-03 | Phase 7 | Pending |
| CI-01 | Phase 7 | Pending |
| WEAR-01 | Phase 8 | Pending |
| WEAR-02 | Phase 8 | Pending |
| WEAR-03 | Phase 8 | Pending |
