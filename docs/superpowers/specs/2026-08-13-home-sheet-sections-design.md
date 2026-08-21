# Home Sheet Sections — Design

**Date:** 2026-08-13
**Branch:** `feature/home-sheet-map-panel`
**Status:** Approved design, ready for implementation planning

## Summary

Populate the SwiftUI home sheet (`HomeSheetView`) with three preview sections —
Nearby Stops, Recent Stops, Bookmarks, in that fixed order. Each shows at most
four items under a header whose trailing chevron pushes the corresponding full
index route.

The home sheet is the entry point to those full indexes, so it must stay cheap:
the design budgets **zero** new network requests for Nearby and Recent, and **at
most four** for Bookmarks, with no polling timer.

**Out of scope:** the three index screens themselves (`.nearbyAll`,
`.recentStopsAll`, `.bookmarksAll`). Their routes are wired and will render the
existing "coming soon" placeholder.

## Goals

- Three sections, four items each, fixed order, each with a working header arrow.
- Reuse the data-loading paths the UIKit experience already uses rather than
  inventing parallel ones.
- Extract genuinely shared utilities so the old and new experiences share one
  implementation.
- Keep the screen light: no redundant fetches, no background refresh cycle.

## Non-Goals

- Building any index screen.
- Changing Bookmarks-tab or Map-panel behaviour. Every extraction below is
  additive and defaults to today's behaviour for existing callers.
- Pull-to-refresh, reordering, or context menus on the home sheet.

## Current State

| Piece | Today |
|---|---|
| `HomeSheetView` | Stub: search bar only, inside a `ScrollView` |
| `HomeSheetViewModel` | `searchPlaceholder` + a `nearbyStops` TODO |
| `.nearbyAll` / `.recentStopsAll` / `.bookmarksAll` | Declared in `AppSheetRoute`, stacking, `.large`; mapped to `unimplementedView(for:)` which fires `assertionFailure` in DEBUG |
| Nearby stops (SwiftUI) | `MapStopsObserver`, `@StateObject` on `MapPanelRootView`, fed by `MapRegionManager` |
| Nearby stops (UIKit) | `MapPanelViewModel.updateNearbyStops` → `NearbyStopsListViewController` |
| Recent stops | `RecentStopsViewModel.loadData()` — region filter over `UserDataStore.recentStops` |
| Bookmarks | `BookmarksViewModel` + `BookmarkDataLoader` — one arrivals request per bookmarked stop on a 30s repeating timer |

## Chosen Approach

`HomeSheetViewModel` composes three purpose-built section models, each wired to
the data source the old experience already uses. Sections stay independently
testable; the home view model only composes and caps at four.

Two approaches were rejected:

- **Reuse the full screen view models** (`MapPanelViewModel`,
  `RecentStopsViewModel`, `BookmarksViewModel`). Zero new model code, but
  `BookmarksViewModel` brings group/distance sorting, collapse persistence, Live
  Activity plumbing, and an unconditional 30-second timer, and its `start()`
  fetches *every* bookmark. Fails the call budget.
- **One flat view model** conforming to `MapRegionDelegate`,
  `BookmarkDataDelegate`, and `RegionsServiceDelegate` at once. Fewest files, but
  three refresh triggers interleave in one object and no section can be tested in
  isolation.

## Shared Utilities

Each is additive and defaulted so existing callers are untouched.

### 1. `BookmarkDataLoader` scoping seam — `OBAKitCore/Bookmarks/`

Today `eligibleBookmarks()` is private and always reads every region bookmark,
and both `loadData()` and `loadDataAndWait()` unconditionally call
`startRefreshTimer()`. Two defaulted parameters open it up:

```swift
public init(
    application: CoreApplication,
    delegate: BookmarkDataDelegate,
    bookmarkProvider: (() -> [Bookmark])? = nil,   // nil → today's eligibleBookmarks()
    autoRefreshes: Bool = true                      // false → skip startRefreshTimer()
)
```

