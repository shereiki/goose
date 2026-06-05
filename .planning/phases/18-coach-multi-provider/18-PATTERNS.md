# Phase 18: Coach Multi-Provider — Pattern Map

**Mapped:** 2026-06-06
**Files analyzed:** 9 (6 new, 3 modified)
**Analogs found:** 9 / 9

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `GooseSwift/CoachProviderProtocol.swift` | protocol + registry | request-response | `GooseSwift/GooseAppModel.swift` (`@Observable`) + `GooseSwift/CoachChatTypes.swift` (type conventions) | role-match |
| `GooseSwift/OpenAICoachChat.swift` → `CoachChatModel` | model (coordinator) | request-response + streaming | `GooseSwift/OpenAICoachChat.swift` itself — refactor in place | exact |
| `GooseSwift/OpenAICoachResponsesClient.swift` → `ChatGPTCoachProvider` | service (streaming client) | streaming (SSE) | `GooseSwift/OpenAICoachResponsesClient.swift` itself — wrap in place | exact |
| `GooseSwift/ClaudeCoachProvider.swift` | service (streaming client) | streaming (SSE) | `GooseSwift/OpenAICoachResponsesClient.swift` — same URLSession.bytes + bytes.lines SSE pattern | role-match |
| `GooseSwift/CustomEndpointCoachProvider.swift` | service (streaming client) | streaming (SSE) | `GooseSwift/OpenAICoachResponsesClient.swift` — OpenAI-compatible SSE, same structure | role-match |
| `GooseSwift/GeminiCoachProvider.swift` | service (streaming + OAuth) | streaming (SSE) + event-driven (OAuth) | `GooseSwift/CodexEmbeddedAuth.swift` (OAuth pattern) + `GooseSwift/OpenAICoachResponsesClient.swift` (SSE) | role-match |
| `GooseSwift/CoachChatTypes.swift` (modify) | types | — | `GooseSwift/CoachChatTypes.swift` itself | exact |
| `GooseSwift/CoachChatScreen.swift` (modify) | view | request-response | `GooseSwift/CoachChatScreen.swift` itself + `GooseSwift/CoachView.swift` (toolbar pattern) | exact |
| `GooseSwift/CoachSettingsSheet.swift` | view (settings sheet) | request-response | `GooseSwift/CoachView.swift` (`CoachProfileMenu`, sheet wiring) + `GooseSwift/RemoteServerPersistence.swift` (URL validation) | role-match |

---

## Pattern Assignments

### `GooseSwift/CoachProviderProtocol.swift` (protocol + registry, request-response)

**Analogs:** `GooseSwift/GooseAppModel.swift` (lines 6–7 for `@Observable` class), `GooseSwift/CoachChatTypes.swift` (enum + DefaultsKey conventions)

**Imports pattern** — copy from `GooseSwift/CoachChatTypes.swift` (line 1):
```swift
import Foundation
```
No additional imports; the protocol and registry use only Foundation types. `@Observable` is in Swift standard library from Swift 5.9+.

**@Observable class pattern** — copy from `GooseSwift/GooseAppModel.swift` (lines 6–7):
```swift
@MainActor @Observable
final class GooseAppModel {
```
Apply identically to `CoachProviderRegistry`:
```swift
@MainActor @Observable
final class CoachProviderRegistry {
```

**UserDefaults key convention** — copy from `GooseSwift/OpenAICoachChat.swift` (line 13):
```swift
private static let modelPresetDefaultsKey = "goose.coach.modelPreset"
```
Use the same dot-namespaced reverse-DNS pattern:
```swift
private static let activeProviderDefaultsKey = "goose.coach.activeProviderId"
```

**Protocol shape** — locked in CONTEXT.md D-06; no codebase analog exists yet (first protocol of this kind). Shape:
```swift
protocol CoachProvider: AnyObject {
  var id: String { get }
  var displayName: String { get }
  var isAuthenticated: Bool { get }
  var availablePresets: [CoachModelPreset] { get }
  func send(
    messages: [CoachChatMessage],
    systemPrompt: String,
    preset: CoachModelPreset
  ) async throws -> AsyncStream<String>
  func signOut()
}
```

---

