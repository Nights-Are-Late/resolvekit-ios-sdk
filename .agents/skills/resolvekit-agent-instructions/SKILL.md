---
name: resolvekit-agent-instructions
description: Instructions for AI coding agents (Codex, Claude Code, etc.) on how to integrate ResolveKit into projects. Covers project detection, function design patterns, integration order, and verification steps. Use this to guide agents through ResolveKit integration.
category: resolvekit
---

# ResolveKit Agent Integration Instructions

## Purpose

This skill instructs AI coding agents on how to integrate ResolveKit into user projects. It provides adaptive routing based on project type, function design patterns, and integration verification steps.

## How to Use This Skill

When a user asks an AI agent to "add ResolveKit", "integrate AI support", or similar:

1. **Load this skill first** to understand the integration framework
2. **Detect the project type** (see below)
3. **Load the platform-specific skill** (`resolvekit-ios-integration` or `resolvekit-android-integration`)
4. **Follow the integration phases** in order

## Project Detection Checklist

Before any integration, inspect the project:

### Detect iOS
- Look for `.xcodeproj`, `.xcworkspace`, or `Package.swift`
- Check for `.swift` files
- Look for `Info.plist` with iOS bundle identifiers
- Check if SwiftUI (look for `@main` struct with `App` protocol) or UIKit (look for `AppDelegate`/`SceneDelegate`)

### Detect Android
- Look for `build.gradle.kts` or `build.gradle`
- Check for `AndroidManifest.xml`
- Check for `src/main/` directory structure
- Determine if Compose (look for `setContent {}`, `@Composable`) or View-based (XML layouts, Activities with `setContentView`)

### Detect Architecture Patterns
- **MVVM**: Look for `ViewModel` classes
- **Clean Architecture**: Look for `domain/`, `data/`, `presentation/` layers
- **Dependency Injection**: Check for Swift DI containers or Hilt/Dagger/Koin on Android
- **State Management**: Check for Redux, Compose StateFlow, Combine, etc.

## Integration Order (Always Follow This)

### Phase 1: Assess and Plan
1. Detect project type (iOS vs Android)
2. Detect UI framework (SwiftUI/UIKit/AppKit vs Compose/Views)
3. Detect existing architecture patterns
4. Identify where tool functions should live (domain layer, services, etc.)
5. Check if backend is running and API key is available
6. Present integration plan to user

### Phase 2: Add Dependencies
**iOS:**
- Add SPM dependency: `https://github.com/resolve-kit/resolvekit-ios-sdk`
- Link ONLY `ResolveKitUI` product (it includes Core transitively)
- Verify framework is set to `Embed & Sign`

**Android:**
- Add KSP plugin if using function authoring
- Add dependencies: `app.resolvekit:sdk`, `app.resolvekit:authoring`, `ksp("app.resolvekit:ksp")`
- Verify `INTERNET` permission in manifest

### Phase 3: Design and Author Tool Functions
This is the MOST important phase. Good tool functions make the agent useful.

#### Function Design Principles
1. **Be specific in descriptions** -- The LLM uses the description to decide when to call the function
2. **Use snake_case for names** -- Consistent with LLM tool calling conventions
3. **Start with requiresApproval=false** for read-only functions, true for mutations
4. **Keep functions focused** -- One function = one capability
5. **Return useful data** -- The result becomes part of the conversation

#### Good Function Examples

iOS:
```swift
@ResolveKit(
    name: "check_subscription_status",
    description: "Returns the current user's subscription tier, whether they are on a free trial, and when their subscription renews or expires",
    requiresApproval: false
)
struct CheckSubscriptionStatus: ResolveKitFunction {
    func perform() async throws -> String {
        let user = await UserManager.shared.currentUser
        return """
        Plan: \(user.planName)
        Status: \(user.isTrialActive ? "Free Trial" : "Active")
        \(user.isTrialActive ? "Trial ends: \(user.trialEndDate)" : "Renews: \(user.renewalDate)"}
        """
    }
}
```

Android:
```kotlin
@ResolveKit(
    name = "check_subscription_status",
    description = "Returns the current user's subscription tier, whether they are on a free trial, and when their subscription renews or expires",
    requiresApproval = false
)
class CheckSubscriptionStatus(
    private val userRepository: UserRepository
) : ResolveKitFunction {
    override suspend fun perform(): Any? {
        val user = userRepository.getCurrentUser()
        return buildString {
            append("Plan: ${user.planName}\n")
            append("Status: ${if (user.isTrialActive) "Free Trial" else "Active"}\n")
            if (user.isTrialActive) {
                append("Trial ends: ${user.trialEndDate}")
            } else {
                append("Renews: ${user.renewalDate}")
            }
        }
    }
}
```

