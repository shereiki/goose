---
phase: 18-coach-multi-provider
plan: 04
subsystem: coach
tags: [swift, gemini, google-oauth, pkce, wkwebview, keychain, sse, streaming, coach-provider]

requires:
  - phase: 18-coach-multi-provider
    plan: 01
    provides: "CoachProvider protocol, CoachProviderRegistry, CoachChatModel, CoachModelPreset Gemini cases"

provides:
  - "GeminiCoachProvider @MainActor @Observable conforming to CoachProvider with streamGenerateContent SSE"
  - "GeminiStoredToken Codable struct with needsRefresh logic (expiresAt<60s or updatedAt>50min)"
  - "GeminiKeychain enum (service com.goose.swift.gemini, account oauth-token, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)"
  - "GeminiKeychainStore internal facade for testable Keychain access"
  - "PKCE helpers: generateCodeVerifier (64 random bytes, base64url) + codeChallenge (SHA256/S256)"
  - "GeminiOAuthWebView UIViewRepresentable + WKNavigationDelegate intercepting gooseswift:// redirect"
  - "extractGeminiDelta() nonisolated SSE parser for candidates[0].content.parts[0].text"
  - "CoachProviderRegistry updated to include all four providers (ChatGPT, Claude, Custom, Gemini)"

affects:
  - 18-05-CoachSettingsSheet
  - 18-06-integration

tech-stack:
  added: []
  patterns:
    - "GeminiKeychain enum following CodexSelfContainedAuthKeychain pattern: baseQuery + save (SecItemDelete+SecItemAdd) + load (SecItemCopyMatching) + delete"
    - "GeminiKeychainStore internal enum facade for @testable import GooseSwift access in unit tests"
    - "PKCE S256: SHA256.hash via CryptoKit + base64url (replace +→-, /→_, strip =) — nonisolated static methods"
    - "GeminiOAuthWebView UIViewRepresentable with Coordinator: WKNavigationDelegate.decidePolicyFor intercepts url.scheme == 'gooseswift'"
    - "AsyncStream wrapping SSE: URLSession.shared.bytes(for:) + bytes.lines async iteration inside AsyncStream { continuation in Task { ... } }"
    - "ephemeral URLSession (httpShouldSetCookies=false, httpCookieAcceptPolicy=.never) for token exchange"
    - "formURLEncoded via URLComponents.queryItems + percentEncodedQuery for OAuth token POST"
    - "nonisolated on static PKCE helpers and extractGeminiDelta — allows unit tests without @MainActor awaiting"
    - "@MainActor @Observable GeminiCoachProvider with isExchangingToken state for sheet lifecycle (Pitfall 5)"

key-files:
  created:
    - GooseSwift/GeminiCoachProvider.swift
    - GooseSwift/GeminiOAuthWebView.swift
    - GooseSwiftTests/GeminiProviderTests.swift
  modified:
    - GooseSwift/CoachProviderProtocol.swift
    - GooseSwift.xcodeproj/project.pbxproj

decisions:
  - "GeminiCoachProvider is @MainActor @Observable (matches CoachChatModel and CoachProviderRegistry; isExchangingToken drives sheet lifecycle)"
  - "PKCE helpers and extractGeminiDelta are nonisolated — pure functions with no actor state; enables synchronous XCTest access without async ceremony"
  - "GeminiKeychainStore internal enum facade exposes save/load/delete for tests (mirrors ClaudeCredentialStore pattern from Wave 2)"
  - "CoachProviderRegistry updated in Wave 4 (not Wave 5) — registry must include Gemini before CoachSettingsSheet wires the picker"
  - "Live OAuth + streaming end-to-end test deferred to Plan 18-06 Task 2 — entry point (CoachSettingsSheet) ships in Wave 5"
  - "OAuth scope uses https://www.googleapis.com/auth/generative-language (not .retriever) per CONTEXT.md D-02 and Pitfall 3"

metrics:
  duration: "~58 minutes"
  completed: "2026-06-06"
  tasks: 3
  files: 4
---

# Phase 18 Plan 04: GeminiCoachProvider Summary

GeminiCoachProvider with Google OAuth 2.0 PKCE flow via WKWebView + streamGenerateContent SSE streaming + Keychain token storage.

## Tasks

### Task 1: Gemini token model + Keychain + PKCE + WKWebView OAuth wrapper

**Status:** COMPLETE — RED + GREEN in one commit (98227d8)

Created `GeminiCoachProvider.swift` and `GeminiOAuthWebView.swift` with:
- `GeminiStoredToken: Codable` struct with `needsRefresh` (expiresAt within 60s, or updatedAt older than 50 min)
- `GeminiKeychain` private enum storing JSON-encoded token in Keychain (`com.goose.swift.gemini`/`oauth-token`)
- `GeminiKeychainStore` internal facade for testable access
- PKCE helpers: `generateCodeVerifier()` (64 random bytes, base64url) and `codeChallenge(for:)` (CryptoKit SHA256, base64url)
- `GeminiOAuthWebView` UIViewRepresentable with `WKNavigationDelegate` Coordinator intercepting `gooseswift://oauth/gemini` redirect

