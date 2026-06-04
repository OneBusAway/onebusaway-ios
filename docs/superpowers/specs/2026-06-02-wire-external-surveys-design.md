# Wire up external surveys — design

**Issue:** [#1148](https://github.com/OneBusAway/onebusaway-ios/issues/1148)
**Date:** 2026-06-02

## Problem

External surveys (`type: "external_survey"`) are served by the backend and fully
parsed by the app, but they are never opened. `ExternalSurveyURLBuilder` — which
assembles the provider URL with embedded-data query params and is fully
unit-tested — is never invoked from production code. A rider who receives an
external survey (e.g. a Qualtrics link) sees only a static, non-interactive text
label and has no way to reach the survey.

This spec wires the existing builder into the live survey UI so external surveys
actually launch.

## Existing pieces

- `OBAKitCore/Surveys/Helper/ExternalSurveyURLBuilder.swift` — builds the URL
  from the survey's first question and appends supported embedded-data fields
  (`user_id`, `region_id`, `route_id`, `stop_id`, `recent_stop_ids`,
  `current_location`). Validates `http(s)` + host; returns `nil` (and logs) on
  invalid/missing URL. Its URL-building logic is unchanged; **one deliberate
  exception**: its stored `application` reference becomes `unowned`/`weak` to
  break a retain cycle (see §5).
- `OBAKitCore/Surveys/Helper/ExternalSurveyURLBuilderProtocol.swift` —
  `func buildURL(for survey: Survey, stop: Stop?) -> URL?`.
- `OBAKitCore/Surveys/Helper/SurveyURLApplicationContext.swift` — requires
  `currentRegionIdentifier: Int?` and `currentCoordinate: CLLocationCoordinate2D?`.
  Becomes class-bound (`: AnyObject`) so it can be held weakly (see §5).
- `OBAKitTests/Surveys/ExternalSurveyURLBuilderTests.swift` — comprehensive
  builder unit tests (kept as-is; the mock context becomes a class).

## Design

### 1. Architecture overview

- `CoreApplication` conforms to `SurveyURLApplicationContext` (it owns both
  `regionsService` and `locationService`, and lives in OBAKitCore alongside the
  protocol).
- `SurveyService` vends the builder and exposes a thin
  `externalSurveyURL(for:stop:)` method.
- A full `Stop?` is threaded through the survey display path so `stop_id` /
  `route_id` resolve.
- The dead `.externalSurvey` label is replaced with a tappable control in both
  `SurveyViewController` (sheet / full) and `SurveyCell` (inline hero). Tapping
  builds + opens the URL; on a successful open it marks the survey completed and
  dismisses / refreshes (failures don't mark completed — see §4).

### 2. Context conformance + builder vending

**`CoreApplication: SurveyURLApplicationContext`** (in an extension):

```swift
public var currentRegionIdentifier: Int? { regionsService.currentRegion?.regionIdentifier }
public var currentCoordinate: CLLocationCoordinate2D? { locationService.currentLocation?.coordinate }
```

**`SurveyService`** gains the context and vends a builder:

- Add `weak var application: SurveyURLApplicationContext?` (held weakly — see §5),
  set via `init`, passed as `self` from the two construction sites in
  `CoreApplication` (around lines 278 / 283).
- Expose a lazily-built `externalSurveyURLBuilder: ExternalSurveyURLBuilderProtocol?`,
  constructed with `userDataStore`, `userDataStore.surveyUserIdentifier`, and the
  context. The property is settable/injectable so tests can swap a mock.
- Add `func externalSurveyURL(for survey: Survey, stop: Stop?) -> URL?` that
  delegates to `externalSurveyURLBuilder?.buildURL(for:stop:)`.

This keeps URL construction owned by `SurveyService` and gives integration tests
a real service → builder seam to exercise (AC 1–11), not just the isolated
builder. Note that `SurveyService` deliberately does **not** open the URL itself:
it lives in OBAKitCore, which must remain application-extension-safe, and
`UIApplication.shared` is unavailable in app extensions. URL *construction* (no
UIKit) belongs here; the *open* seam stays in the OBAKit UI layer (see §4).

When `application` is `nil` (e.g. tests that don't provide a context),
`externalSurveyURLBuilder` is `nil` and `externalSurveyURL(...)` returns `nil`;
tests that need URL construction either provide a mock context or inject a mock
builder directly.

**Concurrency contract.** `SurveyService` is `@MainActor` with a `nonisolated init`.
`CoreApplication` is a non-`Sendable` `NSObject` and is passed into that
`nonisolated init` as the context. The context (and its `regionsService` /
`locationService` reads for `currentRegionIdentifier` / `currentCoordinate`) is
only ever read on the main actor, from `externalSurveyURL(...)` which is invoked
from main-actor UI. `RegionsService` / `LocationService` are non-isolated `@objc`
services whose property reads are main-actor-safe today. This is a deliberate,
audited choice and will be called out in the PR so reviewers don't trip on the
non-`Sendable` capture under strict concurrency.

### 3. Threading the `Stop` through

Add an optional `stop: Stop?` to the display path:

- `SurveyDisplayManager.showSurvey(...)` → add `stop: Stop? = nil`.
- `SurveyBottomSheetController.init(...)` → add `stop: Stop? = nil`.
- `SurveyViewController.init(...)` → add `stop: Stop? = nil`. Keep `stopID` /
  `stopLocation` for the existing hero-submit flow; `stop` purely feeds the
  builder, avoiding churn to the submit path.

Call sites:

- `StopViewController.showFullSurvey` (line ~699) and the hero
  `SurveyStopListItem` already have `stop` → pass it.
- `MapViewController.checkForMapSurvey` (line ~219) → passes `stop: nil`
  (correctly yields nil `stop_id` / `route_id`).

### 4. UI changes, tap behavior, error handling

**`SurveyViewController` `.externalSurvey` case** — replace the inert `LabelRow`
with a label row showing `labelText` plus a `ButtonRow` (localized "Open Survey")
whose `onCellSelection` calls a shared `openExternalSurvey()`.

**`SurveyCell` hero path** — for `.externalSurvey`, instead of hiding everything,
show an "Open Survey" button (reuse the filled-button style). Add a new
`onOpenExternalSurvey` closure to `SurveyStopListItem`; `StopViewController`
handles it (it has `stop`). The new closure is **excluded from
`SurveyStopListItem`'s hand-written `Equatable`/`Hashable`** conformances,
consistent with the existing `onNext`/`onDismiss`/`onSelectionChanged` action
closures (closures aren't `Equatable`; the struct diffs on `survey` / `stopID` /
`selectedOption`).

**`openExternalSurvey()` (shared logic):**

1. `guard let url = surveyService.externalSurveyURL(for: survey, stop: stop)` —
   if `nil`: `Logger.error(...)` + a brief non-crashing alert/toast; **do not**
   dismiss or mark completed (AC 10).
2. Open via an injected `urlOpener: (URL, @escaping (Bool) -> Void) -> Void` seam
   that surfaces success. The production default wraps
   `UIApplication.shared.open(_:options:completionHandler:)` in a closure (it
   cannot be passed as a bare method reference because of the defaulted
   `options` / `completionHandler` parameters):
   ```swift
   { url, completion in UIApplication.shared.open(url, completionHandler: completion) }
   ```
   The seam is a stored property and must not capture the VC, avoiding a cycle.
3. **Only on `success == true`:** `surveyService.markSurveyCompleted(survey)`
   (respects `alwaysVisible` / multi-response rules already in the service), then
   dismiss the sheet (sheet / full path) or refresh the stop list
   (`listView.applyData()`, hero path). On `success == false` (well-formed URL
   the system declined to open): `Logger.error(...)` + brief toast, and **do
   not** mark completed or dismiss (AC 14) — same no-silent-success posture as
   the nil-URL case.

### 5. Object lifecycle / retain-cycle avoidance

`CoreApplication` strongly owns `surveyService`, which would strongly own the
`externalSurveyURLBuilder`, which strongly stores its `application` context — and
that context *is* `CoreApplication`. That forms a strong reference cycle (two,
counting both the service's and the builder's references):

```text
CoreApplication ──strong──▶ surveyService ──strong──▶ builder ──▶ application (== CoreApplication)
```

`refreshSurveysService()` replaces `surveyService` on region changes, so a stale
service retained by a presented VC would leak the cycle. To break it:

- Make `SurveyURLApplicationContext` class-bound: `protocol … : AnyObject`.
- Hold the context **weakly** in `SurveyService` (`weak var application`) and
  **`unowned`/`weak`** in `ExternalSurveyURLBuilder`. `CoreApplication` is the
  long-lived owner; neither the service nor the builder should co-own it.

This is the one change to the otherwise-untouched `ExternalSurveyURLBuilder`
(and its test mock must become a class to satisfy `AnyObject`).

### 6. Testing

- **SurveyService-level integration (AC 1–11):** with a mock
  `SurveyURLApplicationContext` + real builder, assert `externalSurveyURL(for:stop:)`
  returns the exact URL / query items for each embedded-data scenario and the
  nil cases. Proves the service → builder wiring, not just the isolated builder.
- **Completion (AC 14):** after invoking the tap-through path, assert
  `markSurveyCompleted` updates `isSurveyCompleted` / `visibleSurveys` per
  existing rules.
- **Open seam (AC 1, 4, 10, 12):** inject a stub `urlOpener` into the VC; assert
  it's called with the expected URL on valid input and **not** called on nil URL.
  Drive the stub's completion with `true` and assert `markSurveyCompleted` +
  dismiss occur; drive it with `false` and assert they do **not** (AC 12).
- **Location unavailable (AC 6):** assert `current_location` is absent when
  `currentCoordinate` is `nil` — a distinct case from "no stop."
- **UI render (AC 13):** lightweight check that the `.externalSurvey` row / cell
  produces a tappable control (best-effort given the repo's minimal UI-test
  posture).

## Acceptance criteria

Mapped from issue #1148:

**URL construction is actually used (integration):**

1. Valid `https` URL, no embedded data → opens exactly that URL, no extra params.
2. `embedded_data_fields: ["user_id"]` → URL contains `user_id=<current user id>`.
3. `["region_id"]` with a current region → `region_id=<currentRegionIdentifier>`;
   no region → key absent.
4. `["stop_id","route_id"]` from a stop with id `S`, routes `[A,B]` →
   `stop_id=S` and `route_id=A,B`; from the map (no stop) → both absent.
5. `["recent_stop_ids"]` → comma-joined recent stop ids; none → key absent.
6. `["current_location"]` with a known coordinate → `current_location=<lat>,<lon>`;
   none → key absent.
7. All six fields populated → all six expected query items present.
8. Unknown / unsupported embedded keys are silently ignored.
9. A base URL with existing query params keeps them and appends embedded items.

**Failure / edge handling (no silent success):**

10. Missing or non-`http(s)` URL → tapping opens nothing, logs an error, does not
    crash, does not mark completed, does not dismiss.
11. Map-launch path (no `Stop`) builds a URL when only stop-independent fields are
    requested.
12. A well-formed `http(s)` URL the system declines to open (open completion
    returns `false`) → logs an error, shows a brief toast, does **not** mark the
    survey completed, does **not** dismiss. (No silent success on open failure.)

**UI behavior:**

13. An `external_survey` question renders with a visible, tappable control (not an
    inert `LabelRow`).
14. After tapping through, the survey is recorded as shown / completed per existing
    visibility rules and is not re-presented contrary to those rules.

## Out of scope

- `sdk_configuration_values` handling — not modeled on iOS. External surveys on
  iOS rely on URL + query-param embedded data only. This will be stated explicitly
  in the PR description so it isn't silently assumed to work. An SDK-based provider
  is a separate effort.
- No unrelated refactoring of the survey display path beyond the parameter
  threading described above.

## Affected files

- `OBAKitCore/Orchestration/CoreApplication.swift` — context conformance, pass
  `self` into `SurveyService`.
- `OBAKitCore/Surveys/Helper/SurveyURLApplicationContext.swift` — make class-bound
  (`: AnyObject`).
- `OBAKitCore/Surveys/Helper/ExternalSurveyURLBuilder.swift` — change stored
  `application` reference to `unowned`/`weak` (only change; URL logic untouched).
- `OBAKitCore/Surveys/Service/SurveyService.swift` — weak context init param, vend
  builder, `externalSurveyURL(for:stop:)`.
- `OBAKit/Surveys/SurveyDisplayManager.swift` — `stop:` param.
- `OBAKit/Surveys/SurveyBottomSheetController.swift` — `stop:` param.
- `OBAKit/Surveys/SurveyViewController.swift` — `stop:` param, tappable
  `.externalSurvey` row, `openExternalSurvey()`, `urlOpener` seam.
- `OBAKit/Surveys/SurveyCell.swift` — tappable hero `.externalSurvey` button.
- `OBAKit/Surveys/SurveyStopListItem.swift` — `onOpenExternalSurvey` closure.
- `OBAKit/Stops/StopViewController.swift` — pass `stop`, handle hero open.
- `OBAKit/Mapping/MapViewController.swift` — pass `stop: nil`.
- `OBAKitTests/Surveys/` — new integration + completion + open-seam tests.