### `GooseSwift/OpenAICoachChat.swift` → refactored to `CoachChatModel` (model, streaming)

**Analog:** `GooseSwift/OpenAICoachChat.swift` (entire file — refactor in place)

**ObservableObject → @Observable migration pattern** — copy from `GooseSwift/GooseAppModel.swift` (lines 6–7) and apply:

Before (lines 3–12 of `OpenAICoachChat.swift`):
```swift
@MainActor
final class OpenAICoachChatModel: ObservableObject {
  @Published private(set) var isSignedIn = false
  @Published private(set) var deviceCode: CodexLoginDeviceCode?
  @Published private(set) var loginStatus = "Not signed in"
  @Published private(set) var modelPreset: CoachModelPreset
  @Published private(set) var messages: [CoachChatMessage] = []
  @Published private(set) var streamState: CoachStreamState = .idle
  @Published private(set) var errorMessage: String?
```

After (drop `ObservableObject`, drop `@Published`, keep `private(set)`):
```swift
@MainActor @Observable
final class CoachChatModel {
  private(set) var messages: [CoachChatMessage] = []
  private(set) var streamState: CoachStreamState = .idle
  private(set) var errorMessage: String?
  // auth state moves into registry / active provider
```

**sendTask cancellation pattern** — copy from `OpenAICoachChat.swift` (lines 156–185):
```swift
sendTask?.cancel()
sendTask = Task { [weak self] in
  guard let self else { return }
  do {
    // ... stream call
    finishAssistantMessage(assistantID)
    streamState = .idle
  } catch is CancellationError {
    markAssistantMessageCancelled(assistantID)
    streamState = .idle
  } catch where isCancelledError(error) {
    markAssistantMessageCancelled(assistantID)
    streamState = .idle
  } catch {
    let message = describe(error)
    appendAssistantText("\n\(message)", to: assistantID)
    finishAssistantMessage(assistantID)
    errorMessage = message
    streamState = .failed(message)
  }
}
```

**Error description helper** — copy from `OpenAICoachChat.swift` (lines 605–613):
```swift
private func describe(_ error: Error) -> String {
  if isCancelledError(error) {
    return "Generation stopped."
  }
  if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
    return description
  }
  return String(describing: error)
}

private func isCancelledError(_ error: Error) -> Bool {
  if let urlError = error as? URLError {
    return urlError.code == .cancelled
  }
  let nsError = error as NSError
  return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
}
```

**Call-site updates required alongside this refactor:**
- `GooseSwift/CoachView.swift` line 7: `@StateObject private var chat = OpenAICoachChatModel()` → `@State private var chat = CoachChatModel()`
- `GooseSwift/CoachChatScreen.swift` line 4: `@ObservedObject var chat: OpenAICoachChatModel` → `var chat: CoachChatModel` (no wrapper for `@Observable`)
- `GooseSwift/CoachView.swift` line 632: `CoachProfileMenu` — `@ObservedObject var chat` → `var chat: CoachChatModel`

---

### `GooseSwift/ClaudeCoachProvider.swift` (service, streaming SSE)

**Analog:** `GooseSwift/OpenAICoachResponsesClient.swift` (lines 153–243)

**Imports pattern** — same as `OpenAICoachResponsesClient.swift` (line 1):
```swift
import Foundation
import Security
```

**SSE streaming core pattern** — copy from `OpenAIResponsesClient.swift` (lines 183–205), adapt for `AsyncStream<String>` return:
```swift
// OpenAIResponsesClient.swift lines 183–204 — the established SSE pattern
let (bytes, response) = try await URLSession.shared.bytes(for: request)
guard let httpResponse = response as? HTTPURLResponse else {
  throw OpenAIResponsesError.invalidResponse
}
guard (200..<300).contains(httpResponse.statusCode) else {
  let body = try await readErrorBody(from: bytes)
  throw OpenAIResponsesError.httpStatus(httpResponse.statusCode, body)
}

for try await line in bytes.lines {
  try Task.checkCancellation()
  let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmedLine.hasPrefix("data:") {
    let value = String(trimmedLine.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
    // parse value and yield delta
  }
}
```

**AsyncStream wrapping pattern** — `send()` wraps the SSE loop inside `AsyncStream { continuation in Task { ... } }`. This is new infrastructure (no codebase analog yet), but follows the Swift Concurrency `AsyncStream` init pattern directly.

