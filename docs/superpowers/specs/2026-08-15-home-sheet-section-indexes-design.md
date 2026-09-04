# Home Sheet Section Indexes — Design

**Date:** 2026-08-15
**Branch:** `feature/home-sheet-sections-navigation`
**Status:** Approved design, ready for implementation planning

## Summary

Build the three index screens the home sheet's section headers already navigate
to — `.nearbyAll`, `.recentStopsAll`, `.bookmarksAll` — as native SwiftUI views,
reusing the view models and row views the existing experiences already use.
Today all three render the "coming soon" placeholder.

The Nearby index doubles as the native replacement for `.nearbyStops(coordinate:)`,
which serves the same screen today through a UIKit wrapper. That wrapper
(`NearbyStopsSheetHost`) is deleted.

**Prior work:** [`2026-08-13-home-sheet-sections-design.md`](2026-08-13-home-sheet-sections-design.md)
built the three preview sections and explicitly deferred these index screens.

## Goals

- Three native index screens, reachable from the home sheet headers that already
  push their routes.
- Reuse existing view models (`NearbyStopsViewModel`, `RecentStopsViewModel`,
  `BookmarksViewModel`) and existing SwiftUI rows (`HomeStopRow`,
  `BookmarksListView`) rather than writing parallel ones.
- One Nearby screen, not two: `.nearbyAll` and `.nearbyStops(coordinate:)` render
  the same view.
- Extract the Bookmarks tab's row actions so the tab and the sheet share one
  implementation.

## Non-Goals

- Changing the home sheet's preview sections, their data budget, or their layout.
- Changing Bookmarks-tab or Recent-tab behaviour. The extraction in §5 is a pure
  move: existing callers keep today's behaviour.
- An Alarms section on the Recents index. Alarms stay a Recent-tab concern; the
  home sheet's header promises recent *stops*.
- Search on the Bookmarks index.
- Retiring `NearbyStopsViewController` / `RecentStopsViewController` /
  `BookmarksViewController`. They still back their tabs.

## Current State

| Piece | Today |
|---|---|
| `.nearbyAll` / `.recentStopsAll` / `.bookmarksAll` | Declared, stacking, `.large`; dispatched to `AppSheetViewFactory.indexPlaceholderView(for:)` |
| `.nearbyStops(coordinate:)` | `NearbyStopsSheetHost` → UIKit `NearbyStopsViewController` in a `UINavigationController` |
| `NearbyStopsViewModel` | `@MainActor ObservableObject`; `stops` / `isLoading` / `operationError`; `loadStops()` calls `getStops(coordinate:)` |
| `RecentStopsViewModel` | `@MainActor ObservableObject`; `recentStops` / `alarms`; `loadData()`, `delete(recentStop:)`, `deleteAllRecentStops()` |
| `BookmarksViewModel` | `@MainActor ObservableObject`; group/distance sections, collapse persistence, 30s poll via `start()`/`deactivate()` |
| `BookmarksListView` | Complete SwiftUI Bookmarks tab, driven by an injected `BookmarksNavigationHandler` — already router-free |
| Bookmark row actions | Closures inside `BookmarksViewController`: `editBookmark`, `deleteBookmark`, `startLiveActivity` (~90 lines) |
| Sheet chrome convention | `NavigationStack` + inline title + Close button + `.searchSheetBackground()` / `.searchListChrome()` — see `RouteStopsSheetView`, `SearchResultsSheetView` |

## Chosen Approach

Each index screen is a SwiftUI view over the view model its UIKit counterpart
already uses. No new data-loading paths, no new models except one pure
grouping/filtering helper for Nearby.

Rejected: wrapping the three UIKit controllers in `UIViewControllerRepresentable`
(the `MoreSheetHost` / `StopDetailSheetHost` pattern). It is less work, but it
imports `viewRouter`-based navigation into a sheet stack that has its own
coordinator — a tapped row would push a UIKit stop page inside the wrapper's
nav controller instead of stacking `.stopDetails`, and the two stop-page
experiences would diverge. It also entrenches `OBAListView` on a surface being
rebuilt in SwiftUI.