`GeminiProviderTests.swift` created with 5 tests: `testNeedsRefreshWithinWindow`, `testCodeChallengeIsBase64URL`, `testGeminiKeychainRoundtrip`, `testGeminiDeltaExtraction`, `testAvailablePresets`.

All 5 tests pass.

### Task 2: GeminiCoachProvider streaming + token exchange/refresh + protocol conformance

**Status:** COMPLETE — all code in same commit as Task 1 (98227d8)

The full `GeminiCoachProvider` was implemented in Task 1 to make tests compile. Key components:
- `send()` builds POST to `streamGenerateContent?alt=sse` with `Authorization: Bearer` and Gemini message format (`systemInstruction` + `contents` with `"model"` role)
- `handleRedirect(code:codeVerifier:)` exchanges authorization code for tokens via `oauth2.googleapis.com/token` form-encoded POST
- `validToken()` loads Keychain token, refreshes via `refresh_token` grant when `needsRefresh`
- `extractGeminiDelta(from:)` parses `data:` SSE lines extracting `candidates[0].content.parts[0].text`
- Scope uses `https://www.googleapis.com/auth/generative-language` (NOT `.retriever` — Pitfall 3)

### Task 3: Build-only verification that GeminiCoachProvider compiles and conforms

**Status:** COMPLETE — commit b9b0ff0

- `CoachProviderRegistry` updated to include `GeminiCoachProvider()` alongside ChatGPT, Claude, Custom
- `xcodebuild build` → **BUILD SUCCEEDED** with zero `error:` lines
- `xcodebuild test -only-testing:GooseSwiftTests/GeminiProviderTests` → **TEST SUCCEEDED** (5/5 pass)
- `grep generative-language.retriever` → zero matches (correct scope confirmed)

**Live OAuth + streaming end-to-end is deferred to Plan 18-06 Task 2** — the entry point (`CoachSettingsSheet` provider sign-in flow) ships in Wave 5. No human interaction required for this wave.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] @MainActor isolation prevents synchronous test access**
- **Found during:** Task 1 verification (test compilation)
- **Issue:** `GeminiCoachProvider` is `@MainActor @Observable`. Methods `generateCodeVerifier()`, `codeChallenge(for:)`, and `extractGeminiDelta(from:)` were actor-isolated, blocking synchronous `XCTestCase` calls.
- **Fix:** Marked PKCE static helpers and `extractGeminiDelta` as `nonisolated` (pure functions with no actor state). Marked the test class `@MainActor` for `init()` and `availablePresets` access.
- **Files modified:** `GooseSwift/GeminiCoachProvider.swift`, `GooseSwiftTests/GeminiProviderTests.swift`
- **Commit:** 98227d8

**2. [Rule 2 - Missing critical functionality] CoachProviderRegistry missing GeminiCoachProvider registration**
- **Found during:** Task 3 review
- **Issue:** The registry comment said "Wave 2-4: append here" but Wave 2 and Wave 3 had not added their providers (left for Wave 5). However, Gemini needed to be registered for the phase to be complete.
- **Fix:** Updated `CoachProviderRegistry.init()` to instantiate and include all four providers: ChatGPT, Claude, Custom, Gemini.
- **Files modified:** `GooseSwift/CoachProviderProtocol.swift`
- **Commit:** b9b0ff0

## Threat Surface Scan

| Flag | File | Description |
|------|------|-------------|
| T-18-10 mitigated | GeminiCoachProvider.swift | PKCE S256 implemented via CryptoKit SHA256; state param should be added in Wave 5 UI |
| T-18-11 mitigated | GeminiCoachProvider.swift | Token stored only in Keychain (com.goose.swift.gemini) with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; client_id in UserDefaults (non-secret) |
| T-18-12 mitigated | GeminiCoachProvider.swift | signOut() deletes Keychain entry; no in-memory token reference survives beyond validToken() call scope |
| T-18-SC mitigated | — | Zero external packages; CryptoKit, Security, WebKit are native iOS frameworks |

Note: `state` parameter for CSRF protection is not wired in the WKNavigationDelegate redirect check. The Wave 5 `CoachSettingsSheet` will generate and verify the state parameter when presenting the `GeminiOAuthWebView`.

## Self-Check: PASSED

- [x] `GooseSwift/GeminiCoachProvider.swift` — exists (created)
- [x] `GooseSwift/GeminiOAuthWebView.swift` — exists (created)
- [x] `GooseSwiftTests/GeminiProviderTests.swift` — exists (created)
- [x] `GooseSwift/CoachProviderProtocol.swift` — modified (GeminiCoachProvider registered)
- [x] Commit 98227d8 exists (test + implementation)
- [x] Commit b9b0ff0 exists (registry + verification)
- [x] `xcodebuild build` → BUILD SUCCEEDED (zero errors)
- [x] `xcodebuild test -only-testing:GeminiProviderTests` → TEST SUCCEEDED (5/5)
- [x] Live OAuth + streaming end-to-end deferred to Plan 18-06 Task 2 (documented)
