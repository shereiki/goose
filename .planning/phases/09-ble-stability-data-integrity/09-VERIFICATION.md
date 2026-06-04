---
phase: 09-ble-stability-data-integrity
verified: 2026-06-04T22:30:00Z
status: human_needed
score: 14/14 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Forcar desconexao do WHOOP e confirmar reconexao com backoff exponencial na ConnectionView"
    expected: "Fila 'Reconnect' mostra 'reconnecting (attempt N/10)' com N a incrementar com atrasos que dobram (1s, 2s, 4s... ate 60s); apos 10 tentativas, aparece 'failed after 10 attempts' com botao 'Try Again'; 'Stop Reconnecting' cancela o ciclo sem esquecer o dispositivo e nenhuma tentativa adicional e executada apos Stop"
    why_human: "Comportamento de temporizadores BLE e cancelamento de DispatchWorkItem requerem hardware WHOOP real ou simulador BLE; nao e verificavel estaticamente via grep"
  - test: "Forcar desconexao do monitor HR e confirmar reconexao com backoff exponencial na ConnectionView"
    expected: "Fila 'HR Reconnect' mostra 'reconnecting (attempt N/10)' com N a incrementar; apos 10 tentativas, aparece mensagem de falha com botao 'Retry HR Reconnect'; Stop HR Reconnect cancela sem nova tentativa; WHOOP e HR operam de forma independente"
    why_human: "Requer segundo dispositivo BLE (monitor HR); o checkpoint Task 3 do plano 04 foi aprovado por revisao de codigo sem hardware HR disponivel"
  - test: "Verificar que a compactacao de armazenamento aparece no Event Log quando a base de dados tem mais de 24 MB de raw_evidence"
    expected: "Entrada no Event Log 'Storage compacted: N rows, X MB freed' aparece ao lancar a aplicacao quando existem dados acima do limite; nenhuma entrada aparece quando ja esta abaixo do limite"
    why_human: "Requer base de dados com dados reais acima de 24 MB; nao e verificavel estaticamente"
---

# Phase 09: BLE Stability & Data Integrity — Verification Report

