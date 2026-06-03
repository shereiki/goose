# Roadmap: Goose

## Milestones

- ✅ **v1.0 Remote Server + Upstream PRs** — Phases 1-5 (shipped 2026-06-03)
- ⬜ **v2.0 Multi-Device & Platform Foundations** — Phases 6-8

## Phases

<details>
<summary>✅ v1.0 Remote Server + Upstream PRs (Phases 1-5) — SHIPPED 2026-06-03</summary>

- [x] Phase 1: Server Infrastructure (3/3 plans) — completed 2026-06-03
- [x] Phase 2: iOS Server Settings (2/2 plans) — completed 2026-06-03
- [x] Phase 3: iOS Upload Client (3/3 plans) — completed 2026-06-03
- [x] Phase 4: Upload Status Feedback (2/2 plans) — completed 2026-06-03
- [x] Phase 5: Upstream PR Integration (4/4 plans) — completed 2026-06-03

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

**v2.0 Multi-Device & Platform Foundations**

- [ ] **Phase 6: WHOOP Gen4 iOS Support** - iOS app layer changes to expose full Gen4 connect/capture/upload
- [ ] **Phase 7: Android Port Foundations + CI** - Rust core cross-compiles to Android; JNI shim; ADR; server CI
- [ ] **Phase 8: Additional Wearables E2E** - Standard HR GATT device supported BLE to SQLite to upload

## Phase Details

### Phase 6: WHOOP Gen4 iOS Support
**Goal**: Users with a WHOOP 4.0 can connect, capture, and upload data with the same experience as WHOOP 5.0 users
**Depends on**: Phase 3 (upload client already shipped in v1.0)
**Requirements**: GEN4-01, GEN4-02, GEN4-03, GEN4-04, GEN4-05
**Success Criteria** (what must be TRUE):
  1. A user with a WHOOP 4.0 can connect the device and have historical sync and overnight mode work (the `supportsV5*` guards accept the Gen4 command characteristic UUID prefix `61080002-`)
  2. The app model exposes a `generation` field ("4.0" or "5.0") derived from the advertised BLE service UUID, visible to the UI and upload service
  3. Onboarding copy references WHOOP 4.0 alongside WHOOP 5.0
  4. The connected device view displays a generation label ("Gen 4" or "Gen 5") while connected
  5. Upload payload contains `device_generation: "4.0"` for Gen4 captures, verified by a unit or integration test
**Plans**: TBD
**UI hint**: yes

### Phase 7: Android Port Foundations + CI
**Goal**: The Rust core cross-compiles cleanly to `aarch64-linux-android`, a thin JNI shim is in place, an ADR documents the architecture choices, and the server pytest suite runs on CI
**Depends on**: Nothing (independent of Phases 6 and 8 — different file sets)
**Requirements**: ANDROID-01, ANDROID-02, ANDROID-03, CI-01
**Success Criteria** (what must be TRUE):
  1. `cargo build --target aarch64-linux-android` (via `cargo-ndk`) produces `libgoose_core.so` without errors; the GitHub Actions workflow passes on push and PR to `main`
  2. A `#[cfg(target_os = "android")]` JNI wrapper module in `bridge.rs` exposes the C FFI API as JNI-callable `Java_*` functions; `tungstenite` is excluded on Android via `cfg` guard; `panic = "abort"` is set for the Android target profile
  3. `docs/ADR-android-jni.md` exists and documents the `cdylib`+JNI approach, panic strategy, MUTF-8 handling policy, `rusqlite bundled` target limitation (aarch64 only), and what keeps the door open for a future Android app
  4. The server pytest suite (`server/ingest/tests/`) runs on GitHub Actions with a real TimescaleDB container; failures block merge
**Plans**: TBD

### Phase 8: Additional Wearables E2E
**Goal**: A user with any standard Bluetooth heart rate monitor (0x180D service) can connect it to the app and have HR and RR data captured in SQLite and uploaded to the server with a distinct device type
**Depends on**: Phase 6 (needs the `WearableDescriptor`/`rustDeviceType` abstraction introduced for Gen4)
**Requirements**: WEAR-01, WEAR-02, WEAR-03
**Success Criteria** (what must be TRUE):
  1. `Rust/core/src/heart_rate_gatt_protocol.rs` parses the standard 0x2A37 HR Measurement characteristic (HR value + optional RR intervals); integration tests cover the standard encoding variants
  2. The iOS BLE client scans for and connects standard 0x180D Heart Rate Service devices; frames are routed through the existing notification pipeline via an extended `rustDeviceType` heuristic
  3. Upload payload identifies HR monitor data with a distinct `device_type` or `device_generation` value; `GooseUploadService` handles all device classes without the silent WHOOP Gen5 fallback
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Server Infrastructure | v1.0 | 3/3 | Complete | 2026-06-03 |
| 2. iOS Server Settings | v1.0 | 2/2 | Complete | 2026-06-03 |
| 3. iOS Upload Client | v1.0 | 3/3 | Complete | 2026-06-03 |
| 4. Upload Status Feedback | v1.0 | 2/2 | Complete | 2026-06-03 |
| 5. Upstream PR Integration | v1.0 | 4/4 | Complete | 2026-06-03 |
| 6. WHOOP Gen4 iOS Support | v2.0 | 0/? | Not started | - |
| 7. Android Port Foundations + CI | v2.0 | 0/? | Not started | - |
| 8. Additional Wearables E2E | v2.0 | 0/? | Not started | - |
