# Phase 3: iOS Upload Client - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 3-iOS Upload Client
**Areas discussed:** ATS/Hostname strategy, Upload cadence

---

## ATS / Hostname Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| DNS real (e.g. goose.meudominio.com) | HTTPS com certificado válido. ATS padrão. Funciona fora de casa. | |
| mDNS .local (e.g. meuserver.local) | Rede local com Bonjour. Requer NSBonjourServices + NSLocalNetworkUsageDescription. | ✓ |
| IP com HTTP (e.g. http://192.168.x.x) | Mais simples de configurar. Requer NSExceptionAllowsInsecureHTTPLoads. | |

**User's choice:** mDNS .local
**Notes:** O servidor é de uso local em casa — zero config DNS, iPhone descobre automaticamente na mesma rede WiFi. Clarificação inicial do utilizador: servidor é o mesmo que my-whoop, de uso local/backup.

---

## Upload Cadence

| Option | Description | Selected |
|--------|-------------|----------|
| Cada batch imediatamente (Recomendado) | Um POST por batch SQLite (~1s). Dados no servidor quase em real-time. | ✓ (por omissão) |
| Coalescer a cada 30s | 1 POST com dados de 30s. Menos requests, maior latência. | |

**User's choice:** Cada batch imediatamente (decisão por omissão — utilizador focou na topologia de rede)
**Notes:** Para servidor local com boa latência, 1 POST/segundo é razoável.

---

## Claude's Discretion

- Upload service architecture: GooseAppModel+Upload.swift com DispatchQueue dedicada
- Retry: 3x com backoff 1s/2s/4s (in-memory, sem persistência)
- Timeout URLSession: 15s por tentativa
- batch_id: não enviado (idempotência via ON CONFLICT no servidor)
- Logging: ble.record() com source "upload"

## Deferred Ideas

- Migração de dados my-whoop → servidor Goose (pg_dump/pg_restore após Phase 1 deployed)
- Background URLSession (UPLD-V2-02)
- Fila de retry persistida em SQLite (UPLD-V2-01)
