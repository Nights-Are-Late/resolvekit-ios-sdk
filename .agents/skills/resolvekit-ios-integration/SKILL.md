---
name: resolvekit-ios-integration
description: Complete iOS SDK integration guide for ResolveKit. Covers SPM installation, function authoring with @ResolveKit macro, runtime configuration, SwiftUI/UIKit/AppKit UI integration, and troubleshooting.
category: resolvekit
---

# ResolveKit iOS SDK Integration

## Requirements
- Swift tools: 5.9+
- Xcode: 15+
- Platforms: iOS 16+, macOS 12+
- Running ResolveKit backend with valid API key

## Module Layout

| Module | Purpose |
|---|---|
| `ResolveKitCore` | JSON/value types, function protocol, registry, schemas |
| `ResolveKitAuthoring` | `@ResolveKit` macro and authoring protocol |
| `ResolveKitNetworking` | REST + SSE clients |
| `ResolveKitUI` | Runtime + SwiftUI chat view + UIKit/AppKit controllers |

## Step 1: Installation via SPM

### Xcode UI
File -> Add Package Dependencies -> URL:
```
https://github.com/resolve-kit/resolvekit-ios-sdk
```
Select version `1.4.2` or later. Add `ResolveKitUI` product to your app target.

### Package.swift
```swift
dependencies: [
    .package(url: "https://github.com/resolve-kit/resolvekit-ios-sdk", from: "1.4.2")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "ResolveKitUI", package: "resolvekit-ios-sdk")
        ]
    )
]
```

CRITICAL: Only link `ResolveKitUI` -- it transitively depends on `ResolveKitCore`. Linking both causes build conflicts. Set the framework to `Embed & Sign` in General settings.

## Step 2: Define Tool Functions

### Recommended: @ResolveKit Macro
```swift
import ResolveKitAuthoring

@ResolveKit(
    name: "get_subscription_status",
    description: "Returns the user's current subscription tier and renewal date",
    timeout: 10,
    requiresApproval: false
)
struct GetSubscriptionStatus: ResolveKitFunction {
    func perform() async throws -> String {
        // Your app logic here
        return "Pro plan, renews 2026-06-15"
    }
}
```

### Macro Parameters
| Parameter | Required | Default | Description |
|---|---|---|---|
| `name` | Yes | -- | snake_case function name sent to LLM |
| `description` | Yes | -- | Plain-English description for LLM routing |
| `timeout` | No | nil | Seconds before timeout. nil uses backend default |
| `requiresApproval` | No | true | false = execute immediately, true = show approval UI |

### Functions with Parameters
```swift
@ResolveKit(name: "send_feedback", description: "Send user feedback about a feature")
struct SendFeedback: ResolveKitFunction {
    func perform(featureName: String, rating: Int, comment: String) async throws -> Bool {
        // Call your app's feedback API
        return true
    }
}
```

The macro auto-generates typed `Input` struct and JSON schema from the `perform` signature.

### Supported Parameter Types
- `String`, `Bool`, `Int`/`Int8`...`UInt64`, `Double`, `Float`, `CGFloat`
- Optional variants (`T?`) -- auto-excluded from `required`
- Arrays `[T]`, nested arrays `[[T]]`
- Dictionaries `[K: V]`
- Nested `Codable` structs
- Any `Encodable` return type (including `Void`)

### Manual Conformance (Advanced)
For custom JSON schemas or bespoke argument coercion:
```swift
import ResolveKitCore

struct SetLights: AnyResolveKitFunction {
    static let resolveKitName = "set_lights"
    static let resolveKitDescription = "Turn lights on or off"
    static let resolveKitRequiresApproval = true
    static let resolveKitTimeoutSeconds: Int? = 30
    static let resolveKitParametersSchema: JSONObject = [
        "type": .string("object"),
        "properties": .object([
            "room": .object(["type": .string("string")]),
            "on": .object(["type": .string("boolean")])
        ]),
        "required": .array([.string("room"), .string("on")])
    ]

    static func invoke(arguments: JSONObject, context: ResolveKitFunctionContext) async throws -> JSONValue {
        guard
            let room = arguments["room"].flatMap(TypeResolver.coerceString),
            let on = arguments["on"].flatMap(TypeResolver.coerceBool)
        else {
            throw ResolveKitFunctionError.invalidArguments("Expected room:String and on:Bool")
        }
        return .string("Set \(room) lights to \(on ? 100 : 0)%")
    }
}
```

### Function Packs
For organizing tool functions into modular groups:
```swift
import ResolveKitCore

enum CommerceResolveKitPack: ResolveKitFunctionPack {
    static let packName = "commerce_pack"
    static let supportedPlatforms: [ResolveKitPlatform] = [.ios, .macos]
    static let functions: [any AnyResolveKitFunction.Type] = [
        GetSubscriptionStatus.self,
        UpgradeSubscription.self
    ]
}
```

Register via `functionPacks: [CommerceResolveKitPack.self]` in configuration.

## Step 3: Create and Configure Runtime

### Basic Configuration
```swift
import ResolveKitUI

let runtime = ResolveKitRuntime(configuration: ResolveKitConfiguration(
    baseURL: URL(string: "https://your-backend.example.com")!,
    apiKeyProvider: { "iaa_your_api_key" },
    functions: [GetSubscriptionStatus.self, SendFeedback.self]
))
```

