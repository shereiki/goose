# Roadmap: Goose

## Milestones

- ✅ **v1.0 Remote Server + Upstream PRs** — Phases 1-5 (shipped 2026-06-03)
- ✅ **v2.0 Multi-Device & Platform Foundations** — Phases 6-8+8.1 (shipped 2026-06-04)
- 🚧 **v3.0 Wearable UX, CI Hardening & RTC Sync** — Phases 9-14 (in progress)

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

<details>
<summary>✅ v2.0 Multi-Device & Platform Foundations (Phases 6-8+8.1) — SHIPPED 2026-06-04</summary>

- [x] Phase 6: WHOOP Gen4 iOS Support (3/3 plans) — completed 2026-06-03
- [x] Phase 7: Android Port Foundations + CI (4/4 plans) — completed 2026-06-03
- [x] Phase 8: Additional Wearables E2E (4/4 plans) — completed 2026-06-03
- [x] Phase 8.1: Gap closure WEAR-01/WEAR-03 (2/2 plans) — completed 2026-06-04

Full details: `.planning/milestones/v2.0-ROADMAP.md`

Known deferred: WEAR-02 scan UI (v3.0), CR-02 per-row filter (v3.0), hardware BLE tests (no device)

</details>

### 🚧 v3.0 Wearable UX, CI Hardening & RTC Sync (In Progress)

**Milestone Goal:** Complete the HR monitor UX, fix foundational BLE and data integrity bugs, deliver Recovery V2 dashboard, sync WHOOP 4.0 clock, and add pt-PT localisation.

- [x] **Phase 9: BLE Stability & Data Integrity** — Fix CR-02 device_id, BLE reconnect backoff, FFI panic safety, storage retention limit (completed 2026-06-04)
- [ ] **Phase 10: HR Monitor Scan/Connect UI** — Scan list with RSSI, tap-to-connect, connection status
- [ ] **Phase 11: HR Monitor Independent Capture** — HR session decoupled from WHOOP session gate
- [ ] **Phase 12: WHOOP 4.0 RTC Clock Sync** — Auto-sync iPhone time to WHOOP 4.0 after connect
- [ ] **Phase 13: Recovery V2 Dashboard** — Hero score, HRV, RHR, 7-day trend backed by bridge data
- [ ] **Phase 14: pt-PT Localisation** — Static catalog + dynamic status strings in European Portuguese

## Phase Details

### Phase 9: BLE Stability & Data Integrity

**Goal**: BLE connections are resilient, HR monitor frames are stored with correct per-row device identifiers, FFI panics return JSON errors instead of crashing, and storage growth is bounded
**Depends on**: Phase 8.1 (v2.0 complete)
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04, FIX-05
**Success Criteria** (what must be TRUE):

  1. HR monitor frames written to the database contain a non-NULL `device_id` matching the connected HR monitor device
  2. After a WHOOP disconnection, the app retries with exponential backoff (1 s base, doubles, 60 s cap) and stops after 10 attempts, showing attempt count in the UI
  3. After an HR monitor disconnection, the same backoff parameters apply and the UI reflects reconnect state
  4. User can tap a manual retry button to restart reconnection at any time, and a stop button to abort it
  5. A Rust panic in the FFI layer returns a structured JSON error instead of terminating the app process
  6. Raw evidence payload retention is capped at 24 MB; a large history sync does not balloon the SQLite database**Plans**: 4 plans

**Wave 1**

  - [x] 09-01-PLAN.md — FFI panic safety (catch_unwind + panic=unwind) and storage.compact_raw_evidence bridge method (FIX-04, FIX-05 Rust)

**Wave 2** *(blocked on Wave 1 completion)*

  - [x] 09-02-PLAN.md — Propagate active_device_id into capture_sessions (FIX-01 Rust/CR-02)

**Wave 3** *(blocked on Wave 2 completion)*

  - [x] 09-03-PLAN.md — ReconnectBackoff + WHOOP reconnect UI + storage compaction call sites + active_device_id arg (FIX-02, FIX-05 Swift, FIX-01 Swift)

**Wave 4** *(blocked on Wave 3 completion)*

  - [x] 09-04-PLAN.md — HR monitor reconnect backoff + ConnectionView HR row (FIX-03)

### Phase 10: HR Monitor Scan/Connect UI

