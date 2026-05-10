# ResolveKit Integration Checklist

Use this checklist to verify a complete integration. Check off each item as you confirm it.

## Pre-Integration

- [ ] Backend is running and accessible (health check passes)
- [ ] API key obtained from dashboard (starts with `iaa_`)
- [ ] Project type detected (iOS vs Android vs both)
- [ ] UI framework identified (SwiftUI/UIKit vs Compose/Views)
- [ ] Architecture patterns identified (MVVM, Clean, DI framework)

## Dependencies

### iOS
- [ ] SPM dependency added: `https://github.com/resolve-kit/resolvekit-ios-sdk`
- [ ] Only `ResolveKitUI` product linked (NOT `ResolveKitCore`)
- [ ] Framework set to `Embed & Sign` in Xcode target settings
- [ ] Project builds without errors

### Android
- [ ] KSP plugin added (if using function authoring): `id("com.google.devtools.ksp")`
- [ ] Dependencies added: `sdk`, `authoring`, `ksp("ksp")`
- [ ] `INTERNET` permission added to `AndroidManifest.xml`
- [ ] Compose BOM version is `2024.02.00` or later
- [ ] Project builds without errors

## Tool Functions

- [ ] Functions defined with `snake_case` names
- [ ] Descriptions are specific and informative (not vague)
- [ ] `requiresApproval` is `true` for mutations, `false` for reads
- [ ] Functions placed in appropriate project location (domain/tools directory)
- [ ] Functions registered in configuration (or function pack)
- [ ] Parameter types are supported (String, Bool, Int, etc.)
- [ ] Return types are meaningful (not just "ok")

## Runtime Configuration

- [ ] `baseURL` points to running backend
- [ ] `apiKeyProvider` returns valid key (not hardcoded in source)
- [ ] `functions` list includes all defined functions
- [ ] `deviceIDProvider` configured (or uses default auto-UUID)
- [ ] `llmContextProvider` passes useful context (user state, app version)
- [ ] `localeProvider` configured (or uses system default)

## UI Integration

### iOS/SwiftUI
- [ ] `ResolveKitChatView(runtime:)` added to view hierarchy
- [ ] Runtime is `@StateObject` in the presenting view

### iOS/UIKit
- [ ] `ResolveKitChatViewController` created with runtime
- [ ] Presented in navigation controller or modally

### Android/Compose
- [ ] `ResolveKitChatView(runtime = runtime)` added to Compose layout
- [ ] Wrapped in `MaterialTheme`

### Android/Views
- [ ] `ResolveKitChatActivity` intent or `ResolveKitChatFragment` added
- [ ] Configuration passed correctly

## Android-Specific

- [ ] ProGuard rules added to `proguard-rules.pro`
- [ ] Release build tested (`./gradlew :app:assembleRelease`)
- [ ] No crashes in release build

## Verification

- [ ] Project builds successfully (debug mode)
- [ ] Runtime connects (connectionState transitions to `active`)
- [ ] Functions are registered (check backend or debug logs)
- [ ] Chat UI renders correctly
- [ ] Test conversation: user message -> assistant response
- [ ] Test tool call: assistant requests tool -> tool executes -> result returned
- [ ] Error handling tested (wrong API key, offline, etc.)
- [ ] Connection state observed (UI shows connection status)

## Post-Integration

- [ ] Functions tested with real backend scenarios
- [ ] `llmContextProvider` sends meaningful context
- [ ] Appearance mode tested (light/dark)
- [ ] Localization tested (if applicable)
- [ ] Performance tested (no ANR on Android, no main thread blocking on iOS)
