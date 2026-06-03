# Phase 3: iOS Upload Client - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Implementar serviço de upload automático que, após cada batch SQLite confirmado (hook `handleCaptureFrameWriteResult` em `GooseAppModel+NotificationPipeline.swift`), lê os decoded streams do Rust bridge e envia via `POST /v1/ingest-decoded` ao servidor Goose com Bearer token, retry automático (3x, backoff 1s/2s/4s), e sem bloquear a thread principal.

O servidor corre na rede local de casa acessível via mDNS (e.g. `http://goose.local`).

</domain>

<decisions>
## Implementation Decisions

### ATS / Hostname Strategy
- **D-01:** O servidor Goose corre na rede local com hostname mDNS `.local` (e.g. `http://goose.local:8770`). Adicionar ao `Info.plist`:
  - `NSBonjourServices` com o serviço `_http._tcp.` (ou `_goose._tcp.` se preferido)
  - `NSLocalNetworkUsageDescription` com texto explicativo (e.g. "Goose usa a rede local para enviar dados WHOOP ao servidor pessoal")
  - O `NSAllowsLocalNetworking` já existe no Info.plist (para WebSocket debug) — confirmar que cobre HTTP local também.
- **D-02:** A URL pode ser `http://` (sem HTTPS) para servidor local. O ATS permite HTTP para redes locais com `NSAllowsLocalNetworking: true`.

### Upload Trigger
- **D-03:** Upload dispara em `handleCaptureFrameWriteResult` (chamado no `@MainActor` após cada batch SQLite confirmado com `pass == true` e sem `errorDescription`). Frequência: ~1 batch/segundo durante captura BLE activa.
- **D-04:** Não coalescer — enviar cada batch imediatamente. Servidor local com baixa latência aguenta 1 POST/segundo sem problema.

### Upload Service Architecture
- **D-05:** Criar `GooseUploadService` (ou `GooseAppModel+Upload.swift` seguindo o padrão extension). Usa `DispatchQueue(label: "com.goose.swift.upload", qos: .utility)` dedicada — padrão idêntico ao `CaptureFrameWriteQueue` e `OvernightSQLiteMirrorQueue`.
- **D-06:** Lê configurações (URL, token, toggle) das chaves definidas na Phase 2: `goose.remote.serverURL` (UserDefaults), `goose.remote.apiKey` (Keychain, service: `goose.remote`, account: `apiKey`), `goose.remote.uploadEnabled` (UserDefaults).
- **D-07:** Upload não ocorre se: `uploadEnabled == false`, URL não configurada, ou token Keychain ausente. Verificar estas condições antes de disparar cada upload.

### Payload Composition
- **D-08:** O payload de `/v1/ingest-decoded` é um `DecodedBatch` com:
  ```json
  {
    "device": {"id": "<BLE UUID>", "mac": null, "name": null},
    "streams": {"hr": [...], "rr": [...], "events": [...], "battery": [...], ...},
    "device_generation": "5.0" ou "4.0"
  }
  ```
- **D-09:** O `device.id` é o UUID do dispositivo BLE conectado — disponível em `GooseBLETypes` (`deviceID: UUID`). Converter para String com `uuidString`.
- **D-10:** Para obter os decoded streams do batch que acabou de ser confirmado: invocar um método Rust bridge (e.g. `upload.get_recent_batch` ou similar) que retorna as streams do último batch inserido. **Alternativa:** incluir os decoded frames já processados no `CaptureFrameWriteResult` ou passar-los directamente ao upload service. O planner deve investigar qual o método mais limpo para extrair streams pós-insert.
- **D-11:** `device_generation` deriva do tipo de dispositivo BLE identificado (`GooseBLETypes` — verificar se há campo `deviceType` ou `generation`).

### Retry Strategy
- **D-12:** Retry: 3 tentativas com backoff 1s/2s/4s (UPLD-04). In-memory apenas — sem persistência de retry para v1 (UPLD-V2-01 deferred).
- **D-13:** Falha após 3 tentativas: logar via `ble.record(level: .error, ...)` e descarte silencioso. Sem retry queue persistente em v1.

### Idempotência (batch_id)
- **D-14:** `batch_id` não é enviado no payload de `/v1/ingest-decoded` — o endpoint usa `ON CONFLICT (device_id, ts) DO UPDATE` por stream, garantindo idempotência implicitamente sem `batch_id` explícito. O `batch_id` em `raw_batches` é gerido pelo servidor internamente no endpoint `/v1/ingest` (não no `/v1/ingest-decoded`).