`eligibleBookmarks()` consults `bookmarkProvider` when non-nil. The Bookmarks tab
passes neither and behaves exactly as it does today. The home section passes a
provider returning its four bookmarks and `autoRefreshes: false`.

Batch identity, staleness gating, `fetchedStopIDs`, and continuation handling are
untouched — the home section inherits all of it.

### 2. Nearest-N stop selection — `OBAKitCore`

`MapStopsObserver.squaredDistance(_:to:)` already implements
cosine-scaled-longitude ordering, currently only for cap eviction. Promote it to a
shared helper:

```swift
extension Stop {
    static func nearest(_ stops: [Stop], to center: CLLocationCoordinate2D, limit: Int) -> [Stop]
}
```

`MapStopsObserver`'s prune path is refactored onto it so one distance formula
serves both. Its existing cap-eviction tests assert against that exact ordering
and must keep passing.

### 3. Region-filtered recent stops — `OBAKitCore/Models/UserData/UserDataStore`

The region filter plus nil-region handling currently lives inline in
`RecentStopsViewModel.loadData()`:

```swift
public func recentStops(in region: Region?) -> [Stop]
```

Returns `[]` for a nil region. `RecentStopsViewModel` is refactored onto it,
keeping its existing log-once-per-view-model nil-region warning at the call site
(the warning is view-model lifecycle state, not store state, so it does not move).

### 4. Section title strings — `OBAKitCore/Strings/Strings.swift`

`Strings.recentStops` already exists. Two titles are currently inline `OBALoc`
calls and move next to it, keeping their existing keys so no translation is lost:

- `Strings.nearbyStops` — key `nearby_stops_controller.title`, currently inline in
  `NearbyStopsListViewController`
- `Strings.bookmarks` — key `search_controller.bookmarks.header`, currently inline
  in `SearchInteractor`

Both original call sites are updated to use the constants.

### 5. Shared stop-row builder — `OBAKit/Search/SearchList/`

`SearchResultRow.row(for:application:onSelect:)` already builds a `SearchListRow`
for a `Stop` — icon, name, and a "distance • direction" subtitle via its private
`stopSubtitle(_:_:)`. The Nearby and Recent sections want exactly that row. Promote
the stop branch to a named factory so three call sites share one definition:

```swift
extension SearchListRow {
    static func stop(
        _ stop: Stop,
        application: Application,
        kind: Kind,
        onSelect: @escaping () -> Void
    ) -> SearchListRow
}
```

`SearchResultRow`'s `case let stop as Stop` branch delegates to it, passing
`.searchResult(id:)`. `stopSubtitle` moves onto the factory.

One new case is added to `SearchListRow.Kind`:

```swift
/// Carries the stop's id for the same reason `recentStop` does: two stops on
/// opposite sides of a corner share a name.
case nearbyStop(id: String)
```

with the matching `stableIdentifier` arm (`"nearbyStop-\(id)"`) and an
`actionRow` arm in `SearchListRowView`. Recent rows reuse the existing
`.recentStop(id:)` kind. Both render through `SearchListRowView` unchanged.

### Reused without change

`SearchListRowView` renders Nearby and Recent rows as-is. `BookmarkRowViewModel`,
`BookmarkCardView`, and `StopBookmarkRow` are already value-driven and read
formatters from the environment; the home sheet's bookmark rows use them directly
and render identically to the Bookmarks tab.

## Components

### `HomeSheetViewModel` (rewritten)

`@MainActor`, `ObservableObject`. Keeps `searchPlaceholder` and its
`RegionsServiceDelegate` conformance. Gains three child section models and
composes their output. Exposes `activate()`.

`activate()` is **idempotent**. Per the `MapSearchDisplayModel.owner` comment, the
sheet system tears sheet content down and rebuilds it without the user navigating
anywhere, so `.task` / `onAppear` can fire repeatedly per visit. It re-fetches
bookmark arrivals only when one of these holds:

- more than 30 seconds since the last completed fetch,
- the current region changed,
- the four-bookmark selection changed.

Otherwise it returns without touching the network.