**Goal**: Users can discover and connect nearby HR monitors from within the app
**Depends on**: Phase 9
**Requirements**: WEAR-04, WEAR-05
**Success Criteria** (what must be TRUE):

  1. User can initiate an HR monitor scan from the app and see a live list of discovered devices showing device name and RSSI
  2. The scan list updates in real time as devices appear and disappear
  3. User can tap a device in the list to initiate a connection to that HR monitor
  4. The UI shows connection progress and confirms when the HR monitor is connected

**Plans**: TBD
**UI hint**: yes

### Phase 11: HR Monitor Independent Capture

**Goal**: Users can run an HR monitor capture session without requiring an active WHOOP session
**Depends on**: Phase 9, Phase 10
**Requirements**: WEAR-06
**Success Criteria** (what must be TRUE):

  1. HR monitor frames are captured and stored when no WHOOP session is active
  2. HR monitor capture starts and stops independently of the WHOOP session lifecycle
  3. Captured HR monitor data (BPM and RR intervals) appears in the upload payload regardless of WHOOP session state

**Plans**: TBD

### Phase 12: WHOOP 4.0 RTC Clock Sync

**Goal**: WHOOP 4.0 clock drift is automatically corrected after each BLE connection
**Depends on**: Phase 9
**Requirements**: RTC-01
**Success Criteria** (what must be TRUE):

  1. After connecting a WHOOP 4.0, the app automatically reads the device clock and compares it to iPhone time
  2. When drift exceeds the configured threshold, the app writes the current iPhone time to the WHOOP 4.0 via BLE
  3. The sync is silent (no user prompt required) and does not interrupt normal BLE data capture

**Plans**: TBD

### Phase 13: Recovery V2 Dashboard

**Goal**: Users can view a live Recovery V2 dashboard with bridge-backed biometric data
**Depends on**: Phase 9
**Requirements**: DASH-01
**Success Criteria** (what must be TRUE):

  1. User can see a hero recovery score on the Recovery V2 dashboard derived from live bridge data
  2. User can see current HRV and resting heart rate values, not placeholder zeros
  3. User can see a 7-day trend of recovery scores on the dashboard

**Plans**: TBD
**UI hint**: yes

### Phase 14: pt-PT Localisation

**Goal**: All user-visible text in the app is presented in European Portuguese
**Depends on**: Phase 10, Phase 11, Phase 13 (all UI stable)
**Requirements**: L10N-01, L10N-02
**Success Criteria** (what must be TRUE):

  1. All static UI text strings are stored in a `Localizable.xcstrings` String Catalog and rendered in pt-PT when the device language is Portuguese (Portugal)
  2. Dynamic status strings (BLE connection state, sync state, upload state) displayed in the UI appear in pt-PT
  3. No hardcoded English text remains visible in the main user-facing UI flows

**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Server Infrastructure | v1.0 | 3/3 | Complete | 2026-06-03 |
| 2. iOS Server Settings | v1.0 | 2/2 | Complete | 2026-06-03 |
| 3. iOS Upload Client | v1.0 | 3/3 | Complete | 2026-06-03 |
| 4. Upload Status Feedback | v1.0 | 2/2 | Complete | 2026-06-03 |
| 5. Upstream PR Integration | v1.0 | 4/4 | Complete | 2026-06-03 |
| 6. WHOOP Gen4 iOS Support | v2.0 | 3/3 | Complete | 2026-06-03 |
| 7. Android Port Foundations + CI | v2.0 | 4/4 | Complete | 2026-06-03 |
| 8. Additional Wearables E2E | v2.0 | 4/4 | Complete | 2026-06-03 |
| 8.1. Gap closure WEAR-01/WEAR-03 | v2.0 | 2/2 | Complete | 2026-06-04 |
| 9. BLE Stability & Data Integrity | v3.0 | 4/4 | Complete   | 2026-06-04 |
| 10. HR Monitor Scan/Connect UI | v3.0 | 0/? | Not started | - |
| 11. HR Monitor Independent Capture | v3.0 | 0/? | Not started | - |
| 12. WHOOP 4.0 RTC Clock Sync | v3.0 | 0/? | Not started | - |
| 13. Recovery V2 Dashboard | v3.0 | 0/? | Not started | - |
| 14. pt-PT Localisation | v3.0 | 0/? | Not started | - |

## Backlog

### Phase 999.4: Recovery V2 Completion (promoted to Phase 13 — v3.0)

Promoted to Phase 13: Recovery V2 Dashboard.

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
**Plans:** 4/4 plans complete

---

### Phase 999.2: Multi-Language Support (promoted to Phase 14 — v3.0)

Promoted to Phase 14: pt-PT Localisation.

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
