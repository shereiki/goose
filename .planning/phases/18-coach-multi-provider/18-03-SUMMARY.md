---
phase: 18-coach-multi-provider
plan: 03
subsystem: coach
tags: [swift, custom-endpoint, openai-compatible, sse, keychain, url-validation, streaming]

requires:
  - phase: 18-coach-multi-provider
    plan: 01
    provides: "CoachProvider protocol, CoachProviderRegistry, CoachModelPreset, Wave 0 test stubs"
  - phase: 18-coach-multi-provider
    plan: 02
    provides: "ClaudeCoachProvider pattern: Keychain enum + CredentialStore facade + extractDelta internal method"

provides:
  - "CustomEndpointCoachProvider conforming to CoachProvider with OpenAI-compatible Chat Completions SSE streaming"
  - "CustomEndpointKeychain enum (service com.goose.swift.custom-endpoint, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)"
  - "CustomEndpointCredentialStore internal facade for testable Keychain access"
  - "CustomEndpointProviderError (invalidURL, missingAPIKey)"
  - "extractCustomDelta() internal SSE parser for choices[0].delta.content + [DONE] sentinel"
  - "validateBaseURL() delegating to RemoteServerURLValidator.validate() (T-18-07)"
  - "baseURL + modelID persisted in UserDefaults goose.coach.custom.baseURL / goose.coach.custom.modelID"
  - "Real assertions in CustomEndpointProviderTests and CoachKeychainTests (no more XCTSkip)"

affects:
  - 18-05-CoachSettingsSheet
  - 18-06-integration

tech-stack:
  added: []
  patterns:
    - "CustomEndpointKeychain private enum following RemoteServerKeychain + ClaudeKeychain pattern"
    - "CustomEndpointCredentialStore internal enum facade — allows @testable import GooseSwift to call Keychain in tests"
    - "validateBaseURL() as static func delegating to RemoteServerURLValidator.validate() — reuse, no duplication"
    - "extractCustomDelta(from:) internal method (not private) enabling unit testing without mocks"
    - "AsyncStream wrapping SSE: URLSession.shared.bytes(for:) + bytes.lines with [DONE] sentinel break"

key-files:
  created:
    - GooseSwift/CustomEndpointCoachProvider.swift
  modified:
    - GooseSwift.xcodeproj/project.pbxproj
    - GooseSwiftTests/CustomEndpointProviderTests.swift
    - GooseSwiftTests/CoachKeychainTests.swift

key-decisions:
  - "validateBaseURL() reuses RemoteServerURLValidator.validate() directly — not duplicated logic (T-18-07 mitigation via existing validator)"
  - "CustomEndpointKeychain marked private enum (not internal) — testability via CustomEndpointCredentialStore facade, matching ClaudeCoachProvider pattern"
  - "availablePresets returns [] for custom provider (D-04: single dynamic preset via modelID UserDefaults, not CoachModelPreset enum cases)"
  - "send() uses modelID from UserDefaults directly; preset parameter ignored for custom provider (documented in SUMMARY)"
  - "isAuthenticated requires BOTH Keychain key present AND validateBaseURL(baseURL) == true"
  - "signOut() clears Keychain AND both UserDefaults keys (baseURL + modelID)"
  - "CoachProviderRegistry not updated in Wave 3 — follows Wave 2 pattern; registry update deferred to Wave 5/6"

patterns-established:
  - "Custom endpoint [DONE] sentinel breaks SSE loop via explicit check before extractCustomDelta — avoids yielding nil deltas"
  - "buildRequest() trims trailing slash from baseURL before appending /v1/chat/completions"

requirements-completed: [COACH-02, COACH-04]

duration: 15min
completed: 2026-06-06
---

# Phase 18 Plan 03: CustomEndpointCoachProvider Summary

**CustomEndpointCoachProvider streaming OpenAI-compatible Chat Completions SSE with API key in Keychain (com.goose.swift.custom-endpoint) and base URL validated via RemoteServerURLValidator**

## Performance

- **Duration:** 15 min
- **Started:** 2026-06-06T10:58:00Z
- **Completed:** 2026-06-06T11:13:00Z
- **Tasks:** 2 (Task 1: Keychain + URL validation + config storage; Task 2: SSE streaming + delta extraction)
- **Files modified:** 4

## Accomplishments

- `CustomEndpointCoachProvider` fully conforms to `CoachProvider` with `id = "custom"`, empty preset list (D-04 custom uses `modelID` directly), `isAuthenticated`, `signOut()`, and `send()` returning `AsyncStream<String>`
- `CustomEndpointKeychain` stores API key in Keychain service `com.goose.swift.custom-endpoint` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (T-18-08 mitigation)
- URL validation via `RemoteServerURLValidator.validate()` — https required for non-local hosts, http allowed for localhost/private IPs (T-18-07 mitigation, V5 input validation)
- SSE streaming implemented via `URLSession.shared.bytes(for:)` + `bytes.lines`, `[DONE]` sentinel breaks the loop cleanly
- `extractCustomDelta(from:)` correctly parses `choices[0].delta.content` and returns nil for `[DONE]` and role-only deltas
- `CustomEndpointProviderTests` replaces XCTSkip with 3 real assertions: URL validation (3 cases), config persistence (baseURL + modelID), and SSE delta extraction (content, [DONE], role-only)
- `CoachKeychainTests.testCustomEndpointKeychainRoundtrip` replaces XCTSkip with real save/load/delete/nil assertions
- All 7 tests green: CustomEndpointProviderTests (3) + CoachKeychainTests (2) + ClaudeProviderTests (2)