**URLRequest construction pattern** — copy from `OpenAIResponsesClient.swift` (lines 173–182):
```swift
var request = URLRequest(url: endpoint)
request.httpMethod = "POST"
request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
request.setValue("goose-swift", forHTTPHeaderField: "originator")
request.httpBody = bodyData
request.timeoutInterval = 180
```
Adapt headers for Claude: use `x-api-key`, `anthropic-version: 2023-06-01` instead.

**JSON body serialization** — copy from `OpenAIResponsesClient.swift` (lines 168–171):
```swift
guard JSONSerialization.isValidJSONObject(body) else {
  throw OpenAIResponsesError.invalidRequestBody
}
let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
```
`JSONSerialization` not `JSONEncoder` — providers use `[String: Any]` mixed-type dicts (established pattern).

**Keychain helper** — copy from `GooseSwift/RemoteServerPersistence.swift` (lines 57–109), adapt service/account:
```swift
// RemoteServerPersistence.swift lines 57–109 — minimal API key Keychain pattern
enum RemoteServerKeychain {
  private static let service = "goose.remote"
  private static let account = "apiKey"

  static func saveToken(_ token: String) throws {
    let data = Data(token.utf8)
    let query = baseQuery()
    SecItemDelete(query as CFDictionary)
    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else { throw RemoteServerKeychainError.saveFailed(status) }
  }

  static func loadToken() throws -> String? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status != errSecItemNotFound else { return nil }
    guard status == errSecSuccess else { throw RemoteServerKeychainError.saveFailed(status) }
    guard let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func deleteToken() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw RemoteServerKeychainError.deleteFailed(status)
    }
  }

  private static func baseQuery() -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }
}
```
For `ClaudeCoachProvider`: use `service = "com.goose.swift.claude"`, `account = "api-key"` (D-02).
Inline as a private `enum ClaudeKeychain` inside `ClaudeCoachProvider.swift` (same file — matching the `CodexSelfContainedAuthKeychain` co-location pattern from `CodexEmbeddedAuth.swift` lines 373–439).

**Error type pattern** — copy from `OpenAICoachResponsesClient.swift` (lines 15–42):
```swift
enum OpenAIResponsesError: Error, LocalizedError {
  case missingOAuthSession
  case invalidURL
  case invalidRequestBody
  case invalidResponse
  case httpStatus(Int, String)
  case api(String)

  var errorDescription: String? { ... }
}
```
Create `ClaudeProviderError` following same shape.

---

### `GooseSwift/CustomEndpointCoachProvider.swift` (service, streaming SSE)

**Analog:** `GooseSwift/OpenAICoachResponsesClient.swift` (lines 153–243) + `GooseSwift/RemoteServerPersistence.swift` (lines 9–41 for URL validation)

**Same SSE + URLRequest pattern** as `ClaudeCoachProvider` above — only headers and delta extraction differ.

**URL validation** — copy from `RemoteServerPersistence.swift` (lines 9–41):
```swift
// RemoteServerPersistence.swift lines 9–41 — reuse or call this directly
enum RemoteServerURLValidator {
  static func validate(_ raw: String) -> Bool {
    guard let components = URLComponents(string: raw),
          let scheme = components.scheme,
          (scheme == "http" || scheme == "https"),
          let host = components.host,
          !host.isEmpty else {
      return false
    }
    let isNumericIP = host.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil
    if isNumericIP { return isPrivateIP(host) }
    let isLocalHost = host == "localhost" || host.hasSuffix(".local")
    if isLocalHost { return true }
    return scheme == "https"
  }
  // ...
}
```
`CustomEndpointCoachProvider` calls `RemoteServerURLValidator.validate(baseURL)` before building the request. No need to duplicate this logic.

**UserDefaults for non-secret config** — copy from `OpenAICoachChat.swift` (line 13) for the key pattern:
```swift
private static let modelPresetDefaultsKey = "goose.coach.modelPreset"
```
Custom endpoint non-secret config:
```swift
static let baseURLKey = "goose.coach.custom.baseURL"
static let modelIDKey = "goose.coach.custom.modelID"
```
API key goes in Keychain with `service = "com.goose.swift.custom-endpoint"`, `account = "api-key"` (D-02).

