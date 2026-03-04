# Macro-First Open-Source Docs Design

**Date:** 2026-03-04

**Goal:** Update repository documentation so the open-source macro workflow is the primary implementation path and remove stale packaging references.

## Decision

ResolveKit documentation should present `@ResolveKit` from `ResolveKitAuthoring` as the recommended way to define tool functions for open-source adopters. Manual `AnyResolveKitFunction` conformance remains supported, but it should be framed as an advanced fallback for custom schemas or dynamic dispatch rather than the default path.

The repository should also stop describing a split between a packaged SDK track and the open-source source package. Existing release notes and tests can still verify that the package is source-based, but the language should focus on the open-source package layout instead of the removed legacy packaging model.

## Scope

- Reorder the function-definition guidance in `README.md` so the macro path appears first and is explicitly recommended.
- Rewrite README wording that implies `ResolveKitAuthoring` is limited to a private or source-only distribution tier.
- Update project plans and tests that still use stale packaging language when referring to the old distribution model.
- Keep manual conformance documentation available as a fallback path.

## Non-Goals

- No API or package manifest changes.
- No changes to runtime behavior or macro behavior.
- No release process changes beyond wording cleanup in existing docs.

## Verification

- Search the repository for stale packaged-distribution wording after the edits.
- Inspect the diff to ensure macro-first ordering in the README.
- Run the focused source-distribution test suite after renaming or rewording assertions.