## Task Commits

TDD commits:

1. **RED: Failing tests for URL validation + Keychain + SSE delta** - `725acf5` (test)
2. **GREEN: CustomEndpointCoachProvider implementation** - `375424f` (feat)

## Files Created/Modified

- `GooseSwift/CustomEndpointCoachProvider.swift` - CustomEndpointKeychain (private), CustomEndpointCredentialStore (internal facade), CustomEndpointProviderError, CustomEndpointCoachProvider (228 lines)
- `GooseSwift.xcodeproj/project.pbxproj` - CustomEndpointCoachProvider.swift registered in PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase
- `GooseSwiftTests/CustomEndpointProviderTests.swift` - 3 real test methods (XCTSkip removed)
- `GooseSwiftTests/CoachKeychainTests.swift` - testCustomEndpointKeychainRoundtrip real assertions (XCTSkip removed); tearDown extended to clean custom endpoint Keychain

## Decisions Made

- **`availablePresets = []`**: D-04 specifies custom provider uses a single dynamic preset from the user model ID. Since `CoachModelPreset` is a fixed enum, the custom provider returns `[]` and `send()` ignores the `preset` parameter, reading `modelID` from UserDefaults directly.
- **`validateBaseURL()` as static delegation**: Rather than duplicating `RemoteServerURLValidator.validate()` logic, `CustomEndpointCoachProvider.validateBaseURL()` is a thin `static func` that calls the validator directly. This is the test's stable entry point (acceptance criterion) and the security mitigation for T-18-07.
- **`CustomEndpointKeychain` as private enum**: Keeps the Keychain implementation out of the module's internal surface. `CustomEndpointCredentialStore` is the internal facade for tests, consistent with the `ClaudeCredentialStore` pattern from Wave 2.
- **`CoachProviderRegistry` not updated**: Wave 2 (`ClaudeCoachProvider`) did not add itself to the registry either. Registry wiring is handled in Wave 5 (`CoachSettingsSheet`) or Wave 6 (integration). This maintains plan consistency.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Worktree missing Wave 1 and Wave 2 files — merged b641560 before starting**
- **Found during:** Initial setup
- **Issue:** The worktree branch was at `a6bf1e1` (research docs), before the Wave 1 and Wave 2 merge commits. `CoachProvider` protocol, test stubs, and `ClaudeCoachProvider` were absent.
- **Fix:** `git merge b641560 --no-edit` fast-forwarded the worktree to include all Wave 1 and Wave 2 commits.
- **Files modified:** All Wave 1 and Wave 2 files now present in worktree.
- **Impact:** No code changes required; working state restored before implementation.

---

**Total deviations:** 1 auto-fixed (Blocking — worktree sync)
**Impact on plan:** All tasks proceeded as planned after sync. No scope creep.

## Issues Encountered

- iPhone 16 simulator not available on this machine — used iPhone 17 for all build/test commands (same SDK, no behavioural difference)
- First `build-for-testing` attempt used cached DerivedData that did not include the new file; used `-derivedDataPath /tmp/goose-18-03-dd` for a clean build

## Known Stubs

None — all Wave 3 test assertions are real. `testRegistryExposesAllFourProviders` in `CoachProviderRegistryTests` retains XCTSkip because `CustomEndpointCoachProvider` is not yet registered in `CoachProviderRegistry` (deferred to Wave 5/6 per plan).

## Threat Flags

None — implementation fully covers:
- T-18-07 (Tampering: base URL validated via RemoteServerURLValidator — https for non-local hosts)
- T-18-08 (Information Disclosure: API key only in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; never in UserDefaults, never in error strings)

## Self-Check: PASSED

- GooseSwift/CustomEndpointCoachProvider.swift: FOUND (228 lines)
- GooseSwiftTests/CustomEndpointProviderTests.swift: FOUND (XCTSkip removed, 3 real assertions)
- GooseSwiftTests/CoachKeychainTests.swift: FOUND (testCustomEndpointKeychainRoundtrip real)
- Commit 725acf5 (RED test stubs): FOUND
- Commit 375424f (GREEN implementation): FOUND
- grep RemoteServerURLValidator.validate: 1 match
- grep com.goose.swift.custom-endpoint: 2 matches
- grep goose.coach.custom.baseURL/modelID: 2 matches
- grep /v1/chat/completions: 1 match
- grep [DONE]: 2 matches
- Tests CustomEndpointProviderTests (3) + CoachKeychainTests (testCustomEndpointKeychainRoundtrip): PASSED

---
*Phase: 18-coach-multi-provider*
*Completed: 2026-06-06*