---

### `GooseSwift/GeminiCoachProvider.swift` (service, streaming SSE + OAuth)

**Analogs:** `GooseSwift/CodexEmbeddedAuth.swift` (OAuth token lifecycle pattern, lines 137–340) + `GooseSwift/OpenAICoachResponsesClient.swift` (SSE pattern)

**`actor` vs `final class` for auth client** — `CodexSelfContainedAuthClient` uses `actor` (line 137) for thread safety during OAuth. `GeminiCoachProvider` implements `CoachProvider` protocol which requires `AnyObject` — use `@MainActor @Observable final class` to expose `isAuthenticated` and `isExchangingToken` for UI reactivity. The OAuth token exchange can be done in an `async` method (no `actor` needed since the class is `@MainActor`).

**Keychain for OAuth token** — same `RemoteServerKeychain` pattern as above. Service: `"com.goose.swift.gemini"`, account: `"oauth-token"` (D-02). For the full token struct (access + refresh + expiry), follow `CodexSelfContainedAuthKeychain.save(_:)` pattern (lines 377–439 of `CodexEmbeddedAuth.swift`) which JSON-encodes a `Codable` struct:
```swift
// CodexEmbeddedAuth.swift lines 377–392
static func save(_ auth: CodexStoredChatGPTAuth) throws {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  let data = try encoder.encode(auth)
  let query = baseQuery()
  SecItemDelete(query as CFDictionary)
  var attributes = query
  attributes[kSecValueData as String] = data
  attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  let status = SecItemAdd(attributes as CFDictionary, nil)
  guard status == errSecSuccess else {
    throw CodexSelfContainedAuthError.keychainSaveFailed(status)
  }
}
```

**Token refresh check pattern** — copy from `CodexEmbeddedAuth.swift` (lines 22–39):
```swift
// CodexStoredChatGPTAuth lines 22–39
var needsRefresh: Bool {
  if let expiresAt {
    return expiresAt.timeIntervalSinceNow < 60
  }
  return Date().timeIntervalSince(updatedAt) > 50 * 60
}
```
Apply same pattern to `GeminiStoredToken`.

**Token refresh network call** — copy from `CodexEmbeddedAuth.swift` (lines 265–295):
```swift
// refreshStoredAuth pattern
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
request.setValue("application/json", forHTTPHeaderField: "Accept")
request.httpBody = formURLEncoded([
  "grant_type": "refresh_token",
  "refresh_token": auth.refreshToken,
  "client_id": clientID,
])
let (data, response) = try await session.data(for: request)
```
For Gemini token refresh endpoint: `https://oauth2.googleapis.com/token`.

**`formURLEncoded` helper** — copy from `CodexEmbeddedAuth.swift` (lines 327–331):
```swift
private func formURLEncoded(_ values: [String: String]) -> Data {
  var components = URLComponents()
  components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
  return Data((components.percentEncodedQuery ?? "").utf8)
}
```

**Ephemeral URLSession for auth** — copy from `CodexEmbeddedAuth.swift` (lines 143–149):
```swift
let configuration = URLSessionConfiguration.ephemeral
configuration.httpShouldSetCookies = false
configuration.httpCookieAcceptPolicy = .never
configuration.waitsForConnectivity = true
session = URLSession(configuration: configuration)
```
Use ephemeral session for OAuth token exchange (no cookies). Use `URLSession.shared` for SSE streaming (consistent with other providers).

**SSE streaming** — identical to `ClaudeCoachProvider` pattern above (`URLSession.shared.bytes(for:)` + `bytes.lines`). Only the delta extraction function differs (candidates path).

**UserDefaults for OAuth client ID** — same dot-namespaced key convention:
```swift
static let oauthClientIdKey = "goose.coach.gemini.oauthClientId"
```

---

### `GooseSwift/CoachChatTypes.swift` (modify — extend CoachModelPreset)

**Analog:** `GooseSwift/CoachChatTypes.swift` itself (lines 57–91)

**Enum extension pattern** — add new cases to the existing `CoachModelPreset` enum (lines 57–91). The enum uses explicit `String` `rawValue` (implicit from case name); new cases do not break existing UserDefaults persistence.

