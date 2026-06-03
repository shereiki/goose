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

- [x] **ACK-01**: Upload ACK — iOS reads `upserted` count from server response, shows "N records acked" (shipped 2026-06-03)
- [x] **Phase 6: WHOOP Gen4 iOS Support** - iOS app layer changes to expose full Gen4 connect/capture/upload (completed 2026-06-03)
- [x] **Phase 7: Android Port Foundations + CI** - Rust core cross-compiles to Android; JNI shim; ADR; server CI (completed 2026-06-03)
- [x] **Phase 8: Additional Wearables E2E** - Standard HR GATT device supported BLE to SQLite to upload (completed 2026-06-03)

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
**Plans**: 4 plans
Plans:
- [x] 08-P01-PLAN.md — Rust 0x2A37 HR GATT parser + integration tests (WEAR-01)
- [x] 08-P02-PLAN.md — iOS BLE HR monitor extension, genericHRMonitor descriptor, empty-prefix guard, normalized UUID matching, background notification routing (WEAR-02)
- [x] 08-P03-PLAN.md — Upload fix: remove silent Gen5 fallback, add device_class for HR monitors, add DeviceType::HrMonitor variant (WEAR-03)
- [x] 08-P04-PLAN.md — Upload payload unit tests: Gen4 / Gen5 / HR monitor device_class / manual-upload derivation (WEAR-03)
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
  3. Upload payload identifies HR monitor data with BOTH `device_type` (sanitized BLE device name) AND `device_class: "HR_MONITOR"`; `GooseUploadService` handles all device classes without the silent WHOOP Gen5 fallback; a real `DeviceType::HrMonitor` Rust variant backs the routing
**Plans**: TBD

## Backlog

### Phase 08.1: Close gap WEAR-01/WEAR-03: integrate parse_hr_measurement into upload.get_recent_decoded_streams so HR monitor uploads contain decoded hr/rr stream data (INSERTED)

**Goal:** [Urgent work - to be planned]
**Requirements**: TBD
**Depends on:** Phase 8
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 08.1 to break down)

### Phase 999.4: Recovery V2 Completion (BACKLOG)

**Goal:** Complete the Recovery V2 dashboard with real bridge-backed data, replacing placeholder/zero values with trusted packet-derived metrics.

**What's needed (from `recovery-todo.md`):**
- Wire Recovery V2 trend rows to bridge-backed daily recovery, HRV, and resting HR series when the bridge exposes trusted daily values
- Replace zero vitals cards with trusted packet-derived respiratory rate, SpO2, and wrist-temperature fields once their semantics are verified
- Add a real recovery timeline model that links the score to the primary sleep window and the packet/vitals inputs used by the score run
- Add Recovery V2 snapshot tests or simulator screenshots for no-data, bridge-data, and packet-run-blocked states
- Keep Recovery V2 free of fixture/sample values; show `0` or empty state until trusted local data exists

**Milestone:** v3.0
**Requirements:** TBD
**Plans:** 0 plans — promote with `/gsd-review-backlog` when ready

---

### Phase 999.3: Apply upstream PR #15 — Block state-changing debug deep links (BACKLOG)

**Goal:** Integrate upstream PR #15 from b-nnett/goose (by kobemartin) which fixes a security issue with the `gooseswift://` custom URL scheme. Currently, external apps or webpages can invoke state-changing WHOOP research commands via deep link while the device is connected.

**PR:** https://github.com/b-nnett/goose/pull/15
**Author:** kobemartin
**Status:** Open (not yet merged into b-nnett/goose)

**What the PR does:**
- Allows external debug-command deep links to invoke **read-only** research commands only
- Blocks **state-changing** and unknown-risk command categories before any Bluetooth write
- Hides remote URL examples in the UI for commands that cannot be safely invoked remotely

**Why it matters:** The `gooseswift://` scheme is accessible from Safari or any app. Without this fix, a malicious webpage could trigger a WHOOP command (e.g., historical sync, alarm, sensor capture) while the user has Goose open and connected.

