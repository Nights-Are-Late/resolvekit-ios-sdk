# resolvekit-ios-sdk

ResolveKit iOS SDK — native runtime, UI, and tool function integration for Apple platforms.

## Working Contract

- Humans define API surface and quality bars.
- Agents implement code, tests, and CI changes.
- SDK changes must maintain backward compatibility for public APIs.
- Breaking changes must include migration notes.

## Project Overview

ResolveKit iOS SDK embeds agent chat and native tool execution inside iOS/macOS apps.

**Tech Stack**: Swift 5.9+, SwiftSyntax (for macros), SwiftUI/UIKit/AppKit
**Platforms**: iOS 16+, macOS 12+
**Products**: `ResolveKitCore`, `ResolveKitAuthoring`, `ResolveKitNetworking`, `ResolveKitUI`, `ResolveKitPlugin`

## Agent Skills

This repo ships with integration skills in `.agents/skills/`. Load them when relevant:

- `resolvekit-ios-integration` — How to integrate this SDK into an iOS/macOS project. Covers SPM installation, `@ResolveKit` macro function authoring, runtime configuration, SwiftUI/UIKit/AppKit UI integration, and troubleshooting.
- `resolvekit-agent-instructions` — How AI agents should approach ResolveKit integration. Covers project detection, function design patterns, integration order, and verification.

When a user asks to integrate ResolveKit into their iOS project, load `resolvekit-ios-integration` and follow its steps.

## First Read

1. `Package.swift` for project structure and dependencies.
2. `Sources/` for module organization.
3. `Tests/` for test patterns and coverage expectations.
