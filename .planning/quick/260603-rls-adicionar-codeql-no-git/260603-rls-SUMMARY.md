---
status: complete
quick_id: 260603-rls
slug: adicionar-codeql-no-git
description: adicionar codeql no git
date: 2026-06-03
commit: 13e3498
---

# Quick Task 260603-rls: adicionar codeql no git

## Result

Created `.github/workflows/codeql.yml` — CodeQL static analysis for Swift and Python.

## What Was Done

- **Matrix job**: `swift` (macos-15) + `python` (ubuntu-latest)
- **Triggers**: push/PR to `main` + weekly Monday 08:00 UTC + `workflow_dispatch`
- **Swift analysis**: builds `GooseSwift.xcodeproj` with `CODE_SIGNING_ALLOWED=NO` for real compilation (required for data-flow analysis)
- **Python analysis**: no build step needed for FastAPI/server code
- **Queries**: `security-extended` (OWASP Top 10 + iOS/Python platform patterns)
- **Permissions**: `security-events: write` (SARIF upload), `actions: read`, `contents: read`
- **Rust excluded**: experimental CodeQL support; `cargo-audit` + `trivy` already cover Rust advisories
- **Schedule staggered** 1h after `security.yml` (08:00 vs 07:00 UTC) to avoid CI congestion

## Files Changed

| File | Action |
|------|--------|
| `.github/workflows/codeql.yml` | Created (69 lines) |

## Commit

`13e3498` — ci(security): add CodeQL workflow for Swift and Python analysis