Current cases (lines 58–60):
```swift
enum CoachModelPreset: String, CaseIterable, Identifiable {
  case gpt55Low
  case gpt55Medium
  case gpt55High
```

Add new cases after existing ones. Add computed properties `claudeModelID: String?` and `geminiModelID: String?` following the existing `modelID: String` and `effort: String` pattern (lines 77–91):
```swift
var modelID: String {
  "gpt-5.5"
}

var effort: String {
  switch self {
  case .gpt55Low: return "low"
  case .gpt55Medium: return "medium"
  case .gpt55High: return "high"
  }
}
```

---

### `GooseSwift/CoachChatScreen.swift` (modify — update chat type reference)

**Analog:** `GooseSwift/CoachChatScreen.swift` itself (line 4)

The primary change is the property wrapper on `chat`:

Before (line 4):
```swift
@ObservedObject var chat: OpenAICoachChatModel
```

After:
```swift
var chat: CoachChatModel  // @Observable — no wrapper needed
```

If `$draft` is a `@Binding` passed from `CoachView`, no change needed there (it's a separate `@State` in `CoachView`). If `CoachChatScreen` ever needs a `$` binding into `chat`, use `@Bindable var chat: CoachChatModel`.

---

### `GooseSwift/CoachSettingsSheet.swift` (new view)

**Analog:** `GooseSwift/CoachView.swift` (lines 1–53, 631–667 — sheet wiring + `CoachProfileMenu` as structural predecessor)

**Imports pattern** — copy from `GooseSwift/CoachView.swift` (lines 1–2):
```swift
import SwiftUI
```

**Sheet navigation structure** — copy from `CoachView.swift` (lines 33–53):
```swift
.sheet(isPresented: $showingSettings) {
  NavigationStack {
    CoachSettingsSheet(registry: registry)
      .navigationTitle("Coach Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Done") { showingSettings = false }
        }
      }
  }
}
```

**Gear icon in toolbar** — copy from `CoachView.swift` (lines 26–32), replacing `CoachProfileMenu`:
```swift
.toolbar {
  ToolbarItem(placement: .topBarTrailing) {
    Button {
      showingSettings = true
    } label: {
      Image(systemName: "gearshape")
    }
    .accessibilityLabel("Coach settings")
  }
}
```

**Model picker section** — adapt from `CoachView.swift` `CoachProfileMenu` (lines 636–648):
```swift
Section("Model") {
  ForEach(registry.activeProvider?.availablePresets ?? []) { preset in
    Button {
      chat.selectModelPreset(preset)
    } label: {
      if chat.modelPreset == preset {
        Label(preset.title, systemImage: "checkmark")
      } else {
        Text(preset.title)
      }
    }
  }
}
```

**SecureField for API key** — no existing analog in codebase. Use standard SwiftUI `SecureField("API Key", text: $apiKey)` pattern (no project-specific variation to copy).

**URL validation feedback** — copy `RemoteServerURLValidator.validate(_:)` call pattern. Show validation error inline as `.foregroundStyle(.red)` text, same visual pattern as error display in `CoachChatScreen.swift` (lines 56–61):
```swift
if let errorMessage = chat.errorMessage, !errorMessage.isEmpty {
  Label(errorMessage, systemImage: "exclamationmark.triangle")
    .font(.footnote)
    .foregroundStyle(.red)
    .padding(.horizontal, 2)
}
```

---

## Shared Patterns

### @Observable class declaration
**Source:** `GooseSwift/GooseAppModel.swift` (lines 6–7)
**Apply to:** `CoachProviderRegistry`, `CoachChatModel`, `GeminiCoachProvider` (for UI-observable OAuth state)
```swift
@MainActor @Observable
final class GooseAppModel {
```

### Keychain — API key (simple string)
**Source:** `GooseSwift/RemoteServerPersistence.swift` (lines 57–109)
**Apply to:** `ClaudeCoachProvider` (inline `ClaudeKeychain` enum), `CustomEndpointCoachProvider` (inline `CustomEndpointKeychain` enum)
- `SecItemDelete` before `SecItemAdd` (upsert pattern — lines 63–73)
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on all saved items (line 68)
- Return `nil` on `errSecItemNotFound` rather than throwing (line 83–84)
- `baseQuery()` private static method returning `[String: Any]` with `kSecClass`, `kSecAttrService`, `kSecAttrAccount` (lines 102–108)

### Keychain — Codable token struct (OAuth)
**Source:** `GooseSwift/CodexEmbeddedAuth.swift` `CodexSelfContainedAuthKeychain` (lines 373–439)
**Apply to:** `GeminiCoachProvider` (inline `GeminiKeychain` enum for token struct with refresh_token + expiry)
- `JSONEncoder` with `dateEncodingStrategy = .iso8601` for save (lines 379–380)
- `JSONDecoder` with `dateDecodingStrategy = .iso8601` for load (lines 430–432)

### SSE streaming via URLSession.bytes
**Source:** `GooseSwift/OpenAICoachResponsesClient.swift` (lines 183–204)
**Apply to:** `ClaudeCoachProvider`, `CustomEndpointCoachProvider`, `GeminiCoachProvider`
- `URLSession.shared.bytes(for: request)` — never `dataTask`
- `for try await line in bytes.lines` — line-by-line async iteration
- `try Task.checkCancellation()` inside loop — enables sendTask cancellation to propagate
- `bytes.lines` handles chunking and backpressure automatically

### JSON body serialization
**Source:** `GooseSwift/OpenAICoachResponsesClient.swift` (lines 168–171)
**Apply to:** All provider `buildRequest` methods
```swift
guard JSONSerialization.isValidJSONObject(body) else {
  throw ProviderError.invalidRequestBody
}
let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
```
Use `JSONSerialization` not `JSONEncoder` — providers construct `[String: Any]` mixed-type dicts.

### UserDefaults key naming
**Source:** `GooseSwift/OpenAICoachChat.swift` (line 13) + `GooseSwift/CoachChatTypes.swift` (line 94)
**Apply to:** `CoachProviderRegistry`, `CustomEndpointCoachProvider`, `GeminiCoachProvider`
Pattern: `"goose.coach.<subsystem>.<key>"` (dot-namespaced, no CamelCase, descriptive)

### Task cancellation + error classification
**Source:** `GooseSwift/OpenAICoachChat.swift` (lines 156–185, 614–620)
**Apply to:** `CoachChatModel.send()` after refactor
```swift
} catch is CancellationError {
  markAssistantMessageCancelled(assistantID)
  streamState = .idle
} catch where isCancelledError(error) {
  markAssistantMessageCancelled(assistantID)
  streamState = .idle
}

private func isCancelledError(_ error: Error) -> Bool {
  if let urlError = error as? URLError {
    return urlError.code == .cancelled
  }
  let nsError = error as NSError
  return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
}
```

### formURLEncoded helper
**Source:** `GooseSwift/CodexEmbeddedAuth.swift` (lines 327–331)
**Apply to:** `GeminiCoachProvider` (OAuth token exchange + refresh)
```swift
private func formURLEncoded(_ values: [String: String]) -> Data {
  var components = URLComponents()
  components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
  return Data((components.percentEncodedQuery ?? "").utf8)
}
```

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `GooseSwift/GeminiOAuthWebView.swift` (if separated) | view | event-driven (WKWebView + OAuth redirect) | No WKWebView SwiftUI wrapper exists in the codebase. Pattern comes from RESEARCH.md §Pattern 5 and Apple docs (`WKNavigationDelegate.decidePolicyFor`) |
| `CoachProvider` protocol `send()` returning `AsyncStream<String>` | protocol | streaming | No `AsyncStream`-returning protocol exists yet. Pattern is Swift Concurrency standard — wrap SSE loop in `AsyncStream { continuation in Task { ... } }` |

---

## Metadata

**Analog search scope:** `GooseSwift/` directory (all Swift source files)
**Key files scanned:** `OpenAICoachChat.swift`, `OpenAICoachResponsesClient.swift`, `CodexEmbeddedAuth.swift`, `CoachChatTypes.swift`, `CoachView.swift`, `CoachChatScreen.swift`, `RemoteServerPersistence.swift`, `GooseAppModel.swift`
**Pattern extraction date:** 2026-06-06
