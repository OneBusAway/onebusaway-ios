# Release Readiness: Test Coverage & Localization — Design

**Date:** 2026-06-10
**Scope:** Prepare OneBusAway iOS for its first App Store release since v26.1.0 (January 2026; 344 commits ago).

## Context

Major features shipped since v26.1.0: proximity alerts/geofencing, surveys, cloud push
(OneSignal replacement), SQLite stop cache (GRDB), trip transfer/"my current trip",
region storage migration to disk, UIScene adoption (iOS 27 requirement), auto region
selection, ViewModel layers, vehicle map with smooth animation, search list migration,
customizable More tab, and walking speed settings.

A coverage audit found:

1. **No XCUITest target exists.** No accessibility identifiers in app code.
2. **Zero unit tests** for `OBACloudPushService`/`PushService` and `VehiclesViewModel`.
3. **The one-time UserDefaults→disk region migration** (`RegionsService`) is untested.
   Every upgrading user runs it exactly once; failure could lose the selected region
   or custom regions.
4. `MapViewModelTests.test_loadWeather_errorClearsForecast` is flaky in randomized
   full-suite runs (passes in isolation).
5. UIScene config validated against Apple TN3187: manifest is correct; lifecycle
   forwarding is sound (nothing depends on app-level background/foreground delegate
   callbacks).

## Decisions

### Unit tests (highest-risk gaps only)

- **RegionsService migration**: make `migrateFromUserDefaultsIfNeeded` internal
  (tests use `@testable import`). Cover: default-regions migration success +
  corrupted-data discard + write-failure retry semantics; custom-regions partial
  failure leaves legacy key; current-region object→identifier conversion; idempotency.
- **Push**: `OBACloudPushService` token hex conversion, pending callback
  delivery/clearing, failure handling, immediate callback when token exists.
  `PushService` notification routing via a mock `PushServiceProvider`:
  `arrival_and_departure` → `AlarmPushBody` decode → delegate; `donation` → delegate;
  malformed payloads → no delegate call, no crash. No tests that hit
  `UNUserNotificationCenter.requestAuthorization` (simulator-dependent).
- **VehiclesViewModel**: guard paths (nil apiService/region), fetch with stubbed
  agencies and all agencies disabled (no live network), skipped feed statuses,
  lastUpdated/isLoading transitions, agency enable/disable + toggleAll, auto-refresh
  start/stop lifecycle.

### XCUITest target (new)

- New `OBAKitUITests` target (`bundle.ui-testing`) defined in `OBAKitUITests/project.yml`,
  included from the root `project.yml`, attached to the App scheme (not run in the
  existing CI unit-test job; UI tests are opt-in).
- Smoke tests, deliberately network-light:
  1. **Onboarding**: fresh launch (`TEST_ONBOARDING=1` env var already supported) →
     location authorization page → region picker → main UI.
  2. **Main flows**: with a region already selected, verify tab bar renders and each
     tab (Map, Recents, Bookmarks, More) opens without crashing; More tab shows
     expected sections.
- Add `accessibilityIdentifier`s sparingly where queries need them.

### Localization

Target languages: Arabic, Chinese (Simplified + Traditional), Filipino, French,
Korean, Portuguese (Brazil), Russian, Spanish (es), Vietnamese. Ensure full string
coverage in each (some already partially exist). Remove the Transifex integration
entirely (scripts, config, docs references); translations live in-repo from now on.
`CFBundleLocalizations` updated to match.

### Out of scope

- UI tests for deep links, push notifications, or iPad multitasking (manual QA).
- Refactoring view controllers for testability beyond what the above requires.
- Schedule/search/survey UI unit tests (view-model layers already covered).
