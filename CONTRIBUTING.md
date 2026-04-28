# Contributing

ResolveKit iOS SDK is open source under the MIT license.

## Local Development

Use the Swift Package Manager workflows in this repository:

```bash
swift test
swift build
```

## Pull Requests

Before opening a PR:

- keep changes focused and explain user-facing impact
- add or update tests for behavior changes
- update docs when integration behavior or defaults change
- avoid committing secrets, private keys, or local tool state

## Coding Guidelines

- preserve API clarity and source compatibility when possible
- prefer self-host-friendly defaults and explicit configuration
- keep SDK behavior deterministic across iOS and macOS targets
