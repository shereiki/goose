# Goose — Servidor Remoto + Contribuições Upstream

## What This Is

Fork do `b-nnett/goose`: app iOS (SwiftUI + Rust core) que lê dados biométricos de dispositivos WHOOP via BLE.
Este milestone adiciona três capacidades ao fork: (1) servidor self-hosted FastAPI+TimescaleDB para armazenar dados biométricos, (2) upload automático desses dados do iOS para o servidor, (3) review e integração dos PRs abertos do upstream `b-nnett/goose`.

## Core Value

O utilizador deve poder capturar dados WHOOP no iPhone e tê-los persistidos automaticamente no seu servidor pessoal — sem depender de infraestrutura externa.

## Requirements

### Validated

- ✓ BLE GATT connection a dispositivos WHOOP 5.0 e 4.0 — existing
- ✓ Parsing de frames BLE via Rust core (libgoose_core) — existing
- ✓ Armazenamento local SQLite de frames capturados — existing
- ✓ Tabs Home / Health / Coach / More com SwiftUI — existing

### Active

- [ ] Servidor FastAPI + TimescaleDB copiado do my-whoop para `server/` no repo Goose
- [ ] Docker image (Dockerfile + docker-compose.yml) funcional no repo Goose
- [ ] GooseSwift envia dados decodificados ao servidor via POST /v1/ingest-decoded
- [ ] PRs do upstream avaliados, corrigidos e integrados no fork
- [ ] PRs de volta ao upstream b-nnett/goose com as correções

### Out of Scope

- Análise de dados no servidor (dashboard, alertas) — fora deste milestone
- Suporte Android — discutido no upstream mas fora do scope do fork agora
- Autenticação avançada (OAuth, 2FA) — Bearer token simples é suficiente

## Context

- **Fork**: `tigercraft4/goose` é fork de `https://github.com/b-nnett/goose`
- **Upstream open PRs (9)**: #1 (fix timeout/duration), #3 (FFI docs), #4 (scroll perf), #5 (Apple Health), #6 (Rust CI), #7 (list_methods RPC), #10 (CI + bug fixes), #12 (FFI threading), #13 (Windows compat)
- **Upstream open issues (4)**: #2 (Android discussion), #8 (WHOOP 4.0?), #9 (multiplatform), #11 (License + Gen4)
- **Servidor my-whoop**: já existe em `/Users/francisco/Documents/my-whoop/server/` — FastAPI, TimescaleDB, Dockerfile, docker-compose.yml
- **API do servidor**: `POST /v1/ingest-decoded` com Bearer token, recebe dados já decodificados
- **Upload iOS**: o GooseSwift já tem `remote_bind_enabled` como placeholder mas sem implementação de upload

## Constraints

- **Tech stack iOS**: Swift / SwiftUI / URLSession — não introduzir dependências externas
- **Tech stack servidor**: FastAPI + TimescaleDB (manter compatibilidade com my-whoop existente)
- **Git**: planning docs no git (commit_docs: true)
- **Servidor**: deve correr em Docker no servidor pessoal do utilizador

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Copiar servidor completo para server/ no Goose | Manter tudo num repo; facilitar deploy numa única operação git pull | — Pending |
| Upload via URLSession nativo | Sem dependências externas no iOS; URLSession é suficiente para POST JSON | — Pending |
| Bearer token simples para auth do servidor | Servidor pessoal/privado; overhead OAuth desnecessário | — Pending |

---
*Last updated: 2026-06-03 após inicialização*

## Evolution

Este documento evolui nas transições de fase e marcos de milestone.

**Após cada transição de fase** (via `/gsd-transition`):
1. Requirements invalidados? → Mover para Out of Scope com razão
2. Requirements validados? → Mover para Validated com referência de fase
3. Novos requirements emergidos? → Adicionar a Active
4. Decisões a registar? → Adicionar a Key Decisions
5. "What This Is" ainda preciso? → Atualizar se derivou

**Após cada milestone** (via `/gsd-complete-milestone`):
1. Revisão completa de todas as secções
2. Core Value check — ainda a prioridade certa?
3. Auditoria Out of Scope — razões ainda válidas?
4. Atualizar Context com estado atual
