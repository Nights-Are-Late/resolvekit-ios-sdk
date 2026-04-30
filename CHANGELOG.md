# Changelog

All notable changes to the ResolveKit iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.2] - 2026-04-30

### Fixed
- Package linkage conflicts when explicitly linking both  and 
- Locale resolution fallback for unsupported languages
- Tool call batch state updates during streaming

### Changed
-  now auto-starts runtime on appear (no manual  call needed)
-  defaults to auto-generated UUID if nil

### Added
-  config option for app-level locale preferences
-  for per-session tool scoping
-  published property for historical tool call records
-  published property for debug lifecycle events
-  convenience init for UIKit/AppKit
-  macro for typed function authoring (Swift 5.9+)
-  support for modular tool groups

## [1.4.1] - 2026-04-15

### Fixed
- Session reconnect after app backgrounding
- Tool approval UI layout on smaller screens

## [1.4.0] - 2026-04-01

### Added
- macOS (AppKit) support for 
-  for custom JSON context injection
-  for per-session language pinning
-  for aggregate tool approval state

### Changed
- Migrated from manual  conformance to  macro
- Default  changed to  for all tool functions

## [1.3.0] - 2026-03-15

### Added
- Initial public release
- Swift Package Manager integration
- SwiftUI  component
- UIKit  component
-  macro for tool function authoring
- Tool approval UI with checklist
- HTTP/3-first session event stream
- Reconnect with in-flight turn replay