## Shared Shape

All three are stacked `.large` sheets and wear the chrome the search sheets
established:

```
NavigationStack {
    content
        .navigationTitle(...)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button(Strings.close) { dismiss() } } }
}
.searchSheetBackground()
```

with `.searchListChrome()` on each `List` and `EmptyStateView` for empty cases.
Row taps call `coordinator.push(.stopDetails(stopID:))`; `FloatingSheetContainer`
is recursive, so that renders as a second stacked sheet over the index with no
coordinator changes.

New files live in `OBAKit/Sheet/Content/Home/Index/`. XcodeGen builds the target
from the directory tree, so no project-file edits are needed.

The chrome is repeated per view rather than factored into a shared modifier —
three call sites with three different toolbars do not yet justify the
indirection.

## Components

### 1. `NearbyStopsSheetView` — `OBAKit/Sheet/Content/Home/Index/`

Native port of `NearbyStopsViewController`.

- Owns `NearbyStopsViewModel` via `@StateObject` + `@autoclosure`, matching the
  factory's lazy-VM convention.
- `.task { await viewModel.loadStops() }`.
- `.searchable` bound to a `@State` filter string.
- Sections grouped by `Stop.direction`, header text from
  `Formatters.adjectiveFormOfCardinalDirection`, rows drawn with `HomeStopRow`.
- `isLoading` renders a `ProgressView` row; `operationError` renders an inline
  error row with a Retry button.

Errors surface **inline**, not through `application.displayError` as the UIKit
controller does — an alert presented from the app over a stacked sheet is the
wrong affordance here, and `NearbyStopsSheetView` holds no `Application`.

### 2. `NearbyStopsIndexSection` — same directory

A `nonisolated` value type plus a pure static builder:

```swift
static func sections(stops: [Stop], filter: String?) -> [NearbyStopsIndexSection]
```

Applies `Stop.matchesQuery` (existing, `OBAKitCore/Models/Extensions/Searchable.swift`),
groups by direction, sorts groups by `Direction`, and drops empty ones. Extracted
so grouping and filtering are testable without a view — the same reason
`RouteStopsRow.rows(from:)` exists.

### 3. `.nearbyStops` consolidation

`AppSheetViewFactory.nearbyStopsView(coordinate:)` returns `NearbyStopsSheetView`
instead of `NearbyStopsSheetHost`. **`OBAKit/Sheet/Content/Search/NearbyStopsSheetHost.swift`
is deleted**; the factory is its only reference and no test names it.

`.nearbyAll` carries no coordinate, so the factory resolves one:

```
stopsObserver.viewportCenter
  ?? application.locationService.currentLocation?.coordinate
  ?? application.currentRegion?.centerCoordinate
```

All three nil renders `EmptyStateView` rather than fetching around `(0, 0)`.
Resolution lives in a `nonisolated static func` on the factory (or a free
function) so the fallback chain is testable without an `Application`.

Both routes render the same view; `.nearbyAll` differs only in how its
coordinate is obtained.

### 4. `RecentStopsSheetView` — `OBAKit/Sheet/Content/Home/Index/`

- Owns `RecentStopsViewModel` via `@StateObject`; `.task { viewModel.loadData() }`.
- `.searchable` filter over `Stop.matchesQuery`, applied to `viewModel.recentStops`.
- `HomeStopRow` rows in a flat list — recents are already stored
  most-recently-used first, so there is nothing to sort or group.
- `.swipeActions` → `viewModel.delete(recentStop:)`.
- `Delete All` toolbar button → `.confirmationDialog` carrying the existing
  `recent_stops.confirmation_alert.title` string → `viewModel.deleteAllRecentStops()`.