### Full Configuration with All Providers
```swift
let runtime = ResolveKitRuntime(configuration: ResolveKitConfiguration(
    baseURL: URL(string: "https://your-backend.example.com")!,
    apiKeyProvider: { KeychainManager.getResolveKitKey() },
    deviceIDProvider: { UserDefaults.standard.string(forKey: "rk_device_id") },
    llmContextProvider: {
        [
            "user_plan": .string(UserManager.current.plan),
            "app_version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
            "is_onboarding_complete": .bool(UserManager.current.isOnboardingComplete)
        ]
    },
    availableFunctionNamesProvider: {
        UserManager.current.isPro ? allFunctionNames : basicFunctionNames
    },
    localeProvider: { UserManager.current.preferredLanguage },
    functions: [GetSubscriptionStatus.self, SendFeedback.self],
    functionPacks: [CommerceResolveKitPack.self]
))
```

### Configuration Fields Reference
| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `baseURL` | `URL` | No | `https://agent.example.com` | Backend URL |
| `apiKeyProvider` | `() -> String?` | Yes | -- | Called per request, return nil to block |
| `deviceIDProvider` | `() -> String?` | No | Auto-generated UUID | Correlate sessions across launches |
| `llmContextProvider` | `() -> JSONObject` | No | `{}` | Custom context for routing/prompting |
| `availableFunctionNamesProvider` | `() -> [String]?` | No | All registered | Allowlist by user plan/permissions |
| `localeProvider` | `() -> String?` | No | System locale | BCP 47 tag (e.g., "en", "lt") |
| `preferredLocalesProvider` | `() -> [String]?` | No | System locales | Ordered fallback list |
| `functions` | `[AnyResolveKitFunction.Type]` | No | `[]` | Tool function types |
| `functionPacks` | `[ResolveKitFunctionPack.Type]` | No | `[]` | Function pack types |

## Step 4: Integrate Chat UI

### SwiftUI (Recommended)
```swift
import SwiftUI
import ResolveKitUI

struct ContentView: View {
    @StateObject private var runtime = ResolveKitRuntime(configuration: ResolveKitConfiguration(
        baseURL: URL(string: "https://your-backend.example.com")!,
        apiKeyProvider: { "iaa_your_api_key" },
        functions: [GetSubscriptionStatus.self]
    ))

    var body: some View {
        ResolveKitChatView(runtime: runtime)
    }
}
```

`ResolveKitChatView` auto-starts runtime on appear and stops on disappear.

### UIKit
```swift
import UIKit
import ResolveKitUI

let runtime = ResolveKitRuntime(configuration: ResolveKitConfiguration(
    baseURL: URL(string: "https://your-backend.example.com")!,
    apiKeyProvider: { "iaa_your_api_key" },
    functions: [GetSubscriptionStatus.self]
))

let chat = ResolveKitChatViewController(runtime: runtime)
let nav = UINavigationController(rootViewController: chat)
present(nav, animated: true)
```

### AppKit (macOS)
```swift
import AppKit
import ResolveKitUI

let chat = ResolveKitChatViewController(configuration: ResolveKitConfiguration(
    baseURL: URL(string: "https://your-backend.example.com")!,
    apiKeyProvider: { "iaa_your_api_key" }
))
presentAsModalWindow(chat)
```

## Step 5: Runtime Controls

```swift
await runtime.start()                    // Start connection
await runtime.stop()                     // Stop connection
await runtime.refreshSessionContext()    // Push updated llmContext/locale/functions
runtime.setLocale("en")                  // Set locale
runtime.setAppearance(.dark)             // Set appearance mode
await runtime.reloadWithNewSession()     // Force new session
await runtime.sendMessage("Help me")     // Send user message
```

## Step 6: Observe Runtime State

Published properties on `ResolveKitRuntime` (SwiftUI `@Published`):
- `messages` -- Chat message history
- `connectionState` -- Current connection state
- `isTurnInProgress` -- Whether agent is processing
- `pendingToolCall` -- Tool call awaiting approval
- `toolCallChecklist` -- Steps for pending tool
- `toolCallBatchState` -- Execution state
- `executionLog` -- Function execution log
- `chatTheme` -- Fetched theme from backend
- `chatTitle` -- Localized chat title
- `messagePlaceholder` -- Localized placeholder text
- `chatPresentationError` -- Error display info

### Connection States
```
idle -> registering -> connecting -> active
                        -> reconnecting -> reconnected -> active
                        -> failed          (unrecoverable)
                        -> blocked         (missing key / incompatible)
```

## Step 7: Error Handling

```swift
if let error = runtime.chatPresentationError {
    print("Category: \(error.category)")      // network, timeout, generic
    print("Message: \(error.message)")
    print("Suggestion: \(error.recoverySuggestion)")
}
```

## Pitfalls

1. **Framework embedding**: In Xcode, set `ResolveKitUI.framework` to `Embed & Sign`. Just linking causes `dyld` abort at launch.
2. **Duplicate linkage**: Only link `ResolveKitUI` in app targets. Remove redundant `ResolveKitCore` product linkage.
3. **Macro requires struct**: `@ResolveKit` only works on `struct`, not `class` or `enum`.
4. **Main actor**: `ResolveKitRuntime` is `@MainActor ObservableObject`. Register functions on main thread.
5. **Function names**: Must be `snake_case` for LLM compatibility.
6. **API key format**: Must start with `iaa_` prefix.
7. **@ResolveKit macro requires Swift 5.9+**: Check Xcode toolchain version.
8. **perform method**: Must be `async throws` and named exactly `perform`.
