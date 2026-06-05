# Roadmap: Goose

## Milestones

- ✅ **v1.0 Remote Server + Upstream PRs** — Phases 1-5 (shipped 2026-06-03)
- ✅ **v2.0 Multi-Device & Platform Foundations** — Phases 6-8+8.1 (shipped 2026-06-04)
- ✅ **v3.0 Wearable UX, CI Hardening & RTC Sync** — Phases 9-15 (shipped 2026-06-05)
- 🚧 **v4.0 Security, Performance & Coach Expansion** — Phases 16+ (planning)

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

<details>
<summary>✅ v3.0 Wearable UX, CI Hardening & RTC Sync (Phases 9-15) — SHIPPED 2026-06-05</summary>

- [x] Phase 9: BLE Stability & Data Integrity (4/4 plans) — completed 2026-06-04
- [x] Phase 10: HR Monitor Scan/Connect UI (3/3 plans) — completed 2026-06-05
- [x] Phase 10.1: BLE Main-Thread Publishing Fix (1/1 plans) — completed 2026-06-05
- [x] Phase 11: HR Monitor Independent Capture (2/2 plans) — completed 2026-06-05
- [x] Phase 12: WHOOP 4.0 RTC Clock Sync (1/1 plans) — completed 2026-06-05
- [x] Phase 13: Recovery V2 Dashboard (1/1 plans) — completed 2026-06-05
- [x] Phase 14: pt-PT Localisation (4/4 plans) — completed 2026-06-05
- [x] Phase 15: Recovery Formula V2 SDNN (1/1 plans) — completed 2026-06-05

Full details: `.planning/milestones/v3.0-ROADMAP.md`

</details>

### 🚧 v4.0 Security, Performance & Coach Expansion (In Progress)

**Milestone Goal:** Block state-changing debug deep links (security), eliminate ObservableObject re-render overhead via @Observable migration (performance), and expand Coach to support multiple AI providers.