### Claude's Discretion
- Nome da queue: `"com.goose.swift.upload"` seguindo convenção reverse-DNS.
- Timeout URLSession: 15 segundos por tentativa (razoável para servidor local).
- Headers: `Authorization: Bearer {token}`, `Content-Type: application/json`.
- Logging: usar `ble.record(level: .debug, source: "upload", ...)` para sucesso e `level: .error` para falha final.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Endpoint do servidor (contrato de API)
- `/Users/francisco/Documents/my-whoop/server/ingest/app/main.py` §ingest_decoded (linha ~149) — contrato POST /v1/ingest-decoded, modelo DecodedBatch, DecodedDevice, DecodedStreams
- `/Users/francisco/Documents/my-whoop/server/ingest/app/main.py` §healthz — GET /healthz (usado na Phase 4)

### Ficheiros iOS a criar/modificar
- `GooseSwift/GooseAppModel+NotificationPipeline.swift` §handleCaptureFrameWriteResult — hook de upload (linha 256)
- `GooseSwift/GooseAppModel.swift` §captureFrameWriteQueue — instância da write queue
- `GooseSwift/CaptureFrameWriteQueue.swift` — estrutura `CaptureFrameWriteResult` (campos: batchCount, frameCount, inserted, pass)
- `GooseSwift/GooseBLETypes.swift` — `deviceID: UUID` e campo de geração do dispositivo
- `GooseSwift/Info.plist` — adicionar NSBonjourServices + NSLocalNetworkUsageDescription (NSAllowsLocalNetworking já existe)

### Contexto de fases anteriores
- `.planning/phases/02-ios-server-settings/02-CONTEXT.md` — chaves UserDefaults/Keychain (goose.remote.serverURL, goose.remote.uploadEnabled, goose.remote.apiKey)
- `.planning/phases/01-server-infrastructure/01-CONTEXT.md` — endpoint URL base, GOOSE_API_KEY como Bearer token

### Requisitos
- `.planning/REQUIREMENTS.md` §iOS Upload Client (UPLD-01 a UPLD-07)
- `.planning/ROADMAP.md` §Phase 3 — success criteria

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CaptureFrameWriteQueue` — padrão de queue serial + NSLock + DispatchQueue dedicada. Reutilizar este padrão para `GooseUploadService`.
- `OvernightSQLiteMirrorQueue` — padrão de queue background com retry e error logging. Relevante para retry strategy.
- `GooseRustBridge` — ponte FFI para obter dados do Rust core pós-insert.
- `ble.record(level:source:title:body:)` — logging estruturado já usado em todo o codebase.

### Established Patterns
- Background queue com label reverse-DNS: `DispatchQueue(label: "com.goose.swift.upload", qos: .utility)`.
- `@MainActor` para leitura de estado partilhado + dispatch para background queue para trabalho pesado.
- Extension files por concern: criar `GooseAppModel+Upload.swift` para a lógica de upload.
- Nunca chamar `GooseRustBridge` de `@MainActor` directamente — dispatch para background queue primeiro.

### Integration Points
- `GooseAppModel+NotificationPipeline.swift:handleCaptureFrameWriteResult` — adicionar chamada ao upload service após verificar `result.pass && result.errorDescription == nil`.
- `GooseAppModel` terá uma instância do upload service (ou o serviço será um singleton estático com instância no modelo).
- Phase 4 vai ler `lastUploadTimestamp` e `pendingBatchCount` do upload service para o feedback de status.

</code_context>

<specifics>
## Specific Ideas

- O servidor é de backup local, acedido via mDNS na rede WiFi de casa. Sem acesso externo.
- URLSession com `ephemeralSession()` ou `shared` — sem background session em v1 (deferred para v2).
- Migração de dados do my-whoop → servidor Goose: possível via `pg_dump`/`pg_restore` do TimescaleDB (mesma schema). Fora do scope desta fase — nota para depois de Phase 1 deployada.

</specifics>

<deferred>
## Deferred Ideas

- **Migração de dados my-whoop → servidor Goose**: `pg_dump` do TimescaleDB do my-whoop e `pg_restore` no Goose. Possível após a Phase 1 estar deployed. Fora do scope das fases actuais.
- **Background URLSession** (UPLD-V2-02): upload quando a app está suspensa — deferred para v2.
- **Fila de retry persistida em SQLite** (UPLD-V2-01): sobrevive ao restart da app — deferred para v2.

</deferred>

---

*Phase: 3-iOS Upload Client*
*Context gathered: 2026-06-03*