#### Common Function Patterns
| Pattern | Name Example | Description Pattern |
|---|---|---|
| Status check | `check_subscription_status` | "Returns the current user's [X] status and [Y]" |
| Navigation | `navigate_to_settings` | "Opens the [X] screen/section of the app" |
| Data fetch | `get_order_history` | "Returns the user's [X] with [Y details]" |
| Action/mutation | `cancel_subscription` | "[Action] the user's [X]. Requires confirmation." |
| Feature toggle | `enable_beta_feature` | "Enables [X] for the current user session" |

#### Where to Place Functions
- **iOS**: Create a `ResolveKitFunctions/` or `AITools/` directory in your app. Group by domain (e.g., `SubscriptionFunctions/`, `UserFunctions/`).
- **Android**: Place in a `tools/` or `functions/` package under your domain or feature layer. Use constructor injection for dependencies.
- **Function Packs**: Group related functions into `ResolveKitFunctionPack` (iOS) or `ResolveKitFunctionPack` (Android) for modular registration.

### Phase 4: Configure Runtime
1. Create `ResolveKitConfiguration` with:
   - Backend URL (from environment/config)
   - API key provider (secure retrieval)
   - Registered functions
   - Device ID provider (for session correlation)
   - LLM context provider (pass user state, app version, etc.)

2. Where to create the runtime:
   - **iOS**: As `@StateObject` in your root view, or in your DI container
   - **Android**: As a singleton in your DI container, or in `Application` class

### Phase 5: Integrate UI
1. Add chat entry point (button, menu item, gesture)
2. Present chat surface:
   - **iOS/SwiftUI**: `ResolveKitChatView(runtime:)` inline or in a sheet
   - **iOS/UIKit**: Push `ResolveKitChatViewController`
   - **Android/Compose**: `ResolveKitChatView(runtime)` inline or in dialog
   - **Android/Views**: Launch `ResolveKitChatActivity` or embed `ResolveKitChatFragment`

### Phase 6: Configure ProGuard (Android Only)
Add required ProGuard rules to `proguard-rules.pro`. Without these, release builds crash.

### Phase 7: Verify Integration
After integration, verify:
1. Project builds successfully
2. Runtime connects to backend (check `connectionState` becomes `active`)
3. Functions are registered (check backend function list)
4. Chat UI renders correctly
5. Test a conversation with at least one tool call

## Adaptive Behavior by Project Type

### SwiftUI-First iOS App
- Runtime as `@StateObject` in root view
- Inline `ResolveKitChatView` or sheet presentation
- Functions in a dedicated `Tools/` group
- Use `@ResolveKit` macro for all functions

### UIKit iOS App
- Runtime in a service class or app delegate
- Present `ResolveKitChatViewController` modally or via navigation
- May need to wrap in `UINavigationController`

### Compose Android App
- Runtime in ViewModel or Hilt singleton
- Inline `ResolveKitChatView` in Compose layout
- Use KSP `@ResolveKit` for all functions
- Constructor injection for dependencies

### View-Based Android App
- Runtime in Application class or service
- Launch `ResolveKitChatActivity` for full-screen
- Or embed `ResolveKitChatFragment` in existing layouts
- May need to wrap `ResolveKitChatView` in `AndroidView` for mixed Compose/View setups

### Clean Architecture (Both Platforms)
- Functions live in the domain/usecase layer
- Runtime configured in the presentation layer
- LLM context provider pulls from domain state
- Function packs mirror your domain module structure

### Mono-Repo (iOS + Android)
- Run both integration skills
- Share function definitions conceptually (same names, descriptions, parameters)
- Use function packs to keep parity between platforms
- Configure shared backend URL from common config

## What NOT to Do

1. Do NOT hardcode API keys in source
2. Do NOT link both `ResolveKitUI` and `ResolveKitCore` on iOS
3. Do NOT skip ProGuard rules on Android
4. Do NOT use camelCase for function names (use snake_case)
5. Do NOT write vague function descriptions (the LLM needs specific descriptions)
6. Do NOT forget `INTERNET` permission on Android
7. Do NOT pass `java.net.URL` to Android `baseUrl` (it's a `String`)
8. Do NOT mutate configuration after creation (it's immutable)
9. Do NOT ignore connection state (observe it for error handling)
10. Do NOT create functions that mutate state without `requiresApproval: true`

## Verification Commands

After integration, run these checks:

iOS:
```bash
xcodebuild -project YourApp.xcodeproj -scheme YourApp -sdk iphonesimulator build
```

Android:
```bash
./gradlew :app:assembleDebug
./gradlew :app:assembleRelease  # Tests ProGuard rules
```
