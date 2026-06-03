---
created: 2026-06-03T20:22:25.964Z
title: Add Test and Import actions to Remote Server settings
area: ui
files:
  - GooseSwift/MoreRemoteServerViews.swift
  - GooseSwift/GooseAppModel+Upload.swift
  - GooseSwift/GooseUploadService.swift
---

## Problem

The Remote Server section (More > Remote Server) only has:
- Enable Upload toggle
- Status row (server reachability, last sync + Now button, pending batches)

Missing two actions:
1. **Test** — User wants to explicitly verify the connection works (not just the background /healthz). Should test both reachability AND auth (attempt an authenticated read to confirm the API key is valid).
2. **Import** — User wants to pull historical data stored on the server back into the iOS app / local SQLite (reverse of upload). Useful when onboarding a new device or after data loss. Calls the server's read API (`GET /v1/devices/{id}/streams`) and ingests via Rust bridge.

## Solution

**Test button:**
- Tap → runs `GET /healthz` then `GET /v1/counts` (or similar auth-gated endpoint)
- Shows inline result: "Connection OK — server responding, auth valid" or specific error
- Distinct from the background health check (which only runs once per session)

**Import button:**
- Tap → prompts for date range (or defaults to "last 30 days")
- Calls `GET /v1/streams?device=<id>&start=<ts>&end=<ts>` for each stream type (hr, rr, events, battery...)
- Feeds fetched data into the Rust bridge via the existing bridge methods (e.g. `upload.ingest_decoded_streams`)
- Shows progress: "Importing... 12,450 HR samples, 800 RR intervals" → "Import complete"
- Handles auth errors, network errors, and empty responses gracefully

Both actions live in the `Section("Status")` block of `MoreRemoteServerView`, below the existing status rows, only visible when `uploadIsActive` is true.
