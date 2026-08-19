# Stop Details Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the UIKit stopgap behind `AppSheetRoute.stopDetails` with a native SwiftUI sheet that has a pinned Refresh/Close bar, the pushed screen's dark map header that collapses on scroll, and a pinned row of circular Schedule/Filter/Bookmark/More buttons.

**Architecture:** Extract the Stop page's derivation (`StopPageContent`), its shared list sections (`StopDeparturesSections`), its lifecycle wiring (`stopPageLifecycle`), and its UIKit modal flows (`StopPageActionPresenter`) out of `StopPageView` and `StopPageViewController`. The existing pushed and FloatingPanel presentations keep delegating to those pieces with unchanged behaviour; the new `StopDetailsSheetView` composes them with its own collapsing chrome.

**Tech Stack:** Swift 6 language mode, SwiftUI (iOS 18+), Combine, MapKit (`MapSnapshotter`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-07-31-stop-details-sheet-design.md`

## Global Constraints

- **Deployment target:** iOS 18.0+. Modern syntax (shorthand optional binding, `URL.host()`, `onScrollGeometryChange`) is fine.
- **Language mode:** Swift 6 with main-actor default isolation. `OBAKitCore` pins `SWIFT_DEFAULT_ACTOR_ISOLATION` to `nonisolated`. The five concurrency diagnostic groups are **errors** — a data-race warning fails the build.
- **Tests:** Swift Testing (`@Suite(.serialized)`, `@Test`, `#expect`), never XCTest. Suites needing fixtures inherit `OBATestCase` and override `init() async throws`; teardown goes in `deinit`.
- **Localization:** every user-facing string goes through `OBALoc(key, value:comment:)` with a real comment. Reuse existing keys where the string already exists.
- **Linting:** `scripts/swiftlint.sh` must pass.
- **Commits:** one-line subject, imperative, sentence case (e.g. `Add the stop page content derivation`). **No** `Co-Authored-By` trailer, no `feat:`/`fix:` prefixes.
- **Project generation:** not required — new files land in Xcode buildable folders and are picked up automatically.
- **Presentations 1 and 2 must not change behaviour.** `StopPagePresentationTests` is the contract.

**Build and test commands** (used throughout):

```bash
# Build once before the first test run, and after adding new files.
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run one suite.
xcodebuild test-without-building -only-testing:OBAKitTests/<SuiteName> \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run everything.
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## File Structure

**Created**

| File | Responsibility |
| --- | --- |
| `OBAKit/Stops/StopPage/Shared/StopPageContent.swift` | Pure derivation: filtering, grouping, emptiness, loading state, attribution |
| `OBAKit/Stops/StopPage/Shared/StopDeparturesSections.swift` | The shared list sections every presentation renders |
| `OBAKit/Stops/StopPage/Shared/StopPageLifecycleModifier.swift` | `.task`/seed/deactivate/reconcilers/toast, shared by all presentations |
| `OBAKit/Stops/StopPage/StopPageActionPresenter.swift` | Every UIKit modal flow, plus `makeNavigationHandler`, `makeUserActivity`, `loadSnapshot` |
| `OBAKit/Controls/SwiftUI/KeepsScreenAwake.swift` | Idle-timer modifier, replacing the copy inside `CurrentTripView` |
| `OBAKit/Sheet/Content/Stop/Details/StopSheetHeaderCollapse.swift` | Pure scroll-offset → collapse-progress arithmetic |
| `OBAKit/Sheet/Content/Stop/Details/StopPageActionRow.swift` | The four circular buttons + `StopPageActionRowState` |
| `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetTopBar.swift` | Pinned Refresh / fading title / Close strip |
| `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift` | Composes the sheet: chrome inset + list + side effects |

**Modified**

| File | Change |
| --- | --- |
| `OBAKit/Stops/StopPage/StopPageView.swift` | Body delegates to `StopPageContent`, `StopDeparturesSections`, `stopPageLifecycle` |
| `OBAKit/Stops/StopPage/StopPageViewController.swift` | Delegates modal flows to the presenter |
| `OBAKit/Sheet/Content/CurrentTrip/CurrentTripView.swift` | Adopts `keepsScreenAwake()` |
| `OBAKit/Sheet/DI/AppSheetViewFactory.swift` | `presentingController` provider; returns `StopDetailsSheetView` |
| `OBAKit/Sheet/Root/MapPanelRootController.swift` | Bridge also resolves the presenting controller |
| `OBAKitTests/Helpers/Fixtures.swift` | `arrivalDeparture` gains `routeID` / `tripID` parameters |
| `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift` | Asserts the new view |

**Deleted:** `OBAKit/Sheet/Root/StopDetailSheetHost.swift`, `OBAKitTests/Sheet/StopDetailSheetHostTests.swift`

---

### Task 1: `StopPageContent` derivation

Pure value type holding everything `StopPageView.body` currently computes inline. Tests construct it from plain values, so no view model is needed.

**Files:**
- Create: `OBAKit/Stops/StopPage/Shared/StopPageContent.swift`
- Create: `OBAKitTests/Stops/StopPage/StopPageContentTests.swift`
- Modify: `OBAKitTests/Helpers/Fixtures.swift:65-96`

**Interfaces:**
- Consumes: `StopPageListBuilder.routeGroups(_:)`, `[ArrivalDeparture].filter(preferences:)`, `[ArrivalDeparture].filteringTerminalDuplicates()`, `Formatters.formattedAgenciesForRoutes(_:)`
- Produces: `StopPageContent` with stored properties `departures: [ArrivalDeparture]`, `departureIDs: Set<String>`, `routeIDs: Set<RouteID>`, `isGrouped: Bool`, `routeGroups: [StopPageListBuilder.RouteGroup<ArrivalDeparture>]`, `listIsEmpty: Bool`, `hasLoadedArrivals: Bool`, `showsLoadingState: Bool`, `isFilteredEmpty: Bool`, `attributionText: String`; plus `init(stop:allDepartures:hasLoadedArrivals:preferences:isListFiltered:isLoading:hasError:isBrokenBookmark:)` and `@MainActor init(viewModel: StopViewModel)`

- [ ] **Step 1: Parameterize the arrival/departure fixture**

`Fixtures.arrivalDeparture` hardcodes `routeId: "route_1"` and `tripId: "trip_1"`, so every fixture collapses into one route — and `filteringTerminalDuplicates()` would fold them together. Add two defaulted parameters so existing callers are untouched.

In `OBAKitTests/Helpers/Fixtures.swift`, change the signature and the two dictionary entries:

```swift
    class func arrivalDeparture(
        predicted: Bool = true,
        scheduledArrival: Int = 1_700_000_000,
        predictedArrival: Int? = nil,
        scheduledDeparture: Int = 1_700_000_000,
        predictedDeparture: Int? = nil,
        stopSequence: Int = 5,
        routeID: String = "route_1",
        tripID: String = "trip_1"
    ) throws -> ArrivalDeparture {
```

and within the dictionary literal:

```swift
            "routeId": routeID,
            ...
            "tripId": tripID,
```

- [ ] **Step 2: Write the failing tests**

Create `OBAKitTests/Stops/StopPage/StopPageContentTests.swift`:

```swift
//
//  StopPageContentTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Pure-value tests for the Stop page's derivation. This logic used to live
/// inline in `StopPageView.body`, where none of it could be asserted.
@MainActor
@Suite(.serialized)
final class StopPageContentTests: OBATestCase {

    private func departures() throws -> [ArrivalDeparture] {
        [
            try Fixtures.arrivalDeparture(routeID: "route_1", tripID: "trip_1"),
            try Fixtures.arrivalDeparture(routeID: "route_2", tripID: "trip_2"),
            try Fixtures.arrivalDeparture(routeID: "route_2", tripID: "trip_3")
        ]
    }

    private func makeContent(
        allDepartures: [ArrivalDeparture],
        preferences: StopPreferences = StopPreferences(),
        isListFiltered: Bool = false,
        hasLoadedArrivals: Bool = true,
        isLoading: Bool = false,
        hasError: Bool = false,
        isBrokenBookmark: Bool = false
    ) -> StopPageContent {
        StopPageContent(
            stop: nil,
            allDepartures: allDepartures,
            hasLoadedArrivals: hasLoadedArrivals,
            preferences: preferences,
            isListFiltered: isListFiltered,
            isLoading: isLoading,
            hasError: hasError,
            isBrokenBookmark: isBrokenBookmark
        )
    }

    // MARK: - Filtering

    @Test func `Unfiltered content keeps every route`() throws {
        let content = makeContent(allDepartures: try departures())
        #expect(content.departures.count == 3)
        #expect(content.routeIDs == ["route_1", "route_2"])
    }

    @Test func `Filtering drops hidden routes only when the filter is on`() throws {
        let prefs = StopPreferences(sortType: .time, hiddenRoutes: ["route_2"])

        let filtered = makeContent(allDepartures: try departures(), preferences: prefs, isListFiltered: true)
        #expect(filtered.departures.count == 1)
        #expect(filtered.routeIDs == ["route_1"])

        let unfiltered = makeContent(allDepartures: try departures(), preferences: prefs, isListFiltered: false)
        #expect(unfiltered.departures.count == 3)
    }

    // MARK: - Grouping

    @Test func `Grouped mode builds one group per route`() throws {
        let prefs = StopPreferences(sortType: .route, hiddenRoutes: [])
        let content = makeContent(allDepartures: try departures(), preferences: prefs)

        #expect(content.isGrouped)
        #expect(content.routeGroups.count == 2)
    }

    @Test func `Chronological mode builds no groups`() throws {
        let content = makeContent(allDepartures: try departures())
        #expect(!content.isGrouped)
        #expect(content.routeGroups.isEmpty)
    }

    // MARK: - Emptiness

    @Test func `Empty departures produce an empty list`() {
        let content = makeContent(allDepartures: [])
        #expect(content.listIsEmpty)
    }

    @Test func `Filtered empty is true only when the filter emptied a non-empty feed`() throws {
        let prefs = StopPreferences(sortType: .time, hiddenRoutes: ["route_1", "route_2"])
        let content = makeContent(allDepartures: try departures(), preferences: prefs, isListFiltered: true)

        #expect(content.departures.isEmpty)
        #expect(content.isFilteredEmpty)
    }

    @Test func `Filtered empty is false when the feed itself is empty`() {
        let content = makeContent(allDepartures: [], isListFiltered: true)
        #expect(!content.isFilteredEmpty)
    }

    @Test func `Filtered empty is false when the filter is off`() throws {
        let content = makeContent(allDepartures: [], isListFiltered: false)
        #expect(!content.isFilteredEmpty)
    }

    // MARK: - Loading state

    @Test func `Loading state covers the first frame before any fetch`() {
        let content = makeContent(allDepartures: [], hasLoadedArrivals: false)
        #expect(content.showsLoadingState)
    }

    @Test func `Loading state holds while a fetch is in flight`() throws {
        let content = makeContent(allDepartures: try departures(), isLoading: true)
        #expect(content.showsLoadingState)
    }

    @Test func `A first fetch that failed is not a loading state`() {
        let content = makeContent(allDepartures: [], hasLoadedArrivals: false, hasError: true)
        #expect(!content.showsLoadingState)
    }

    @Test func `A broken bookmark is not a loading state`() {
        let content = makeContent(allDepartures: [], hasLoadedArrivals: false, isBrokenBookmark: true)
        #expect(!content.showsLoadingState)
    }

    // MARK: - Attribution

    @Test func `Attribution is empty without a stop`() {
        #expect(makeContent(allDepartures: []).attributionText.isEmpty)
    }

    @Test func `Attribution names the stop's agencies`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let content = StopPageContent(
            stop: stop,
            allDepartures: [],
            hasLoadedArrivals: true,
            preferences: StopPreferences(),
            isListFiltered: false,
            isLoading: false,
            hasError: false,
            isBrokenBookmark: false
        )

        let agencies = Formatters.formattedAgenciesForRoutes(stop.routes)
        #expect(content.attributionText.isEmpty == agencies.isEmpty)
        if !agencies.isEmpty {
            #expect(content.attributionText.contains(agencies))
        }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: **build failure** — `cannot find 'StopPageContent' in scope`.

- [ ] **Step 4: Implement `StopPageContent`**

Create `OBAKit/Stops/StopPage/Shared/StopPageContent.swift`:

```swift
//
//  StopPageContent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Everything the Stop page's list needs, derived once from the view model's
/// current state.
///
/// A plain value, constructed inside a `body`, so the "one shallow body
/// re-evaluates on the view model's refresh and status-timer churn" property
/// the page is built around still holds. Being pure, it is also directly
/// testable — this logic used to be inlined in `StopPageView.body`, where it
/// wasn't.
struct StopPageContent {

    /// Departures both list modes project: hidden routes removed (when the
    /// filter is on), then terminal duplicates collapsed.
    let departures: [ArrivalDeparture]
    let departureIDs: Set<String>
    let routeIDs: Set<RouteID>

    let isGrouped: Bool
    let routeGroups: [StopPageListBuilder.RouteGroup<ArrivalDeparture>]
    let listIsEmpty: Bool

    let hasLoadedArrivals: Bool
    let showsLoadingState: Bool
    /// `true` only when the route filter is what emptied the list.
    let isFilteredEmpty: Bool
    let attributionText: String

    init(
        stop: Stop?,
        allDepartures: [ArrivalDeparture],
        hasLoadedArrivals: Bool,
        preferences: StopPreferences,
        isListFiltered: Bool,
        isLoading: Bool,
        hasError: Bool,
        isBrokenBookmark: Bool
    ) {
        // `filteringTerminalDuplicates()` collapses the arrival/departure pair
        // the API emits for a single vehicle visit at a terminal or loop stop —
        // without it the rider sees the same bus twice, with two different
        // countdowns (parity with `StopViewController`).
        let visible = isListFiltered ? allDepartures.filter(preferences: preferences) : allDepartures
        let departures = visible.filteringTerminalDuplicates()

        self.departures = departures
        self.departureIDs = Set(departures.map(\.id))
        self.routeIDs = Set(departures.map(\.routeID))

        let isGrouped = preferences.sortType == .route
        let routeGroups = isGrouped ? StopPageListBuilder.routeGroups(departures) : []
        self.isGrouped = isGrouped
        self.routeGroups = routeGroups

        // Grouped mode drops past departures, so it can have nothing to render
        // while `departures` is non-empty (the last bus of the evening has
        // left). Deciding emptiness from the groups themselves keeps that case
        // on the empty state instead of a void.
        self.listIsEmpty = isGrouped ? routeGroups.isEmpty : departures.isEmpty

        self.hasLoadedArrivals = hasLoadedArrivals
        // Any in-flight fetch, plus the pre-`.task` first frame (nothing
        // fetched, no error yet) so the page never flashes "No departures"
        // before the first request has even started.
        self.showsLoadingState = isLoading || (!hasLoadedArrivals && !hasError && !isBrokenBookmark)

        // Grouped mode can be empty while `allDepartures` isn't (every
        // departure is in the past); that's a no-service state, not a
        // filtered-out one — hence `departures`, not `listIsEmpty`.
        self.isFilteredEmpty = isListFiltered && departures.isEmpty && !allDepartures.isEmpty

        self.attributionText = Self.attribution(for: stop)
    }

    private static func attribution(for stop: Stop?) -> String {
        guard let stop else { return "" }
        let agencies = Formatters.formattedAgenciesForRoutes(stop.routes)
        guard !agencies.isEmpty else { return "" }
        let fmt = OBALoc(
            "stop_controller.data_attribution_format",
            value: "Data provided by %@",
            comment: "A string listing the data providers (agencies) for this stop's data. It contains one or more providers separated by commas. e.g. Data provided by King County Metro, Sound Transit"
        )
        return String(format: fmt, agencies)
    }
}

extension StopPageContent {
    /// Convenience for the view layer, which holds the view model.
    @MainActor
    init(viewModel: StopViewModel) {
        self.init(
            stop: viewModel.stop,
            allDepartures: viewModel.stopArrivals?.arrivalsAndDepartures ?? [],
            hasLoadedArrivals: viewModel.stopArrivals != nil,
            preferences: viewModel.stopPreferences,
            isListFiltered: viewModel.isListFiltered,
            isLoading: viewModel.isLoading,
            hasError: viewModel.operationError != nil,
            isBrokenBookmark: viewModel.isBrokenBookmark
        )
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/StopPageContentTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS, all cases.

- [ ] **Step 6: Run SwiftLint**

```bash
scripts/swiftlint.sh
```

Expected: no new violations.

- [ ] **Step 7: Commit**

```bash
git add OBAKit/Stops/StopPage/Shared/StopPageContent.swift \
        OBAKitTests/Stops/StopPage/StopPageContentTests.swift \
        OBAKitTests/Helpers/Fixtures.swift
git commit -m "Extract the stop page list derivation into a testable value"
```

---

### Task 2: `StopDeparturesSections`

Move the shared section stack out of `StopPageView` so the new sheet can render it without duplicating any of it. Behaviour must not change: `StopPagePresentationTests` is the gate.

**Files:**
- Create: `OBAKit/Stops/StopPage/Shared/StopDeparturesSections.swift`
- Modify: `OBAKit/Stops/StopPage/StopPageView.swift`

**Interfaces:**
- Consumes: `StopPageContent` (Task 1); existing `SurveyCardRepresentable`, `DonationCardRepresentable`, `ServiceAlertsSection`, `StopPageModeToggle`, `ChronologicalListView`, `GroupedListView`, `StopPageEmptyStateRow`, `StopPageLoadingRow`, `StopPageFooterSection`
- Produces: `StopDeparturesSections` — a `View` whose `body` returns several `Section`s. Initializer parameters, in order: `content: StopPageContent`, `survey: Survey?`, `stopID: StopID`, `serviceAlerts: [ServiceAlert]`, `sortType: StopSort`, `walkMinutes: Int?`, `minutesAfter: UInt`, `isBrokenBookmark: Bool`, `errorText: String?`, `showsDonation: Bool`, `isLoadMoreExhausted: Bool`, `isLoading: Bool`, `pastCollapsed: Bool`, `expandedDepartureID: String?`, `expandedRouteID: RouteID?`, `statusProvider: (ArrivalDeparture) -> DepartureStatus`, `alarmLookup: (ArrivalDeparture) -> Alarm?`, `alarmLeadTime: (Alarm) -> Int`, `canAlarm: (ArrivalDeparture) -> Bool`, `actionsProvider: (ArrivalDeparture) -> DepartureRowActions`, `panelBuilder: (ArrivalDeparture) -> TripDetailPanelView`, and the callbacks `onSurveyNext: (String) -> Void`, `onSurveyDismiss: () -> Void`, `onSurveyExternal: () -> Void`, `onDonate: () -> Void`, `onDonationClose: () -> Void`, `onSelectAlert: (ServiceAlert) -> Void`, `onChangeMode: (StopSort) -> Void`, `onTogglePast: () -> Void`, `onToggleExpand: (ArrivalDeparture) -> Void`, `onToggleRoute: (RouteID) -> Void`, `onRetry: () -> Void`, `onShowAllRoutes: () -> Void`, `onLoadMore: () -> Void`

- [ ] **Step 1: Create the extracted view**

Create `OBAKit/Stops/StopPage/Shared/StopDeparturesSections.swift`. The bodies below are moved verbatim from `StopPageView.body` — only the value sources change (from `viewModel.x` to parameters).

```swift
//
//  StopDeparturesSections.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The Stop page sections every presentation renders, in the order they all
/// render them: survey, donation, service alerts, mode toggle, departures,
/// footer.
///
/// Returns several `Section`s from one body — the shape `ServiceAlertsSection`
/// already uses — so callers drop it straight into their own `List` and keep
/// ownership of the header and chrome above it.
///
/// A plain-value view: it never touches `StopViewModel`.
struct StopDeparturesSections: View {

    let content: StopPageContent

    let survey: Survey?
    let stopID: StopID
    let serviceAlerts: [ServiceAlert]
    let sortType: StopSort
    let walkMinutes: Int?
    let minutesAfter: UInt
    let isBrokenBookmark: Bool
    let errorText: String?
    let showsDonation: Bool
    let isLoadMoreExhausted: Bool
    let isLoading: Bool

    let pastCollapsed: Bool
    let expandedDepartureID: String?
    let expandedRouteID: RouteID?

    let statusProvider: (ArrivalDeparture) -> DepartureStatus
    let alarmLookup: (ArrivalDeparture) -> Alarm?
    let alarmLeadTime: (Alarm) -> Int
    let canAlarm: (ArrivalDeparture) -> Bool
    let actionsProvider: (ArrivalDeparture) -> DepartureRowActions
    let panelBuilder: (ArrivalDeparture) -> TripDetailPanelView

    let onSurveyNext: (String) -> Void
    let onSurveyDismiss: () -> Void
    let onSurveyExternal: () -> Void
    let onDonate: () -> Void
    let onDonationClose: () -> Void
    let onSelectAlert: (ServiceAlert) -> Void
    let onChangeMode: (StopSort) -> Void
    let onTogglePast: () -> Void
    let onToggleExpand: (ArrivalDeparture) -> Void
    let onToggleRoute: (RouteID) -> Void
    let onAlarmToggle: (ArrivalDeparture) -> Void
    let onRetry: () -> Void
    let onShowAllRoutes: () -> Void
    let onLoadMore: () -> Void

    /// Leading/trailing inset shared by the page's full-width card rows,
    /// matching the inset-grouped card margin.
    private static let horizontalRowInset: CGFloat = 0

    var body: some View {
        if let survey {
            Section {
                SurveyCardRepresentable(
                    survey: survey,
                    stopID: stopID,
                    onNext: onSurveyNext,
                    onDismiss: onSurveyDismiss,
                    onOpenExternalSurvey: onSurveyExternal
                )
                .listRowInsets(EdgeInsets(top: 4, leading: Self.horizontalRowInset, bottom: 4, trailing: Self.horizontalRowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }

        // Inline donation request (parity with the legacy UIKit
        // `DonationListItem`). Sits after the survey and before service alerts,
        // matching the legacy section order.
        if showsDonation {
            Section {
                DonationCardRepresentable(
                    onDonate: onDonate,
                    onLearnMore: onDonate,
                    onClose: onDonationClose
                )
                .listRowInsets(EdgeInsets(top: 4, leading: Self.horizontalRowInset, bottom: 4, trailing: Self.horizontalRowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }

        if !serviceAlerts.isEmpty {
            ServiceAlertsSection(alerts: serviceAlerts, onSelect: onSelectAlert)
        }

        if content.hasLoadedArrivals {
            Section {
                StopPageModeToggle(mode: sortType, onChange: onChangeMode)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }

        if content.listIsEmpty {
            if content.showsLoadingState {
                Section {
                    StopPageLoadingRow()
                }
            } else {
                Section {
                    StopPageEmptyStateRow(
                        isBrokenBookmark: isBrokenBookmark,
                        errorText: errorText,
                        isFilteredEmpty: content.isFilteredEmpty,
                        minutesAfter: minutesAfter,
                        fillsPage: fillsPage,
                        onRetry: onRetry,
                        onShowAllRoutes: onShowAllRoutes
                    )
                }
            }
        } else if !content.isGrouped {
            ChronologicalListView(
                partition: StopPageListBuilder.chronologicalPartition(content.departures, walkMinutes: walkMinutes),
                walkMinutes: walkMinutes,
                showPast: !pastCollapsed,
                expandedDepartureID: expandedDepartureID,
                statusProvider: statusProvider,
                alarmLookup: alarmLookup,
                actionsProvider: actionsProvider,
                onTogglePast: onTogglePast,
                onToggleExpand: onToggleExpand,
                panelBuilder: panelBuilder
            )
        } else {
            GroupedListView(
                groups: content.routeGroups,
                expandedRouteID: expandedRouteID,
                openTripDepartureID: expandedDepartureID,
                statusProvider: statusProvider,
                alarmLookup: alarmLookup,
                alarmLeadTime: alarmLeadTime,
                canAlarm: canAlarm,
                onToggleRoute: onToggleRoute,
                onToggleTrip: onToggleExpand,
                onAlarmToggle: onAlarmToggle,
                panelBuilder: panelBuilder
            )
        }

        if content.hasLoadedArrivals {
            StopPageFooterSection(
                showLoadMore: !isLoadMoreExhausted,
                isLoading: isLoading,
                attribution: content.attributionText,
                onLoadMore: onLoadMore
            )
        }
    }

    /// `true` when the empty row is the page's only content — no header card
    /// resolved above it, so the row claims most of the list's height and its
    /// message sits centred rather than stranded under the chrome.
    private var fillsPage: Bool {
        !content.hasLoadedArrivals && errorText != nil
    }
}
```

- [ ] **Step 2: Rewrite `StopPageView.body` to use it**

In `OBAKit/Stops/StopPage/StopPageView.swift`, replace the whole `var body: some View { ... }` computation from the `let walkTime = ...` line through the closing brace of the `List { ... }` with the version below. The `.listStyle(.plain)` and every modifier after it stay exactly as they are.

The one behavioural subtlety to preserve: `fillsPage` was previously `viewModel.stop == nil`. `StopDeparturesSections` derives it as "no arrivals loaded and there is an error", which is the same condition in practice — a first fetch that fails leaves `stop == nil` and an error. Keep `StopPagePresentationTests` green to confirm.

```swift
    var body: some View {
        // Hoist the single computed walk value so the header chip, the
        // chronological partition, and the divider all read one snapshot of it.
        let walkTime = viewModel.walkTime
        let content = StopPageContent(viewModel: viewModel)

        List {
            if let stop = viewModel.stop {
                if !showToolbarOnBottom {
                    Section {
                        StopPageHeaderView(stop: stop, walkTime: walkTime, statusText: viewModel.statusText, snapshotLoader: snapshotLoader, onWalkingDirections: navigation.showWalkingDirections)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            } else if content.showsLoadingState {
                // Loading only. A first fetch that fails leaves no header at
                // all — a "loading" skeleton sitting above an error message
                // reads as two contradictory states on one page; the centered
                // error row below owns the screen instead.
                if !showToolbarOnBottom {
                    Section {
                        StopPageHeaderPlaceholderView()
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            StopDeparturesSections(
                content: content,
                survey: viewModel.currentSurvey,
                stopID: viewModel.stopID,
                serviceAlerts: viewModel.stopArrivals?.serviceAlerts ?? [],
                sortType: viewModel.stopPreferences.sortType,
                walkMinutes: walkTime?.walkMinutes,
                minutesAfter: viewModel.minutesAfter,
                isBrokenBookmark: viewModel.isBrokenBookmark,
                errorText: viewModel.operationErrorMessage,
                showsDonation: content.hasLoadedArrivals && viewModel.shouldRequestDonations && !donationHidden,
                isLoadMoreExhausted: viewModel.isLoadMoreExhausted,
                isLoading: viewModel.isLoading,
                pastCollapsed: pastCollapsed,
                expandedDepartureID: expandedDepartureID,
                expandedRouteID: expandedRouteID,
                statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                alarmLookup: { viewModel.alarm(for: $0) },
                alarmLeadTime: { viewModel.alarmLeadTimeMinutes($0) },
                canAlarm: { viewModel.canCreateAlarm(for: $0) },
                actionsProvider: makeActions(for:),
                panelBuilder: makePanel(for:),
                onSurveyNext: { answer in
                    Task { await viewModel.submitHeroAnswer(answer, stopLocation: viewModel.stop?.coordinate) }
                },
                onSurveyDismiss: { viewModel.dismissCurrentSurvey() },
                onSurveyExternal: {
                    viewModel.launchExternalSurvey(viewModel.currentSurvey, onFailure: navigation.showExternalSurveyError)
                },
                onDonate: navigation.showDonation,
                onDonationClose: { navigation.dismissDonation { donationHidden = true } },
                onSelectAlert: navigation.showAlertDetail,
                onChangeMode: { newValue in
                    withAnimation {
                        // Switching modes collapses every open accordion (§4.6).
                        expandedDepartureID = nil
                        expandedRouteID = nil
                        userDefaults.set(newValue.rawValue, forKey: Self.lastUsedStopSortKey)
                        viewModel.updateSortType(newValue)
                    }
                },
                onTogglePast: { withAnimation { pastCollapsed.toggle() } },
                onToggleExpand: { departure in
                    withAnimation(.snappy) {
                        expandedDepartureID = expandedDepartureID == departure.id ? nil : departure.id
                    }
                },
                onToggleRoute: { routeID in
                    withAnimation(.snappy) {
                        expandedRouteID = expandedRouteID == routeID ? nil : routeID
                        expandedDepartureID = nil
                    }
                },
                onAlarmToggle: { departure in
                    if viewModel.alarm(for: departure) != nil {
                        Task { await viewModel.cancelAlarm(for: departure) }
                    } else {
                        navigation.showAlarmPicker(departure)
                    }
                },
                onRetry: { Task { await viewModel.refresh() } },
                onShowAllRoutes: { viewModel.isListFiltered = false },
                onLoadMore: { Task { await viewModel.loadMoreDepartures() } }
            )
        }
```

Then update the two reconcilers below to read from `content`, since `departureIDs` / `routeIDs` are no longer locals:

```swift
        .onChange(of: content.departureIDs) { _, ids in
            if let id = expandedDepartureID, !ids.contains(id) { expandedDepartureID = nil }
        }
        .onChange(of: content.routeIDs) { _, ids in
            if let rid = expandedRouteID, !ids.contains(rid) { expandedRouteID = nil }
        }
```

Finally delete the now-unused private members from `StopPageView`: `hasLoadedArrivals`, `showsLoadingState`, `filteredDepartures`, `attributionText`, and `horizontalRowInset`.

- [ ] **Step 3: Build and run the regression suite**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/StopPagePresentationTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS. This suite is the contract that presentations 1 and 2 are unchanged.

- [ ] **Step 4: Run the full suite**

```bash
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Stops/StopPage/Shared/StopDeparturesSections.swift \
        OBAKit/Stops/StopPage/StopPageView.swift
git commit -m "Extract the shared stop page sections from the page view"
```

---

### Task 3: `stopPageLifecycle` modifier

**Files:**
- Create: `OBAKit/Stops/StopPage/Shared/StopPageLifecycleModifier.swift`
- Modify: `OBAKit/Stops/StopPage/StopPageView.swift`

**Interfaces:**
- Produces: `View.stopPageLifecycle(viewModel:userDefaults:liveActivityStarted:)` returning `some View`

- [ ] **Step 1: Create the modifier**

```swift
//
//  StopPageLifecycleModifier.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Lifecycle every Stop page presentation shares: start and stop the view
/// model, seed the last-used list mode, and show the Live Activity toast.
///
/// `.refreshable` is deliberately absent — the pushed screen and the
/// FloatingPanel sheet offer pull-to-refresh, the map sheet refreshes from its
/// toolbar button only, so that one modifier stays with each caller.
private struct StopPageLifecycleModifier: ViewModifier {
    @ObservedObject var viewModel: StopViewModel
    let userDefaults: UserDefaults
    let liveActivityStarted: Bool

    /// Global (not per-stop) "last mode the user picked" seed.
    static let lastUsedStopSortKey = "OBALastUsedStopSort"

    @State private var didSeedMode = false

    func body(content: Content) -> some View {
        content
            .task { await viewModel.start() }
            .onAppear(perform: seedLastUsedModeIfNeeded)
            .onDisappear { viewModel.deactivate() }
            .overlay(alignment: .bottom) {
                if liveActivityStarted {
                    Text(OBALoc("live_activity.started.title", value: "Tracking on Lock Screen", comment: "Toast shown when a Live Activity starts on the Lock Screen"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.tint, in: Capsule())
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: liveActivityStarted)
    }

    /// One-shot: a stop the user has never customised opens in the last mode
    /// they picked anywhere in the app. A stop with saved preferences owns its
    /// sort type and is left alone — including one deliberately set to
    /// Chronological, which `stopPreferences.sortType` alone can't tell apart
    /// from the default.
    private func seedLastUsedModeIfNeeded() {
        guard !didSeedMode else { return }
        didSeedMode = true
        guard !viewModel.hasCustomizedPreferences,
              let raw = userDefaults.string(forKey: Self.lastUsedStopSortKey),
              let seeded = StopSort(rawValue: raw)
        else { return }
        viewModel.seedSortType(seeded)
    }
}

extension View {
    func stopPageLifecycle(
        viewModel: StopViewModel,
        userDefaults: UserDefaults,
        liveActivityStarted: Bool
    ) -> some View {
        modifier(StopPageLifecycleModifier(
            viewModel: viewModel,
            userDefaults: userDefaults,
            liveActivityStarted: liveActivityStarted
        ))
    }
}
```

- [ ] **Step 2: Adopt it in `StopPageView`**

In `StopPageView`, delete `@State private var didSeedMode`, the `seedLastUsedModeIfNeeded()` method, and these modifiers: `.task { await viewModel.start() }`, `.onAppear(perform: seedLastUsedModeIfNeeded)`, `.onDisappear { viewModel.deactivate() }`, the `.overlay(alignment: .bottom) { ... }` toast, and `.animation(.spring(duration: 0.3), value: viewModel.liveActivityStarted)`.

Replace them with one modifier, keeping `.refreshable` where it is:

```swift
        .refreshable { await viewModel.refresh() }
        .stopPageLifecycle(
            viewModel: viewModel,
            userDefaults: userDefaults,
            liveActivityStarted: viewModel.liveActivityStarted
        )
```

Change the mode-toggle callback's `userDefaults.set(newValue.rawValue, forKey: Self.lastUsedStopSortKey)` to use the modifier's key, and delete `StopPageView`'s own `lastUsedStopSortKey` constant:

```swift
                    userDefaults.set(newValue.rawValue, forKey: StopPageLifecycleKeys.lastUsedStopSort)
```

Add the shared key holder to `StopPageLifecycleModifier.swift`, since the modifier type itself is `private`:

```swift
/// The seed key, shared between the modifier that reads it and the mode
/// toggle callbacks that write it.
enum StopPageLifecycleKeys {
    static let lastUsedStopSort = "OBALastUsedStopSort"
}
```

and change the modifier to read `StopPageLifecycleKeys.lastUsedStopSort`, deleting its own `lastUsedStopSortKey`.

- [ ] **Step 3: Build and test**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add OBAKit/Stops/StopPage/Shared/StopPageLifecycleModifier.swift \
        OBAKit/Stops/StopPage/StopPageView.swift
git commit -m "Share the stop page lifecycle wiring through one modifier"
```

---

### Task 4: `StopPageActionPresenter`

Move every UIKit modal flow off the view controller so a SwiftUI sheet can drive them.

**Files:**
- Create: `OBAKit/Stops/StopPage/StopPageActionPresenter.swift`
- Modify: `OBAKit/Stops/StopPage/StopPageViewController.swift`
- Create: `OBAKitTests/Stops/StopPage/StopPageActionPresenterTests.swift`

**Interfaces:**
- Produces: `@MainActor final class StopPageActionPresenter` with `init(application: Application, presentingController: @escaping () -> UIViewController?)`; methods `makeNavigationHandler(viewModel:closeSheet:) -> StopPageNavigationHandler`, `makeUserActivity(stop: Stop) -> NSUserActivity?`, `loadSnapshot(stop: Stop, size: CGSize, traitCollection: UITraitCollection) async -> UIImage?`, `showScheduleForStop(stopID:)`, `showScheduleForRoute(_:)`, `showBookmarkEditor(for:stop:preloadedArrivals:)`, `showRouteFilter(stop:hiddenRoutes:onUpdate:)`, `showWalkingDirections(coordinate:)`, `showNearbyStops(coordinate:)`, `showServiceAlerts(_:)`, `showReportProblem(stop:)`, `showFullSurvey(_:heroResponseID:stop:stopID:)`, `showExternalSurveyError()`, `showDonation()`, `showDonationDismiss(onHide:)`, `showAlarmPicker(for:viewModel:)`, `startLiveActivity(for:viewModel:)`, `showError(_:)`, `showAlarmPermissionDeniedAlert(onDismiss:)`

- [ ] **Step 1: Create the presenter**

Create `OBAKit/Stops/StopPage/StopPageActionPresenter.swift`. Move the bodies of these members out of `StopPageViewController` **verbatim**, replacing `self` (as a presenting controller) with `presentingController()` and `self.application` with `application`:

`showScheduleForStop`, `showScheduleForRoute(for:)`, `showBookmarkEditor(for:)`, `filter()`, `showWalkingDirections()`, `showReportProblem()`, `showFullSurvey(_:heroResponseID:)`, `showExternalSurveyError()`, `showDonationUI()`, `showDonationDismissUI(onHide:)`, `showAlarmPicker(for:)`, `startLiveActivity(for:)`, `buildLiveActivityContentState(for:)`, `presentAlarmPermissionDeniedAlert()`, `loadSnapshot(size:)`, the `nearbyAction` and `alertsAction` bodies from `locationMenu()`/`fileMenu()`, plus the `AlarmBuilderDelegate`, `BookmarkEditorDelegate` and `StopPreferencesViewDelegate` conformances and the `googleMapsAvailable` lazy property.

```swift
//
//  StopPageActionPresenter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import ActivityKit
import OBAKitCore

/// Every flow that leaves the Stop page or presents a modal over it.
///
/// Extracted from `StopPageViewController` so both the pushed presentation and
/// the SwiftUI map sheet drive the same code. The sheet has no view controller
/// of its own, so the presenting controller arrives as a provider closure
/// resolved at call time rather than a stored reference — see
/// `AppSheetViewFactory`, which walks to the topmost presented controller so
/// modals land above the sheet stack instead of underneath it.
@MainActor
final class StopPageActionPresenter: NSObject {

    private let application: Application
    private let presentingController: () -> UIViewController?

    init(application: Application, presentingController: @escaping () -> UIViewController?) {
        self.application = application
        self.presentingController = presentingController
        super.init()
    }

    /// `application.canOpenURL` is an XPC round-trip and Google Maps can't be
    /// installed or removed within a screen's lifetime, so resolve availability
    /// once instead of on every chrome rebuild.
    private lazy var googleMapsAvailable: Bool = {
        guard let coordinate = lastKnownCoordinate,
              let url = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate)
        else { return false }
        return application.canOpenURL(url)
    }()

    /// Set whenever a flow is invoked with a stop, so `googleMapsAvailable` has
    /// a coordinate to probe with.
    private var lastKnownCoordinate: CLLocationCoordinate2D?

    // MARK: - Navigation Handler

    /// Builds the handler the SwiftUI layer consumes. `closeSheet` is a no-op
    /// for the pushed presentation, which leaves via the navigation bar.
    func makeNavigationHandler(
        viewModel: StopViewModel,
        closeSheet: @escaping () -> Void = {}
    ) -> StopPageNavigationHandler {
        StopPageNavigationHandler(
            showTrip: { [weak self] departure in
                guard let self, let host = self.presentingController() else { return }
                self.application.viewRouter.navigateTo(arrivalDeparture: departure, from: host)
            },
            showScheduleForStop: { [weak self] in
                self?.showScheduleForStop(stopID: viewModel.stopID)
            },
            showScheduleForRoute: { [weak self] departure in
                self?.showScheduleForRoute(departure)
            },
            canScheduleForRoute: application.currentRegion?.supportsScheduleForRoute ?? true,
            showWalkingDirections: { [weak self] in
                guard let coordinate = viewModel.stop?.coordinate else { return }
                self?.showWalkingDirections(coordinate: coordinate)
            },
            showAlertDetail: { [weak self] alert in
                guard let self, let host = self.presentingController() else { return }
                self.application.viewRouter.navigateTo(alert: alert, from: host)
            },
            showBookmarkEditor: { [weak self] departure in
                self?.showBookmarkEditor(
                    for: departure,
                    stop: viewModel.stop,
                    preloadedArrivals: viewModel.stopArrivals?.arrivalsAndDepartures
                )
            },
            showAlarmPicker: { [weak self] departure in
                self?.showAlarmPicker(for: departure, viewModel: viewModel)
            },
            startLiveActivity: { [weak self] departure in
                self?.startLiveActivity(for: departure, viewModel: viewModel)
            },
            showExternalSurveyError: { [weak self] in self?.showExternalSurveyError() },
            showDonation: { [weak self] in self?.showDonation() },
            dismissDonation: { [weak self] onHide in self?.showDonationDismiss(onHide: onHide) },
            makeTripPreview: { [weak self] departure in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    TripViewControllerPreview(departure: departure, application: self.application)
                        .frame(width: 320, height: 400)
                )
            },
            showRouteFilter: { [weak self] in
                guard let self, let stop = viewModel.stop else { return }
                self.showRouteFilter(
                    stop: stop,
                    hiddenRoutes: Set(viewModel.stopPreferences.hiddenRoutes),
                    onUpdate: { prefs in viewModel.updateStopPreferences(prefs) }
                )
            },
            showServiceAlerts: { [weak self] in
                self?.showServiceAlerts(viewModel.stopArrivals?.serviceAlerts ?? [])
            },
            showNearbyStops: { [weak self] in
                guard let coordinate = viewModel.stop?.coordinate else { return }
                self?.showNearbyStops(coordinate: coordinate)
            },
            showReportProblem: { [weak self] in
                guard let stop = viewModel.stop else { return }
                self?.showReportProblem(stop: stop)
            },
            closeSheet: closeSheet
        )
    }

    // MARK: - Schedules

    func showScheduleForStop(stopID: StopID) {
        let controller = ScheduleForStopViewController(stopID: stopID, application: application)
        presentingController()?.present(controller, animated: true)
    }

    func showScheduleForRoute(_ arrivalDeparture: ArrivalDeparture) {
        let controller = ScheduleForRouteViewController(routeID: arrivalDeparture.routeID, application: application)
        presentingController()?.present(controller, animated: true)
    }

    // MARK: - Bookmarks

    /// `nil` starts the stop-level "Add Bookmark" workflow; a departure jumps
    /// straight into editing a trip bookmark.
    func showBookmarkEditor(
        for arrivalDeparture: ArrivalDeparture?,
        stop: Stop?,
        preloadedArrivals: [ArrivalDeparture]?
    ) {
        guard let host = presentingController() else { return }

        if let arrivalDeparture {
            let controller = EditBookmarkViewController(application: application, arrivalDeparture: arrivalDeparture, bookmark: nil, delegate: self)
            let navigation = UINavigationController(rootViewController: controller)
            application.viewRouter.present(navigation, from: host)
        } else {
            guard let stop else { return }
            let controller = AddBookmarkViewController(application: application, stop: stop, preloadedArrivals: preloadedArrivals, delegate: self)
            let navigation = application.viewRouter.buildNavigation(controller: controller)
            application.viewRouter.present(navigation, from: host, isModal: true)
        }
    }

    // MARK: - Route Filter

    func showRouteFilter(stop: Stop, hiddenRoutes: Set<RouteID>, onUpdate: @escaping (StopPreferences) -> Void) {
        stopPreferencesUpdate = onUpdate
        let view = StopPreferencesWrappedView(stop, initialHiddenRoutes: hiddenRoutes, delegate: self)
            .environment(\.coreApplication, application)
        presentingController()?.present(UIHostingController(rootView: view), animated: true)
    }

    private var stopPreferencesUpdate: ((StopPreferences) -> Void)?

    // MARK: - Location

    func showNearbyStops(coordinate: CLLocationCoordinate2D) {
        guard let host = presentingController() else { return }
        let controller = NearbyStopsViewController(coordinate: coordinate, application: application)
        application.viewRouter.navigate(to: controller, from: host)
    }

    func showServiceAlerts(_ alerts: [ServiceAlert]) {
        guard let host = presentingController() else { return }
        let controller = ServiceAlertListController(application: application, serviceAlerts: alerts)
        application.viewRouter.navigate(to: controller, from: host)
    }

    func showReportProblem(stop: Stop) {
        guard let host = presentingController() else { return }
        let controller = ReportProblemViewController(application: application, stop: stop)
        let navigation = application.viewRouter.buildNavigation(controller: controller)
        application.viewRouter.present(navigation, from: host, isModal: true)
    }

    /// One available maps app opens directly; more than one presents an action
    /// sheet to disambiguate.
    func showWalkingDirections(coordinate: CLLocationCoordinate2D) {
        lastKnownCoordinate = coordinate

        var options: [(title: String, url: URL)] = []

        if let appleMapsURL = AppInterop.appleMapsWalkingDirectionsURL(coordinate: coordinate) {
            options.append((
                OBALoc("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop"),
                appleMapsURL
            ))
        }

        #if !targetEnvironment(simulator)
        if let googleMapsURL = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate), googleMapsAvailable {
            options.append((
                OBALoc("stops_controller.walking_directions_google", value: "Walking Directions (Google Maps)", comment: "Button that launches Google Maps with walking directions to this stop"),
                googleMapsURL
            ))
        }
        #endif

        guard let first = options.first else { return }

        if options.count == 1 {
            application.open(first.url, options: [:], completionHandler: nil)
            return
        }

        let sheet = UIAlertController(
            title: OBALoc("stops_controller.walking_directions", value: "Walking Directions", comment: "Button that launches a maps app with walking directions to this stop"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for option in options {
            sheet.addAction(UIAlertAction(title: option.title, style: .default) { [weak self] _ in
                self?.application.open(option.url, options: [:], completionHandler: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: Strings.cancel, style: .cancel))
        present(actionSheet: sheet)
    }

    /// An unanchored action sheet is a hard crash on a regular-width device.
    /// The sheet presentation is iPhone-only, but the pushed presentation is
    /// not, and both come through here.
    private func present(actionSheet: UIAlertController) {
        guard let host = presentingController() else { return }
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(origin: host.view.center, size: .zero)
        }
        host.present(actionSheet, animated: true)
    }

    // MARK: - Surveys

    func showFullSurvey(_ survey: Survey, heroResponseID: String?, stop: Stop?, stopID: StopID) {
        let controller = SurveyViewController(
            survey: survey,
            surveyService: application.surveyService,
            stop: stop,
            stopID: stopID,
            stopLocation: stop?.coordinate,
            heroResponseID: heroResponseID
        )
        presentingController()?.present(UINavigationController(rootViewController: controller), animated: true)
    }

    func showExternalSurveyError() {
        let alert = UIAlertController(
            title: OBALoc("stop_controller.external_survey_error.title", value: "Can't Open Survey", comment: "Title shown when an external survey link cannot be opened"),
            message: OBALoc("stop_controller.external_survey_error.message", value: "This survey link couldn't be opened. Please try again later.", comment: "Message shown when an external survey link cannot be opened"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
        presentingController()?.present(alert, animated: true)
    }

    // MARK: - Donations

    func showDonation() {
        guard
            application.donationsManager.donationsEnabled,
            let donationModel = application.donationsManager.buildObservableDonationModel()
        else { return }

        let view = DonationLearnMoreView()
            .environmentObject(donationModel)
            .environmentObject(AnalyticsModel(application.analytics))

        presentingController()?.present(UIHostingController(rootView: view), animated: true)
    }

    /// `onHide` fires only when the user actually hides the card (dismiss or
    /// remind-later), so the SwiftUI page can drop the section immediately.
    func showDonationDismiss(onHide: @escaping () -> Void) {
        let controller = UIAlertController(
            title: Strings.donationsDismissAlertTitle,
            message: Strings.donationsDismissAlertMessage,
            preferredStyle: .actionSheet
        )

        controller.addAction(title: Strings.donationsDismissAlertButtonDismiss, style: .destructive) { [weak self] _ in
            self?.application.donationsManager.dismissDonationsRequests()
            onHide()
        }
        controller.addAction(title: Strings.donationsDismissAlertButtonRemindLater, style: .default) { [weak self] _ in
            self?.application.donationsManager.remindUserLater()
            onHide()
        }
        controller.addAction(title: Strings.cancel, style: .cancel, handler: nil)

        present(actionSheet: controller)
    }

    // MARK: - Alarms

    private var alarmBuilder: AlarmBuilder?
    private var alarmBuilderDeparture: ArrivalDeparture?
    private weak var alarmViewModel: StopViewModel?

    func showAlarmPicker(for arrivalDeparture: ArrivalDeparture, viewModel: StopViewModel) {
        // The SwiftUI alarm affordances are gated on `canCreateAlarm`, but that
        // gate is only re-evaluated on the refresh tick — a departure can slip
        // inside the one-minute floor while the row still offers the button.
        guard viewModel.canCreateAlarm(for: arrivalDeparture),
              let host = presentingController()
        else { return }

        alarmBuilderDeparture = arrivalDeparture
        alarmViewModel = viewModel
        let existingAlarm = viewModel.alarm(for: arrivalDeparture)
        alarmBuilder = AlarmBuilder(
            arrivalDeparture: arrivalDeparture,
            application: application,
            initialMinutes: existingAlarm.map { viewModel.alarmLeadTimeMinutes($0) },
            delegate: self
        )
        alarmBuilder?.showBulletin(above: host)
    }

    func showAlarmPermissionDeniedAlert(onDismiss: @escaping () -> Void) {
        let alert = UIAlertController(
            title: OBALoc("stop_page.alarm_permission_denied.title", value: "Notifications Are Off", comment: "Title of the alert shown when the user tries to set a departure alarm but notifications are denied in Settings."),
            message: String(
                format: OBALoc("stop_page.alarm_permission_denied.message", value: "To get departure alarms, allow notifications for %@ in Settings.", comment: "Body of the alert shown when the user tries to set a departure alarm but notifications are denied in Settings. %@ is the app name."),
                Bundle.main.appName
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.cancel, style: .cancel))
        alert.addAction(UIAlertAction(
            title: OBALoc("stop_page.alarm_permission_denied.open_settings", value: "Open Settings", comment: "Button that opens the system Settings app so the user can enable notifications."),
            style: .default
        ) { [weak self] _ in
            guard let self, let url = URL(string: UIApplication.openSettingsURLString) else { return }
            self.application.open(url, options: [:], completionHandler: nil)
        })
        presentingController()?.present(alert, animated: true)
        onDismiss()
    }

    func showError(_ error: Error) {
        guard let host = presentingController() else { return }
        Task { @MainActor in
            await AlertPresenter.show(error: error, presentingController: host)
        }
    }

    // MARK: - Live Activity

    func startLiveActivity(for departure: ArrivalDeparture, viewModel: StopViewModel) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let staticData = TripAttributes.StaticData(
            routeShortName: departure.routeShortName,
            routeHeadsign: departure.tripHeadsign ?? "",
            stopID: departure.stopID,
            routeColorHex: departure.route.color?.toHex(),
            regionID: application.currentRegion?.regionIdentifier ?? 0
        )

        guard let contentState = buildLiveActivityContentState(for: departure, viewModel: viewModel) else {
            Logger.error("Failed to build content state for Live Activity")
            return
        }

        do {
            let activity = try Activity.request(
                attributes: TripAttributes(staticData: staticData),
                content: .init(state: contentState, staleDate: nil),
                pushType: .token
            )
            application.liveActivityTracker.track(activity: activity, metadata: .init(departure))
            Logger.info("Started Live Activity with ID: \(activity.id)")
            viewModel.signalLiveActivityStarted()
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            showLiveActivityErrorAlert()
        }
    }

    private func buildLiveActivityContentState(for departure: ArrivalDeparture, viewModel: StopViewModel) -> TripAttributes.ContentState? {
        let allArrivals = viewModel.stopArrivals?.arrivalsAndDepartures ?? [departure]
        let sameRoute = allArrivals.filter { $0.routeID == departure.routeID }
        let upcoming = sameRoute.isEmpty ? [departure] : Array(sameRoute.prefix(3))
        let arrivals = upcoming.map { arrDep in
            TripAttributes.ContentState.ArrivalInfo(
                departureTime: Int(arrDep.arrivalDepartureDate.timeIntervalSince1970),
                scheduleStatus: .init(arrDep.scheduleStatus),
                scheduleDeviation: arrDep.deviationFromScheduleInMinutes * 60,
                isArrival: arrDep.arrivalDepartureStatus == .arriving
            )
        }
        return TripAttributes.ContentState(arrivals: arrivals)
    }

    // MARK: - User Activity

    /// Publishes this stop's `NSUserActivity` for Handoff, Siri and Spotlight.
    func makeUserActivity(stop: Stop) -> NSUserActivity? {
        guard let region = application.regionsService.currentRegion,
              let builder = application.userActivityBuilder
        else { return nil }
        return builder.userActivity(for: stop, region: region)
    }

    // MARK: - Snapshot

    /// Bridges the callback-based `MapSnapshotter` into async/await for the
    /// SwiftUI header.
    func loadSnapshot(stop: Stop, size: CGSize, traitCollection: UITraitCollection) async -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let factory = application.stopIconFactory
        // The header design is always-dark (white identity text over a dark
        // scrim), so render in dark style regardless of the system appearance.
        let traits = traitCollection.modifyingTraits { $0.userInterfaceStyle = .dark }
        return await withCheckedContinuation { continuation in
            let snapshotter = MapSnapshotter(size: size, stopIconFactory: factory)
            snapshotter.snapshot(stop: stop, traitCollection: traits) { image in
                // `MapSnapshotter`'s internal `MKMapSnapshotter.start`
                // completion is `[weak self]`, so the wrapper must outlive the
                // async render or the completion early-returns and this
                // continuation never resumes — leaving the header blank.
                withExtendedLifetime(snapshotter) {
                    continuation.resume(returning: image)
                }
            }
        }
    }
}

// MARK: - AlarmBuilderDelegate

extension StopPageActionPresenter: AlarmBuilderDelegate {
    func alarmBuilderStartedRequest(_ alarmBuilder: AlarmBuilder) {
        ProgressHUD.show()
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm) {
        if let departure = alarmBuilderDeparture, let viewModel = alarmViewModel {
            // `replaceAlarm` indexes the new alarm synchronously and no-ops the
            // delete when the departure had no prior alarm, so it serves both
            // the create and change flows.
            Task { await viewModel.replaceAlarm(with: alarm, for: departure) }

            if alarmBuilder.trackOnLockScreen {
                startLiveActivity(for: departure, viewModel: viewModel)
            }
        } else {
            alarmViewModel?.recordAlarmCreated(alarm)
        }

        let message = OBALoc("stop_controller.alarm_created_message", value: "Alarm created", comment: "A message that appears when a user's alarm is created.")
        ProgressHUD.showSuccessAndDismiss(message: message)
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, error: Error) {
        ProgressHUD.dismiss()
        showError(error)
    }
}

// MARK: - BookmarkEditorDelegate

extension StopPageActionPresenter: BookmarkEditorDelegate {
    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true, completion: nil)
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
        viewController.dismiss(animated: true) {
            let msg = isNewBookmark
                ? OBALoc("stops_controller.created_new_bookmark", value: "Added Bookmark", comment: "Message displayed when a new bookmark is created.")
                : OBALoc("stops_controller.updated_bookmark", value: "Updated Bookmark", comment: "Message displayed an existing bookmark is updated.")
            ProgressHUD.showSuccessAndDismiss(message: msg, dismissAfter: 1.0)
        }
    }
}

// MARK: - StopPreferencesViewDelegate

extension StopPageActionPresenter: StopPreferencesViewDelegate {
    func stopPreferences(stopID: StopID, updated stopPreferences: StopPreferences) {
        stopPreferencesUpdate?(stopPreferences)
    }
}
```

If `showLiveActivityErrorAlert()` is currently a private helper on the view controller, move it across too; if it lives in a shared extension, leave it where it is.

- [ ] **Step 2: Rewire `StopPageViewController`**

Add a stored presenter and delegate to it. In the class body:

```swift
    private lazy var actionPresenter = StopPageActionPresenter(
        application: application,
        presentingController: { [weak self] in self }
    )
```

Replace `makeNavigationHandler()` with:

```swift
    private func makeNavigationHandler() -> StopPageNavigationHandler {
        actionPresenter.makeNavigationHandler(viewModel: viewModel, closeSheet: { [weak self] in
            self?.onClose?()
        })
    }
```

Replace the body of `loadSnapshot(size:)`:

```swift
    private func loadSnapshot(size: CGSize) async -> UIImage? {
        guard let stop = viewModel.stop else { return nil }
        return await actionPresenter.loadSnapshot(stop: stop, size: size, traitCollection: traitCollection)
    }
```

Replace `beginUserActivity()`'s body:

```swift
    private func beginUserActivity() {
        guard let stop = viewModel.stop else { return }
        self.userActivity = actionPresenter.makeUserActivity(stop: stop)
    }
```

Point the remaining call sites — the menu actions in `fileMenu()`, `locationMenu()`, `helpMenu()`, the `@objc func showScheduleForStop()` target, `filter()`, and the survey/alarm Combine sinks — at the presenter, e.g.:

```swift
    @objc func showScheduleForStop() {
        actionPresenter.showScheduleForStop(stopID: viewModel.stopID)
    }
```

Then delete from the view controller: the private extension holding the moved flows, the `AlarmBuilderDelegate` / `BookmarkEditorDelegate` / `StopPreferencesViewDelegate` conformances and their stored properties (`alarmBuilder`, `alarmBuilderDeparture`), and the `googleMapsAvailable` lazy property. Keep the `AppContext`, `Idleable` and `Previewable` conformances, `bindChrome`, `bindArrivalsFeedback`, `bindSurveyPresentation`, `bindAlarmFeedback`, `configureBarButtons` and the menu builders.

- [ ] **Step 3: Write the presenter tests**

Create `OBAKitTests/Stops/StopPage/StopPageActionPresenterTests.swift`:

```swift
//
//  StopPageActionPresenterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The presenter owns every "leaves the Stop page" flow for both the pushed
/// screen and the map sheet. These tests pin down which controller each flow
/// presents, and — most importantly — that the presenter presents from the
/// controller its provider resolves rather than no-oping.
@MainActor
@Suite(.serialized)
final class StopPageActionPresenterTests: OBATestCase {

    private var queue: OperationQueue!
    private var window: UIWindow!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// A presented controller only materializes when the presenter is in a
    /// window, so every test roots one.
    private func makeHost() -> UIViewController {
        let host = UIViewController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        return host
    }

    private func makePresenter(host: UIViewController) -> (StopPageActionPresenter, Application) {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let presenter = StopPageActionPresenter(
            application: application,
            presentingController: { host }
        )
        return (presenter, application)
    }

    /// `present` is asynchronous; poll briefly rather than assuming one runloop
    /// turn is enough.
    private func waitForPresentation(on controller: UIViewController) async -> UIViewController? {
        for _ in 0..<20 {
            if let presented = controller.presentedViewController { return presented }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return controller.presentedViewController
    }

    @Test func `Schedule for stop presents the schedule controller`() async {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)

        presenter.showScheduleForStop(stopID: "1_10914")

        let presented = await waitForPresentation(on: host)
        #expect(presented is ScheduleForStopViewController)
    }

    @Test func `Stop level bookmark presents the add bookmark controller`() async throws {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)
        let stop = try #require(Fixtures.loadSomeStops().first)

        presenter.showBookmarkEditor(for: nil, stop: stop, preloadedArrivals: nil)

        let presented = await waitForPresentation(on: host)
        let navigation = try #require(presented as? UINavigationController)
        #expect(navigation.viewControllers.first is AddBookmarkViewController)
    }

    @Test func `Departure level bookmark presents the edit bookmark controller`() async throws {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)
        let departure = try Fixtures.arrivalDeparture()

        presenter.showBookmarkEditor(for: departure, stop: nil, preloadedArrivals: nil)

        let presented = await waitForPresentation(on: host)
        let navigation = try #require(presented as? UINavigationController)
        #expect(navigation.viewControllers.first is EditBookmarkViewController)
    }

    @Test func `Report a problem presents the report controller`() async throws {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)
        let stop = try #require(Fixtures.loadSomeStops().first)

        presenter.showReportProblem(stop: stop)

        let presented = await waitForPresentation(on: host)
        let navigation = try #require(presented as? UINavigationController)
        #expect(navigation.viewControllers.first is ReportProblemViewController)
    }

    @Test func `External survey error presents an alert`() async {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)

        presenter.showExternalSurveyError()

        let presented = await waitForPresentation(on: host)
        #expect(presented is UIAlertController)
    }

    /// The reason the presenting-controller provider exists. UIKit ignores
    /// `present` on a controller that already has a `presentedViewController`,
    /// and in the sheet system the host always does — so a provider that
    /// returns the topmost controller must be honoured, or the modal silently
    /// never appears.
    @Test func `Presenting resolves the provider at call time not at init`() async {
        let host = makeHost()
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        // The provider starts pointing at `host`, then moves to a modal that
        // gets presented afterwards — exactly the sheet-stack shape.
        var target: UIViewController = host
        let presenter = StopPageActionPresenter(
            application: application,
            presentingController: { target }
        )

        let modal = UIViewController()
        host.present(modal, animated: false)
        _ = await waitForPresentation(on: host)
        target = modal

        presenter.showScheduleForStop(stopID: "1_10914")

        let presented = await waitForPresentation(on: modal)
        #expect(presented is ScheduleForStopViewController)
        #expect(host.presentedViewController === modal)
    }
}
```

- [ ] **Step 4: Build and run the presenter suite**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/StopPageActionPresenterTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS. If a controller's initializer differs from the signature above, correct the call — do not weaken the assertion.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS, including `StopPagePresentationTests`.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Stops/StopPage/StopPageActionPresenter.swift \
        OBAKit/Stops/StopPage/StopPageViewController.swift \
        OBAKitTests/Stops/StopPage/StopPageActionPresenterTests.swift
git commit -m "Extract the stop page modal flows into a shared presenter"
```

---

### Task 5: `keepsScreenAwake()` modifier

**Files:**
- Create: `OBAKit/Controls/SwiftUI/KeepsScreenAwake.swift`
- Modify: `OBAKit/Sheet/Content/CurrentTrip/CurrentTripView.swift`

**Interfaces:**
- Produces: `View.keepsScreenAwake() -> some View`

- [ ] **Step 1: Create the modifier**

```swift
//
//  KeepsScreenAwake.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit

/// Holds the idle timer off while a live, self-refreshing screen is visible —
/// the SwiftUI equivalent of `Idleable`.
///
/// The `wasDisabledByUs` latch matters: another screen may already have
/// disabled the timer, and re-enabling it on our way out would cut that screen's
/// wake short.
private struct KeepsScreenAwakeModifier: ViewModifier {
    @State private var wasDisabledByUs = false

    func body(content: Content) -> some View {
        content
            .onAppear(perform: disable)
            .onDisappear(perform: reEnable)
    }

    private func disable() {
        guard !UIApplication.shared.isIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        wasDisabledByUs = true
    }

    private func reEnable() {
        guard wasDisabledByUs else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        wasDisabledByUs = false
    }
}

extension View {
    func keepsScreenAwake() -> some View {
        modifier(KeepsScreenAwakeModifier())
    }
}
```

- [ ] **Step 2: Adopt it in `CurrentTripView`**

Delete `@State private var wasIdleTimerDisabledByUs`, `disableIdleTimer()` and `reEnableIdleTimer()`. Remove the `disableIdleTimer()` call from `.onAppear` and the `reEnableIdleTimer()` call from `.onDisappear`, and remove both from the `scenePhase` handler's `.active` and `.background` branches. Add `.keepsScreenAwake()` to the view's modifier chain.

The scene-phase branches keep their view-model calls:

```swift
        .onChange(of: scenePhase) { previous, phase in
            switch phase {
            case .active:
                if previous == .background {
                    viewModel.start()
                }
            case .background:
                viewModel.deactivate()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .keepsScreenAwake()
```

- [ ] **Step 3: Build and test**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add OBAKit/Controls/SwiftUI/KeepsScreenAwake.swift \
        OBAKit/Sheet/Content/CurrentTrip/CurrentTripView.swift
git commit -m "Share the idle timer handling through a view modifier"
```

---

### Task 6: `StopSheetHeaderCollapse`

The pure arithmetic behind the collapsing header, isolated so it can be tested.

**Files:**
- Create: `OBAKit/Sheet/Content/Stop/Details/StopSheetHeaderCollapse.swift`
- Create: `OBAKitTests/Sheet/StopSheetHeaderCollapseTests.swift`

**Interfaces:**
- Produces: `nonisolated enum StopSheetHeaderCollapse` with `static func progress(scrollOffset: CGFloat, collapsibleHeight: CGFloat) -> CGFloat`

- [ ] **Step 1: Write the failing tests**

```swift
//
//  StopSheetHeaderCollapseTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import Testing
@testable import OBAKit

/// The collapsing header's arithmetic. Extracted from the view because it is
/// the part most likely to misbehave and the only part a unit test can reach —
/// the scroll interaction itself needs a real scroll view.
@Suite(.serialized)
struct StopSheetHeaderCollapseTests {

    @Test func `At rest the header is fully expanded`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 0, collapsibleHeight: 170) == 0)
    }

    @Test func `Scrolling the full collapsible height fully collapses`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 170, collapsibleHeight: 170) == 1)
    }

    @Test func `Halfway through the range is half collapsed`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 85, collapsibleHeight: 170) == 0.5)
    }

    @Test func `Overscrolling past full collapse clamps to one`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 900, collapsibleHeight: 170) == 1)
    }

    @Test func `Rubber banding above the top clamps to zero`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: -120, collapsibleHeight: 170) == 0)
    }

    /// A stop that never resolves has no header to collapse. Without this
    /// guard the range divides by zero.
    @Test func `A zero collapsible height reports no progress`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 50, collapsibleHeight: 0) == 0)
    }

    @Test func `A negative collapsible height reports no progress`() {
        #expect(StopSheetHeaderCollapse.progress(scrollOffset: 50, collapsibleHeight: -10) == 0)
    }

    @Test func `Progress is monotonic across the range`() {
        var previous: CGFloat = -1
        for offset in stride(from: CGFloat(0), through: 170, by: 10) {
            let value = StopSheetHeaderCollapse.progress(scrollOffset: offset, collapsibleHeight: 170)
            #expect(value >= previous)
            previous = value
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: **build failure** — `cannot find 'StopSheetHeaderCollapse' in scope`.

- [ ] **Step 3: Implement**

```swift
//
//  StopSheetHeaderCollapse.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics

/// Maps scroll position to how far the stop sheet's map header has collapsed,
/// 0 (fully expanded) through 1 (gone).
///
/// A pure function rather than logic inside the view, both so it can be tested
/// and so the feedback-loop hazard has one obvious home. The chrome lives in a
/// `safeAreaInset` whose height shrinks as this value rises; if progress were
/// derived from `contentOffset.y` alone, shrinking the inset would shift the
/// offset, which would change progress, which would resize the inset again.
/// Callers pass `contentOffset.y + contentInsets.top`, a sum that holds steady
/// when the inset changes, which breaks the loop.
nonisolated enum StopSheetHeaderCollapse {

    /// - Parameters:
    ///   - scrollOffset: `contentOffset.y + contentInsets.top` — distance
    ///     scrolled from the top, invariant to inset changes.
    ///   - collapsibleHeight: the header's laid-out height, measured rather
    ///     than assumed: it is `@ScaledMetric` and grows further when route
    ///     chips wrap, so a hard-coded constant would mis-collapse at most
    ///     Dynamic Type sizes.
    /// - Returns: progress clamped to `0...1`; `0` when there is nothing to
    ///   collapse.
    static func progress(scrollOffset: CGFloat, collapsibleHeight: CGFloat) -> CGFloat {
        guard collapsibleHeight > 0 else { return 0 }
        return min(max(scrollOffset / collapsibleHeight, 0), 1)
    }
}
```

- [ ] **Step 4: Run to verify pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/StopSheetHeaderCollapseTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/Content/Stop/Details/StopSheetHeaderCollapse.swift \
        OBAKitTests/Sheet/StopSheetHeaderCollapseTests.swift
git commit -m "Add the stop sheet header collapse arithmetic"
```

---

### Task 7: `StopPageActionRow`

**Files:**
- Create: `OBAKit/Sheet/Content/Stop/Details/StopPageActionRow.swift`
- Create: `OBAKitTests/Sheet/StopPageActionRowStateTests.swift`

**Interfaces:**
- Produces: `StopPageActionRowState` with `init(routeCount: Int, hasHiddenRoutes: Bool, isListFiltered: Bool, hasServiceAlerts: Bool)` and properties `canFilter: Bool`, `isFilterOn: Bool`, `filterSystemImage: String`, `canShowServiceAlerts: Bool`; and `StopPageActionRow` taking `state: StopPageActionRowState`, `onSchedule: () -> Void`, `onSetListFiltered: (Bool) -> Void`, `onBookmark: () -> Void`, `onServiceAlerts: () -> Void`, `onNearbyStops: () -> Void`, `onWalkingDirections: () -> Void`, `onReportProblem: () -> Void`

- [ ] **Step 1: Write the failing state tests**

```swift
//
//  StopPageActionRowStateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

/// The action row's enabled and filled predicates, extracted from the view so
/// they can be asserted directly rather than through view inspection.
@Suite(.serialized)
struct StopPageActionRowStateTests {

    @Test func `A multi route stop can be filtered`() {
        let state = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(state.canFilter)
    }

    @Test func `A single route stop cannot be filtered`() {
        let state = StopPageActionRowState(routeCount: 1, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(!state.canFilter)
    }

    @Test func `A stop with no routes cannot be filtered`() {
        let state = StopPageActionRowState(routeCount: 0, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(!state.canFilter)
    }

    @Test func `The filter reads as on only when hidden routes are actually applied`() {
        let applied = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: true, isListFiltered: true, hasServiceAlerts: false)
        #expect(applied.isFilterOn)
        #expect(applied.filterSystemImage == "line.3.horizontal.decrease.circle.fill")

        let savedButOff = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: true, isListFiltered: false, hasServiceAlerts: false)
        #expect(!savedButOff.isFilterOn)
        #expect(savedButOff.filterSystemImage == "line.3.horizontal.decrease.circle")

        let noneHidden = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(!noneHidden.isFilterOn)
    }

    @Test func `Service alerts are reachable only when the stop has some`() {
        let withAlerts = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: true)
        #expect(withAlerts.canShowServiceAlerts)

        let without = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(!without.canShowServiceAlerts)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: **build failure** — `cannot find 'StopPageActionRowState' in scope`.

- [ ] **Step 3: Implement the row and its state**

```swift
//
//  StopPageActionRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The action row's enabled/filled predicates, as a value so they can be
/// tested without inspecting a view — the precedent set by
/// `SheetDetentConfiguration.shouldDisableBackgroundForFullScreen`.
nonisolated struct StopPageActionRowState {
    let routeCount: Int
    let hasHiddenRoutes: Bool
    let isListFiltered: Bool
    let hasServiceAlerts: Bool

    /// A single-route stop has nothing to filter down to.
    var canFilter: Bool { routeCount > 1 }

    /// Saved hidden routes only count while the filter is actually applied.
    var isFilterOn: Bool { hasHiddenRoutes && isListFiltered }

    var filterSystemImage: String {
        isFilterOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }

    var canShowServiceAlerts: Bool { hasServiceAlerts }
}

/// Schedule, Filter, Bookmark and More, as circular buttons under the stop
/// sheet's map header.
///
/// Filter is promoted out of the More menu into its own button, so More carries
/// only the four remaining actions. A plain-value view: every action is a
/// closure supplied by `StopDetailsSheetView`.
struct StopPageActionRow: View {
    let state: StopPageActionRowState

    let onSchedule: () -> Void
    /// `true` applies the saved route filter, `false` shows all routes.
    let onSetListFiltered: (Bool) -> Void
    let onBookmark: () -> Void
    let onServiceAlerts: () -> Void
    let onNearbyStops: () -> Void
    let onWalkingDirections: () -> Void
    let onReportProblem: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes four icon-and-label items can't share one line
    /// legibly, so the row scrolls instead of shrinking the labels into
    /// illegibility — the accommodation `StopPageToolbar` makes.
    private var scrollsHorizontally: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if scrollsHorizontally {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) { items }
                        .padding(.horizontal, 12)
                }
            } else {
                HStack(alignment: .top, spacing: 0) { items }
            }
        }
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var items: some View {
        button(title: Strings.schedules, systemImage: "calendar", action: onSchedule)

        filterItem

        button(
            title: OBALoc("stop_page.toolbar.bookmark", value: "Bookmark", comment: "Bottom-toolbar item on the Stop page that opens the Add Bookmark screen."),
            systemImage: "bookmark",
            action: onBookmark
        )

        moreItem
    }

    private var filterItem: some View {
        Menu {
            filterChoice(
                title: OBALoc("stops_controller.filter.all_routes", value: "All Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a filtered list to all of the list items. e.g. a stop serves routes 1, 2, and 3. The user has filtered the stop to only show route 3. Chooosing this item will show 1, 2, and 3 again."),
                isSelected: !state.isFilterOn,
                filtered: false
            )
            filterChoice(
                title: OBALoc("stops_controller.filter.filtered_routes", value: "Filtered Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a list of all items to a filtered list. e.g. a stop serves routes 1, 2, and 3. The user wants to only view route 3. Choosing this item would show that subset of routes."),
                isSelected: state.isFilterOn,
                filtered: true
            )
        } label: {
            label(title: Strings.filter, systemImage: state.filterSystemImage)
        }
        .disabled(!state.canFilter)
        .accessibilityLabel(Strings.filter)
        .accessibilityValue(state.isFilterOn
            ? OBALoc("stop_page.filter.a11y_on", value: "on", comment: "VoiceOver value of the route-filter bar button when the filter is active.")
            : OBALoc("stop_page.filter.a11y_off", value: "off", comment: "VoiceOver value of the route-filter bar button when the filter is inactive."))
    }

    @ViewBuilder
    private func filterChoice(title: String, isSelected: Bool, filtered: Bool) -> some View {
        Button {
            onSetListFiltered(filtered)
        } label: {
            Text(title)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var moreItem: some View {
        Menu {
            Button(action: onServiceAlerts) {
                Label(Strings.serviceAlerts, systemImage: "exclamationmark.circle")
            }
            .disabled(!state.canShowServiceAlerts)

            Section {
                Button(action: onNearbyStops) {
                    Label(OBALoc("stops_controller.nearby_stops", value: "Nearby Stops", comment: "Title of the row that will show stops that are near this one."), systemImage: "location")
                }
                Button(action: onWalkingDirections) {
                    Label(OBALoc("stops_controller.walking_directions", value: "Walking Directions", comment: "Button that launches a maps app with walking directions to this stop"), systemImage: "figure.walk")
                }
            }

            Section {
                Button(action: onReportProblem) {
                    Label(OBALoc("stops_controller.report_problem", value: "Report a Problem", comment: "Button that launches the 'Report Problem' UI."), systemImage: "exclamationmark.bubble")
                }
            }
        } label: {
            label(title: Strings.more, systemImage: "ellipsis")
        }
        .accessibilityLabel(Strings.more)
    }

    private func button(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label(title: title, systemImage: systemImage)
        }
        .accessibilityLabel(title)
    }

    /// A filled circle with the glyph, captioned beneath.
    private func label(title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .secondarySystemFill), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.tint)
        .frame(maxWidth: scrollsHorizontally ? nil : .infinity)
        .frame(minWidth: scrollsHorizontally ? 84 : nil)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}

#Preview("Action row") {
    StopPageActionRow(
        state: StopPageActionRowState(routeCount: 4, hasHiddenRoutes: true, isListFiltered: true, hasServiceAlerts: true),
        onSchedule: {}, onSetListFiltered: { _ in }, onBookmark: {},
        onServiceAlerts: {}, onNearbyStops: {}, onWalkingDirections: {}, onReportProblem: {}
    )
}
```

- [ ] **Step 4: Run to verify pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/StopPageActionRowStateTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/Content/Stop/Details/StopPageActionRow.swift \
        OBAKitTests/Sheet/StopPageActionRowStateTests.swift
git commit -m "Add the stop sheet circular action row"
```

---

### Task 8: `StopDetailsSheetTopBar`

**Files:**
- Create: `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetTopBar.swift`

**Interfaces:**
- Produces: `StopDetailsSheetTopBar` taking `title: String`, `titleOpacity: Double`, `statusText: String`, `isRefreshing: Bool`, `onRefresh: () -> Void`, `onClose: () -> Void`

- [ ] **Step 1: Create the bar**

```swift
//
//  StopDetailsSheetTopBar.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The stop sheet's pinned top strip: Refresh, the stop name, and Close.
///
/// It replaces the navigation bar the pushed presentation uses. The sheet has
/// no bar of its own, and this strip is the one piece of chrome that never
/// scrolls away — so Close remains reachable in every state, including a first
/// fetch that failed and left no header at all.
///
/// The title fades in as the map header collapses, so the sheet always names
/// the stop the rider is looking at without repeating it while the header is
/// on screen.
struct StopDetailsSheetTopBar: View {
    let title: String
    /// 0 while the header is expanded, 1 once it has collapsed.
    let titleOpacity: Double
    /// "Updated: Just Now" — the refresh button's VoiceOver value only. A
    /// visible label that rewrites itself every few seconds makes the bar feel
    /// restless, which is why `StopPageToolbar` hides it the same way.
    let statusText: String
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            refreshButton

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .opacity(titleOpacity)
                // Hidden from VoiceOver while invisible; the header below names
                // the stop in that state.
                .accessibilityHidden(titleOpacity < 0.5)

            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            ZStack {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 30)
            .background(Color(uiColor: .secondarySystemFill), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .accessibilityLabel(Strings.refresh)
        .accessibilityValue(statusText)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(uiColor: .secondarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.close)
    }
}

#Preview("Expanded") {
    StopDetailsSheetTopBar(title: "3rd Ave & Pike St", titleOpacity: 0, statusText: "Updated: Just Now", isRefreshing: false, onRefresh: {}, onClose: {})
}

#Preview("Collapsed") {
    StopDetailsSheetTopBar(title: "3rd Ave & Pike St", titleOpacity: 1, statusText: "Updated: Just Now", isRefreshing: true, onRefresh: {}, onClose: {})
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetTopBar.swift
git commit -m "Add the stop sheet pinned top bar"
```

---

### Task 9: `StopDetailsSheetView`

Compose the sheet: collapsing chrome inset, list, side effects.

**Files:**
- Create: `OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift`

**Interfaces:**
- Consumes: `StopPageContent`, `StopDeparturesSections`, `stopPageLifecycle`, `keepsScreenAwake`, `StopSheetHeaderCollapse`, `StopPageActionRow`/`StopPageActionRowState`, `StopDetailsSheetTopBar`, `StopPageActionPresenter`, `StopPageHeaderView`, `StopPageHeaderPlaceholderView`
- Produces: `StopDetailsSheetView` with `init(viewModel: @autoclosure @escaping () -> StopViewModel, presenter: StopPageActionPresenter, feedback: DataLoadFeedbackGenerator, formatters: Formatters, userDefaults: UserDefaults)`

- [ ] **Step 1: Create the view**

```swift
//
//  StopDetailsSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// The Stop page as a native SwiftUI sheet over the map panel.
///
/// It renders the same departures as the pushed screen — through the shared
/// `StopDeparturesSections` — but replaces the navigation bar with a pinned
/// Refresh/Close strip and a row of circular actions, and collapses the map
/// header away as the list scrolls so the actions stay reachable.
///
/// This is the only view here that observes `StopViewModel`; the header, the
/// action row and the sections all take plain values, so the view model's
/// refresh and status-timer churn re-evaluates one shallow body.
struct StopDetailsSheetView: View {
    /// The stop this sheet was built for. Stored rather than read off the view
    /// model because the model lives in a `@StateObject` that SwiftUI only
    /// instantiates at render time — this is what identifies the view before
    /// then, both in debug output and to the factory's tests.
    let stopID: StopID

    @StateObject private var viewModel: StopViewModel
    @EnvironmentObject private var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.scenePhase) private var scenePhase

    private let presenter: StopPageActionPresenter
    private let feedback: DataLoadFeedbackGenerator
    private let formatters: Formatters
    private let userDefaults: UserDefaults

    @State private var expandedDepartureID: String?
    @State private var expandedRouteID: RouteID?
    @State private var donationHidden = false
    @State private var collapseProgress: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var userActivity: NSUserActivity?
    /// Gates the one-shot success haptic to the first arrivals load, matching
    /// `StopViewController.bindArrivalsSink()`; later refreshes are silent.
    @State private var firstLoad = true

    @AppStorage("StopViewController.pastDeparturesCollapsed") private var pastCollapsed = true

    init(
        stopID: StopID,
        viewModel: @autoclosure @escaping () -> StopViewModel,
        presenter: StopPageActionPresenter,
        feedback: DataLoadFeedbackGenerator,
        formatters: Formatters,
        userDefaults: UserDefaults
    ) {
        self.stopID = stopID
        _viewModel = StateObject(wrappedValue: viewModel())
        self.presenter = presenter
        self.feedback = feedback
        self.formatters = formatters
        self.userDefaults = userDefaults
    }

    private var navigation: StopPageNavigationHandler {
        presenter.makeNavigationHandler(viewModel: viewModel, closeSheet: { coordinator.pop() })
    }

    var body: some View {
        let content = StopPageContent(viewModel: viewModel)
        let walkTime = viewModel.walkTime

        List {
            StopDeparturesSections(
                content: content,
                survey: viewModel.currentSurvey,
                stopID: viewModel.stopID,
                serviceAlerts: viewModel.stopArrivals?.serviceAlerts ?? [],
                sortType: viewModel.stopPreferences.sortType,
                walkMinutes: walkTime?.walkMinutes,
                minutesAfter: viewModel.minutesAfter,
                isBrokenBookmark: viewModel.isBrokenBookmark,
                errorText: viewModel.operationErrorMessage,
                showsDonation: content.hasLoadedArrivals && viewModel.shouldRequestDonations && !donationHidden,
                isLoadMoreExhausted: viewModel.isLoadMoreExhausted,
                isLoading: viewModel.isLoading,
                pastCollapsed: pastCollapsed,
                expandedDepartureID: expandedDepartureID,
                expandedRouteID: expandedRouteID,
                statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                alarmLookup: { viewModel.alarm(for: $0) },
                alarmLeadTime: { viewModel.alarmLeadTimeMinutes($0) },
                canAlarm: { viewModel.canCreateAlarm(for: $0) },
                actionsProvider: makeActions(for:),
                panelBuilder: makePanel(for:),
                onSurveyNext: { answer in
                    Task { await viewModel.submitHeroAnswer(answer, stopLocation: viewModel.stop?.coordinate) }
                },
                onSurveyDismiss: { viewModel.dismissCurrentSurvey() },
                onSurveyExternal: {
                    viewModel.launchExternalSurvey(viewModel.currentSurvey, onFailure: navigation.showExternalSurveyError)
                },
                onDonate: navigation.showDonation,
                onDonationClose: { navigation.dismissDonation { donationHidden = true } },
                onSelectAlert: navigation.showAlertDetail,
                onChangeMode: { newValue in
                    withAnimation {
                        expandedDepartureID = nil
                        expandedRouteID = nil
                        userDefaults.set(newValue.rawValue, forKey: StopPageLifecycleKeys.lastUsedStopSort)
                        viewModel.updateSortType(newValue)
                    }
                },
                onTogglePast: { withAnimation { pastCollapsed.toggle() } },
                onToggleExpand: { departure in
                    withAnimation(.snappy) {
                        expandedDepartureID = expandedDepartureID == departure.id ? nil : departure.id
                    }
                },
                onToggleRoute: { routeID in
                    withAnimation(.snappy) {
                        expandedRouteID = expandedRouteID == routeID ? nil : routeID
                        expandedDepartureID = nil
                    }
                },
                onAlarmToggle: { departure in
                    if viewModel.alarm(for: departure) != nil {
                        Task { await viewModel.cancelAlarm(for: departure) }
                    } else {
                        navigation.showAlarmPicker(departure)
                    }
                },
                onRetry: { Task { await viewModel.refresh() } },
                onShowAllRoutes: { viewModel.isListFiltered = false },
                onLoadMore: { Task { await viewModel.loadMoreDepartures() } }
            )
        }
        .listStyle(.plain)
        // No `.refreshable`: this presentation refreshes from the top bar's
        // button only, which is why that button stays pinned.
        //
        // The metric is `contentOffset.y + contentInsets.top`, not
        // `contentOffset.y`. The chrome below lives in a `safeAreaInset` whose
        // height shrinks as `collapseProgress` rises; that shrink shifts the
        // content offset, which would feed back into progress and oscillate.
        // The sum holds steady when the inset changes, breaking the loop.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            collapseProgress = StopSheetHeaderCollapse.progress(
                scrollOffset: offset,
                collapsibleHeight: headerHeight
            )
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            chrome(showsLoadingState: content.showsLoadingState)
        }
        .stopPageLifecycle(
            viewModel: viewModel,
            userDefaults: userDefaults,
            liveActivityStarted: viewModel.liveActivityStarted
        )
        .keepsScreenAwake()
        .defaultAppStorage(userDefaults)
        .environment(\.obaFormatters, formatters)
        .onChange(of: content.departureIDs) { _, ids in
            if let id = expandedDepartureID, !ids.contains(id) { expandedDepartureID = nil }
        }
        .onChange(of: content.routeIDs) { _, ids in
            if let rid = expandedRouteID, !ids.contains(rid) { expandedRouteID = nil }
        }
        .onReceive(viewModel.$stop.compactMap { $0 }) { stop in
            userActivity?.invalidate()
            let activity = presenter.makeUserActivity(stop: stop)
            activity?.becomeCurrent()
            userActivity = activity
        }
        .onReceive(viewModel.$stopArrivals.compactMap { $0 }) { _ in
            guard firstLoad else { return }
            firstLoad = false
            feedback.dataLoad(.success)
        }
        .onReceive(viewModel.$operationError.compactMap { $0 }) { _ in
            feedback.dataLoad(.failed)
        }
        .onReceive(viewModel.presentFullSurvey) { payload in
            presenter.showFullSurvey(
                payload.survey,
                heroResponseID: payload.heroResponseID,
                stop: viewModel.stop,
                stopID: viewModel.stopID
            )
        }
        .onReceive(viewModel.surveySubmissionError) { error in
            presenter.showError(error)
        }
        .onReceive(viewModel.$alarmError.compactMap { $0 }) { error in
            presenter.showError(error)
        }
        .onReceive(viewModel.$alarmPermissionDenied.dropFirst().filter { $0 }) { _ in
            presenter.showAlarmPermissionDeniedAlert {
                // Reset so a later already-denied attempt re-fires the binding.
                viewModel.clearAlarmPermissionDenied()
            }
        }
        .onChange(of: scenePhase) { previous, phase in
            switch phase {
            case .active:
                // Only re-arm on the .background → .active edge.
                // `.inactive → .active` (returning from Control Center or a
                // banner) never stopped the timer, so re-arming would issue a
                // redundant network call.
                if previous == .background {
                    Task { await viewModel.start() }
                }
            case .background:
                viewModel.deactivate()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onDisappear {
            userActivity?.invalidate()
            userActivity = nil
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private func chrome(showsLoadingState: Bool) -> some View {
        VStack(spacing: 0) {
            StopDetailsSheetTopBar(
                title: viewModel.stop?.name ?? "",
                titleOpacity: Double(collapseProgress),
                statusText: viewModel.statusText,
                isRefreshing: viewModel.isLoading,
                onRefresh: { Task { await viewModel.refresh() } },
                onClose: { coordinator.pop() }
            )

            collapsibleHeader(showsLoadingState: showsLoadingState)

            StopPageActionRow(
                state: StopPageActionRowState(
                    routeCount: viewModel.stop?.routes.count ?? 0,
                    hasHiddenRoutes: viewModel.stopPreferences.hasHiddenRoutes,
                    isListFiltered: viewModel.isListFiltered,
                    hasServiceAlerts: !(viewModel.stopArrivals?.serviceAlerts ?? []).isEmpty
                ),
                onSchedule: navigation.showScheduleForStop,
                onSetListFiltered: { filtered in
                    viewModel.isListFiltered = filtered
                    // Picking "Filtered Routes" opens the picker, matching the
                    // pushed presentation's `filterMenu()` — otherwise choosing
                    // it on a stop with no saved hidden routes silently does
                    // nothing.
                    if filtered { navigation.showRouteFilter() }
                },
                onBookmark: { navigation.showBookmarkEditor(nil) },
                onServiceAlerts: navigation.showServiceAlerts,
                onNearbyStops: navigation.showNearbyStops,
                onWalkingDirections: navigation.showWalkingDirections,
                onReportProblem: navigation.showReportProblem
            )
        }
    }

    /// The pushed screen's dark map card, shrinking to nothing as the list
    /// scrolls. Its natural height is measured rather than assumed: it is
    /// `@ScaledMetric` and grows further when route chips wrap, so a constant
    /// would mis-collapse at most Dynamic Type sizes.
    ///
    /// No implicit animation here — the collapse follows the finger, and
    /// animating a value already driven by a continuous gesture is what makes
    /// this pattern jitter.
    @ViewBuilder
    private func collapsibleHeader(showsLoadingState: Bool) -> some View {
        Group {
            if let stop = viewModel.stop {
                StopPageHeaderView(
                    stop: stop,
                    walkTime: viewModel.walkTime,
                    statusText: viewModel.statusText,
                    snapshotLoader: { size in
                        await presenter.loadSnapshot(stop: stop, size: size, traitCollection: UITraitCollection.current)
                    },
                    onWalkingDirections: navigation.showWalkingDirections
                )
            } else if showsLoadingState {
                StopPageHeaderPlaceholderView()
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            // Only record the natural height — once collapsing starts the
            // measured height is the scaled one, which would shrink the range
            // toward zero and snap the header shut.
            if collapseProgress == 0, newHeight > 0 {
                headerHeight = newHeight
            }
        }
        .frame(height: max(headerHeight * (1 - collapseProgress), 0), alignment: .top)
        .opacity(Double(1 - collapseProgress))
        .clipped()
        .accessibilityHidden(collapseProgress > 0.5)
    }

    // MARK: - Row plumbing

    private func makePanel(for departure: ArrivalDeparture) -> TripDetailPanelView {
        TripDetailPanelView(
            departure: departure,
            status: DepartureStatus(arrivalDeparture: departure),
            alarm: nil,
            alarmLeadTimeMinutes: 0,
            canAlarm: ActivityAuthorizationInfo().areActivitiesEnabled,
            refreshToken: viewModel.lastUpdated,
            cachedTripDetails: viewModel.cachedApproachTripDetails(for: departure),
            approachLoader: { await viewModel.approachTripDetails(for: departure) },
            onSetAlarm: { navigation.startLiveActivity(departure) },
            onCancelAlarm: {},
            onChangeAlarm: {},
            canSchedule: navigation.canScheduleForRoute,
            onSchedule: { navigation.showScheduleForRoute(departure) },
            onBookmark: { navigation.showBookmarkEditor(departure) },
            onViewFullTrip: { navigation.showTrip(departure) }
        )
    }

    private func makeActions(for departure: ArrivalDeparture) -> DepartureRowActions {
        DepartureRowActions(
            canAlarm: viewModel.canCreateAlarm(for: departure),
            canSchedule: navigation.canScheduleForRoute,
            hasAlarm: viewModel.alarm(for: departure) != nil,
            onAlarmToggle: {
                if viewModel.alarm(for: departure) != nil {
                    Task { await viewModel.cancelAlarm(for: departure) }
                } else {
                    navigation.showAlarmPicker(departure)
                }
            },
            onSchedule: { navigation.showScheduleForRoute(departure) },
            onBookmark: { navigation.showBookmarkEditor(departure) },
            onShowTrip: { navigation.showTrip(departure) },
            makePreview: { navigation.makeTripPreview(departure) }
        )
    }
}
```

`ActivityKit` must be imported for `ActivityAuthorizationInfo`; add `import ActivityKit` alongside the others.

- [ ] **Step 2: Build**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: build succeeds. If the compiler reports the body is too complex to type-check, extract the `StopDeparturesSections(...)` call into a `private var departures: some View`.

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Sheet/Content/Stop/Details/StopDetailsSheetView.swift
git commit -m "Add the SwiftUI stop details sheet"
```

---

### Task 10: Wire the sheet into the factory

**Files:**
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift`
- Modify: `OBAKit/Sheet/Root/MapPanelRootController.swift`
- Modify: `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`
- Delete: `OBAKit/Sheet/Root/StopDetailSheetHost.swift`, `OBAKitTests/Sheet/StopDetailSheetHostTests.swift`

**Interfaces:**
- Produces: `AppSheetViewFactory.init(application:onPresentTrip:presentingController:)`; `stopDetailView(stopID:) -> StopDetailsSheetView`

- [ ] **Step 1: Add the presenting-controller provider to the factory**

In `AppSheetViewFactory`:

```swift
    let application: Application
    let onPresentTrip: (ArrivalDeparture) -> Void
    /// Resolves the controller a UIKit modal should be presented from.
    ///
    /// The sheet system bridges SwiftUI `.sheet(...)` to UIKit modals on the
    /// host, so by the time a stop sheet is visible the host already has a
    /// `presentedViewController` — and UIKit silently ignores `present` on such
    /// a controller. The provider walks to the top of that chain, the same way
    /// `TripPresentationBridge` does.
    let presentingController: () -> UIViewController?

    init(
        application: Application,
        onPresentTrip: @escaping (ArrivalDeparture) -> Void,
        presentingController: @escaping () -> UIViewController? = { nil }
    ) {
        self.application = application
        self.onPresentTrip = onPresentTrip
        self.presentingController = presentingController
    }
```

Replace `stopDetailView`:

```swift
    func stopDetailView(stopID: Stop.ID) -> StopDetailsSheetView {
        StopDetailsSheetView(
            stopID: stopID,
            viewModel: StopViewModel(environment: self.application, stopID: stopID),
            presenter: StopPageActionPresenter(
                application: self.application,
                presentingController: self.presentingController
            ),
            feedback: DataLoadFeedbackGenerator(application: self.application),
            formatters: self.application.formatters,
            userDefaults: self.application.userDefaults
        )
    }
```

Update the doc comment above it to describe the SwiftUI view rather than the host.

- [ ] **Step 2: Resolve the topmost controller in `MapPanelRootController`**

Extend `TripPresentationBridge` with a resolver and reuse it in `present`:

```swift
        /// Topmost presented controller, so modals land above the sheet stack
        /// rather than underneath it — UIKit ignores `present` on a controller
        /// that already has a `presentedViewController`.
        func topmostController() -> UIViewController? {
            guard let host else { return nil }
            var presenter: UIViewController = host
            while let next = presenter.presentedViewController {
                presenter = next
            }
            return presenter
        }
```

and in `present(_:)`, replace the inline walk with `guard let presenter = topmostController() else { return }`, keeping the two `TripViewController` guards that follow it.

Then pass the resolver into the factory:

```swift
        let factory = AppSheetViewFactory(
            application: application,
            onPresentTrip: { [weak bridge] arrival in bridge?.present(arrival) },
            presentingController: { [weak bridge] in bridge?.topmostController() }
        )
```

- [ ] **Step 3: Delete the stopgap**

```bash
git rm OBAKit/Sheet/Root/StopDetailSheetHost.swift \
       OBAKitTests/Sheet/StopDetailSheetHostTests.swift
```

- [ ] **Step 4: Update the factory test**

In `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`, replace the stop-detail test. It asserts the factory-to-view handoff, the same thing the `StopDetailSheetHost` test asserted and the same shape as the `moreView` test beside it:

```swift
    @Test func `Stop detail view returns the SwiftUI sheet forwarding the stop ID`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in })
        let view = factory.stopDetailView(stopID: "1_10914")

        #expect(view.stopID == "1_10914")
    }
```

- [ ] **Step 5: Build and run the full suite**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS, with no reference to `StopDetailSheetHost` anywhere:

```bash
grep -rn "StopDetailSheetHost" OBAKit OBAKitTests --include="*.swift" || echo "clean"
```

- [ ] **Step 6: Lint**

```bash
scripts/swiftlint.sh
```

Expected: no new violations.

- [ ] **Step 7: Commit**

```bash
git add OBAKit/Sheet/DI/AppSheetViewFactory.swift \
        OBAKit/Sheet/Root/MapPanelRootController.swift \
        OBAKitTests/Sheet/AppSheetViewFactoryTests.swift
git commit -m "Route the stop details sheet to the SwiftUI view"
```

---

### Task 11: Manual verification

The collapse interaction, the map snapshot and the modal-over-sheet behaviour can't be asserted in unit tests. Verify them by hand before calling the feature done.

**Files:** none

- [ ] **Step 1: Reach the sheet**

Nothing pushes `.stopDetails` yet — that is out of scope by design. To exercise it, temporarily add a button to `HomeSheetView`'s body:

```swift
        Button("Debug: open stop") {
            coordinator.push(.stopDetails(stopID: "1_75403"))
        }
```

using a stop ID valid for the current region. **This is scaffolding — do not commit it.**

- [ ] **Step 2: Walk the checklist on device or simulator**

- [ ] Header collapses smoothly on scroll; no jitter, flicker, or oscillation
- [ ] Header re-expands on scroll back to top
- [ ] Action row stays pinned under the top bar once collapsed
- [ ] Stop name fades into the top bar as the header goes
- [ ] Refresh spins while loading and is disabled; the list updates
- [ ] Pull-to-refresh does **nothing** (it was deliberately removed)
- [ ] Close dismisses the sheet; drag-down also dismisses it
- [ ] Schedule, Bookmark, Filter and each More item present their screen **above** the sheet, not underneath
- [ ] Filter is disabled on a single-route stop; its glyph fills when a filter is applied
- [ ] Service Alerts is disabled on a stop with none
- [ ] Map snapshot renders dark and doesn't reload while scrolling
- [ ] Largest accessibility Dynamic Type size: the action row scrolls horizontally, nothing clips
- [ ] VoiceOver: Refresh announces its freshness value; Close is reachable in every state, including a stop whose first fetch fails

- [ ] **Step 3: Remove the scaffolding**

Delete the debug button and confirm the tree is clean:

```bash
git status --short
```

Expected: no modification to `HomeSheetView.swift`.

---

## Self-Review

**Spec coverage**

| Spec section | Task |
| --- | --- |
| `StopPageContent` | 1 |
| `StopDeparturesSections` | 2 |
| `stopPageLifecycle` | 3 |
| `StopPageActionPresenter` (all flows, `makeUserActivity`, `loadSnapshot`) | 4 |
| `StopPageViewController` rewiring | 4 |
| `keepsScreenAwake` + `CurrentTripView` adoption | 5 |
| `StopSheetHeaderCollapse` | 6 |
| `StopPageActionRow` + `StopPageActionRowState` | 7 |
| `StopDetailsSheetTopBar` | 8 |
| `StopDetailsSheetView`, collapsing chrome, no `.refreshable`, side effects, scene phase | 9 |
| Factory wiring, presenting-controller provider, deletions | 10 |
| Previews and manual verification | 7, 8, 11 |

Every spec section maps to a task.

**Deviations from the spec, and why**

1. The spec put `StopSheetHeaderCollapse` and `StopPageActionRow` state under `Sheet/Content/Stop/Details/`; the plan keeps that. No change.
2. The spec described `StopPageActionPresenter` as taking `Application` and a provider; the plan adds `closeSheet` as a parameter of `makeNavigationHandler` rather than of the initializer, because the pushed controller and the sheet close differently and the handler is per-view-model anyway.
3. `StopViewModel`'s initializer takes `environment:`, not `application:` — `Application` conforms to `StopViewModelEnvironment`. The spec's prose said "a `StopViewModel` for that stop" without a signature; Task 10 uses the real one.
4. `Fixtures.arrivalDeparture` needed `routeID` / `tripID` parameters for grouping and de-duplication tests. Folded into Task 1.

**Placeholder scan:** no TBD/TODO, no "add error handling", no "similar to Task N". Every code step carries real code.

**Type consistency:** `StopPageContent` properties are referenced identically in Tasks 2 and 9. `StopDeparturesSections`'s parameter list in Task 2's interface block matches its use in Tasks 2 and 9, including `onAlarmToggle`, which the prose list initially omitted and the code includes. `StopPageActionRowState`'s four initializer parameters match between Tasks 7 and 9. `StopSheetHeaderCollapse.progress(scrollOffset:collapsibleHeight:)` matches between Tasks 6 and 9. `StopPageLifecycleKeys.lastUsedStopSort` is defined in Task 3 and used in Tasks 3 and 9.

**Known risk:** Task 9's collapsing chrome is the one piece with no unit-test coverage beyond the pure progress function. If it proves unstable, the spec's named fallback applies — degrade to a two-state cross-fade at a threshold, keeping `StopSheetHeaderCollapse` as the threshold test and the action row pinned.
