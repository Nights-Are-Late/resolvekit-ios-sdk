# Source-Only Release Design

**Date:** 2026-03-04

**Goal:** Publish version `1.0.1` as the standard open-source Swift Package release.

## Decision

ResolveKit will be distributed directly from the repository source through Swift Package Manager tags. Consumers should depend on the package using the git URL and the `1.0.1` tag, with `Package.swift` as the only public distribution surface.

## Scope

- Keep the package source layout in `Package.swift` as the public distribution surface.
- Update package-facing version references to `1.0.1`.
- Remove the legacy packaging scaffolding added during the interrupted release attempt.
- Align repository tests with the source-only release model.
- Create a `develop` branch.
- Create and push an annotated `1.0.1` tag.
- Create a GitHub release for `1.0.1` with notes only.

## Non-Goals

- No alternative packaging flow beyond the source package.
- No wrapper package under `distribution/public-sdk`.
- No legacy packaging scripts.

## Verification

- Run `swift test` after the source-package changes.
- Inspect git status before creating release state.
- Push `main`, `develop`, and tag `1.0.1`.
- Create the GitHub release from the tag with notes only.
