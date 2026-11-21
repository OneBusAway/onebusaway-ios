# Pre-PR Verification & SwiftLint CI Gate (#1340, #1834, #1838)

## Overview

This repository uses automated code quality, architectural boundary, and project generation gates both in CI (`.github/workflows/tests.yml`) and locally before opening pull requests (`scripts/pre_pr_check`).

To ensure PRs pass CI without surprise failures or review delays, contributors can run the unified pre-PR check command locally:

```bash
scripts/pre_pr_check
```

## How CI Gates Map to `scripts/pre_pr_check`

The unified pre-PR check mirrors the CI gate structure across four steps:

### 1. Module Boundaries & Invariants

* **In CI (`lint` job):**
  * Checks architectural invariants and module boundaries via `scripts/check_module_boundaries`.
  * Verifies module boundary self-tests via `scripts/check_module_boundaries --test`.
* **Locally (`scripts/pre_pr_check` or `scripts/pre_pr_check --boundaries-only`):**
  * Runs both boundary checks and self-tests to ensure target isolation and dependency rules are respected.

### 2. SwiftLint Errors & Custom Rules

* **In CI (`lint` job):**
  * Runs on Linux inside the official Swift image (`SWIFTLINT_PIN="0.65.1"`).
  * Fails only on **error-tier** rules (including custom rules such as `hardcoded_app_name`, `epoch_decoded_as_int`, and `epoch_narrowed_to_int`, plus strict `file_length` and `type_body_length` limits).
  * Warnings annotate via GitHub Actions reporter but do not fail the build.
* **Locally (`scripts/pre_pr_check` or `scripts/pre_pr_check --lint-only`):**
  * Runs local `swiftlint lint` using the repository's `.swiftlint.yml`.
  * Verifies custom rules and error thresholds. Fails with non-zero exit status and actionable guidance if any error exists.
  * Summarizes warnings without failing the check.
  * Warns loudly if the local SwiftLint version differs from the CI pinned version (`0.65.1`).
  * Can also be called via `scripts/swiftlint.sh --pre-pr`.

> ⚠️ **Warning:** Bump `SWIFTLINT_PIN` in `.github/workflows/tests.yml` deliberately after reviewing new error-tier rules — do not rely on an unpinned `brew install` of SwiftLint, which can introduce differing lint behaviors across developer machines.

### 3. Project Generation Matrix Validation

* **In CI (`build` & `watch` jobs):**
  * Generates `OneBusAway --no-watch` for the main build and test job.
  * Generates `OneBusAway` (with watch targets) for the device/watch smoke job.
  * Asserts `KiedyBus` does not generate watch targets (`scripts/assert_no_watch_target`).
  * Asserts `OneBusAway --no-watch` does not generate watch targets (`scripts/assert_no_watch_target`).
* **Locally (`scripts/pre_pr_check` or `scripts/pre_pr_check --project-only`):**
  * Validates the project generation matrix across all configurations:
    1. `scripts/generate_project OneBusAway` verifying `WatchApp` target inclusion
    2. `scripts/generate_project OneBusAway --no-watch` followed by `scripts/assert_no_watch_target`
    3. `scripts/generate_project KiedyBus` followed by `scripts/assert_no_watch_target`
  * Guarantees project configuration changes do not break white-label apps or leak watch targets into iOS-only builds.
  * Verifies that the project generation matrix does not introduce unexpected modifications to tracked repository files or create untracked artifacts.
  * **Preserves developer configuration:** Backs up the active project and all derived `Info.plist` and `.entitlements` files across `Apps/`, `OBAWidget/`, and `WatchApp/` before validation. Restores the developer's exact prior configuration (re-running generation with detected app, watch, and `--healthkit` arguments, and falling back to file-level restore on failure or cancellation via an EXIT trap), so active watch, KiedyBus, HealthKit, or local override setups are never lost.

### 4. Changed Targets & Working Copy Verification

* **Locally (`scripts/pre_pr_check` or `scripts/pre_pr_check --targets-only`):**
  * Analyzes changed files against the base branch (`upstream/main` or `origin/main`) and groups them by target/component (`OBAKitCore`, `OBAKit`, `OBAKitWatch`, `WatchApp`, `OBAWidget`, `Apps/*`, `Tests`, `Tooling`, `Documentation`).
  * Identifies affected targets to help developers understand which test suites and CI jobs their changes will exercise.
  * Checks `git status` for uncommitted changes, with optional strict enforcement via `--require-clean`. With `--require-clean`, a dirty tree also fails before any other step runs.

## Command Reference

| Command | Description |
|---|---|
| `scripts/pre_pr_check` | Complete pre-PR gate: module boundaries + SwiftLint + project generation matrix + target/working copy checks |
| `scripts/pre_pr_check --boundaries-only` | Run only module boundary and architectural invariant checks |
| `scripts/pre_pr_check --lint-only` | Run only SwiftLint errors and custom rules check |
| `scripts/pre_pr_check --project-only` | Run only project generation matrix validation |
| `scripts/pre_pr_check --targets-only` | Run only changed targets and working copy analysis |
| `scripts/pre_pr_check --require-clean` | Enforce zero uncommitted changes in git working tree (honored across all modes) |
| `scripts/swiftlint.sh --pre-pr` | Convenience alias delegating to `pre_pr_check` |

## Historical Notes (#1340, #1325, #1303, #1834, #1838)

1. **`longPressGesture` is `private`** again — only used in `MapViewController.swift`.
2. **Lint is its own CI job** (`lint:` beside `build:`), so a lint failure does not erase test signal for the same run.
3. **SwiftLint is version-pinned** in `.github/workflows/tests.yml` (`SWIFTLINT_PIN`, official portable release). Bump the pin after reviewing new error-tier rules — do not rely on unpinned `brew install`.
4. Extension doc comments no longer claim a `type_body_length` ceiling that the split already removed.
5. **Unified pre-PR verification** folds module boundary checks, fixture self-tests, SwiftLint custom rules, and project generation matrix into a single local command that leaves the developer's tree in its exact prior configuration.
