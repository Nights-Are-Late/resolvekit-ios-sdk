# Macro-First Open-Source Docs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the repository docs macro-first for open-source users and remove stale packaging wording.

**Architecture:** Keep the package and runtime unchanged. Update the README, release-plan docs, and source-distribution tests together so the repository consistently describes a single open-source Swift Package distribution model with `@ResolveKit` as the preferred authoring flow.

**Tech Stack:** Markdown, Swift Testing, git

---

### Task 1: Record the documentation direction

**Files:**
- Create: `docs/plans/2026-03-04-macro-first-open-source-docs-design.md`
- Create: `docs/plans/2026-03-04-macro-first-open-source-docs.md`

**Step 1: Write the design doc**

Create the design document describing the macro-first, open-source documentation direction.

**Step 2: Write the implementation plan**

Create this plan with the exact doc and test files to update.

**Step 3: Verify the plan docs exist**

Run: `find docs/plans -maxdepth 1 -type f | sort | grep macro-first-open-source-docs`
Expected: both `2026-03-04-macro-first-open-source-docs*.md` files are listed

### Task 2: Make the README macro-first

**Files:**
- Modify: `README.md`

**Step 1: Rewrite the section ordering**

Move the `@ResolveKit` macro section above the manual conformance section and change the lead-in text so the macro path is the recommended default.

**Step 2: Remove stale distribution wording**

Replace mentions of a separate packaged SDK track, private-source-only macro usage, or private/internal distribution tiers with open-source package wording.

**Step 3: Verify the README diff**

Run: `git diff -- README.md`
Expected: the macro section appears first and stale packaged-distribution wording is removed

### Task 3: Update project docs and tests for the open-source wording

**Files:**
- Modify: `docs/plans/2026-03-04-source-only-release-design.md`
- Modify: `docs/plans/2026-03-04-source-only-release.md`
- Modify: `Tests/ResolveKitCoreTests/ResolveKitCoreTests.swift`

**Step 1: Rewrite historical wording carefully**

Keep the meaning of the source-release plan intact, but replace stale packaged-distribution phrasing with open-source package wording where possible.

**Step 2: Rename test labels and helpers**

Update test names and assertion descriptions so they validate the open-source source-package model without describing an alternate packaged SDK track.

**Step 3: Verify the targeted test file diff**

Run: `git diff -- Tests/ResolveKitCoreTests/ResolveKitCoreTests.swift`
Expected: test intent is unchanged, but labels and wording align with the open-source package model

### Task 4: Verify the repository state

**Files:**
- Modify: none

**Step 1: Search for stale packaged-distribution wording**

Run: `rg -n "private source repo|private/internal distributions|legacy packaging|packaged SDK track" README.md docs Tests`
Expected: no matches

**Step 2: Run the focused source-distribution tests**

Run: `swift test --filter ResolveKitOpenSourcePackageContractTests`
Expected: PASS

**Step 3: Inspect git status**

Run: `git status --short --branch`
Expected: only the intended docs, test, and plan changes are present on the worktree branch