- Empty: `EmptyStateView` reusing the existing `recent_stops.empty_set.title` /
  `.body` strings, without the tab's "Find Stops on Maps" button — the map is
  already behind the sheet.

The Alarms section is deliberately absent (see Non-Goals).

### 5. `BookmarkActions` — `OBAKit/Bookmarks/`

A `@MainActor final class` holding `Application`, extracted from
`BookmarksViewController` so the tab and the sheet share one implementation of:

- `reportDeletion(of:)` — reports the remove-bookmark analytics event. The
  caller still performs the delete on its own view model, so `BookmarkActions`
  needs no `BookmarksViewModel` reference.
- `startLiveActivity(for:arrivalDepartures:) -> TrackResult` — the full ~90-line
  path, including the already-running duplicate guard, `demoteLivePeers`, and
  the started toast. Arrivals are passed in by the caller, so `BookmarkActions`
  needs no `BookmarksViewModel`. Failure is **returned**, not alerted:
  `showLiveActivityErrorAlert()` is a `UIViewController` extension
  (`OBAKit/LiveActivities/UIViewController+LiveActivityAlerts.swift`), so the
  tab keeps calling it while the sheet raises a SwiftUI `.alert`.
- `makeBookmarkEditor(for:delegate:)` — builds the
  `EditBookmarkViewController` inside a `UINavigationController`. **Presentation
  stays with the caller**: `BookmarksViewController` keeps presenting via
  `application.viewRouter.present(_:from:)`; the sheet presents the same
  controller through a small `UIViewControllerRepresentable` inside a SwiftUI
  `.sheet(item:)`. The sheet supplies its own lightweight `BookmarkEditorDelegate`
  — dismiss the presented editor, then `viewModel.rebuildSections()` — rather
  than routing through `BookmarksViewController`'s.

`liveActivityKeys(for:)` and `buildContentState(from:)` move with it.
`updateRunningLiveActivities`, `reloadWidget`, and the sort-menu rebuild stay on
`BookmarksViewController` — those are tab/app-lifecycle chores, not row actions.

This is the only part of the work that edits shipping code rather than adding to
it. `BookmarksViewController` must come out behaviourally identical.

### 6. `BookmarksSheetView` — `OBAKit/Sheet/Content/Home/Index/`

Renders `BookmarksListView` unchanged, with:

- `BookmarksViewModel` via `@StateObject`; `viewModel.start()` on appear and
  `viewModel.deactivate()` on disappear, so the 30s poll never outlives the sheet.
- A sheet-flavoured `BookmarksNavigationHandler`:

| Closure | Sheet implementation |
|---|---|
| `selectBookmark` | `coordinator.push(.stopDetails(stopID: bookmark.stopID))` |
| `togglePin` | `application.userDataStore.setPinned(!bookmark.isPinned, for:)` |
| `editBookmark` | sets `@State editingBookmark`, presenting `BookmarkActions.makeBookmarkEditor` via `.sheet(item:)` |
| `deleteBookmark` | `BookmarkActions.reportDeletion(of:)` then `viewModel.deleteBookmark` |
| `trackBookmark` | `BookmarkActions.startLiveActivity(for:)` |
| `liveActivitiesEnabled` | `ActivityAuthorizationInfo().areActivitiesEnabled` |
| `refresh` | `await viewModel.refreshAndWait()` + `DataLoadFeedbackGenerator` haptic, reading `lastRefreshHadError` |
| `makeStopPreview` | existing `StopViewControllerPreview` verbatim |

- Sort as a toolbar `Menu` over `viewModel.updateSortType(byGroup:)`, mirroring
  the tab's `rebuildSortMenu` items and checkmarks.
- Empty state comes from `BookmarksListView` itself (`viewModel.emptyState`) — no
  extra handling here.

Manage Bookmarks/Groups is not offered from the sheet; it stays a tab-level
editing surface.

The handler is built by a `static func makeNavigationHandler(...)` seam so tests
can exercise the wiring without a `UIHostingController` — the same reasoning as
`MoreSheetHost.makeNavigationController`.

