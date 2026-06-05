---
phase: 18-coach-multi-provider
plan: 01
subsystem: ui
tags: [swift, swiftui, observable, coach, provider-protocol, chatgpt, asyncstream]

requires:
  - phase: 17-observable-migration
    provides: "@Observable @MainActor pattern established for GooseAppModel and HealthDataStore"

provides:
  - "CoachProvider protocol (D-06) with id/displayName/isAuthenticated/availablePresets/send/signOut"
  - "CoachProviderRegistry @Observable class persisting active provider to UserDefaults"
  - "CoachChatModel @Observable @MainActor with init(registry:) and send() routed through registry"
  - "ChatGPTCoachProvider wrapping CodexSelfContainedAuthClient + OpenAIResponsesClient behind protocol"
  - "CoachModelPreset extended with Claude (3 cases) and Gemini (2 cases) presets"
  - "Five Wave 0 XCTest stubs for Phases 18-01 through 18-04"

affects:
  - 18-02-ClaudeCoachProvider
  - 18-03-CustomEndpointCoachProvider
  - 18-04-GeminiCoachProvider
  - 18-05-CoachSettingsSheet

tech-stack:
  added: []
  patterns:
    - "CoachProvider: AnyObject protocol with AsyncStream<String> return from send() — each provider wraps SSE loop in AsyncStream continuation"
    - "CoachProviderRegistry @MainActor @Observable — registry pattern for multi-provider dispatch"
    - "toolContextProvider closure hook on ChatGPTCoachProvider — binds healthStore/appModel context before send()"
    - "@State private var registry = CoachProviderRegistry() + @State private var chat: CoachChatModel — @Observable init in explicit CoachView.init()"

key-files:
  created:
    - GooseSwift/CoachProviderProtocol.swift
    - GooseSwift/CoachChatModel.swift
    - GooseSwift/ChatGPTCoachProvider.swift
    - GooseSwiftTests/CoachProviderTests.swift
    - GooseSwiftTests/CoachProviderRegistryTests.swift
    - GooseSwiftTests/CoachKeychainTests.swift
    - GooseSwiftTests/ClaudeProviderTests.swift
    - GooseSwiftTests/CustomEndpointProviderTests.swift
  modified:
    - GooseSwift/CoachChatTypes.swift
    - GooseSwift/CoachView.swift
    - GooseSwift/CoachChatScreen.swift
    - GooseSwift/OpenAICoachChat.swift
    - GooseSwift.xcodeproj/project.pbxproj
    - GooseSwift.xcodeproj/xcshareddata/xcschemes/GooseSwift.xcscheme

key-decisions:
  - "ChatGPTCoachProvider uses toolContextProvider closure hook to bind live healthStore/appModel; avoids coupling protocol to GooseAppModel"
  - "CoachChatModel deinit removed (Swift @MainActor constraint); sendTask cancel handled via cancelStreaming() call-site"
  - "GooseSwiftTests test action added to GooseSwift scheme (was empty — tests were not runnable)"
  - "CoachProviderRegistryTests marked @MainActor to satisfy Swift concurrency requirement for @Observable initializer"

patterns-established:
  - "AsyncStream wrapping pattern: SSE loop inside AsyncStream { continuation in Task { ... } } — yielding text deltas"
  - "Provider isolation: tool calls stay internal to ChatGPTCoachProvider, not visible through CoachProvider protocol"
  - "System prompt injection: CoachLocalToolContext.build() serialised as JSON into systemPrompt for non-ChatGPT providers"

requirements-completed: [COACH-01, COACH-06]

duration: 14min
completed: 2026-06-06
---

# Phase 18 Plan 01: Coach Multi-Provider Foundation Summary

**CoachProvider protocol + registry + ChatGPTCoachProvider wrapping existing OAuth/streaming logic, with @Observable CoachChatModel dispatching through the registry**

## Performance

- **Duration:** 14 min
- **Started:** 2026-06-05T23:41:00Z
- **Completed:** 2026-06-06T00:55:00Z
- **Tasks:** 4 (Task 1: stubs, Task 2: protocol+registry, Task 3a: CoachChatModel, Task 3b: ChatGPTCoachProvider+call sites)
- **Files modified:** 11

## Accomplishments

- `CoachProvider` protocol (D-06) defined with exact six-member shape; `CoachProviderRegistry` @Observable persists active provider id to `goose.coach.activeProviderId`
- `OpenAICoachChatModel` (ObservableObject) fully replaced by `CoachChatModel` (@Observable @MainActor) with `init(registry:)` and `send()` routing through registry
- `ChatGPTCoachProvider` isolates all ChatGPT streaming logic (two-loop tool-call flow, SSE, auth) behind the protocol; existing Keychain token works without any user action (COACH-06)
- `CoachModelPreset` extended with 5 new cases (3 Claude + 2 Gemini) plus `claudeModelID`/`geminiModelID` computed properties; existing GPT cases preserved
- Five Wave 0 XCTest stubs created and compiling; GooseSwiftTests target added to scheme test action; `testRegistryPersistsActiveProviderID` green

## Task Commits

1. **Task 1: Wave 0 test stubs** - `a202681` (test)
2. **Task 2: CoachProvider protocol + CoachProviderRegistry + CoachModelPreset** - `ed000c6` (feat)
3. **Task 3a: CoachChatModel rename + @Observable conversion** - `a023c4b` (feat)
4. **Task 3b: ChatGPTCoachProvider + rewire call sites** - `fc03708` (feat)

## Files Created/Modified

