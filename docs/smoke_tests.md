# Release Smoke Tests

This document describes the release smoke testing scripts and workflows in OneBusAway iOS.

## Overview

Static compiles (`xcodebuild build`) and unit tests (`xcodebuild test`) do not verify whether an app actually launches and stays alive on a simulator device. In particular, failures such as:

- Missing or misconfigured `LD_RUNPATH_SEARCH_PATHS` causing immediate dynamic linker (`dyld`) termination (`Library not loaded`, `Reason: image not found`)
- Missing embedded frameworks or incorrect framework embedding paths
- Corrupted or missing keys in `Info.plist`
- Asset catalog or critical resource loading failures on startup
- Swift initialization runtime crashes or thread aborts during cold launch

are only caught when the app bundle is installed and launched on a simulator.

Two dedicated smoke test scripts automate this validation deterministically, backed by shared routines in `scripts/lib/smoke_common.sh`:
1. `scripts/app_smoke_test` — Smoke tests the main iOS app shell (`App.app` built for `OneBusAway` or `KiedyBus`).
2. `scripts/watch_smoke_test` — Smoke tests the watchOS app shell (`WatchApp.app`).

---

## Simulator Resolution & Overrides

Simulators are resolved automatically using:
- `scripts/resolve_simulator_udid` (for iOS simulators)
- `scripts/resolve_watch_simulator_udid` (for watchOS simulators)

Both scripts pick the most appropriate simulator on the newest installed runtime and support deterministic overrides across local developer machines and CI runners:

### Named Simulator Override
Target a device by name (exact or case-insensitive substring):
```bash
scripts/resolve_simulator_udid --name "iPhone 18 Pro"
scripts/resolve_watch_simulator_udid --name "Apple Watch Ultra 2"
```

### Explicit UDID Override
Validate and use an explicit simulator UDID:
```bash
scripts/resolve_simulator_udid --udid "6F86FE65-A734-42C1-BF22-245618CCB265"
scripts/resolve_watch_simulator_udid --udid "$WATCH_UDID"
```

### Environment Variables
You can also supply default overrides via environment variables:
- `SIMULATOR_OVERRIDE_UDID` / `SIMULATOR_OVERRIDE_NAME`
- `WATCH_SIMULATOR_OVERRIDE_UDID` / `WATCH_SIMULATOR_OVERRIDE_NAME`

---

## Running Smoke Tests

### iOS App Smoke Test (`scripts/app_smoke_test`)

```bash
# Basic run: builds App scheme, boots simulator, installs, launches, and verifies 8s liveness
scripts/app_smoke_test

# Specify custom DerivedData path
scripts/app_smoke_test DerivedData

# Reuse prebuilt binary (e.g. after building in an earlier step)
scripts/app_smoke_test --skip-build

# Override target simulator by name or UDID
scripts/app_smoke_test --name "iPhone 18 Pro"
scripts/app_smoke_test --udid "6F86FE65-A734-42C1-BF22-245618CCB265"

# Capture a screenshot if the app fails or crashes
scripts/app_smoke_test --screenshot-on-failure
scripts/app_smoke_test --screenshot-dir ./artifacts/smoke_screenshots

# Dry run preflight checks (validates simulator, paths, flags without building or launching)
scripts/app_smoke_test --dry-run
```

### watchOS App Smoke Test (`scripts/watch_smoke_test`)

```bash
# Basic run: builds WatchApp scheme, boots watch simulator, installs, launches, verifies liveness
scripts/watch_smoke_test

# Specify custom DerivedData path (used in CI)
scripts/watch_smoke_test DerivedData

# Target Apple Watch Ultra
scripts/watch_smoke_test --ultra

# Override watch simulator by name or UDID
scripts/watch_smoke_test --name "OBA Watch Smoke"
scripts/watch_smoke_test --udid "$WATCH_UDID"

# Reuse prebuilt binary
scripts/watch_smoke_test --skip-build

# Capture a screenshot if the watch app fails
scripts/watch_smoke_test --screenshot-on-failure

# Dry run preflight checks
scripts/watch_smoke_test --dry-run
```

---

## Failure Diagnostics

When an app crashes or fails to stay alive during the smoke test verification window, the smoke test scripts output actionable diagnostics:

1. **Host Crash Reports (`~/Library/Logs/DiagnosticReports/`)**:
   Scans the local macOS DiagnosticReports directory for crash logs (`.ips` / `.crash`) generated during the smoke run. Extracts:
   - `Termination Reason` and `Termination Signal`
   - `Exception Type` and `Exception Codes`
   - `Dyld Error Message` and `Application Specific Information`
   - Crashed thread backtrace

2. **Targeted dyld & Simulator System Logs**:
   Queries `xcrun simctl spawn <UDID> log show` using compact filtering predicates:
   ```bash
   eventMessage CONTAINS "Library not loaded" OR eventMessage CONTAINS "OS_REASON_DYLD" OR eventMessage CONTAINS "dyld"
   ```
   This isolates the exact missing symbol or image before it is buried by system launch daemons.

3. **Process Logs**:
   Captures recent system log entries filtered by process name or bundle identifier.

4. **Diagnostic Screenshot Capture**:
   When `--screenshot-on-failure` or `--screenshot-dir <DIR>` (or `SMOKE_SCREENSHOT_ON_FAILURE=1` / `SMOKE_SCREENSHOT_DIR`) is enabled, a full-resolution PNG of the simulator screen is captured via `xcrun simctl io <UDID> screenshot <PATH>` and saved for headless debugging.

---

## CI Integration

In GitHub Actions workflows (`.github/workflows/tests.yml`), the watch smoke test runs in the macOS `watch` job to assert that dyld loads and the application remains alive after boot:

```yaml
- name: Watch app launch smoke test
  if: success() || failure()
  timeout-minutes: 15
  run: scripts/watch_smoke_test DerivedData
```

### Suggested CI Enhancement: Diagnostic Screenshots (Optional)

When diagnosing headless CI simulator launch failures, workflows can optionally capture and preserve diagnostic screenshots as workflow artifacts:

```yaml
- name: Watch app launch smoke test
  if: success() || failure()
  timeout-minutes: 15
  run: scripts/watch_smoke_test DerivedData --screenshot-dir DerivedData/smoke_screenshots

- name: Upload smoke test diagnostics on failure
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: smoke-test-diagnostics
    path: DerivedData/smoke_screenshots/
```
