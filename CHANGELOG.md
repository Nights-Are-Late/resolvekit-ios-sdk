# Changelog

All notable changes to the ResolveKit iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.2] - 2026-04-30

### Fixed
- Package linkage conflicts when explicitly linking both `ResolveKitCore` and `ResolveKitUI`
- Locale resolution fallback for unsupported languages
- Tool call batch state updates during streaming

### Changed
- `ResolveKitChatView` now auto-starts runtime on appear (no manual `start()` call needed)
- `deviceIDProvider` defaults to auto-generated UUID if nil

### Added
- `preferredLocalesProvider` config option for app-level locale preferences
- `availableFunctionNamesProvider` for per-session tool scoping
- `toolCallBatches` published property for historical tool call records
- `executionLog` published property for debug lifecycle events
- `init(configuration:)` convenience init for UIKit/AppKit
- `@ResolveKit` macro for typed function authoring (Swift 5.9+)
- `ResolveKitFunctionPack` support for modular tool groups

## [1.4.1] - 2026-04-15

### Fixed
- Session reconnect after app backgrounding
- Tool approval UI layout on smaller screens

## [1.4.0] - 2026-04-01

### Added
- macOS (AppKit) support for `ResolveKitChatViewController`
- `llmContextProvider` for custom JSON context injection
- `localeProvider` for per-session language pinning
- `toolCallBatchState` for aggregate tool approval state

### Changed
- Migrated from manual `AnyResolveKitFunction` conformance to `@ResolveKit` macro
- Default `requiresApproval` changed to `true` for all tool functions

## [1.3.0] - 2026-03-15

### Added
- Initial public release
- Swift Package Manager integration
- SwiftUI `ResolveKitChatView` component
- UIKit `ResolveKitChatViewController` component
- `@ResolveKit` macro for tool function authoring
- Tool approval UI with checklist
- HTTP/3-first session event stream
- Reconnect with in-flight turn replay