**Integration approach:**
1. Fetch the diff: `git fetch https://github.com/kobemartin/goose.git codex/block-state-change-debug-deep-links`
2. Review the changes against our fork (we've modified `GooseAppModel.swift` and debug commands significantly)
3. Apply with `git cherry-pick` or manual merge, resolving conflicts with our changes
4. Verify: deep links to read-only commands still work, state-changing commands are blocked

**Requirements:** TBD
**Plans:** 0 plans — promote with `/gsd-review-backlog` when ready

---

### Phase 999.2: Multi-Language Support (BACKLOG)

**Goal:** Add localisation support so the app UI can be presented in multiple languages. Currently all UI strings are hardcoded in English. Add Portuguese (pt-PT) as the first localisation target, using Apple's standard String Catalog (`.xcstrings`) localisation system.

**Current state (2026-06-03):**
- All user-facing strings are hardcoded in Swift source (no `NSLocalizedString` or `String(localized:)`)
- A small number of Portuguese strings were found and corrected to English as a first pass
- No `.lproj` directories, no `.xcstrings` files, no `localizable` strings infrastructure

**What's needed:**
1. Enable localisation in `GooseSwift.xcodeproj` — add pt-PT locale
2. Create `Localizable.xcstrings` (String Catalog, Xcode 15+ format)
3. Wrap all user-facing strings in `String(localized:)` or `LocalizedStringKey`
4. Provide pt-PT translations for all strings
5. Test locale switching on device

**Requirements:** TBD
**Plans:** 0 plans — promote with `/gsd-review-backlog` when ready

---

### Phase 999.1: Coach Multi-Provider & Custom Endpoint (BACKLOG)

**Goal:** Expand the Coach tab from a single hardcoded provider (OpenAI GPT-5.5 via Responses API) to support multiple named accounts per provider, additional providers, and a user-configured custom endpoint using an OpenAI-compatible Chat Completions API (`POST /v1/chat/completions`).

**Current implementation assessment (2026-06-03):**
- `OpenAICoachResponsesClient` — calls OpenAI Responses API (`/v1/responses`), hardcoded to `gpt-5.5`
- `CoachModelPreset` — enum with 3 GPT-5.5 effort variants only (`low`/`medium`/`high`)
- `OpenAICoachChatModel` — single-provider `@Published` model; no provider abstraction
- API key stored as a single Keychain item — no multi-account support
- No `CoachProvider` protocol or provider registry exists

**What's needed:**
1. `CoachProvider` protocol — abstract interface `send(messages:systemPrompt:) async throws -> AsyncStream<String>`
2. Named accounts per provider — stored in Keychain with a provider prefix (multiple keys)
3. Additional providers: Claude API (Anthropic), Gemini (Google), local (Ollama/LM Studio)
4. Custom endpoint — user-configured base URL + API key + model ID; must implement OpenAI Chat Completions-compatible protocol (`POST /v1/chat/completions` with SSE streaming)
5. Provider picker UI — in Coach settings or More tab, shows configured accounts, lets user add/remove/select active account
6. Migration path — existing single OpenAI key promoted to named account on first launch

**Requirements:** TBD
**Plans:** 0 plans — promote with `/gsd-review-backlog` when ready

---

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Server Infrastructure | v1.0 | 3/3 | Complete | 2026-06-03 |
| 2. iOS Server Settings | v1.0 | 2/2 | Complete | 2026-06-03 |
| 3. iOS Upload Client | v1.0 | 3/3 | Complete | 2026-06-03 |
| 4. Upload Status Feedback | v1.0 | 2/2 | Complete | 2026-06-03 |
| 5. Upstream PR Integration | v1.0 | 4/4 | Complete | 2026-06-03 |
| 6. WHOOP Gen4 iOS Support | v2.0 | 3/3 | Complete   | 2026-06-03 |
| 7. Android Port Foundations + CI | v2.0 | 4/4 | Complete    | 2026-06-03 |
| 8. Additional Wearables E2E | v2.0 | 4/4 | Complete    | 2026-06-03 |
