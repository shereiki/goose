---
status: testing
phase: 18-coach-multi-provider
source: [18-VERIFICATION.md]
started: 2026-06-06T13:49:00Z
updated: 2026-06-06T13:49:00Z
---

## Current Test

number: 1
name: COACH-06 migration smoke test (no re-auth on cold launch)
expected: |
  ChatGPT is the active provider, shows "Signed in" status, no re-authentication required.
  Sending a message produces a streaming reply.
awaiting: user response

## Tests

### 1. COACH-06 Migration Smoke Test

expected: Cold-launch app with existing ChatGPT OAuth token in Keychain. ChatGPT is active provider, shows "Signed in", no re-auth required. Message streams.
result: [pending]

### 2. Claude Streaming End-to-End

expected: Enter Anthropic API key in Claude config, save, send message. Streaming reply from api.anthropic.com/v1/messages arrives.
result: [pending]

### 3. Custom Endpoint Streaming End-to-End

expected: Enter HTTPS base URL + API key + model ID in Custom config, save, send message. Streaming reply from {baseURL}/v1/chat/completions arrives.
result: [pending]

### 4. Gemini OAuth + Streaming

expected: Enter Google Client ID, complete OAuth in WKWebView, send message. Streaming reply from Google Generative Language API arrives. If no Client ID available, record as "deferred".
result: [pending]

### 5. Provider Switching

expected: Authenticate two providers, switch between them, each backend responds correctly. No cross-provider credential leakage.
result: [pending]

### 6. ChatGPT Sign-In Button in Settings Sheet

expected: Tapping "Sign in with ChatGPT" in CoachSettingsSheet initiates the sign-in flow. (Currently: button action is empty — sign-in only works via chat sheet.)
result: [pending]

### 7. UI-SPEC Conformance

expected: CoachSettingsSheet rendered UI matches 18-UI-SPEC.md design specification.
result: [pending]

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0
blocked: 0

## Gaps