**Phase Goal:** Fix 5 open defects (FIX-01..FIX-05) identified in the upstream review — FFI panic safety, WHOOP reconnect backoff, HR monitor reconnect backoff, device ID propagation, and storage compaction
**Verified:** 2026-06-04T22:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | A Rust panic inside FFI dispatch returns a JSON error object instead of aborting the process | VERIFIED | `catch_unwind(AssertUnwindSafe(...))` wrap em `goose_bridge_handle_json` (bridge.rs linha 2736); teste `bridge_panic_catch_returns_error_json_and_normal_requests_still_succeed` passa |
| 2 | The bridge exposes storage.compact_raw_evidence which returns a compaction report | VERIFIED | Match arm em bridge.rs linha 2661; `storage_compact_raw_evidence_bridge` em linha 5840; teste `bridge_compact_raw_evidence_reduces_storage_and_is_noop_when_already_below_limit` passa |
| 3 | Compaction is a no-op (compacted_rows = 0) when the database is already below the byte limit | VERIFIED | Confirmado por segundo passo do teste compaction (compacted_rows == 0 na segunda chamada) |
| 4 | After a capture batch import that supplies active_device_id, the capture session row stores that non-NULL device id | VERIFIED | `CapturedFrameBatchOptions.active_device_id` em capture_import.rs linha 87; `set_capture_session_device_id` atualiza `capture_sessions`; teste `batch_import_with_active_device_id_stores_non_null_device_id_in_capture_session` passa |
| 5 | Existing capture imports that omit active_device_id still succeed (backward compatible) with active_device_id remaining NULL | VERIFIED | `#[serde(default)]` em `CaptureImportFrameBatchArgs`; teste `batch_import_without_active_device_id_leaves_session_device_id_null` passa |
| 6 | The upload bridge still returns HR monitor frames filtered by device_type (no JOIN regression) | VERIFIED | `grep -n 'JOIN capture_sessions' Rust/core/src/bridge.rs` retorna vazio; regressao em `upload_device_type_filter_hr_frames_are_stored_separate_from_goose_frames` |
| 7 | After a WHOOP disconnection, the app retries with exponential backoff (1s base, doubles, 60s cap) and stops after 10 attempts | VERIFIED | `struct ReconnectBackoff` com `nextDelay()` formula `min(1.0 * 2^attemptCount, 60.0)`, `maxAttempts = 10`; `scheduleNextReconnect` e `cancelReconnectCycle` em GooseBLEClient+Commands.swift |
| 8 | ConnectionView shows the reconnect attempt count and a failure message after 10 attempts | VERIFIED | `LabeledContent("Reconnect", value: ble.reconnectState)` exibe `reconnectBackoff.statusString`; `Text("Reconnection failed after 10 attempts...")` presente em ConnectionView.swift linha 61 |
| 9 | User can tap Try Again to restart reconnection and Stop to abort without forgetting the device | VERIFIED | `stopReconnect()` nao limpa `rememberedDeviceID` (confirmado por grep); `retryReconnect()` reseta backoff e chama `scheduleNextReconnect`; botoes em ConnectionView.swift linhas 52-62 |
| 10 | A scheduled retry does NOT fire after Stop/success/manual retry — cancellation via DispatchWorkItem + generation token | VERIFIED | `reconnectGeneration` incrementado em `cancelReconnectCycle()`; guard `self.reconnectGeneration == generation` dentro do `DispatchWorkItem` (GooseBLEClient+Commands.swift linha 720) |
| 11 | D-09: Storage compaction triggered at launch in GooseAppModel and after each write in CaptureFrameWriteQueue | VERIFIED | `DispatchQueue.global(qos: .utility).async` chama `runStorageCompactionIfNeeded()` em GooseAppModel.swift linha 384; chamada silenciosa em CaptureFrameWriteQueue.swift linha 330; limite 25_165_824 em ambos |
| 12 | CaptureFrameWriteQueue passes active_device_id (peripheral UUID) into capture.import_frame_batch | VERIFIED | `activeDeviceID: String?` (lock-protected via `stateLock`); arg `"active_device_id": activeDeviceID ?? NSNull()` em CaptureFrameWriteQueue.swift linha 289 |
| 13 | After an HR monitor disconnection, the manager retries with the same exponential backoff as WHOOP | VERIFIED | `GooseBLEHRMonitorManager` tem `reconnectBackoff = ReconnectBackoff()` (mesmo tipo); `scheduleNextHRReconnect`/`cancelHRReconnectCycle` espelham o padrao WHOOP; `callbackQueue` armazenado em `start(queue:)` |
| 14 | A scheduled HR retry does NOT fire after Stop/success/manual retry — cancellation via DispatchWorkItem + generation token on the HR manager | VERIFIED | `hrReconnectGeneration` incrementado em `cancelHRReconnectCycle()`; guard `self.hrReconnectGeneration == generation` dentro do `DispatchWorkItem` (GooseBLEClient+HRMonitor.swift linha 51); `pendingHRPeripheral` capturado antes de `hrPeripheral = nil` |

