# Source-Only Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Publish `1.0.1` as a source-only release and create the `develop` branch without shipping binary artifacts.

**Architecture:** Keep `Package.swift` as the only package distribution entrypoint, remove binary release scaffolding, and update tests so they validate the source-based release model instead of binary release assets. Once the repository verifies cleanly, publish the new branch and tag, then create a GitHub release page with no attached binaries.

**Tech Stack:** Swift Package Manager, Swift Testing, git, GitHub CLI

---

### Task 1: Record the source-only release plan

**Files:**
- Create: `docs/plans/2026-03-04-source-only-release-design.md`
- Create: `docs/plans/2026-03-04-source-only-release.md`

**Step 1: Write the design doc**

Create the design document describing the approved source-only release model.

**Step 2: Write the implementation plan**

Create this plan with exact files, commands, and verification steps.

**Step 3: Verify the docs exist**

Run: `find docs/plans -maxdepth 1 -type f | sort`
Expected: both `2026-03-04-source-only-release-*.md` files are listed

### Task 2: Convert tests to the source-only release model

**Files:**
- Modify: `Tests/ResolveKitCoreTests/ResolveKitCoreTests.swift`

**Step 1: Write the failing tests**

Replace the binary distribution contract assertions with source-only release assertions:
- README install example references `from: "1.0.1"`
- `Package.swift` exposes the source targets directly
- Repository does not require `distribution/public-sdk/Package.swift`
- Repository does not require `scripts/build-binary-release.sh` or `scripts/build-and-release-github.sh`

**Step 2: Run test to verify it fails**

Run: `swift test --filter ResolveKitBinaryDistributionContractTests`
Expected: FAIL while the old binary-release assertions are still in place

**Step 3: Write minimal implementation**

Update `Tests/ResolveKitCoreTests/ResolveKitCoreTests.swift` to assert the approved source-only release behavior only.

**Step 4: Run test to verify it passes**

Run: `swift test --filter ResolveKitBinaryDistributionContractTests`
Expected: PASS

### Task 3: Remove binary-release scaffolding and keep source release metadata

**Files:**
- Modify: `README.md`
- Modify: `Sources/ResolveKitUI/ResolveKitConfiguration.swift`
- Delete: `distribution/public-sdk/Package.swift`
- Delete: `scripts/build-binary-release.sh`
- Delete: `scripts/build-and-release-github.sh`

**Step 1: Confirm version metadata stays on `1.0.1`**

Ensure the SDK runtime version and README package example use `1.0.1`.

**Step 2: Remove binary-only files**

Delete the wrapper package and GitHub binary release scripts that are no longer part of the approved design.

**Step 3: Check git diff**

Run: `git diff -- README.md Sources/ResolveKitUI/ResolveKitConfiguration.swift Tests/ResolveKitCoreTests/ResolveKitCoreTests.swift`
Expected: diff shows only source-only release changes

### Task 4: Verify the repository

**Files:**
- Modify: none

**Step 1: Run the focused release tests**

Run: `swift test --filter ResolveKitBinaryDistributionContractTests`
Expected: PASS

**Step 2: Run the full test suite**

Run: `swift test`
Expected: PASS

**Step 3: Inspect git state**

Run: `git status --short --branch`
Expected: only intended release changes are present

### Task 5: Publish the release

**Files:**
- Modify: none

**Step 1: Commit the source-only release changes**

Run: `git add README.md Sources/ResolveKitUI/ResolveKitConfiguration.swift Tests/ResolveKitCoreTests/ResolveKitCoreTests.swift docs/plans`
Run: `git commit -m "release: prepare 1.0.1 source release"`
Expected: commit created on `main`

**Step 2: Create the develop branch**

Run: `git branch develop`
Expected: local `develop` branch exists at the release commit

**Step 3: Create the annotated tag**

Run: `git tag -a 1.0.1 -m "Release 1.0.1"`
Expected: local tag exists

**Step 4: Push the branches and tag**

Run: `git push origin main`
Run: `git push origin develop`
Run: `git push origin 1.0.1`
Expected: remote branches and tag created

**Step 5: Create the GitHub release**

Run: `gh release create 1.0.1 --title "1.0.1" --notes "Source-only Swift Package release."`
Expected: GitHub release exists for tag `1.0.1` with no binary attachments