### `HomeNearbyStopsSectionModel`

Reads `MapStopsObserver.stops` and republishes
`Stop.nearest(stops, to: viewportCenter, limit: 4)`. Holds the observer as a
dependency; adds **no** `MapRegionDelegate` conformance of its own — the observer
is already the single subscriber and adding a second would double the work on
every settle.

`MapStopsObserver.viewport` is private today. It gains a read-only
`viewportCenter: CLLocationCoordinate2D?` accessor, published so a settle in a new
region re-sorts the section. When it is `nil` (no settle yet), the section renders
the observer's first four stops in its existing id order rather than showing
nothing — a brief, stable ordering that the first settle corrects.

Empty when the map is zoomed out past `MapRegionManager.requiredHeightToShowStops`
(the observer is `reset()` there), which is correct: there is nothing nearby to
preview.

### `HomeRecentStopsSectionModel`

`userDataStore.recentStops(in: application.currentRegion)`, first four. Recents are
already stored MRU-first, so no sort. Refreshes on `activate()` and on region
change. No network.

### `HomeBookmarksSectionModel`

Selection: `userDataStore.findBookmarks(in: currentRegion)`, **sorted by
`sortOrder`**, first four.

> `findBookmarks(in:)` returns raw persisted order — only `bookmarksInGroup`
> sorts. Without an explicit sort the four shown would not match the user's
> Manage Bookmarks ordering.

Owns a `BookmarkDataLoader` built with the scoped provider and
`autoRefreshes: false`. Conforms to `BookmarkDataDelegate`; on
`dataLoaderDidUpdate` it rebuilds `[BookmarkRowViewModel]` via
`loader.dataForKey(_:)` and `loader.hasFetchedData(forStopID:)`, exactly as
`BookmarksViewModel.rebuildSections()` does.

`highlightedTripIDs` is always empty here — the flash-on-change affordance belongs
to the polling tab, and there is no polling on this screen.

### `HomeSectionHeader` (new view)

Title + trailing chevron button. Takes a title and an action. Used by all three
sections. The whole header is one button; the title carries the accessibility
label and the chevron is decorative.

### `HomeSheetView` (extended)

```
ScrollView
├── searchBarRow                          ← unchanged
├── HomeSectionHeader + nearby rows
├── HomeSectionHeader + recent rows
└── HomeSectionHeader + bookmark rows     ← BookmarkCardView / StopBookmarkRow
```

Nearby and Recent rows are `SearchListRowView`s built by
`SearchListRow.stop(_:application:kind:onSelect:)`; Bookmarks use
`BookmarkCardView` / `StopBookmarkRow`.

## Data Flow and Call Budget

| Section | Source | New requests |
|---|---|---|
| Nearby | `MapStopsObserver` ← `MapRegionManager` | **0** — piggybacks on stop requests the map already makes |
| Recent | `UserDataStore` (UserDefaults) | **0** |
| Bookmarks | scoped `BookmarkDataLoader` | **≤4**, on `activate()` only; fewer when some of the four are stop-only bookmarks, which the loader already skips |

No repeating timer is installed by this screen.

## Ownership Change

`MapStopsObserver` is currently constructed as a `@StateObject` inside
`MapPanelRootView.init`, but `AppSheetViewFactory` is constructed earlier, in
`MapPanelRootController.init`, and cannot see it.

The observer moves up to `MapPanelRootController.init` and is passed to both the
factory and `MapPanelRootView` (as `@ObservedObject`). This mirrors exactly how
`MapSearchDisplayModel` is already threaded, and the reasoning in
`AppSheetViewFactory`'s init comment — the factory and the hosting view must share
one instance — applies unchanged.

## Navigation

- **Row tap** → `coordinator.push(.stopDetails(stopID:))`. Bookmark rows push
  their `bookmark.stopID`.
- **Header chevron** → `.nearbyAll`, `.recentStopsAll`, `.bookmarksAll`.