- `GooseSwift/CoachProviderProtocol.swift` - CoachProvider protocol (D-06) + CoachProviderRegistry @Observable class
- `GooseSwift/CoachChatModel.swift` - @Observable @MainActor coordinator routing send() through registry
- `GooseSwift/ChatGPTCoachProvider.swift` - ChatGPT conformance wrapping existing OAuth + OpenAIResponsesClient
- `GooseSwift/CoachChatTypes.swift` - Extended CoachModelPreset with Claude/Gemini cases and model ID properties
- `GooseSwift/CoachView.swift` - @State registry + @State chat (explicit init); CoachProfileMenu updated
- `GooseSwift/CoachChatScreen.swift` - @ObservedObject removed; var chat: CoachChatModel
- `GooseSwift/OpenAICoachChat.swift` - Cleared (placeholder comment only)
- `GooseSwift.xcodeproj/project.pbxproj` - Added 3 app source files + 5 test files
- `GooseSwift.xcodeproj/xcshareddata/xcschemes/GooseSwift.xcscheme` - Added GooseSwiftTests test action
- `GooseSwiftTests/CoachProvider*.swift` + `GooseSwiftTests/Claude*.swift` + `GooseSwiftTests/Custom*.swift` - Wave 0 stubs

## Decisions Made

- **toolContextProvider closure**: `ChatGPTCoachProvider` exposes `var toolContextProvider: (() -> [String: Any])?` — bound by `CoachChatModel.send()` before calling the provider. This keeps `ChatGPTCoachProvider` free from direct `GooseAppModel`/`HealthDataStore` dependencies while enabling live tool context injection for ChatGPT's internal tool-call loop.
- **deinit removed from CoachChatModel**: Swift enforces that `@MainActor`-isolated properties (like `sendTask`) cannot be accessed from `deinit` (which is nonisolated). Cancellation is handled via `cancelStreaming()` at call sites.
- **Scheme test action**: The existing scheme had an empty `<Testables>` section. GooseSwiftTests was added so `xcodebuild test` works from the command line.
- **@MainActor on test class**: `CoachProviderRegistryTests` must be `@MainActor` because `CoachProviderRegistry.init()` and `selectProvider(id:)` are main-actor-isolated.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed deinit that accessed @MainActor property from nonisolated context**
- **Found during:** Task 3a (CoachChatModel)
- **Issue:** Swift 6 strict concurrency: `deinit` is nonisolated, cannot access `sendTask` which is main-actor-isolated
- **Fix:** Removed `deinit { sendTask?.cancel() }`, added `nonisolated func cancel()` as placeholder; cancellation handled at call sites via `cancelStreaming()`
- **Files modified:** GooseSwift/CoachChatModel.swift
- **Committed in:** a023c4b

**2. [Rule 1 - Bug] Added @MainActor to CoachProviderRegistryTests**
- **Found during:** Task 1/2 integration (test run)
- **Issue:** `CoachProviderRegistry()` and `selectProvider(id:)` are `@MainActor`-isolated; test class was nonisolated causing compile error
- **Fix:** Added `@MainActor` to `CoachProviderRegistryTests`
- **Files modified:** GooseSwiftTests/CoachProviderRegistryTests.swift
- **Committed in:** a202681

**3. [Rule 3 - Blocking] Added GooseSwiftTests to scheme test action**
- **Found during:** Task 2 verification
- **Issue:** `xcodebuild test -only-testing:GooseSwiftTests/...` failed with "scheme not configured for test action"
- **Fix:** Added `<TestableReference>` for `GooseSwiftTests` (blueprint `T50000000000000000000001`) to scheme's `<Testables>`
- **Files modified:** GooseSwift.xcodeproj/xcshareddata/xcschemes/GooseSwift.xcscheme
- **Committed in:** a202681

---

**Total deviations:** 3 auto-fixed (1 Bug, 1 Bug, 1 Blocking)
**Impact on plan:** All auto-fixes necessary for correctness and Swift 6 concurrency compliance. No scope creep.

## Issues Encountered

- iPhone 16 simulator not available on this machine — used iPhone 17 for all build/test commands (same SDK, no behavioural difference for this work)

## Known Stubs

None — all provider stub test files use `XCTSkip` to defer execution until the provider is implemented in later waves. The stubs compile and produce skipped-test output (not failures).

## Threat Flags

None — no new network endpoints, auth paths, or trust boundaries introduced beyond what was already in the plan's threat model. `ChatGPTCoachProvider` preserves existing `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` Keychain semantics via `CodexSelfContainedAuthClient`.

## Next Phase Readiness

- Wave 2 (`ClaudeCoachProvider`): protocol + registry stable; `ClaudeProviderTests` stub ready; `CoachProviderRegistry.allProviders` has a `// Wave 2-4: append here` comment
- Wave 3 (`CustomEndpointCoachProvider`): same — `CustomEndpointProviderTests` stub ready
- Wave 4 (`GeminiCoachProvider`): same — Gemini preset cases already in `CoachModelPreset`
- Wave 5 (`CoachSettingsSheet`): `selectModelPreset(_:)` on `CoachChatModel` ready; `CoachProviderRegistry.selectProvider(id:)` ready

## Self-Check: PASSED

- CoachProviderProtocol.swift: FOUND
- CoachChatModel.swift: FOUND
- ChatGPTCoachProvider.swift: FOUND
- CoachProviderTests.swift: FOUND
- CoachProviderRegistryTests.swift: FOUND
- 18-01-SUMMARY.md: FOUND
- Commit a202681 (test stubs): FOUND
- Commit ed000c6 (protocol+registry): FOUND
- Commit a023c4b (CoachChatModel): FOUND
- Commit fc03708 (ChatGPTCoachProvider): FOUND

---
*Phase: 18-coach-multi-provider*
*Completed: 2026-06-06*
