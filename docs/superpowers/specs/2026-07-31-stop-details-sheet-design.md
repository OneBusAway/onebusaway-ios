# Stop Details Sheet — Design

**Date:** 2026-07-31
**Branch:** `feature/stop-page-view-sheet`

## Summary

Replace the UIKit stopgap behind `AppSheetRoute.stopDetails` with a native SwiftUI
sheet, built from the existing Stop page components. The sheet gets a Refresh
button and a Close button at the top, and a row of circular action buttons —
Schedule, Filter, Bookmark, More — below the header. It lives in
`OBAKit/Sheet/Content/Stop/Details/`.

Behaviour parity with `StopPageViewController` is the goal; the chrome is what
changes.

## Current state

Three presentations of the Stop page exist or are planned. Understanding which is
which is a prerequisite for reading the rest of this document.

**1. Pushed (shipping).** `Router` → `StopPageViewController(showToolbarOnBottom:
false)`. A dark, full-bleed map-snapshot header (`StopPageHeaderView`) as the first
list row; chrome in the navigation bar via `configureBarButtons()` (Schedules,
Filter, More).

**2. FloatingPanel sheet (shipping).** `MapViewController` → `StopSheetPresenter`
→ `StopPageViewController(showToolbarOnBottom: true)`. A light, compact
`StopPageSheetHeaderView` pinned as a top `safeAreaInset`, and `StopPageToolbar`
(Refresh / Bookmark / Schedules / More, with Filter, Service Alerts, Nearby Stops,
Walking Directions and Report a Problem inside More) as a bottom `safeAreaInset`.
Has a `.tip` detent that collapses the header via `isCollapsed`.

**3. SwiftUI sheet (the subject of this document).** `AppSheetRoute.stopDetails` →
`AppSheetViewFactory.stopDetailView` → `StopDetailSheetHost`, which wraps
`StopPageViewController` — *without* `showToolbarOnBottom` — in a
`UINavigationController` and adds a Close button. The result is the pushed chrome
rendered inside a sheet. This is the stopgap being replaced.