**Score:** 14/14 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Rust/core/Cargo.toml` | `panic = "unwind"` em `[profile.release]` | VERIFIED | Linha 161; `panic = "abort"` ausente (grep confirma 0 ocorrencias) |
| `Rust/core/src/bridge.rs` | `catch_unwind` wrap + `storage.compact_raw_evidence` + `#[cfg(debug_assertions)] test.panic` | VERIFIED | catch_unwind linha 2736; compact arm linha 2661; test.panic arm linha 2674 com atributo linha 2673 |
| `Rust/core/tests/bridge_tests.rs` | Testes de panic-catch e compaction | VERIFIED | 2 testes passam: panic e compact |
| `Rust/core/src/capture_import.rs` | `active_device_id` em `CapturedFrameBatchOptions` | VERIFIED | Linha 87; propagacao via `set_capture_session_device_id` apos o loop de frames |
| `GooseSwift/GooseBLEReconnect.swift` | `struct ReconnectBackoff` com nextDelay(), reset(), statusString | VERIFIED | 27 linhas; todos os campos e metodos presentes; formula correta |
| `GooseSwift/GooseBLEClient+Commands.swift` | `scheduleNextReconnect`, `cancelReconnectCycle`, `stopReconnect`, `retryReconnect` | VERIFIED | Todos presentes; cancelReconnectCycle chamado em didConnect, BT-off, Stop, e retryReconnect |
| `GooseSwift/GooseBLEClient+CentralDelegate.swift` | `cancelReconnectCycle` no ramo BT power-off | VERIFIED | Linha 87 (BT-off), linha 177 (connect-failed), linha 189 (connect-success) |
| `GooseSwift/CaptureFrameWriteQueue.swift` | `active_device_id` arg + compaction pos-escrita | VERIFIED | `activeDeviceID` property lock-protected; arg linha 289; compact linha 330 com limite 25_165_824 |
| `GooseSwift/GooseAppModel.swift` | `runStorageCompactionIfNeeded` chamado no lancamento | VERIFIED | DispatchQueue.global wrapping em linha 384; metodo privado em linha 417 |
| `GooseSwift/GooseBLEClient+HRMonitor.swift` | Backoff HR com `reconnectBackoff`, `callbackQueue`, `hrReconnectWorkItem`, `hrReconnectGeneration`, `pendingHRPeripheral` | VERIFIED | Todos os campos presentes; `let disconnectedPeripheral = peripheral` antes de nil (Pitfall 4) na linha 162 |
| `GooseSwift/GooseBLEClient.swift` | `@Published hrReconnectState`, `hrIsReconnecting`, `hrReconnectFailed`, forwarders `stopHRReconnect`/`retryHRReconnect` | VERIFIED | Linhas 24, 957, 961, 971, 975 |
| `GooseSwift/ConnectionView.swift` | "Stop Reconnecting", "Try Again", "HR Reconnect" row, "Stop HR Reconnect", "Retry HR Reconnect" | VERIFIED | Todos os textos presentes; botoes WHOOP linhas 52-62; HR row linha 24; HR botoes linhas 67-76 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `goose_bridge_handle_json` | `handle_bridge_request_json` | `catch_unwind(AssertUnwindSafe(...))` | WIRED | bridge.rs linha 2736 |
| `storage.compact_raw_evidence match arm` | `store.compact_raw_evidence_payloads_to_limit` | `storage_compact_raw_evidence_bridge` | WIRED | bridge.rs linhas 2661-2665; fn linha 5840 |
| `CaptureImportFrameBatchArgs.active_device_id` | `CapturedFrameBatchOptions.active_device_id` | `capture_import_frame_batch_bridge` com `as_deref()` | WIRED | bridge.rs linha 5827 |
| `CapturedFrameBatchOptions.active_device_id` | `capture_sessions.active_device_id` | `store.set_capture_session_device_id` apos frame loop | WIRED | capture_import.rs linhas 310-315 |
| `GooseBLEClient.attemptAutomaticReconnect` | `ReconnectBackoff.nextDelay()` | `scheduleNextReconnect` via `DispatchWorkItem` | WIRED | GooseBLEClient+Commands.swift linha 710 |
| `GooseBLEClient.stopReconnect / retryReconnect / didConnect` | `DispatchWorkItem + reconnectGeneration` | `cancelReconnectCycle()` | WIRED | GooseBLEClient+Commands.swift linhas 700-703, 731, 741 |
| `ConnectionView` | `GooseBLEClient.stopReconnect / retryReconnect` | `Button` actions | WIRED | ConnectionView.swift linhas 52-62 |
| `GooseAppModel.runStorageCompactionIfNeeded` | `storage.compact_raw_evidence` bridge | `rust.request` em background queue | WIRED | GooseAppModel.swift linhas 384-385, 417-423 |
| `CaptureFrameWriteQueue capture.import_frame_batch args` | `activeDeviceID (peripheral UUID)` | `activeDeviceID` property (lock-protected) | WIRED | CaptureFrameWriteQueue.swift linha 289 |
| `GooseBLEHRMonitorManager.didDisconnectPeripheral` | `ReconnectBackoff.nextDelay()` | `scheduleNextHRReconnect` via `DispatchWorkItem` em `callbackQueue` | WIRED | GooseBLEClient+HRMonitor.swift linhas 37-57 |
| `GooseBLEHRMonitorManager.hrStopReconnect / hrRetryReconnect / didConnect` | `hrReconnectWorkItem + hrReconnectGeneration` | `cancelHRReconnectCycle()` | WIRED | GooseBLEClient+HRMonitor.swift linhas 31-34, 63, 76 |
| `ConnectionView` | `GooseBLEClient.hrReconnectState / stopHRReconnect / retryHRReconnect` | `LabeledContent` + `Button` actions | WIRED | ConnectionView.swift linhas 24, 67-76 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `ConnectionView` Reconnect row | `ble.reconnectState` | `updateReconnectState()` chamado dentro do `DispatchWorkItem` BLE | Sim — `reconnectBackoff.statusString` com contagem real de tentativas | FLOWING |
| `ConnectionView` HR Reconnect row | `ble.hrReconnectState` | `owner?.updateHRReconnectState()` dentro do `DispatchWorkItem` HR | Sim — `reconnectBackoff.statusString` da instancia independente HR | FLOWING |
| `CaptureFrameWriteQueue` import args | `active_device_id` | `activeDeviceID` property definida via `GooseAppModel` ao conectar | Sim — UUID string do peripheral CoreBluetooth; `NSNull()` quando nil (backward compat) | FLOWING |
| `GooseAppModel` event log | `compacted_rows`, `freed_bytes` | `rust.request("storage.compact_raw_evidence")` no lançamento | Sim — dados reais da base de dados SQLite via Rust bridge | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Panic em FFI retorna JSON error em vez de abortar | `cargo test --test bridge_tests -- panic` | 1 passed; 0 failed | PASS |
| Normal request nao e afetado por catch_unwind | Incluido no mesmo teste (regressao core.version) | ok | PASS |
| Compaction reduz storage acima do limite | `cargo test --test bridge_tests -- compact` | 1 passed; 0 failed | PASS |
| Segunda compaction e no-op quando ja abaixo do limite | Incluido no mesmo teste | ok | PASS |
| active_device_id armazenado como nao-NULL na capture_session | `cargo test --test capture_import_tests -- device_id` | 2 passed; 0 failed | PASS |
| Suite Rust completa sem regressoes | `cargo test` (todas as suites) | 0 failed em todas as suites | PASS |