- [x] **Phase 16: Deep Link Security** — Block state-changing `gooseswift://` commands from external callers (PR #15) (completed 2026-06-05)
- [ ] **Phase 17: @Observable Migration** — Migrate GooseAppModel + HealthDataStore to @Observable, eliminate NavigationRequestObserver warnings
- [ ] **Phase 18: Coach Multi-Provider** — CoachProvider protocol, Claude + custom endpoint support, provider picker UI

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

**Plans**: 3 plans
**UI hint**: yes

Plans:

- [x] 10-01-PLAN.md — Promote HR monitor BLE state to @Published, add connecting/disconnect/fail handling, test scaffold
- [x] 10-02-PLAN.md — Build HRMonitorView (scan list, connect sheet, connected panel) + on-device verification
- [x] 10-03-PLAN.md — Wire HRMonitorView into the More tab Device section (MoreRoute.hrMonitor)

### Phase 10.1: BLE Main-Thread Publishing Fix (INSERTED)

**Goal:** All `@Published` property mutations in `GooseBLEClient+Commands.swift` and `GooseBLEClient+Parsing.swift` happen on the main thread, eliminating the runtime "Publishing changes from background threads" warnings produced by CoreBluetooth callbacks.
**Requirements**: BLE-MT-01, BLE-MT-02, BLE-MT-03
**Depends on:** Phase 10
**Plans:** 1/1 plans complete
**Success Criteria** (what must be TRUE):

  1. No "Publishing changes from background threads is not allowed" runtime warnings appear when the app is connected to a WHOOP or HR monitor
  2. `updateConnectionState`, `updateActiveDeviceName`, and all other `@Published`-mutating methods in `GooseBLEClient+Commands.swift` dispatch mutations to the main thread
  3. `GooseBLEClient+Parsing.swift` line 430 equivalent mutation is also dispatched to main thread
  4. No existing BLE behaviour or reconnect logic is broken

Plans:

- [x] 10.1-01-PLAN.md — Main-thread guards on all @Published mutators in GooseBLEClient+Commands.swift and +Parsing.swift; resolve duplicate updateReconnectState warning; cargo test -p goose-core gate

### Phase 11: HR Monitor Independent Capture

**Goal**: Users can run an HR monitor capture session without requiring an active WHOOP session
**Depends on**: Phase 9, Phase 10
**Requirements**: WEAR-06
**Success Criteria** (what must be TRUE):

  1. HR monitor frames are captured and stored when no WHOOP session is active
  2. HR monitor capture starts and stops independently of the WHOOP session lifecycle
  3. Captured HR monitor data (BPM and RR intervals) appears in the upload payload regardless of WHOOP session state

**Plans**: 2 plans

**Wave 1**

  - [x] 11-01-PLAN.md — Add .hrMonitor capture mode + startHRMonitorCapture/stopHRMonitorCapture without WHOOP gate (D-01, D-03)

**Wave 2** *(blocked on Wave 1 completion)*

  - [x] 11-02-PLAN.md — Auto-start/stop on hrConnectionState via onHRConnectionStateChange callback + D-04 upload verification + cargo test gate (D-02, D-04)

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

**Plans**: 4 plans
**UI hint**: yes

**Wave 1**

- [x] 14-01-PLAN.md — Infrastructure: create Localizable.xcstrings, register pt-PT in project.pbxproj, fix GooseAppTab.title + MoreRoute.title/subtitle to String(localized:), translate tab + More-route titles/subtitles (L10N-01)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 14-02-PLAN.md — Static catalog translations: Home dashboard, Health families (Recovery V2, Sleep V2, Cardio, Strain, Stress), Coach view (~150 strings) (L10N-01)

**Wave 3** *(blocked on Wave 2 completion — shared Localizable.xcstrings)*

- [x] 14-03-PLAN.md — Static catalog translations: More tab, Connection/Device/HR Monitor, Capture/Debug/Raw Export, Onboarding (~150 strings) (L10N-01)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 14-04-PLAN.md — LocalizedStatusStrings.swift (14 @Published display extensions, D-04) + display-site rewiring + MoreStatusKind.title + final sweep + xcodebuild verification (L10N-02)

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
| 9. BLE Stability & Data Integrity | v3.0 | 4/4 | Complete    | 2026-06-04 |
| 10. HR Monitor Scan/Connect UI | v3.0 | 3/3 | Complete    | 2026-06-04 |
| 10.1. BLE Main-Thread Publishing Fix | v3.0 | 1/1 | Complete    | 2026-06-04 |
| 11. HR Monitor Independent Capture | v3.0 | 2/2 | Complete    | 2026-06-05 |
| 12. WHOOP 4.0 RTC Clock Sync | v3.0 | 1/1 | Complete    | 2026-06-05 |
| 13. Recovery V2 Dashboard | v3.0 | 1/1 | Complete    | 2026-06-05 |
| 14. pt-PT Localisation | v3.0 | 4/4 | Complete    | 2026-06-05 |

## Backlog

### Phase 999.5: GooseAppModel @Observable Migration (BACKLOG)

**Goal:** Migrate `GooseAppModel` (and `HealthDataStore`) from `ObservableObject` + `@Published` to Swift's `@Observable` macro (iOS 17+), eliminating the global `objectWillChange` signal that causes all `@EnvironmentObject` observers to re-render on every property change regardless of which property was accessed.

**Why:** The residual `Update NavigationRequestObserver tried to update multiple times per frame` warning (3× at capture startup) is caused by `applyHealthPacketCaptureFamilySnapshot` making 3+ `@Published` writes in sequence, each firing `objectWillChange`. With `@Observable`, only views that access the specific changed property re-render — eliminating the spurious navigation observer updates entirely.

**What's needed:**

1. Replace `class GooseAppModel: ObservableObject` → `@Observable class GooseAppModel`
2. Remove all `@Published` annotations from `GooseAppModel` properties
3. Replace `@EnvironmentObject var model: GooseAppModel` → `@Environment(GooseAppModel.self) var model` in all views
4. Same migration for `HealthDataStore`
5. Remove `ObservedObject` wrappers for `ble: GooseBLEClient` where applicable

**Scope:** Large refactor (~150 files). Safe to defer — existing behaviour is correct, only performance of re-renders is affected.

**Requirements:** TBD
**Plans:** 4/4 plans complete

---

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

### Phase 15: Recovery Formula V2 (SDNN Accuracy)

**Goal:** Corrigir a fórmula `goose_recovery_v0` — renomear `hrvRmssdMs` para `hkHRVSDNNMs` para reflectir a métrica real da Apple Watch, remover a conversão `/1.2` (aproximação populacional SDNN→RMSSD), e normalizar os baselines directamente em SDNN para eliminar desvios individuais no score de recuperação. Inclui também a implementação de `rmssd_segment_aware` (cálculo fisiologicamente correcto de RMSSD a partir de RR intervals segmentados).
**Requirements**: TBD
**Depends on:** Phase 13
**Reference:** [OKKHALIL3 review comment — PR #5](https://github.com/b-nnett/goose/pull/5#discussion_r3359064144); [po-sc PR #19 commits 303f329 / rmssd_segment_aware](https://github.com/b-nnett/goose/pull/19#issuecomment-4632805440)
**Plans:** 1/1 plans complete

**Scope:**

1. `rmssd_segment_aware(segments: &[Vec<f64>], min_pairs: usize) -> Option<f64>` — implementar no `Rust/core/src/metrics.rs`. Calcula RMSSD apenas dentro de cada segmento (janela de captura), nunca entre janelas distintas. Inclui filtro de artefactos (banda 300–2000 ms, regra de Malik 20%). A ausência desta função no fork causa inflação de RMSSD quando existem múltiplas janelas de captura.
2. Unit tests cobrindo: banda fisiológica (300/2000 ms), regra de Malik (diferença relativa > 20% rejeita o par), invariante cross-window (beats de janelas diferentes nunca são diferenciados).
3. Renomear `hrvRmssdMs` → `hkHRVSDNNMs`, remover conversão `/1.2`, normalizar baselines em SDNN.

Plans:

- [x] TBD (run /gsd-plan-phase 15 to break down) (completed 2026-06-05)

---

### Phase 999.6: body_hex Storage Optimization (BACKLOG)

**Goal:** Eliminar o campo `body_hex` duplicado no cached parsed-payload JSON para frames grandes, reduzindo o tamanho da base de dados e acelerando o batch de métricas.

**Source:** Commit `3eef377` do po-sc (PR #19, [comentário de 2026-06-05](https://github.com/b-nnett/goose/pull/19#issuecomment-4632805440)). No upstream, este fix reduziu ~43 MB num DB de 147 MB no raw-motion stream e tornou o metric batch 27% mais rápido.

**What's needed:**

1. Verificar se o fork duplica `payload_hex` num campo `body_hex` no cached parsed-payload JSON para frames grandes (verificar `Rust/core/src/protocol.rs:515` e o comportamento do `parse_frame_batch` bridge).
2. Se confirmado: condicionar a inclusão de `body_hex` ao tamanho do frame ou a uma flag `include_body_hex` — excluir para frames de raw-motion (K10/K21) que são volumosos e cujo payload já está em `payload_hex`.
3. Medir impacto: comparar tamanho da DB e tempo do metric batch antes/depois.

**Why:** Frames de raw-motion gerados durante capture sessions podem crescer a centenas de MB em capturas longas. Remover a duplicação é uma quick-win de storage sem perda de dados.

**Requirements:** TBD
**Plans:** 0 plans — promote with `/gsd-review-backlog` when ready

---

### Phase 16: Deep Link Security

**Goal**: External apps and webpages cannot trigger state-changing WHOOP commands via the `gooseswift://` URL scheme
**Depends on**: Phase 15 (v3.0 complete)
**Requirements**: SEC-01
**Reference**: Upstream PR #15 (kobemartin — codex/block-state-change-debug-deep-links)
**Success Criteria** (what must be TRUE):

  1. Read-only debug commands (inspect, read) continue to work via deep link
  2. State-changing commands (Bluetooth writes, alarm set, sensor capture) are blocked when invoked from external URL scheme
  3. Remote URL examples hidden in UI for commands that cannot be safely invoked remotely

**Plans**: TBD

### Phase 17: @Observable Migration

**Goal**: GooseAppModel and HealthDataStore use Swift @Observable macro — only views that access a changed property re-render
**Depends on**: Phase 16
**Requirements**: PERF-01, PERF-02, PERF-03
**Success Criteria** (what must be TRUE):

  1. `class GooseAppModel: ObservableObject` → `@Observable class GooseAppModel` (all ~80 @Published removed)
  2. `class HealthDataStore: ObservableObject` → `@Observable class HealthDataStore`
  3. All views updated from `@EnvironmentObject var model` → `@Environment(GooseAppModel.self) var model`
  4. `Update NavigationRequestObserver tried to update multiple times per frame` no longer appears in logs during BLE capture

**Plans**: 4 plans (4 waves)
- [ ] 17-01-PLAN.md — Wave 1: GooseAppModel @Observable migration + @Environment rewire + MoreDataStore Combine removal
- [ ] 17-02-PLAN.md — Wave 2: HealthDataStore @Observable migration + @State ownership + @ObservedObject removal
- [ ] 17-03-PLAN.md — Wave 3: GooseBLEClient @Observable migration (NSObject kept) + MoreView onChange route status
- [ ] 17-04-PLAN.md — Wave 4: GooseSwiftApp injection sweep + full build verification + PERF-03 runtime check

### Phase 18: Coach Multi-Provider

**Goal**: Coach tab supports multiple AI providers and user-configured custom endpoints
**Depends on**: Phase 16
**Requirements**: COACH-01, COACH-02, COACH-03, COACH-04, COACH-05, COACH-06
**Success Criteria** (what must be TRUE):

  1. `CoachProvider` protocol exists — any conforming type can serve as the AI backend
  2. User can configure at least two providers (OpenAI + Claude) with named accounts in Keychain
  3. User can enter a custom OpenAI-compatible endpoint (base URL + API key + model) and use it for chat
  4. Provider picker UI in More/Coach settings shows configured accounts with add/remove/select
  5. Existing single OpenAI key is automatically migrated to a named account on first launch
  6. Streaming responses work for all supported providers

**Plans**: 6 plans (6 waves)

- [ ] 18-01-PLAN.md — Wave 1: CoachProvider protocol + CoachProviderRegistry + CoachChatModel refactor + ChatGPTCoachProvider + Wave 0 test stubs (COACH-01, COACH-06)
- [ ] 18-02-PLAN.md — Wave 2: ClaudeCoachProvider (Anthropic Messages API SSE + Keychain) (COACH-02, COACH-03)
- [ ] 18-03-PLAN.md — Wave 3: CustomEndpointCoachProvider (OpenAI Chat Completions SSE + URL validation + Keychain) (COACH-02, COACH-04)
- [ ] 18-04-PLAN.md — Wave 4: GeminiCoachProvider (Google OAuth PKCE via WKWebView + streamGenerateContent SSE) (COACH-02, COACH-03)
- [ ] 18-05-PLAN.md — Wave 5: CoachSettingsSheet provider picker UI + gear icon + four-provider registry (COACH-05)
- [ ] 18-06-PLAN.md — Wave 6: Integration, build/test verification, migration smoke test (COACH-01, COACH-05, COACH-06)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 9. BLE Stability & Data Integrity | v3.0 | 4/4 | Complete | 2026-06-04 |
| 10. HR Monitor Scan/Connect UI | v3.0 | 3/3 | Complete | 2026-06-05 |
| 10.1. BLE Main-Thread Publishing Fix | v3.0 | 1/1 | Complete | 2026-06-05 |
| 11. HR Monitor Independent Capture | v3.0 | 2/2 | Complete | 2026-06-05 |
| 12. WHOOP 4.0 RTC Clock Sync | v3.0 | 1/1 | Complete | 2026-06-05 |
| 13. Recovery V2 Dashboard | v3.0 | 1/1 | Complete | 2026-06-05 |
| 14. pt-PT Localisation | v3.0 | 4/4 | Complete | 2026-06-05 |
| 15. Recovery Formula V2 SDNN | v3.0 | 1/1 | Complete | 2026-06-05 |
| 16. Deep Link Security | v4.0 | 1/0 | Complete    | 2026-06-05 |
| 17. @Observable Migration | v4.0 | 4/4 | Complete | 2026-06-05 |
| 18. Coach Multi-Provider | v4.0 | 0/6 | Planned | - |