`StopPageNavigationHandler` already carries the five sheet-only closures
(`showRouteFilter`, `showServiceAlerts`, `showNearbyStops`, `showReportProblem`,
`closeSheet`) that presentation 2 introduced.

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Where the UIKit modal flows live | Extracted into a shared `StopPageActionPresenter` | A SwiftUI sheet has no view controller; duplicating ~450 lines would drift |
| How the sheet reaches UIKit | Present from the topmost presented controller | UIKit ignores `present` on a controller that already has a `presentedViewController` |
| Navigation out of the page | UIKit modals over the sheet stack | Full parity now; `.tripDetails` / `.transitAlert` sheet routes remain unimplemented |
| Composition strategy | Extract derivation + shared sections; `StopPageView` delegates to them, the new sheet composes them directly | Avoids a third boolean flag on `StopPageView` |
| Chrome scope | New circular action row applies to presentation 3 only | Presentation 2 keeps its bottom toolbar untouched |
| Detent | `.large` only, unchanged | Already configured; no map peek wanted |
| Header | `StopPageHeaderView` — the pushed screen's dark map card | Visual consistency with the pushed screen; `.large` covers the map, so the compact header's "map is visible above" rationale does not hold here |
| Chrome behaviour | Top bar pinned in a fixed inset; the action row pinned as a **sticky overlay**; the map card scrolls between them | Gives the requested order *and* permanently reachable actions. A collapsing `safeAreaInset` would do the same but hangs the app — see [Collapsing chrome](#collapsing-chrome) |
| Pull to refresh | Removed in presentation 3 | Refresh is the button's job here |
| Entry point | Register in the factory only | Nothing pushes `.stopDetails` yet; map annotations are separate work |
| iPad | Out of scope for this experience | Sheet is iPhone-only |

## Architecture

### New: `StopPageContent` (`OBAKit/Stops/StopPage/Shared/`)

A plain value type constructed from `StopViewModel` inside a view `body`. It owns
the derivation currently inlined in `StopPageView.body`:

- `filteredDepartures` — hidden-route filtering plus `filteringTerminalDuplicates()`,
  which collapses the arrival/departure pair the API emits for one vehicle visit at
  a terminal or loop stop
- `isGrouped`, `routeGroups`, `listIsEmpty`
- `showsLoadingState`, `hasLoadedArrivals`
- `attributionText`
- `departureIDs` / `routeIDs`, the sets the expansion reconcilers compare against

Being a value computed per body evaluation, it preserves the existing invariant that
the view model's refresh and status-timer churn re-evaluates exactly one shallow
body. Because it is pure, it is directly unit-testable — today none of this logic is.

### New: `StopDeparturesSections` (`OBAKit/Stops/StopPage/Shared/`)

A `View` returning the shared section stack: survey → donation → service alerts →
mode toggle → departures (chronological / grouped / empty / loading) → footer.
Returning several `Section`s from one body is the shape `ServiceAlertsSection`
already uses. Takes plain values and closures; holds no view model reference.

### New: `StopPageActionPresenter` (`OBAKit/Stops/StopPage/`)

Takes `Application` and a `presentingController: () -> UIViewController?` provider.
Owns every flow currently in `StopPageViewController`'s private extensions:

- schedule for stop, schedule for route
- bookmark editor (stop-level and departure-level)
- route filter picker (`StopPreferencesWrappedView`)
- walking directions, including the multi-app disambiguation sheet
- nearby stops, service alert list, report a problem
- full survey presentation and the external-survey error alert
- donation learn-more modal and the donation dismiss action sheet
- the `AlarmBuilder` lead-time bulletin, as `AlarmBuilderDelegate`
- Live Activity start

`BookmarkEditorDelegate` and `StopPreferencesViewDelegate` move onto it. It vends
`makeNavigationHandler(viewModel:)` returning the existing
`StopPageNavigationHandler`, so no consumer duplicates closure wiring.

It also vends `makeUserActivity(stop:)` from `application.userActivityBuilder`, and
`loadSnapshot(size:)` for the header's map card — the async bridge over
`MapSnapshotter` that `StopPageViewController` owns today, moved so the sheet can
reach it without a view controller. It moves verbatim, including the forced
`userInterfaceStyle = .dark` (the card is always-dark by design, so the snapshot
must be too) and the `withExtendedLifetime` around the snapshotter:
`MapSnapshotter`'s internal `MKMapSnapshotter.start` completion is `[weak self]`, so
without it the wrapper deallocates mid-render, the continuation never resumes, and
the header stays permanently blank.

### Rewired: `StopPageView`

Keeps both current modes and both booleans. Its body becomes header selection plus
`StopDeparturesSections`, backed by `StopPageContent`. Behaviour for presentations 1
and 2 is unchanged — this is a pure refactor they do not observe, and
`StopPagePresentationTests` is the contract that proves it.

### Reused unchanged: `StopPageHeaderView`

The pushed screen's dark map card is reused as-is, fed by the presenter's
`loadSnapshot(size:)`. No changes to the file.

`StopPageSheetHeaderView` — the compact light header — is **not** used here and is
not modified, so the FloatingPanel sheet is provably unaffected by this work.

### New: `stopPageLifecycle` and `keepsScreenAwake` modifiers

`stopPageLifecycle(viewModel:userDefaults:)` lives beside `StopPageContent` in
`OBAKit/Stops/StopPage/Shared/`. `keepsScreenAwake()` is presentation-agnostic and
lives in `OBAKit/Controls/SwiftUI/`, next to the other shared SwiftUI helpers.

### Rewired: `StopPageViewController`

Passes `{ self }` as the presenting-controller provider and delegates the flows to
the presenter. Retains its Combine bindings, navigation-bar chrome, `Previewable`,
`NSUserActivity`, `Idleable` and haptics.

### New: `StopDetailsSheetView` (`OBAKit/Sheet/Content/Stop/Details/`)

Owns `StopViewModel` as a `@StateObject` via an `@autoclosure`, matching how
`CurrentTripView` receives its view model from the factory. Reads
`SheetCoordinator<AppSheetRoute>` from the environment and closes via
`coordinator.pop()`.

Body: a `.plain` `List` containing `StopDeparturesSections`, with all chrome —
top bar, map card, action row — installed as a single top `safeAreaInset`.
`safeAreaInset` rather than a `VStack` wrapper, for the reason `StopPageView` already
documents: a wrapper resolves the top safe area differently across detents and lets
the header droop.

### New: `StopDetailsSheetTopBar` (`OBAKit/Sheet/Content/Stop/Details/`)

The slim pinned strip: Refresh leading, Close trailing, and the stop name fading in
between them as the map card collapses. Refresh is disabled and shows a spinner while
`isRefreshing`; its VoiceOver value carries the freshness text (`statusText`), the
same treatment `StopPageToolbar` uses so a label that rewrites itself every few
seconds doesn't make the bar restless.

### New: `StopSheetHeaderCollapse` (`OBAKit/Sheet/Content/Stop/Details/`)

A pure value that maps scroll offset to a 0…1 collapse progress, extracted from the
view so it can be unit-tested — the precedent set by
`shouldDisableBackgroundForFullScreen`. See [Collapsing chrome](#collapsing-chrome)
for the mechanism and the feedback-loop hazard it exists to avoid.

### New: `StopPageActionRow` (`OBAKit/Sheet/Content/Stop/Details/`)

The four circular buttons. Plain values and closures.

Its enabled/filled predicates are extracted into a `StopPageActionRowState` value in
the same file, so they can be asserted directly rather than through view
inspection — the precedent set by `shouldDisableBackgroundForFullScreen`, which was
pulled out of a view modifier for the same reason.

### Deleted

`StopDetailSheetHost.swift` and `OBAKitTests/Sheet/StopDetailSheetHostTests.swift`.
`AppSheetViewFactory.stopDetailView(stopID:)` returns `StopDetailsSheetView`.

## UI

Chrome order at rest, top to bottom: top bar → map card → action row → departures.

### Header

`StopPageHeaderView`, the pushed screen's dark full-bleed map card, reused unchanged.
It already carries the "Updated: …" status line, stop name, code/direction subtitle
with inline route chips, and the walk pill that opens walking directions. The map
snapshot comes from the presenter's `loadSnapshot(size:)`.

It stays always-dark, as on the pushed screen. Its own `.task(id: cardWidth)` loads
the snapshot once and keeps it, and since the collapse animates height rather than
width, no reload is triggered while scrolling.

`StopPageHeaderPlaceholderView` covers the loading state, as on the pushed screen. The
sheet does not need the compact header's "always render a close button" behaviour,
because Close lives in the pinned top bar and survives every state — including a first
fetch that fails, where the header is absent entirely.

`isCollapsed` is not used: it belongs to the FloatingPanel `.tip` detent, and this
route is `.large`-only.

### Collapsing chrome

> **Superseded on 2026-07-31 after the collapsing version shipped and hung the
> app.** The original design is kept below the line as a record of what was
> tried and why it fails. What ships is described here.

**What ships.** `StopDetailsSheetTopBar` sits alone in the top `safeAreaInset`
at a fixed height. The map card is the list's first row. The action row is an
**overlay** whose vertical position tracks scrolling:

```swift
private var actionRowOffset: CGFloat {
    topBarHeight + max(0, mapCardHeight - scrollOffset)
}
```

At rest that puts it directly beneath the map card; as the list scrolls it rises
until it meets the top bar and stops, with the card sliding underneath. A spacer
row of `actionRowHeight` sits after the card so the first departures are not
hidden beneath the overlay at rest, and both heights are measured so they track
Dynamic Type together.

**Why an overlay rather than a second inset.** An overlay takes no part in the
list's layout, so its position can depend on scroll offset without the scroll
view ever observing the result. That is the exact property the collapsing header
lacked: there, scroll drove an inset's *height*, and the inset's height fed back
into scroll offset. Here, scroll position drives only the overlay's `y` and the
title's opacity — the list's insets never change.

Verified on an iOS 26.5 simulator with six stepped scrolls through the mid-range
(the region that hung the collapsing version): `actionRowOffset` moved 220 → 50
→ 220 exactly as designed, the measured heights stayed constant, and the body
evaluated 15 times in total. No oscillation.

---

**Why the collapsing version cannot work as designed.** The original plan put
the top bar, map card and action row in one `safeAreaInset` whose height shrank
with a `collapseProgress` derived from scroll position, and claimed the feedback
loop was avoided by measuring `contentOffset.y + contentInsets.top` rather than
`contentOffset.y`, on the theory that the sum is invariant when the inset
resizes.

**That theory is false.** Measured on an iOS 26.5 simulator with a forced
scroll, the moment the 170 pt header collapsed:

```
offset=819.33  progress 1.0 -> 1.0
offset=649.33  progress 1.0 -> 1.0     ← the metric fell by exactly 170
```

The metric shifts by precisely the inset delta. It settles only because progress
is clamped at 1.0 at that extreme. Anywhere in the mid-range the shift changes
progress, which resizes the inset, which shifts the metric again — an unbounded
oscillation on the main thread. The observable symptom is the entire app
freezing: no scrolling, no taps anywhere, including the pinned chrome.

Two properties of the bug made it easy to miss. It does not reproduce at rest
(idle body-evaluation count stays in single digits), and it does not reproduce
when a programmatic scroll jumps straight to either extreme — only a continuous
drag through the middle triggers it. It shipped because the manual verification
task that would have caught it was never run.

**If the collapse is ever revisited**, the fix is not a better metric — it is
removing the feedback edge. The inset's height must not be a function of scroll
position. Any future attempt needs on-device verification of a slow drag through
the mid-range before it is considered working.

### Action row

Below the map card, carrying its own trailing divider, so the sequence reads identity
/ actions / departures. It never scrolls away: once the card has collapsed it sits
directly beneath the top bar.

| Button | Action | State |
| --- | --- | --- |
| Schedule | `showScheduleForStop()` → `ScheduleForStopViewController` | always enabled |
| Filter | `Menu`: All Routes / Filtered Routes, checkmark on the active one | disabled at ≤ 1 route; glyph fills when `hasHiddenRoutes && isListFiltered` |
| Bookmark | `showBookmarkEditor(nil)` → `AddBookmarkViewController` | always enabled |
| More | `Menu`: Service Alerts · Nearby Stops, Walking Directions · Report a Problem | Service Alerts disabled when the stop has none |

Two behaviours carried over deliberately from `StopPageToolbar`:

1. Picking "Filtered Routes" both sets `isListFiltered = true` *and* opens the route
   picker. On a stop with no saved hidden routes the toggle alone would silently do
   nothing.
2. Filter is promoted out of More into its own button, so More holds only the
   remaining four actions.

At accessibility Dynamic Type sizes the row scrolls horizontally rather than
compressing labels into illegibility — the accommodation `StopPageToolbar` makes,
for the same reason.

## Data flow

**Construction.** `AppSheetViewFactory.stopDetailView(stopID:)` builds the view with
a `StopViewModel` for that stop, a `StopPageActionPresenter`, a
`DataLoadFeedbackGenerator`, `application.formatters` and
`application.userDefaults`. The header's `snapshotLoader` closure wraps the
presenter's `loadSnapshot(size:)`. `@StateObject` means SwiftUI instantiates the view model
exactly once per view identity; since the route ids as `stopDetails-<stopID>`, a
different stop is a different identity with its own view model.

**Ownership.** `StopDetailsSheetView` is the only observer of `StopViewModel`,
preserving the invariant `StopPageView` documents. Header, action row and
`StopDeparturesSections` all receive plain values and closures.

**Shared lifecycle.** A `stopPageLifecycle(viewModel:userDefaults:)` modifier carries
the presentation-agnostic behaviour both compositions need:

- `.task { await viewModel.start() }`
- `.onAppear` last-used-mode seeding (a stop the user has never customised opens in
  the last mode they picked anywhere in the app)
- `.onDisappear { viewModel.deactivate() }`
- the two `onChange` reconcilers that clear an expanded departure or route when a
  refresh drops it from the feed
- the "Tracking on Lock Screen" toast overlay

`.refreshable` is deliberately *not* in it — that is the one lifecycle element the
presentations now disagree on.

**Local state.** `expandedDepartureID`, `expandedRouteID`, `donationHidden` and the
`@AppStorage` past-departures toggle stay as `@State` on the composition.
`.defaultAppStorage(userDefaults)` is applied so the sheet reads and writes the
app-group suite; without it the past-collapsed and service-alerts preferences would
silently fork to `UserDefaults.standard`.

**Refresh.** The button calls `Task { await viewModel.refresh() }`;
`viewModel.isLoading` drives both its spinner and its disabled state. `refresh()`
already guards re-entrancy. The button stays pinned in the header `safeAreaInset`,
so it is reachable at any scroll position. `StopViewModel`'s ~15 s auto-refresh timer
is unaffected.

**Actions out.** The navigation handler is built once from the presenter and bound to
this view model. Every closure resolves its presenting controller lazily at call
time, so a sheet pushed above this one still gets the modal on top.

## Reaching UIKit from the sheet

Every "leaves the page" flow is UIKit and needs `someViewController.present(...)`.
`StopDetailsSheetView` is a struct with no view controller.

Presenting from the app's root does not work. The sheet system is built on SwiftUI
`.sheet(...)` (`FloatingSheetContainer`), which bridges to UIKit modals on the
hosting controller, so by the time the stop sheet is visible the chain reads
`host → base sheet (.home) → stacked sheet (.stopDetails)`. UIKit silently ignores
`present` on a controller that already has a `presentedViewController`.

The fix already exists in `MapPanelRootController`'s `TripPresentationBridge`: walk
to the end of the chain and present from there.

```swift
var presenter: UIViewController = host
while let next = presenter.presentedViewController {
    presenter = next
}
presenter.present(navigation, animated: true)
```

The host is held by a small bridge class with a `weak var host: UIViewController?`,
because `self` is not available inside `MapPanelRootController.init` before
`super.init` runs, and `weak` also breaks the retain cycle host → `UIHostingController`
→ rootView → factory → closure → bridge → host.

`AppSheetViewFactory` gains a `presentingController: () -> UIViewController?`
alongside its existing `onPresentTrip`, resolved by the same bridge, and passes it to
`StopPageActionPresenter`. This generalises `TripPresentationBridge` from one flow to
a dozen.

Sheet *dismissal* does not use this path: `closeSheet` pops the SwiftUI layer, which
is also the path the drag-down gesture takes, keeping `SheetCoordinator` storage in
sync.

## Side effects ported from the view controller

**Haptics.** `DataLoadFeedbackGenerator` is injected from the factory, as
`CurrentTripView` already does. A success tap fires on the first arrivals load only
(a `firstLoad` latch); an error buzz fires on every failed fetch. These use
`.onReceive(viewModel.$stopArrivals)` and `.onReceive(viewModel.$operationError)`
rather than `.onChange`, because neither `StopArrivals` nor `Error` is `Equatable`.

**Surveys.** `.onReceive(viewModel.presentFullSurvey)` → the presenter shows
`SurveyViewController` with the hero response id, so the hero question is not
re-submitted. `.onReceive(viewModel.surveySubmissionError)` → the standard error
alert via `AlertPresenter`.

**Alarms.** `.onReceive(viewModel.$alarmError)` → error alert.
`.onReceive(viewModel.$alarmPermissionDenied)` → the "Notifications Are Off / Open
Settings" alert, keeping the `dropFirst().filter { $0 }` shape and the
`clearAlarmPermissionDenied()` reset that lets a later attempt re-fire. The lead-time
picker is `AlarmBuilder`, owned by the presenter, which is also its delegate — the
create / change / replace flow and its `ProgressHUD` feedback move over intact.

**Live Activity.** `startLiveActivity(for:)` moves to the presenter, which has the
`Application` needed for the tracker and region id. The toast overlay rides along in
the shared lifecycle modifier.

**`NSUserActivity`.** The presenter vends `makeUserActivity(stop:)`; the view calls
`becomeCurrent()` when the stop resolves and invalidates on disappear. That is the
mechanism UIKit's `userActivity` property uses underneath, so Handoff, Siri and
Spotlight keep working without a view controller.

**Idle timer.** `CurrentTripView` already reimplements `Idleable` in SwiftUI with a
`wasIdleTimerDisabledByUs` latch. Rather than write it a third time, extract a
`keepsScreenAwake()` modifier and use it here. Switching `CurrentTripView` over is a
one-line follow-up, included but optional.

### iPad

The sheet is iPhone-only, so nothing in `StopDetailsSheetView` needs popover
anchoring: the walking-directions and donation-dismiss action sheets present as
sheets and cannot hit the unanchored-popover crash.

The anchoring code must still survive the extraction. `StopPageActionPresenter` is
shared with presentation 1, which is not scoped to iPhone —
`FloatingSheetContainer` explicitly handles the regular size class, so a
regular-width path is reachable in this codebase. Dropping the
`popoverPresentationController` setup while moving those two flows would regress the
pushed screen on a regular-width device. It moves across verbatim, anchored to
whatever `presentingController()` resolves to, and is simply never exercised by the
sheet. Dropping iPad app-wide is separate work with its own blast radius.

### Deliberate deviations from parity

1. **Scene phase.** `StopPageViewController` does not stop its refresh timer when the
   app backgrounds; `CurrentTripView` does. The sheet follows `CurrentTripView`:
   deactivate on `.background`, restart on the `.background → .active` edge only, not
   on `.inactive → .active` (returning from Control Center or a banner would
   otherwise fire a redundant fetch). A sheet floating over a live map is where
   pointless network churn shows up.
2. **`Previewable`.** The peek/preview path is a pushed-navigation concept with no
   sheet equivalent, so it is not ported. `StopPageViewController` keeps it.

### Not ported

`bookmarkContext` and `transferContext` exist for `Router`'s
`StopContextConfigurable` and are meaningful only for the pushed controller.

## Testing

Swift Testing (`@Suite(.serialized)`, `@Test`, `#expect`), inheriting `OBATestCase`
where fixtures are needed.

**New — `StopPageContentTests`.** The extraction's main payoff; this logic is
untested today because it is inlined in a view body.

- filtered vs. unfiltered departures, and the terminal-duplicate collapse that
  otherwise shows one bus twice with two different countdowns
- grouped mode empty while `departures` is non-empty (the last bus of the evening has
  left) — the case the code deliberately decides from groups rather than departures
- `showsLoadingState` precedence, including the pre-`.task` first frame that must not
  flash "No departures"
- `isFilteredEmpty` only when the filter is what emptied the list
- `attributionText` with and without agency names

**New — `StopPageActionPresenterTests`.** With a stub presenting controller, assert
each flow presents the right controller: `ScheduleForStopViewController`,
`AddBookmarkViewController` (stop-level) vs. `EditBookmarkViewController`
(departure-level), `NearbyStopsViewController`, `ReportProblemViewController`,
`ServiceAlertListController`. Plus the test that matters most: present a dummy modal
first, then assert the presenter walks past it and lands on top rather than
no-oping — the failure mode the provider exists to prevent.

**New — `StopPageActionRowStateTests`.** The button predicates (filter disabled at
≤ 1 route, glyph filled when `hasHiddenRoutes && isListFiltered`, Service Alerts
disabled when none) are extracted into a small value type and tested directly,
following the precedent of `shouldDisableBackgroundForFullScreen`, which was pulled
out of a view modifier for exactly this reason.

**Updated — `AppSheetViewFactoryTests`.** The existing assertion that
`stopDetailView` returns a `StopDetailSheetHost` becomes an assertion about
`StopDetailsSheetView` carrying the right stop ID.

**Deleted — `StopDetailSheetHostTests`,** with its subject.

**Regression guard — `StopPagePresentationTests`** already covers presentations 1 and
2 (pushed keeps its navigation-bar items, sheet installs none, preview mode
suppresses both). It must pass unchanged; that suite is the contract that the
`StopPageView` refactor is behaviour-preserving.

**New — `StopSheetHeaderCollapseTests`.** The pure progress function: 0 at rest, 1 at
and beyond the full distance, clamped outside both ends, 0 when the distance is zero,
and monotonic across the range. Still used and still valid after the collapse was
removed — the same function now maps scroll distance to the pinned title's opacity.

Note what this suite could not catch, and why the hang shipped anyway: the function
was always correct. The defect lived in what its output was wired to — the height of
a `safeAreaInset` — which no unit test in this codebase can observe.

**Previews.** SwiftUI previews for the sheet in loading, loaded, first-load-error and
filtered-empty states, plus expanded and collapsed chrome. The collapse interaction
itself, the map snapshot, and the inset feedback-loop behaviour are verified by hand
on device — `MapSnapshotter` wraps MapKit and scroll geometry needs a real scroll
view, so neither is worth faking.

**Verification.** SwiftLint, then
`xcodebuild test-without-building -only-testing:OBAKitTests` on iPhone 16 (iOS 26).
New files land in buildable folders, so no `generate_project` run is needed to pick
them up. Strict concurrency is escalated to errors in the Swift 6 language mode, so a
data-race warning fails the build — build early rather than at the end, since the
presenter mixes `@MainActor` UI with the actor-isolated API service.

No UI tests; the repo's focus is unit tests.

## Out of scope

- **Entry point.** Nothing pushes `.stopDetails` today: `MapPanelRootView` draws no
  stop annotations and `HomeSheetView` is a placeholder. The sheet is verified
  through previews and unit tests, and becomes user-reachable when the
  map-annotation / home-sheet work lands.
- **Presentations 1 and 2.** No chrome changes; behaviour must be identical.
- **Sheet routes for navigation out.** `.tripDetails`, `.transitAlert` and
  `.nearbyAll` stay unimplemented; those flows use UIKit modals.
- **`.medium` detent.** `.large`-only, as configured today.