### Probe Execution

Nenhum probe convencional (scripts/tests/probe-*.sh) definido para esta fase.

### Requirements Coverage

| Requirement | Plano(s) | Descricao | Status | Evidencia |
|-------------|----------|-----------|--------|----------|
| FIX-01 | 09-01, 09-02, 09-03 | HR monitor frames stored with correct non-NULL device_id | SATISFIED | `active_device_id` em bridge args, CapturedFrameBatchOptions, set via store.set_capture_session_device_id; Swift propaga peripheral UUID |
| FIX-02 | 09-03 | WHOOP BLE reconnect com exponential backoff + manual retry/stop | SATISFIED (human_needed) | ReconnectBackoff, scheduleNextReconnect, ConnectionView buttons — comportamento runtime requer verificacao humana |
| FIX-03 | 09-04 | HR monitor BLE reconnect com mesmo backoff WHOOP | SATISFIED (human_needed) | GooseBLEHRMonitorManager com backoff identico, callbackQueue, ConnectionView HR row — requer hardware HR para verificar |
| FIX-04 | 09-01 | Rust FFI com catch_unwind + panic=unwind | SATISFIED | panic=unwind em [profile.release]; catch_unwind em goose_bridge_handle_json; teste passa |
| FIX-05 | 09-01, 09-03 | Raw evidence retention limitada a 24 MB | SATISFIED | storage.compact_raw_evidence bridge method; chamado no lancamento (GooseAppModel) e apos cada escrita (CaptureFrameWriteQueue); limite 25_165_824 em ambos os sites |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (nenhum encontrado) | — | — | — | — |

