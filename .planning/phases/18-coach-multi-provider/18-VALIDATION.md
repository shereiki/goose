---
phase: 18
slug: coach-multi-provider
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-06
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Config file** | `GooseSwiftTests/` target in `GooseSwift.xcodeproj` |
| **Quick run command** | `xcodebuild build -scheme GooseSwift -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 \| grep -c 'error:' \| { read n; [ "$n" -eq 0 ] && echo 'BUILD OK' || echo "BUILD ERRORS: $n"; }` |
| **Full suite command** | `xcodebuild test -scheme GooseSwift -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 \| tail -5` |
| **Estimated runtime** | ~90 seconds (build) / ~5 minutes (full test) |

---

## Sampling Rate

- **After every task commit:** `xcodebuild build` — zero errors
- **After every plan wave:** `xcodebuild test` full suite green
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 90 seconds (build check)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | COACH-01 | Protocol compiles with all 4 conformances | unit (compile) | `xcodebuild build` succeeds | ❌ Wave 0 | ⬜ pending |
| 18-01-02 | 01 | 1 | COACH-01 | AsyncStream<String> emits strings from send() | unit | `GooseSwiftTests/CoachProviderTests.swift` | ❌ Wave 0 | ⬜ pending |
| 18-01-03 | 01 | 1 | COACH-06 | Registry.init() finds existing ChatGPT auth and sets activeProvider | unit | `GooseSwiftTests/CoachProviderRegistryTests.swift` | ❌ Wave 0 | ⬜ pending |
| 18-02-01 | 02 | 2 | COACH-02 | Claude Keychain save/load/delete roundtrip | unit | `GooseSwiftTests/CoachKeychainTests.swift` | ❌ Wave 0 | ⬜ pending |
| 18-02-02 | 02 | 2 | COACH-03 | ClaudeCoachProvider SSE delta extraction (mocked response) | unit | `GooseSwiftTests/ClaudeProviderTests.swift` | ❌ Wave 0 | ⬜ pending |
| 18-03-01 | 03 | 3 | COACH-04 | CustomEndpointCoachProvider URL validation rejects http:// external hosts | unit | `GooseSwiftTests/CustomEndpointProviderTests.swift` | ❌ Wave 0 | ⬜ pending |
| 18-04-01 | 04 | 4 | COACH-02 | GeminiCoachProvider sign-in flow completes, token stored in Keychain | manual | In-app: sign in with Google, send message, confirm response | — | ⬜ pending |
| 18-05-01 | 05 | 5 | COACH-05 | CoachSettingsSheet renders without crash | manual | `xcodebuild build` + SwiftUI preview | — | ⬜ pending |
| 18-06-01 | 06 | 6 | COACH-05 | Existing ChatGPT key migrates to named account on first launch | manual | Cold launch with legacy key in Keychain | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `GooseSwiftTests/CoachProviderTests.swift` — stubs for COACH-01 (protocol compile + AsyncStream shape)
- [ ] `GooseSwiftTests/CoachKeychainTests.swift` — stubs for COACH-02 (Claude + Custom Keychain roundtrip)
- [ ] `GooseSwiftTests/ClaudeProviderTests.swift` — stubs for COACH-03 (SSE delta parsing)
- [ ] `GooseSwiftTests/CustomEndpointProviderTests.swift` — stubs for COACH-04 (URL validation)
- [ ] `GooseSwiftTests/CoachProviderRegistryTests.swift` — stubs for COACH-06 (migration detection)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Gemini OAuth sign-in flow | COACH-02 | Requires real Google OAuth token and network | Open CoachSettingsSheet, tap "Sign in with Google", complete OAuth, send a message, confirm streamed response |
| Streaming response end-to-end | COACH-06 | Requires live API key and network connection | Configure each provider (Claude, Custom), send a message, confirm tokens stream in real time |
| Migration smoke test | COACH-05 | Requires Keychain with legacy ChatGPT key | Cold launch app with existing ChatGPT key, open Coach tab, confirm existing sessions still work |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