### 7. `AppSheetViewFactory` changes

- `.nearbyAll`, `.recentStopsAll`, `.bookmarksAll` leave the
  `indexPlaceholderView` branch and get per-route builders.
- `indexPlaceholderView` stays — `unimplementedView` still calls it on the
  release path — but its doc comment, which describes the three index routes,
  is rewritten.
- `nearbyStopsView(coordinate:)` returns `NearbyStopsSheetView`.

## Navigation

```
home sheet (base)
 └─ header chevron → .nearbyAll / .recentStopsAll / .bookmarksAll   [stacked depth 0]
     └─ row tap → .stopDetails(stopID:)                             [stacked depth 1]
```

The home sheet's `onChange(of: coordinator.stackedRoutes)` already re-activates
its preview sections when the stacked layer empties, so a stop viewed from an
index, a bookmark pinned, or a recent stop deleted is reflected on return
without new plumbing.

## Testing

Swift Testing, `.serialized` suites, under `OBAKitTests/Sheet/Home/` (and
`OBAKitTests/Bookmarks/` for the extraction).

| Suite | Covers |
|---|---|
| `NearbyStopsIndexSectionTests` | Direction grouping and order; `nil`/empty filter passes everything; a filter that matches nothing yields no sections; unmatched groups are dropped, not emptied |
| `NearbyCoordinateResolverTests` | The viewport → location → region fallback chain, including all-nil |
| `RecentStopsSheetViewTests` | Filter helper; `delete(recentStop:)` and `deleteAllRecentStops()` against a real `UserDataStore` |
| `BookmarkActionsTests` | Duplicate-Track guard promotes rather than duplicating; delete reports the analytics event; `liveActivityKeys` fallbacks. **None of this is tested today.** |
| `BookmarksSheetViewTests` | `makeNavigationHandler` seam: `selectBookmark` pushes `.stopDetails` on a coordinator; `togglePin` flips the store |
| `AppSheetViewFactoryTests` | **Inverts** the existing `Index routes dispatch to a placeholder` test (line ~143) — the three routes must now build real views |

Existing `AppSheetRouteTests` assertions on the three routes' ids, stacking, and
detents are unaffected.

## Risks

| Risk | Mitigation |
|---|---|
| `BookmarkActions` extraction changes Bookmarks-tab behaviour | Pure move, no signature changes for the tab's call sites; new tests pin the Track guard and delete analytics before the move |
| Live Activity code is hard to test (`ActivityKit` needs a device/entitlement) | Test the pure parts — `liveActivityKeys`, `buildContentState`, the identity comparison — and leave `Activity.request` itself to manual verification |
| Deleting `NearbyStopsSheetHost` regresses the search flow's nearby screen | `.nearbyStops(coordinate:)` keeps its route, detents, and payload; only the rendered view changes, and it is exercised by the same factory test |
| A stacked-sheet modal (bookmark editor) presenting from depth 0 | `.sheet(item:)` inside the index view presents over the sheet, not through `viewRouter`; verified manually on device |
| Bookmarks index polls while a `.stopDetails` sheet is stacked over it | Accepted — matches the tab, and `deactivate()` still fires when the index itself goes away |

## Decisions

1. **Nearby index fetches fresh, grouped by direction** — not a re-slice of
   `MapStopsObserver`. The index is the "show me everything" screen; the map's
   accumulated-and-pruned set is a preview budget, not a complete list.
2. **One Nearby screen for both routes.** Two screens showing stops around a
   coordinate would drift.
3. **Full `BookmarksListView` reuse.** Anything less would make long-press behave
   differently in the sheet than in the tab.
4. **Recents gets search, swipe-delete, and Delete All; no Alarms.**
5. **Errors surface inline on the Nearby index**, not via `application.displayError`.
6. **Chrome is repeated, not factored out**, until a fourth index screen exists.