Sem marcadores TBD/FIXME/XXX nos ficheiros modificados. Sem stub patterns. Sem `return null`/`return []` em caminhos de dados.

### Human Verification Required

#### 1. WHOOP Reconnect Backoff UI (FIX-02)

**Test:** Forcar desconexao do WHOOP (desligar a banda ou sair do alcance). Abrir ConnectionView. Observar a fila "Reconnect" durante multiplas tentativas. Deixar chegar ate 10 tentativas. Testar Stop e Try Again. Testar reconexao bem-sucedida a meio de um ciclo ativo.

**Expected:**
- Primeira tentativa ~1s apos desconexao (nao imediatamente)
- Atrasos subsequentes dobram: 1s, 2s, 4s, 8s, 16s, 32s, 60s (cap)
- Apos 10 tentativas: fila mostra "failed after 10 attempts", botao "Try Again" aparece com mensagem de falha
- "Try Again" reinicia o ciclo a partir da tentativa 1
- "Stop Reconnecting" retorna ao estado "idle", oculta os botoes, dispositivo recordado mantem-se (nao e esquecido)
- Nenhuma tentativa adicional e executada apos Stop (token de geracao suprime o DispatchWorkItem ja agendado)
- Reconexao bem-sucedida a meio de um ciclo suprime qualquer tentativa pendente

**Why human:** Temporizadores BLE e comportamento de DispatchWorkItem cancelado nao sao verificaveis estaticamente; requer hardware WHOOP e observacao em tempo real

#### 2. HR Monitor Reconnect Backoff UI (FIX-03)

**Test:** Forcar desconexao do monitor HR. Abrir ConnectionView. Observar a fila "HR Reconnect" durante multiplas tentativas. Testar todos os controlos.

**Expected:**
- Mesmos parametros de backoff que o WHOOP (1s base, duplica, cap 60s, 10 tentativas)
- Apos 10 tentativas: "Retry HR Reconnect" aparece com mensagem de falha
- "Stop HR Reconnect" cancela e suprime tentativas pendentes
- WHOOP e HR operam de forma independente com controlos separados

**Why human:** Requer segundo dispositivo BLE (monitor HR); o checkpoint Task 3 do plano 04 foi aprovado por revisao de codigo sem hardware HR disponivel

#### 3. Storage Compaction Event Log (FIX-05)

**Test:** Com base de dados contendo mais de 24 MB de raw_evidence, reiniciar a aplicacao e verificar o Event Log.

**Expected:** Entrada "Storage compacted: N rows, X MB freed" aparece no Event Log apenas quando foram compactadas linhas; nada aparece quando ja esta abaixo do limite

**Why human:** Requer base de dados com dados reais acima de 24 MB para acionar o caminho de log

### Gaps Summary

Nenhum gap encontrado. Todos os 14 must-haves verificados contra o codebase. Todas as ligacoes criticas estao presentes e ligadas. Suite Rust completa a passar sem regressoes.

O status `human_needed` deve-se a tres itens de verificacao comportamental que nao sao verificaveis estaticamente: o comportamento dos temporizadores BLE em tempo real para reconexao WHOOP (FIX-02), reconexao HR (FIX-03) e a log de compactacao que requer dados reais acima do limite (FIX-05). Estes sao verificacoes de runtime legitimas que foram explicitamente identificadas como checkpoints humanos nos planos.

---

_Verified: 2026-06-04T22:30:00Z_
_Verifier: Claude (gsd-verifier)_