Those three routes are exempted from the DEBUG `assertionFailure` in
`AppSheetViewFactory.unimplementedView(for:)` and render the release-style
"coming soon" placeholder in all configurations. The assert stays armed for every
other unwired route. Registering a real view later is a one-line factory change
per route, and removing the exemption is the natural cleanup step at that point.

## Empty States

A section with no items is omitted entirely, header included.

When all three are empty, one `EmptyStateView` is shown using the existing
`nearby_controller.empty_set.title` / `.body` strings. The "Search Wider Area"
button from `NearbyStopsListViewController` is **not** carried over — it drives
`MapRegionManager.preferredLoadDataRegionFudgeFactor` and a timed reset that the
SwiftUI path has no equivalent plumbing for. Adding it is separate work.

## Decisions

- **Nearby means the map viewport**, not the user's location: nearest four to the
  map's center. Matches the UIKit panel and what is visibly pinned behind the
  sheet, and works without location permission.
- **Bookmarks are picked by `sortOrder`**, not by favorite status or distance.
  Favorites are not hoisted — that rule was not requested, and `isFavorite` remains
  available if it is wanted later.
- **Section order is fixed** — Nearby, Recent, Bookmarks — with no promotion or
  reflow when an earlier section is empty.
- **Bookmark rows show live arrivals** for the four displayed only, fetched once
  per activation with no polling.

## Testing

Swift Testing, `@Suite(.serialized)`, per `OBAKitTests` convention.

**`HomeSheetViewModelTests`**
- Each section caps at four items when more are available.
- An empty section is omitted from the rendered list.
- Section order stays Nearby → Recent → Bookmarks when an earlier section is empty.
- `activate()` called twice in quick succession issues one bookmark fetch.
- `activate()` after a region change re-fetches.

**`HomeSectionModelTests`**
- Nearby: nearest-four by map center; empty when the observer has been `reset()`.
- Recent: region-filtered, MRU order preserved, nil region yields empty.
- Bookmarks: selection sorted by `sortOrder`; stop-only bookmarks produce rows with
  no arrival data and never report as loading.

**`BookmarkDataLoaderTests` (extended)**
- `bookmarkProvider` scopes fetches to exactly the supplied bookmarks.
- `autoRefreshes: false` installs no timer; `loadData()` twice does not double up.
- Default init is unchanged: all region bookmarks, timer installed.

**`StopNearestTests`**
- Ordering matches `MapStopsObserver`'s existing cap-eviction expectations.
- `limit` larger than the input returns everything; empty input returns empty.

**`SearchResultRowTests` (extended)**
- `SearchListRow.stop(...)` produces the same title, subtitle, and icon the
  existing `case let stop as Stop` branch produced, for each `kind` passed.
- Subtitle drops the distance when there is no location fix.
- `.nearbyStop(id:)` yields a distinct `stableIdentifier` from `.recentStop(id:)`
  for the same stop, so a stop appearing in both sections does not collide.

**`AppSheetViewFactoryTests` (extended)**
- The three index routes render the placeholder without asserting.
- Every other unwired route still asserts.

**`UserDataStoreTests` (extended)**
- `recentStops(in:)` filters by region and returns `[]` for nil.

**Regression:** existing `MapStopsObserverTests`, `BookmarksViewModel` tests, and
`RecentStopsViewModel` tests must pass unchanged — every extraction defaults to
current behaviour.

## Risks

- **Repeated sheet content teardown** re-triggering fetches. Mitigated by the
  idempotent `activate()`; the staleness rule is the thing to verify on device,
  not just in tests.
- **`MapStopsObserver` ownership move** touches the map root's construction path.
  It is a mechanical change following the `MapSearchDisplayModel` precedent, but it
  is the one edit in this design that can regress map behaviour, so it warrants its
  own step and its own verification.
- **Strict concurrency.** Every target builds in Swift 6 language mode with the
  five concurrency diagnostic groups escalated to errors; CI fails PRs that add
  warnings. New view models are `@MainActor`; the `bookmarkProvider` closure must
  be main-actor-isolated to match `BookmarkDataLoader`.
