# Home Sheet Section Indexes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the three index screens the home sheet's section headers already navigate to — Nearby Stops, Recent Stops, Bookmarks — as native SwiftUI sheets over the view models the existing UIKit screens already use.

**Architecture:** Each index is a stacked `.large` sheet rendered by `AppSheetViewFactory`, wearing the chrome the search sheets established (`NavigationStack` + inline title + Close button + `.searchSheetBackground()` / `.searchListChrome()`). Nearby and Recents are new SwiftUI views over `NearbyStopsViewModel` / `RecentStopsViewModel` with `HomeStopRow` rows; Bookmarks renders the existing `BookmarksListView` with a sheet-flavoured `BookmarksNavigationHandler`. Row taps push `.stopDetails` on the coordinator, which the recursive `FloatingSheetContainer` renders as a second stacked sheet. Pure grouping/filtering/resolution logic is extracted to `nonisolated` static functions so it is testable without a view.

**Tech Stack:** Swift 6 language mode, SwiftUI, Combine, MapKit/CoreLocation, ActivityKit, Swift Testing, XcodeGen.

**Spec:** [`docs/superpowers/specs/2026-08-15-home-sheet-section-indexes-design.md`](../specs/2026-08-15-home-sheet-section-indexes-design.md)

## Global Constraints

- **Target:** iOS 18.0+. Swift 6 language mode with main-actor default isolation; the five concurrency diagnostic groups are escalated to **errors**, so a data-race warning fails the build.
- **Project generation:** `scripts/generate_project OneBusAway` must be re-run after **any** file is added or deleted, before building. XcodeGen builds the target from the directory tree.
- **Build/test destination:** `platform=iOS Simulator,name=iPhone 16`. Do **not** use iPhone 17 Pro.
- **Never erase or reset the iOS Simulator.**
- **Tests:** Swift Testing (`@Suite(.serialized)` / `@Test` / `#expect`), never XCTest. Suites needing fixtures inherit `OBATestCase` and override `init() async throws`; teardown goes in `deinit`.
- **Test names** are backtick-quoted sentences: ``func `Nearby index groups stops by direction`()``.
- **Strings:** every user-visible string goes through `OBALoc(key, value:comment:)` with a `comment:` that names the screen. Reuse existing keys where the spec says so — do not mint a second key for text that already exists.
- **Commits:** single-line subject, conventional-commit prefix (`feat:`, `refactor:`, `test:`, `fix:`). **No `Co-Authored-By` line and no Claude/AI attribution of any kind.**
- **Lint:** `scripts/swiftlint.sh` must be clean before each commit.
- **File header:** every new Swift file starts with the standard OBA copyright block (copy it from a neighbouring file in the same directory).
- New index files live in `OBAKit/Sheet/Content/Home/Index/`.

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `OBAKit/Sheet/Content/Home/Index/NearbyStopsIndexSection.swift` | Pure grouping + filtering of stops into direction sections |
| `OBAKit/Sheet/Content/Home/Index/NearbyCoordinateResolver.swift` | Pure viewport → location → region coordinate fallback |
| `OBAKit/Sheet/Content/Home/Index/NearbyStopsSheetView.swift` | The Nearby index screen (chrome + content subview) |
| `OBAKit/Sheet/Content/Home/Index/RecentStopsSheetView.swift` | The Recents index screen, incl. its filter helper |
| `OBAKit/Sheet/Content/Home/Index/BookmarksSheetView.swift` | The Bookmarks index screen + its navigation handler seam |
| `OBAKit/Sheet/Content/Home/Index/BookmarkEditorHost.swift` | `UIViewControllerRepresentable` presenting `EditBookmarkViewController` |
| `OBAKit/Bookmarks/BookmarkActions.swift` | Row actions shared by the Bookmarks tab and the Bookmarks sheet |
| `OBAKitTests/Sheet/Home/NearbyStopsIndexSectionTests.swift` | Grouping/filtering tests |
| `OBAKitTests/Sheet/Home/NearbyCoordinateResolverTests.swift` | Fallback-chain tests |
| `OBAKitTests/Sheet/Home/RecentStopsSheetViewTests.swift` | Recents filter + delete tests |
| `OBAKitTests/Sheet/Home/BookmarksSheetViewTests.swift` | Navigation-handler wiring tests |
| `OBAKitTests/Bookmarks/BookmarkActionsTests.swift` | Track guard + delete analytics tests |

**Modified**

| File | Change |
|---|---|
| `OBAKit/Sheet/DI/AppSheetViewFactory.swift` | Three routes leave the placeholder branch; `nearbyStopsView` returns the new view |
| `OBAKit/Bookmarks/BookmarksViewController.swift` | Row actions delegate to `BookmarkActions` |
| `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift` | Placeholder-loop test shrinks, then dies; per-route tests replace it |

**Deleted**

| File | Reason |
|---|---|
| `OBAKit/Sheet/Content/Search/NearbyStopsSheetHost.swift` | `.nearbyStops` now renders `NearbyStopsSheetView` |

---

## Task 1: `NearbyStopsIndexSection` — direction grouping and search filtering

**Files:**
- Create: `OBAKit/Sheet/Content/Home/Index/NearbyStopsIndexSection.swift`
- Test: `OBAKitTests/Sheet/Home/NearbyStopsIndexSectionTests.swift`

**Interfaces:**
- Consumes: `Stop`, `Direction`, `Formatters.adjectiveFormOfCardinalDirection(_:)`, `Stop.matchesQuery(_:)` (all existing, in OBAKitCore).
- Produces:
  ```swift
  nonisolated struct NearbyStopsIndexSection: Identifiable {
      let direction: Direction
      let title: String
      let stops: [Stop]
      var id: Int { direction.rawValue }
      static func sections(stops: [Stop], filter: String?) -> [NearbyStopsIndexSection]
  }
  ```

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Sheet/Home/NearbyStopsIndexSectionTests.swift`:

```swift
//
//  NearbyStopsIndexSectionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class NearbyStopsIndexSectionTests: OBATestCase {

    /// Every stop lands in exactly one section, and that section's direction is
    /// the stop's own. Asserted structurally rather than against hard-coded
    /// directions so the test survives a fixture refresh.
    @Test func `Sections group every stop under its own direction`() throws {
        let stops = try Fixtures.loadSomeStops()

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: nil)

        #expect(sections.reduce(0) { $0 + $1.stops.count } == stops.count)
        for section in sections {
            #expect(section.stops.allSatisfy { $0.direction == section.direction })
        }
    }

    /// Sections are ordered by `Direction`'s own ordering (n, ne, e, … unknown),
    /// so the list doesn't reshuffle between loads.
    @Test func `Sections are ordered by direction`() throws {
        let stops = try Fixtures.loadSomeStops()

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: nil)

        #expect(sections.map(\.direction) == sections.map(\.direction).sorted())
    }

    /// No empty sections: a direction whose stops are all filtered out is
    /// dropped rather than rendered as a bare header.
    @Test func `Sections are never empty`() throws {
        let stops = try Fixtures.loadSomeStops()

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: nil)

        #expect(!sections.isEmpty)
        #expect(sections.allSatisfy { !$0.stops.isEmpty })
    }

    /// A blank or whitespace-only filter is treated as no filter at all —
    /// `.searchable` hands us "" the moment the field is focused.
    @Test func `Blank filter matches everything`() throws {
        let stops = try Fixtures.loadSomeStops()

        let unfiltered = NearbyStopsIndexSection.sections(stops: stops, filter: nil)
        let blank = NearbyStopsIndexSection.sections(stops: stops, filter: "   ")

        #expect(blank.map(\.id) == unfiltered.map(\.id))
        #expect(blank.reduce(0) { $0 + $1.stops.count } == stops.count)
    }

    /// A filter naming one stop narrows the result to stops that match it.
    @Test func `Filter narrows results to matching stops`() throws {
        let stops = try Fixtures.loadSomeStops()
        let target = try #require(stops.first)

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: target.name)
        let matched = sections.flatMap(\.stops)

        #expect(matched.contains { $0.id == target.id })
        #expect(matched.allSatisfy { $0.matchesQuery(target.name) })
        #expect(matched.count < stops.count)
    }

    /// A filter that matches nothing yields no sections, which is what drives
    /// the view's "no results" empty state.
    @Test func `Filter matching nothing yields no sections`() throws {
        let stops = try Fixtures.loadSomeStops()

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: "zzzzz-no-such-stop")

        #expect(sections.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile FAILS with `cannot find 'NearbyStopsIndexSection' in scope`.

- [ ] **Step 3: Write the implementation**

Create `OBAKit/Sheet/Content/Home/Index/NearbyStopsIndexSection.swift`:

```swift
//
//  NearbyStopsIndexSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// One direction's worth of stops on the Nearby Stops index.
///
/// A plain value with a pure builder, so the grouping and search rules can be
/// asserted without standing up a view — the same reasoning behind
/// `RouteStopsRow.rows(from:)`.
nonisolated struct NearbyStopsIndexSection: Identifiable {
    let direction: Direction
    let title: String
    let stops: [Stop]

    /// `Direction` is unique per section, so its raw value is a stable id.
    var id: Int { direction.rawValue }

    /// Groups `stops` by direction, dropping anything that doesn't match
    /// `filter`. Sections come back in `Direction` order and are never empty.
    ///
    /// A nil, blank, or whitespace-only `filter` matches everything:
    /// `.searchable` hands the view an empty string the moment the field is
    /// focused, which must not blank the list.
    static func sections(stops: [Stop], filter: String?) -> [NearbyStopsIndexSection] {
        let query = String.nilifyBlankValue(
            filter?.localizedLowercase.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? nil

        var grouped: [Direction: [Stop]] = [:]
        for stop in stops where stop.matchesQuery(query) {
            grouped[stop.direction, default: []].append(stop)
        }

        return grouped.keys.sorted().map { direction in
            NearbyStopsIndexSection(
                direction: direction,
                title: Formatters.adjectiveFormOfCardinalDirection(direction) ?? "",
                stops: grouped[direction] ?? []
            )
        }
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/NearbyStopsIndexSectionTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 6 tests PASS.

- [ ] **Step 5: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Sheet/Content/Home/Index/NearbyStopsIndexSection.swift OBAKitTests/Sheet/Home/NearbyStopsIndexSectionTests.swift
git commit -m "feat: add direction grouping and filtering for the nearby stops index"
```

---

## Task 2: `NearbyCoordinateResolver` — the viewport → location → region fallback

**Files:**
- Create: `OBAKit/Sheet/Content/Home/Index/NearbyCoordinateResolver.swift`
- Test: `OBAKitTests/Sheet/Home/NearbyCoordinateResolverTests.swift`

**Interfaces:**
- Consumes: `CLLocationCoordinate2D`, `CLLocation`, `Region.centerCoordinate` (existing, `OBAKitCore/Models/Region.swift:527`).
- Produces:
  ```swift
  nonisolated enum NearbyCoordinateResolver {
      static func coordinate(
          viewportCenter: CLLocationCoordinate2D?,
          currentLocation: CLLocation?,
          region: Region?
      ) -> CLLocationCoordinate2D?
  }
  ```

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Sheet/Home/NearbyCoordinateResolverTests.swift`:

```swift
//
//  NearbyCoordinateResolverTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class NearbyCoordinateResolverTests: OBATestCase {

    private let viewport = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
    private let device = CLLocation(latitude: 40.7, longitude: -74.0)

    /// The map's viewport wins: the user asked for "nearby" from a sheet over
    /// the map they're looking at, not from wherever the device happens to be.
    @Test func `Viewport center wins when present`() {
        let resolved = NearbyCoordinateResolver.coordinate(
            viewportCenter: viewport,
            currentLocation: device,
            region: Fixtures.pugetSoundRegion
        )

        #expect(resolved?.latitude == viewport.latitude)
        #expect(resolved?.longitude == viewport.longitude)
    }

    /// Before the map's first settle there is no viewport center, so the
    /// device's own location is the next best anchor.
    @Test func `Device location is used when there is no viewport center`() {
        let resolved = NearbyCoordinateResolver.coordinate(
            viewportCenter: nil,
            currentLocation: device,
            region: Fixtures.pugetSoundRegion
        )

        #expect(resolved?.latitude == device.coordinate.latitude)
        #expect(resolved?.longitude == device.coordinate.longitude)
    }

    /// Location permission denied and no settle yet: the region's center is
    /// still somewhere the user has transit data for.
    @Test func `Region center is the last resort`() {
        let region = Fixtures.pugetSoundRegion

        let resolved = NearbyCoordinateResolver.coordinate(
            viewportCenter: nil,
            currentLocation: nil,
            region: region
        )

        #expect(resolved?.latitude == region.centerCoordinate.latitude)
        #expect(resolved?.longitude == region.centerCoordinate.longitude)
    }

    /// Nothing to anchor on. Returning nil is what makes the view render its
    /// empty state instead of fetching stops around (0, 0) in the Gulf of Guinea.
    @Test func `Nil is returned when nothing can anchor the search`() {
        let resolved = NearbyCoordinateResolver.coordinate(
            viewportCenter: nil,
            currentLocation: nil,
            region: nil
        )

        #expect(resolved == nil)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile FAILS with `cannot find 'NearbyCoordinateResolver' in scope`.

- [ ] **Step 3: Write the implementation**

Create `OBAKit/Sheet/Content/Home/Index/NearbyCoordinateResolver.swift`:

```swift
//
//  NearbyCoordinateResolver.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import OBAKitCore

/// Picks the coordinate the Nearby Stops index searches around.
///
/// `AppSheetRoute.nearbyAll` carries no payload — it's pushed from a section
/// header, not from a tapped place — so the anchor has to be resolved at build
/// time. Kept as a pure function rather than inlined into the factory so the
/// fallback chain is assertable without an `Application`.
nonisolated enum NearbyCoordinateResolver {

    /// Preference order: the map's last settled center, then the device's
    /// location, then the current region's center. Nil when none is available,
    /// which the view renders as an empty state rather than searching (0, 0).
    static func coordinate(
        viewportCenter: CLLocationCoordinate2D?,
        currentLocation: CLLocation?,
        region: Region?
    ) -> CLLocationCoordinate2D? {
        viewportCenter
            ?? currentLocation?.coordinate
            ?? region?.centerCoordinate
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/NearbyCoordinateResolverTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 4 tests PASS.

- [ ] **Step 5: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Sheet/Content/Home/Index/NearbyCoordinateResolver.swift OBAKitTests/Sheet/Home/NearbyCoordinateResolverTests.swift
git commit -m "feat: add coordinate resolution for the nearby stops index"
```

---

## Task 3: `NearbyStopsSheetView` and the `.nearbyAll` route

**Files:**
- Create: `OBAKit/Sheet/Content/Home/Index/NearbyStopsSheetView.swift`
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift:79` (dispatch), `:184` (placeholder doc comment)
- Modify: `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift:143-155`

**Interfaces:**
- Consumes: `NearbyStopsIndexSection.sections(stops:filter:)` (Task 1), `NearbyCoordinateResolver.coordinate(viewportCenter:currentLocation:region:)` (Task 2), `NearbyStopsViewModel(coordinate:application:)`, `HomeStopRow(stop:onSelect:)`, `EmptyStateView(title:description:systemImage:)`, `SheetCoordinator<AppSheetRoute>`.
- Produces:
  ```swift
  struct NearbyStopsSheetView: View {
      let coordinate: CLLocationCoordinate2D?
      let application: Application
      init(application: Application, coordinate: CLLocationCoordinate2D?)
  }

  // on AppSheetViewFactory:
  func nearbyAllView() -> NearbyStopsSheetView
  ```

- [ ] **Step 1: Write the failing factory test**

In `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`, **replace** the existing `Index routes dispatch to a placeholder without asserting` test (lines ~139-155) with the narrowed loop plus a new Nearby test:

```swift
    /// The two index routes whose screens don't exist yet must still reach the
    /// placeholder rather than `unimplementedView`, whose DEBUG
    /// `assertionFailure` guards genuinely unwired routes.
    ///
    /// Goes through `view(for:)` rather than calling `indexPlaceholderView`
    /// directly: the dispatch is the thing under test. `view(for:)` is
    /// `@ViewBuilder`, so its switch — and any `assertionFailure` on the branch
    /// it picks — runs at call time. Completing this loop without trapping is
    /// the assertion.
    @Test @MainActor
    func `Remaining index routes dispatch to a placeholder without asserting`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let factory = makeFactory(application: application)

        for route in [AppSheetRoute.recentStopsAll, .bookmarksAll] {
            _ = factory.view(for: route)
        }
    }

    /// `.nearbyAll` carries no coordinate, so the factory resolves one. With a
    /// current region present there is always an anchor, so the view must not
    /// be handed nil.
    @Test @MainActor
    func `Nearby all view resolves a coordinate`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).nearbyAllView()

        #expect(view.coordinate != nil)
    }
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile FAILS with `value of type 'AppSheetViewFactory' has no member 'nearbyAllView'`.

- [ ] **Step 3: Write the view**

Create `OBAKit/Sheet/Content/Home/Index/NearbyStopsSheetView.swift`:

```swift
//
//  NearbyStopsSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import OBAKitCore

/// The Nearby Stops index — `AppSheetRoute.nearbyAll` and
/// `AppSheetRoute.nearbyStops(coordinate:)`. Native replacement for
/// `NearbyStopsViewController`.
///
/// Split in two: this view owns the chrome and the "no anchor at all" case,
/// while `NearbyStopsSheetContent` owns the view model. A `@StateObject` can't
/// be created conditionally, and there is no honest coordinate to build one
/// with when the map hasn't settled, the device has no fix, and there is no
/// current region.
struct NearbyStopsSheetView: View {
    /// Nil when nothing could anchor the search. Stored (rather than resolved
    /// internally) so the factory's fallback chain is visible to tests.
    let coordinate: CLLocationCoordinate2D?
    let application: Application

    @Environment(\.dismiss) private var dismiss

    init(application: Application, coordinate: CLLocationCoordinate2D?) {
        self.application = application
        self.coordinate = coordinate
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(Strings.nearbyStops))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { dismiss() }
                    }
                }
        }
        .searchSheetBackground()
    }

    @ViewBuilder
    private var content: some View {
        if let coordinate {
            NearbyStopsSheetContent(
                viewModel: NearbyStopsViewModel(coordinate: coordinate, application: application)
            )
        } else {
            EmptyStateView(
                title: OBALoc(
                    "nearby_stops_sheet.no_location.title",
                    value: "Location Unavailable",
                    comment: "Title shown on the Nearby Stops index sheet when no map viewport, device location, or region is available to search around."
                ),
                description: OBALoc(
                    "nearby_stops_sheet.no_location.body",
                    value: "Move the map or turn on location services to see stops near you.",
                    comment: "Body shown on the Nearby Stops index sheet when no map viewport, device location, or region is available to search around."
                ),
                systemImage: AppSymbol.locationUnavailable
            )
        }
    }
}

/// The list itself. Owns `NearbyStopsViewModel` so the parent can decline to
/// build one when there's no coordinate.
private struct NearbyStopsSheetContent: View {
    @StateObject private var viewModel: NearbyStopsViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @State private var searchText = ""

    init(viewModel: @autoclosure @escaping () -> NearbyStopsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    private var sections: [NearbyStopsIndexSection] {
        NearbyStopsIndexSection.sections(stops: viewModel.stops, filter: searchText)
    }

    var body: some View {
        list
            .searchable(text: $searchText)
            .task { await viewModel.loadStops() }
    }

    @ViewBuilder
    private var list: some View {
        if let error = viewModel.operationError {
            // Inline rather than `application.displayError`: an app-level alert
            // over a stacked sheet is the wrong affordance, and this view holds
            // no `Application` to raise one with.
            EmptyStateView(
                title: Strings.error,
                description: error.localizedDescription,
                systemImage: AppSymbol.error
            ) {
                Button(Strings.retry) {
                    Task { await viewModel.loadStops() }
                }
            }
        } else if viewModel.isLoading && viewModel.stops.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sections.isEmpty {
            EmptyStateView(
                title: OBALoc(
                    "nearby_stops_sheet.empty.title",
                    value: "No Nearby Stops",
                    comment: "Title shown on the Nearby Stops index sheet when no stops match."
                ),
                description: OBALoc(
                    "nearby_stops_sheet.empty.body",
                    value: "There are no other stops in the vicinity.",
                    comment: "Body shown on the Nearby Stops index sheet when no stops match."
                ),
                systemImage: AppSymbol.search
            )
        } else {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.stops, id: \.id) { stop in
                            HomeStopRow(stop: stop) {
                                coordinator.push(.stopDetails(stopID: stop.id))
                            }
                        }
                    } header: {
                        Text(section.title)
                            .font(.headline)
                    }
                    .textCase(nil)
                }
            }
            .searchListChrome()
        }
    }
}
```

`Strings.error` and `Strings.retry` already exist (`OBAKitCore/Strings/Strings.swift:49` and `:89`) — use them, don't mint new keys.

- [ ] **Step 4: Wire the route in the factory**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`, change the dispatch branch:

```swift
        case .nearbyAll:
            nearbyAllView()

        case .recentStopsAll, .bookmarksAll:
            indexPlaceholderView(for: route)
```

and add the builder next to `nearbyStopsView`:

```swift
    /// `AppSheetRoute.nearbyAll` — the home sheet's "Nearby Stops" header. The
    /// route carries no coordinate (it's pushed from a section header, not a
    /// tapped place), so the anchor is resolved here from what the app knows.
    func nearbyAllView() -> NearbyStopsSheetView {
        NearbyStopsSheetView(
            application: application,
            coordinate: NearbyCoordinateResolver.coordinate(
                viewportCenter: stopsObserver.viewportCenter,
                currentLocation: application.locationService.currentLocation,
                region: application.currentRegion
            )
        )
    }
```

Update the `indexPlaceholderView` doc comment, which currently says "The home sheet's section headers navigate to these three routes":

```swift
    /// The remaining index routes navigate here before their screens exist, so
    /// they render the "coming soon" placeholder in every configuration rather
    /// than asserting. `unimplementedView` stays armed for routes nobody has
    /// wired a push for yet — remove a route from here once its real view is
    /// registered above.
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/AppSheetViewFactoryTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all factory tests PASS, including `Nearby all view resolves a coordinate`.

- [ ] **Step 6: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Sheet/Content/Home/Index/NearbyStopsSheetView.swift OBAKit/Sheet/DI/AppSheetViewFactory.swift OBAKitTests/Sheet/AppSheetViewFactoryTests.swift
git commit -m "feat: add the nearby stops index sheet"
```

---

## Task 4: Point `.nearbyStops(coordinate:)` at the new view and delete the UIKit host

**Files:**
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift:154-158`
- Delete: `OBAKit/Sheet/Content/Search/NearbyStopsSheetHost.swift`
- Modify: `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`

**Interfaces:**
- Consumes: `NearbyStopsSheetView(application:coordinate:)` (Task 3).
- Produces: `AppSheetViewFactory.nearbyStopsView(coordinate:) -> NearbyStopsSheetView` (return type changes from `NearbyStopsSheetHost`).

- [ ] **Step 1: Write the failing test**

Add to `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`:

```swift
    /// `.nearbyStops` and `.nearbyAll` are the same screen; only the way the
    /// coordinate is obtained differs. This one carries its anchor in the route,
    /// so it must be passed through untouched.
    @Test @MainActor
    func `Nearby stops view forwards the route coordinate`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)

        let view = makeFactory(application: application).nearbyStopsView(coordinate: coordinate)

        #expect(view.coordinate?.latitude == coordinate.latitude)
        #expect(view.coordinate?.longitude == coordinate.longitude)
    }
```

Add `import CoreLocation` to the test file's imports if it isn't already there.

If an existing test in this file asserts `nearbyStopsView` returns a `NearbyStopsSheetHost`, delete it — the host is going away.

- [ ] **Step 2: Run the tests and verify they fail**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile FAILS — `NearbyStopsSheetHost` has no member `coordinate` of optional type (the host's `coordinate` is non-optional).

- [ ] **Step 3: Repoint the factory and delete the host**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`, replace the `nearbyStopsView` builder:

```swift
    /// `AppSheetRoute.nearbyStops` — stops around a coordinate the user picked
    /// (a dropped pin, a map-item result). Same screen as `.nearbyAll`; only the
    /// source of the coordinate differs.
    func nearbyStopsView(coordinate: CLLocationCoordinate2D) -> NearbyStopsSheetView {
        NearbyStopsSheetView(application: application, coordinate: coordinate)
    }
```

Then:

```bash
git rm OBAKit/Sheet/Content/Search/NearbyStopsSheetHost.swift
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/AppSheetViewFactoryTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all factory tests PASS. If the build reports an unresolved reference to `NearbyStopsSheetHost` anywhere else, run `grep -rn "NearbyStopsSheetHost" OBAKit OBAKitTests` and remove the stragglers.

- [ ] **Step 5: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Sheet/DI/AppSheetViewFactory.swift OBAKitTests/Sheet/AppSheetViewFactoryTests.swift
git commit -m "refactor: render the nearby stops route with the native index sheet"
```

---

## Task 5: `RecentStopsSheetView` and the `.recentStopsAll` route

**Files:**
- Create: `OBAKit/Sheet/Content/Home/Index/RecentStopsSheetView.swift`
- Create: `OBAKitTests/Sheet/Home/RecentStopsSheetViewTests.swift`
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift`
- Modify: `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`

**Interfaces:**
- Consumes: `RecentStopsViewModel(application:)` with `recentStops`, `loadData()`, `delete(recentStop:)`, `deleteAllRecentStops()`; `HomeStopRow`; `UserDataStore.addRecentStop(_:region:)` / `recentStops(in:)`.
- Produces:
  ```swift
  struct RecentStopsSheetView: View {
      let application: Application
      init(application: Application)
      static func filter(stops: [Stop], query: String?) -> [Stop]
  }

  // on AppSheetViewFactory:
  func recentStopsAllView() -> RecentStopsSheetView
  ```

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Sheet/Home/RecentStopsSheetViewTests.swift`:

```swift
//
//  RecentStopsSheetViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class RecentStopsSheetViewTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Seeds recents the way production does, with the region identifier that
    /// `RESTAPIResponse.loadReferences` would otherwise have assigned.
    @MainActor
    private func seedRecents(count: Int, application: Application) throws -> [Stop] {
        let stops = try Fixtures.loadSomeStops()
        let seeded = Array(stops.prefix(count))
        for stop in seeded {
            stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
            application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        }
        return seeded
    }

    // MARK: - Filtering

    /// A blank query is what `.searchable` supplies the moment the field is
    /// focused; it must not blank the list.
    @Test func `Blank query returns every recent stop`() throws {
        let stops = try Fixtures.loadSomeStops()

        #expect(RecentStopsSheetView.filter(stops: stops, query: nil).count == stops.count)
        #expect(RecentStopsSheetView.filter(stops: stops, query: "   ").count == stops.count)
    }

    /// Filtering preserves the store's most-recently-used ordering rather than
    /// re-sorting by relevance.
    @Test func `Filtering narrows results and preserves order`() throws {
        let stops = try Fixtures.loadSomeStops()
        let target = try #require(stops.first)

        let filtered = RecentStopsSheetView.filter(stops: stops, query: target.name)

        #expect(filtered.contains { $0.id == target.id })
        #expect(filtered.count < stops.count)
        let expectedOrder = stops.filter { stop in filtered.contains { $0.id == stop.id } }
        #expect(filtered.map(\.id) == expectedOrder.map(\.id))
    }

    /// No match yields nothing, which is what drives the view's empty state.
    @Test func `Query matching nothing returns no stops`() throws {
        let stops = try Fixtures.loadSomeStops()

        #expect(RecentStopsSheetView.filter(stops: stops, query: "zzzzz-no-such-stop").isEmpty)
    }

    // MARK: - Deletion

    /// Swipe-to-delete removes exactly the swiped stop and leaves the rest.
    @Test @MainActor func `Deleting one recent stop leaves the others`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let seeded = try seedRecents(count: 3, application: application)

        let viewModel = RecentStopsViewModel(application: application)
        viewModel.loadData()
        try #require(viewModel.recentStops.count == 3)

        let doomed = try #require(seeded.first)
        viewModel.delete(recentStop: doomed)

        #expect(viewModel.recentStops.count == 2)
        #expect(!viewModel.recentStops.contains { $0.id == doomed.id })
    }

    /// Delete All empties both the view model and the store behind it.
    @Test @MainActor func `Deleting all recent stops empties the list`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        _ = try seedRecents(count: 3, application: application)

        let viewModel = RecentStopsViewModel(application: application)
        viewModel.loadData()
        try #require(!viewModel.recentStops.isEmpty)

        viewModel.deleteAllRecentStops()

        #expect(viewModel.recentStops.isEmpty)
        #expect(application.userDataStore.recentStops(in: application.currentRegion).isEmpty)
    }
}
```

Also add the factory test to `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`, and drop `.recentStopsAll` from the placeholder loop so it reads `for route in [AppSheetRoute.bookmarksAll]`:

```swift
    /// `.recentStopsAll` renders the native index, not the placeholder.
    @Test @MainActor
    func `Recent stops all view forwards the application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).recentStopsAllView()

        #expect(view.application === application)
    }
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile FAILS with `cannot find 'RecentStopsSheetView' in scope`.

- [ ] **Step 3: Write the view**

Create `OBAKit/Sheet/Content/Home/Index/RecentStopsSheetView.swift`:

```swift
//
//  RecentStopsSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The Recent Stops index — `AppSheetRoute.recentStopsAll`. A native list over
/// the same `RecentStopsViewModel` the Recent tab uses.
///
/// The tab's Alarms section is deliberately absent: the home sheet's header
/// promises recent *stops*, and alarm deep-links have no place in the sheet
/// stack. The tab's "Find Stops on Maps" empty-state button is dropped too —
/// the map is already right behind this sheet.
struct RecentStopsSheetView: View {
    let application: Application

    @StateObject private var viewModel: RecentStopsViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isConfirmingDeleteAll = false

    init(application: Application) {
        self.application = application
        _viewModel = StateObject(wrappedValue: RecentStopsViewModel(application: application))
    }

    /// Applies the search field's query, preserving the store's
    /// most-recently-used ordering. A nil, blank, or whitespace-only query
    /// matches everything — `.searchable` hands the view "" on focus.
    ///
    /// Static and pure so the rule is assertable without a view.
    static func filter(stops: [Stop], query: String?) -> [Stop] {
        let normalized = String.nilifyBlankValue(
            query?.localizedLowercase.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? nil
        return stops.filter { $0.matchesQuery(normalized) }
    }

    private var stops: [Stop] {
        Self.filter(stops: viewModel.recentStops, query: searchText)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(Strings.recentStops))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(OBALoc(
                            "recent_stops.delete_all",
                            value: "Delete All",
                            comment: "A button that deletes all of the recent stops in the app."
                        ), role: .destructive) {
                            isConfirmingDeleteAll = true
                        }
                        .disabled(viewModel.recentStops.isEmpty)
                    }
                }
                .confirmationDialog(
                    OBALoc(
                        "recent_stops.confirmation_alert.title",
                        value: "Are you sure you want to delete all of your recent stops?",
                        comment: "Title for a confirmation alert displayed before the user deletes all of their recent stops."
                    ),
                    isPresented: $isConfirmingDeleteAll,
                    titleVisibility: .visible
                ) {
                    Button(Strings.delete, role: .destructive) {
                        viewModel.deleteAllRecentStops()
                    }
                    Button(Strings.cancel, role: .cancel) { }
                }
        }
        .searchSheetBackground()
        .task { viewModel.loadData() }
    }

    @ViewBuilder
    private var content: some View {
        if stops.isEmpty {
            EmptyStateView(
                title: OBALoc(
                    "recent_stops.empty_set.title",
                    value: "No Recent Stops",
                    comment: "Title for the empty set indicator on the Recent Stops controller."
                ),
                description: OBALoc(
                    "recent_stops.empty_set.body",
                    value: "Transit stops that you view in the app will appear here.",
                    comment: "Body for the empty set indicator on the Recent Stops controller."
                ),
                systemImage: AppSymbol.search
            )
        } else {
            List {
                ForEach(stops, id: \.id) { stop in
                    HomeStopRow(stop: stop) {
                        coordinator.push(.stopDetails(stopID: stop.id))
                    }
                    .swipeActions(edge: .trailing) {
                        Button(Strings.delete, role: .destructive) {
                            viewModel.delete(recentStop: stop)
                        }
                    }
                }
            }
            .searchListChrome()
        }
    }
}
```

- [ ] **Step 4: Wire the route in the factory**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`:

```swift
        case .recentStopsAll:
            recentStopsAllView()

        case .bookmarksAll:
            indexPlaceholderView(for: route)
```

and add the builder:

```swift
    /// `AppSheetRoute.recentStopsAll` — the home sheet's "Recent Stops" header.
    func recentStopsAllView() -> RecentStopsSheetView {
        RecentStopsSheetView(application: application)
    }
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/RecentStopsSheetViewTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/AppSheetViewFactoryTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 5 recents tests PASS; all factory tests PASS.

- [ ] **Step 6: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Sheet/Content/Home/Index/RecentStopsSheetView.swift OBAKitTests/Sheet/Home/RecentStopsSheetViewTests.swift OBAKit/Sheet/DI/AppSheetViewFactory.swift OBAKitTests/Sheet/AppSheetViewFactoryTests.swift
git commit -m "feat: add the recent stops index sheet"
```

---

## Task 6: Extract `BookmarkActions` from `BookmarksViewController`

This task must be **behaviour-preserving** for the Bookmarks tab. Nothing about the tab changes except where the code lives.

**Files:**
- Create: `OBAKit/Bookmarks/BookmarkActions.swift`
- Create: `OBAKitTests/Bookmarks/BookmarkActionsTests.swift`
- Modify: `OBAKit/Bookmarks/BookmarksViewController.swift` (remove lines ~180-199, ~207-211, ~213-288, ~366-392; rewire the handler closures)

**Interfaces:**
- Consumes: `Application` (`analytics`, `viewRouter`, `liveActivityTracker`), `TripAttributes`, `Activity<TripAttributes>.running(matching:)`, `TripLiveActivityRelevance.prominenceScore()/.content(state:staleDate:relevanceScore:)`, `Activity<TripAttributes>.demoteLivePeers(exceptActivityID:relativeTo:)`, `ProgressHUD.showSuccessAndDismiss(message:)`, `AnalyticsLabels.removeBookmark` / `.addRemoveBookmarkValue(routeID:headsign:stopID:)`, `EditBookmarkViewController(application:stop:bookmark:delegate:)`.
- Produces:
  ```swift
  @MainActor final class BookmarkActions {
      enum TrackResult: Equatable { case started, promotedExisting, failed }

      init(application: Application)

      static func liveActivityKeys(for bookmark: Bookmark) -> (routeShortName: String, routeHeadsign: String)
      static func buildContentState(from arrivalDepartures: [ArrivalDeparture]) -> TripAttributes.ContentState?

      func reportDeletion(of bookmark: Bookmark)
      @discardableResult
      func startLiveActivity(for bookmark: Bookmark, arrivalDepartures: [ArrivalDeparture]) -> TrackResult
      func makeBookmarkEditor(for bookmark: Bookmark, delegate: BookmarkEditorDelegate) -> UINavigationController
  }
  ```

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Bookmarks/BookmarkActionsTests.swift`:

```swift
//
//  BookmarkActionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class BookmarkActionsTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private static let seedEpoch = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func makeTripBookmark(application: Application) throws -> Bookmark {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(
            name: "Trip Bookmark",
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            arrivalDeparture: arrivalDeparture,
            dateCreated: Self.seedEpoch
        )
        application.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    @MainActor
    private func makeStopBookmark(application: Application) throws -> Bookmark {
        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        let bookmark = Bookmark(
            name: "Stop Bookmark",
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: stop,
            dateCreated: Self.seedEpoch
        )
        application.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    /// Deleting a trip bookmark reports the unstar event, with the route and
    /// stop the user actually removed.
    @Test @MainActor func `Reporting a deletion emits the unstar event`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let analytics = try #require(application.analytics as? AnalyticsMock)
        let bookmark = try makeTripBookmark(application: application)

        BookmarkActions(application: application).reportDeletion(of: bookmark)

        let event = try #require(analytics.reportedEvents.last)
        #expect(event.label == AnalyticsLabels.removeBookmark)
    }

    /// A stop bookmark has no route or headsign, so there is no unstar event to
    /// report — matching the tab, which guards on both being present.
    @Test @MainActor func `Reporting a stop bookmark deletion emits nothing`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let analytics = try #require(application.analytics as? AnalyticsMock)
        let bookmark = try makeStopBookmark(application: application)
        let before = analytics.reportedEvents.count

        BookmarkActions(application: application).reportDeletion(of: bookmark)

        #expect(analytics.reportedEvents.count == before)
    }

    /// The identity keys fall back to the bookmark's own name and an empty
    /// headsign, so a bookmark missing route metadata still compares equal to
    /// the activity started from it.
    @Test @MainActor func `Live activity keys fall back to the bookmark name`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try makeStopBookmark(application: application)

        let keys = BookmarkActions.liveActivityKeys(for: bookmark)

        #expect(keys.routeShortName == bookmark.routeShortName ?? bookmark.name)
        #expect(keys.routeHeadsign == (bookmark.tripHeadsign ?? ""))
    }

    /// No arrivals means no content state, which is what makes `startLiveActivity`
    /// report failure instead of requesting an empty activity.
    @Test @MainActor func `Content state is nil without arrivals`() {
        #expect(BookmarkActions.buildContentState(from: []) == nil)
    }

    /// With arrivals, at most the first three are carried into the activity.
    @Test @MainActor func `Content state carries at most three arrivals`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        try #require(stopArrivals.arrivalsAndDepartures.count >= 3)

        let state = try #require(BookmarkActions.buildContentState(from: stopArrivals.arrivalsAndDepartures))

        #expect(state.arrivals.count == 3)
    }

    /// Tracking a bookmark with no loaded arrivals can't build a content state,
    /// so it reports failure rather than requesting a contentless activity.
    @Test @MainActor func `Tracking without arrivals fails`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try makeTripBookmark(application: application)

        let result = BookmarkActions(application: application)
            .startLiveActivity(for: bookmark, arrivalDepartures: [])

        #expect(result == .failed)
    }
}
```

`Activity.request` needs a real device and entitlement, so the `.started` and `.promotedExisting` paths are verified manually in Step 6, not here. The pure parts above are what the extraction can actually regress.

- [ ] **Step 2: Run the tests and verify they fail**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile FAILS with `cannot find 'BookmarkActions' in scope`.

- [ ] **Step 3: Create `BookmarkActions`**

Create `OBAKit/Bookmarks/BookmarkActions.swift`. Move the bodies verbatim from `BookmarksViewController` — `liveActivityKeys(for:)` (:207-211), `deleteBookmark`'s analytics half (:186-199), `startLiveActivity` (:213-280), `showLiveActivityStartedToast` (:285-288), `buildContentState` (:366-379), `trackLiveActivity` (:387-392), and the editor construction from `editBookmark` (:180-184). Keep every existing comment.

```swift
//
//  BookmarkActions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import ActivityKit
import OBAKitCore

/// Bookmark row actions shared by the Bookmarks tab (`BookmarksViewController`)
/// and the Bookmarks index sheet (`BookmarksSheetView`).
///
/// Holds no view model and presents nothing: arrivals are passed in, deletion is
/// performed by the caller's view model, and the bookmark editor is *built* here
/// but presented by whoever asked for it. That's what lets a `UIViewController`
/// and a SwiftUI view share one implementation — the tab presents via
/// `viewRouter`, the sheet via `.sheet(item:)`.
@MainActor
final class BookmarkActions {

    /// What `startLiveActivity` did. Failure is returned rather than alerted:
    /// `showLiveActivityErrorAlert()` is a `UIViewController` extension, so the
    /// tab raises a `UIAlertController` while the sheet raises a SwiftUI `.alert`.
    enum TrackResult: Equatable {
        case started
        case promotedExisting
        case failed
    }

    private let application: Application

    init(application: Application) {
        self.application = application
    }

    // MARK: - Deletion

    /// Reports the remove-bookmark analytics event. The caller still performs
    /// the delete on its own view model.
    func reportDeletion(of bookmark: Bookmark) {
        guard let routeID = bookmark.routeID, let headsign = bookmark.tripHeadsign else { return }

        application.analytics?.reportEvent(
            pageURL: "app://localhost/bookmarks",
            label: AnalyticsLabels.removeBookmark,
            value: AnalyticsLabels.addRemoveBookmarkValue(
                routeID: routeID,
                headsign: headsign,
                stopID: bookmark.stopID))
    }

    // MARK: - Bookmark Editor

    /// Builds the bookmark editor inside a navigation controller. Presentation
    /// is the caller's job.
    func makeBookmarkEditor(for bookmark: Bookmark, delegate: BookmarkEditorDelegate) -> UINavigationController {
        let editor = EditBookmarkViewController(
            application: application,
            stop: bookmark.stop,
            bookmark: bookmark,
            delegate: delegate
        )
        return UINavigationController(rootViewController: editor)
    }

    // MARK: - Live Activities

    /// The route name/headsign pair stored in a Live Activity's `StaticData`.
    /// Creation and reconciliation must apply the same fallbacks — comparing
    /// raw optionals against these stored values would never match a bookmark
    /// whose route name or headsign is missing.
    static func liveActivityKeys(for bookmark: Bookmark) -> (routeShortName: String, routeHeadsign: String) {
        // Use structured properties directly from the Bookmark model instead of parsing
        // the display name, which would break on hyphenated route names like "A-Line".
        (bookmark.routeShortName ?? bookmark.name, bookmark.tripHeadsign ?? "")
    }

    static func buildContentState(from arrivalDepartures: [ArrivalDeparture]) -> TripAttributes.ContentState? {
        guard !arrivalDepartures.isEmpty else {
            return nil
        }
        let arrivals = arrivalDepartures.prefix(3).map { arrDep in
            TripAttributes.ContentState.ArrivalInfo(
                departureTime: Int(arrDep.arrivalDepartureDate.timeIntervalSince1970),
                scheduleStatus: .init(arrDep.scheduleStatus),
                scheduleDeviation: arrDep.deviationFromScheduleInMinutes * 60,
                isArrival: arrDep.arrivalDepartureStatus == .arriving
            )
        }
        return TripAttributes.ContentState(arrivals: Array(arrivals))
    }

    @discardableResult
    func startLiveActivity(for bookmark: Bookmark, arrivalDepartures: [ArrivalDeparture]) -> TrackResult {
        let (routeShortName, routeHeadsign) = Self.liveActivityKeys(for: bookmark)

        let routeColorHex = arrivalDepartures.first?.route.color?.toHex()
        let staticData = TripAttributes.StaticData(
            routeShortName: routeShortName,
            routeHeadsign: routeHeadsign,
            stopID: bookmark.stopID,
            routeColorHex: routeColorHex,
            regionID: application.currentRegion?.regionIdentifier ?? 0
        )

        // Tapping Track again on a bookmark that is already tracked — or tracking
        // the same trip from the stop page — would otherwise mint a second
        // activity for one stop, leaving the user with duplicate Lock Screen
        // cards and duplicate OBACloud push registrations. Re-Track still needs
        // to promote the existing activity: after A→B the Island is on B with A
        // demoted to 0, so tapping Track on A again must bump A (not just toast).
        if let existing = Activity<TripAttributes>.running(matching: staticData) {
            Logger.info("Live Activity already running for stop \(staticData.stopID) route \(staticData.routeShortName); promoting instead of duplicating.")
            let existingID = existing.id
            Task {
                await Activity<TripAttributes>.promoteToDynamicIsland(activityID: existingID)
            }
            showLiveActivityStartedToast()
            return .promotedExisting
        }

        guard let contentState = Self.buildContentState(from: arrivalDepartures) else {
            // Shouldn't happen — the context menu only offers Track once arrival
            // data has loaded — but if data was cleared between the menu render
            // and the tap, tell the user rather than silently doing nothing.
            Logger.error("Failed to build content state for Live Activity")
            return .failed
        }

        let attributes = TripAttributes(staticData: staticData)
        // Prominence so the Dynamic Island switches to this Track when another
        // trip is already live (#1189 Problem 2). Default score is 0 and equal
        // scores keep the first-started activity.
        let prominence = TripLiveActivityRelevance.prominenceScore()
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: TripLiveActivityRelevance.content(
                    state: contentState,
                    staleDate: nil,
                    relevanceScore: prominence
                ),
                pushType: .token
            )
            trackLiveActivity(activity, arrivalDepartures: arrivalDepartures)
            let activityID = activity.id
            Task {
                await Activity<TripAttributes>.demoteLivePeers(
                    exceptActivityID: activityID,
                    relativeTo: prominence
                )
            }
            Logger.info("Started Live Activity with ID: \(activity.id)")
            showLiveActivityStartedToast()
            return .started
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            return .failed
        }
    }

    /// Shared by the start path and the already-tracking guard, so a duplicate
    /// tap gets the same confirmation the first tap did rather than silently
    /// appearing to do nothing.
    private func showLiveActivityStartedToast() {
        let message = OBALoc("live_activity.started.title", value: "Tracking on Lock Screen", comment: "Toast shown when a Live Activity starts on the Lock Screen")
        ProgressHUD.showSuccessAndDismiss(message: message)
    }

    /// Hands `activity` to the app-scoped tracker, which owns the push-token and lifecycle
    /// observers. They deliberately outlive this controller — and every other screen — so that an
    /// activity is unregistered when it actually ends rather than when a view controller happens
    /// to be deallocated. See `LiveActivityTracker`.
    private func trackLiveActivity(_ activity: Activity<TripAttributes>, arrivalDepartures: [ArrivalDeparture]) {
        application.liveActivityTracker.track(
            activity: activity,
            metadata: .init(arrivalDepartures.first)
        )
    }
}
```

- [ ] **Step 4: Rewire `BookmarksViewController` onto it**

In `OBAKit/Bookmarks/BookmarksViewController.swift`:

1. Add a stored property beside `dataLoadFeedbackGenerator`:

```swift
    private lazy var bookmarkActions = BookmarkActions(application: application)
```

2. Replace the three handler closures in `makeNavigationHandler()`:

```swift
            editBookmark: { [weak self] bookmark in
                guard let self else { return }
                let editor = self.bookmarkActions.makeBookmarkEditor(for: bookmark, delegate: self)
                self.application.viewRouter.present(editor, from: self)
            },
            deleteBookmark: { [weak self] bookmark in
                guard let self else { return }
                self.bookmarkActions.reportDeletion(of: bookmark)
                self.viewModel.deleteBookmark(bookmark)
            },
            trackBookmark: { [weak self] bookmark in
                guard let self else { return }
                let arrivals = self.viewModel.arrivalDepartures(for: bookmark)
                if self.bookmarkActions.startLiveActivity(for: bookmark, arrivalDepartures: arrivals) == .failed {
                    self.showLiveActivityErrorAlert()
                }
            },
```

3. Delete from the controller: `editBookmark(_:)`, `deleteBookmark(_:)`, `startLiveActivity(for:)`, `showLiveActivityStartedToast()`, `buildContentState(from:)`, `trackLiveActivity(_:arrivalDepartures:)`, and `liveActivityKeys(for:)`.

4. `updateRunningLiveActivities()` stays, but its two moved dependencies are now static on `BookmarkActions`. Change its call sites:

```swift
                let keys = BookmarkActions.liveActivityKeys(for: bookmark)
```

```swift
            if matchingBookmark != nil, let contentState = BookmarkActions.buildContentState(from: arrivalDepartures) {
```

and inside the same branch, replace the `trackLiveActivity(...)` call with:

```swift
                if !application.liveActivityTracker.isForwardingPushToken(activityID: activity.id) {
                    application.liveActivityTracker.track(
                        activity: activity,
                        metadata: .init(arrivalDepartures.first)
                    )
                }
```

5. Drop `import ActivityKit` from `BookmarksViewController` only if nothing else in the file still uses it — `updateRunningLiveActivities` does, so it stays.

- [ ] **Step 5: Run the tests and verify they pass**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/BookmarkActionsTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 6 new tests PASS, and the **whole** suite PASSES — this is a refactor, so nothing else may move.

- [ ] **Step 6: Verify the tab by hand**

Run the app on a device (Live Activities don't start in the Simulator). On the Bookmarks tab: long-press a trip bookmark → Track starts a Lock Screen activity; Track again promotes rather than duplicating; Edit opens the editor and saving updates the row; Delete → confirm removes the bookmark. Any difference from `main` is a regression in this task.

- [ ] **Step 7: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Bookmarks/BookmarkActions.swift OBAKit/Bookmarks/BookmarksViewController.swift OBAKitTests/Bookmarks/BookmarkActionsTests.swift
git commit -m "refactor: extract bookmark row actions into BookmarkActions"
```

---

## Task 7: `BookmarksSheetView` and the `.bookmarksAll` route

**Files:**
- Create: `OBAKit/Sheet/Content/Home/Index/BookmarksSheetView.swift`
- Create: `OBAKit/Sheet/Content/Home/Index/BookmarkEditorHost.swift`
- Create: `OBAKitTests/Sheet/Home/BookmarksSheetViewTests.swift`
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift`
- Modify: `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`

**Interfaces:**
- Consumes: `BookmarksListView(viewModel:navigation:)`, `BookmarksNavigationHandler` (all 8 closures), `BookmarksViewModel(application:)` with `start()`, `deactivate()`, `refreshAndWait()`, `lastRefreshHadError`, `deleteBookmark(_:)`, `updateSortType(byGroup:)`, `sortByGroup`, `arrivalDepartures(for:)`, `rebuildSections()`; `BookmarkActions` (Task 6); `StopViewControllerPreview(stopID:application:)`; `DataLoadFeedbackGenerator(application:)`.
- Produces:
  ```swift
  struct BookmarksSheetView: View {
      let application: Application
      init(application: Application)
      static func makeNavigationHandler(
          application: Application,
          viewModel: BookmarksViewModel,
          actions: BookmarkActions,
          coordinator: SheetCoordinator<AppSheetRoute>,
          feedback: DataLoadFeedbackGenerator,
          onEdit: @escaping (Bookmark) -> Void,
          onTrackFailure: @escaping () -> Void
      ) -> BookmarksNavigationHandler
  }

  // on AppSheetViewFactory:
  func bookmarksAllView() -> BookmarksSheetView
  ```

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Sheet/Home/BookmarksSheetViewTests.swift`:

```swift
//
//  BookmarksSheetViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class BookmarksSheetViewTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private static let seedEpoch = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func seedBookmark(application: Application) throws -> Bookmark {
        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        let bookmark = Bookmark(
            name: "Bookmark",
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: stop,
            dateCreated: Self.seedEpoch
        )
        application.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    /// Builds the handler the sheet installs, with inert presentation callbacks.
    @MainActor
    private func makeHandler(
        application: Application,
        coordinator: SheetCoordinator<AppSheetRoute>
    ) -> BookmarksNavigationHandler {
        BookmarksSheetView.makeNavigationHandler(
            application: application,
            viewModel: BookmarksViewModel(application: application),
            actions: BookmarkActions(application: application),
            coordinator: coordinator,
            feedback: DataLoadFeedbackGenerator(application: application),
            onEdit: { _ in },
            onTrackFailure: { }
        )
    }

    /// A tapped bookmark stacks the stop details sheet on the coordinator —
    /// not a `viewRouter` push, which would open a UIKit stop page inside the
    /// sheet and diverge from every other row tap in the sheet system.
    @Test @MainActor func `Selecting a bookmark pushes stop details`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

        makeHandler(application: application, coordinator: coordinator)
            .selectBookmark(bookmark)

        #expect(coordinator.stackedRoutes == [.stopDetails(stopID: bookmark.stopID)])
    }

    /// Pinning from the sheet writes through to the store, which is what the
    /// home sheet's bookmarks preview reads.
    @Test @MainActor func `Toggling a pin writes through to the store`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        try #require(!bookmark.isPinned)
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

        let handler = makeHandler(application: application, coordinator: coordinator)
        handler.togglePin(bookmark)

        let stored = try #require(application.userDataStore.bookmarks.first { $0.id == bookmark.id })
        #expect(stored.isPinned)

        handler.togglePin(stored)
        let unpinned = try #require(application.userDataStore.bookmarks.first { $0.id == bookmark.id })
        #expect(!unpinned.isPinned)
    }

    /// Deleting removes the bookmark from the store.
    @Test @MainActor func `Deleting a bookmark removes it from the store`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

        makeHandler(application: application, coordinator: coordinator)
            .deleteBookmark(bookmark)

        #expect(!application.userDataStore.bookmarks.contains { $0.id == bookmark.id })
    }

    /// Editing routes to the presentation callback the sheet supplies rather
    /// than presenting anything itself.
    @Test @MainActor func `Editing a bookmark calls the presentation callback`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        var edited: Bookmark?

        let handler = BookmarksSheetView.makeNavigationHandler(
            application: application,
            viewModel: BookmarksViewModel(application: application),
            actions: BookmarkActions(application: application),
            coordinator: SheetCoordinator<AppSheetRoute>(root: .home),
            feedback: DataLoadFeedbackGenerator(application: application),
            onEdit: { edited = $0 },
            onTrackFailure: { }
        )
        handler.editBookmark(bookmark)

        #expect(edited?.id == bookmark.id)
    }

    /// Tracking a bookmark with no loaded arrivals can't start an activity, so
    /// the failure callback fires and the sheet can raise its alert.
    @Test @MainActor func `Track failure calls the failure callback`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        var failed = false

        let handler = BookmarksSheetView.makeNavigationHandler(
            application: application,
            viewModel: BookmarksViewModel(application: application),
            actions: BookmarkActions(application: application),
            coordinator: SheetCoordinator<AppSheetRoute>(root: .home),
            feedback: DataLoadFeedbackGenerator(application: application),
            onEdit: { _ in },
            onTrackFailure: { failed = true }
        )
        handler.trackBookmark(bookmark)

        #expect(failed)
    }
}
```

Also add the factory test and **delete** the now-empty placeholder loop test (`Remaining index routes dispatch to a placeholder without asserting`) from `AppSheetViewFactoryTests`:

```swift
    /// `.bookmarksAll` renders the native index, not the placeholder. With all
    /// three index routes wired, no route reaches `indexPlaceholderView` any
    /// more — it survives only as `unimplementedView`'s release-build fallback.
    @Test @MainActor
    func `Bookmarks all view forwards the application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).bookmarksAllView()

        #expect(view.application === application)
    }
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: compile FAILS with `cannot find 'BookmarksSheetView' in scope`.

- [ ] **Step 3: Write the editor host**

Create `OBAKit/Sheet/Content/Home/Index/BookmarkEditorHost.swift`:

```swift
//
//  BookmarkEditorHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// Presents `EditBookmarkViewController` from a SwiftUI sheet.
///
/// The Bookmarks tab reaches the same editor through `viewRouter.present(_:from:)`,
/// which needs a presenting `UIViewController` the sheet doesn't have. Both
/// paths build the controller with `BookmarkActions.makeBookmarkEditor`.
struct BookmarkEditorHost: UIViewControllerRepresentable {
    let application: Application
    let bookmark: Bookmark
    /// Fires when the editor is dismissed, whether saved or cancelled, so the
    /// list can rebuild.
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let coordinator = context.coordinator
        return BookmarkActions(application: application)
            .makeBookmarkEditor(for: bookmark, delegate: coordinator)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    /// `BookmarkEditorDelegate` is a UIKit-era protocol, so the representable's
    /// coordinator adopts it and forwards both outcomes to one closure.
    @MainActor
    final class Coordinator: NSObject, BookmarkEditorDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func bookmarkEditorCancelled(_ viewController: UIViewController) {
            onFinish()
        }

        func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
            onFinish()
        }
    }
}
```

`BookmarkEditorDelegate` is declared `: NSObjectProtocol` in `OBAKit/Bookmarks/AddBookmarkViewController.swift:13`, which is why the coordinator subclasses `NSObject`. `EditBookmarkViewController` holds its delegate weakly, so the coordinator must stay owned by the representable's `Context` — don't construct it inline in `makeUIViewController`.

- [ ] **Step 4: Write the sheet view**

Create `OBAKit/Sheet/Content/Home/Index/BookmarksSheetView.swift`:

```swift
//
//  BookmarksSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import ActivityKit
import OBAKitCore

/// The Bookmarks index — `AppSheetRoute.bookmarksAll`.
///
/// Renders `BookmarksListView` unchanged, so group sections, collapse state,
/// pull-to-refresh, and the row context menu can't drift from the Bookmarks
/// tab. Only the navigation handler differs: taps stack `.stopDetails` on the
/// sheet coordinator instead of pushing through `viewRouter`.
///
/// Manage Bookmarks/Groups is deliberately not offered here — that stays a
/// tab-level editing surface.
struct BookmarksSheetView: View {
    let application: Application

    @StateObject private var viewModel: BookmarksViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    @State private var editingBookmark: Bookmark?
    @State private var isShowingTrackError = false

    private let actions: BookmarkActions
    private let feedback: DataLoadFeedbackGenerator

    init(application: Application) {
        self.application = application
        self.actions = BookmarkActions(application: application)
        self.feedback = DataLoadFeedbackGenerator(application: application)
        _viewModel = StateObject(wrappedValue: BookmarksViewModel(application: application))
    }

    /// Builds the handler the list is driven by. Static and fully injected so
    /// the wiring is assertable without a `UIHostingController` — the same
    /// reasoning as `MoreSheetHost.makeNavigationController`.
    ///
    /// Presentation stays with the caller: `onEdit` and `onTrackFailure` are how
    /// this view raises its own SwiftUI sheet and alert.
    static func makeNavigationHandler(
        application: Application,
        viewModel: BookmarksViewModel,
        actions: BookmarkActions,
        coordinator: SheetCoordinator<AppSheetRoute>,
        feedback: DataLoadFeedbackGenerator,
        onEdit: @escaping (Bookmark) -> Void,
        onTrackFailure: @escaping () -> Void
    ) -> BookmarksNavigationHandler {
        BookmarksNavigationHandler(
            selectBookmark: { bookmark in
                coordinator.push(.stopDetails(stopID: bookmark.stopID))
            },
            editBookmark: onEdit,
            deleteBookmark: { bookmark in
                actions.reportDeletion(of: bookmark)
                viewModel.deleteBookmark(bookmark)
            },
            trackBookmark: { bookmark in
                let arrivals = viewModel.arrivalDepartures(for: bookmark)
                if actions.startLiveActivity(for: bookmark, arrivalDepartures: arrivals) == .failed {
                    onTrackFailure()
                }
            },
            togglePin: { bookmark in
                application.userDataStore.setPinned(!bookmark.isPinned, for: bookmark)
            },
            liveActivitiesEnabled: { ActivityAuthorizationInfo().areActivitiesEnabled },
            refresh: {
                await viewModel.refreshAndWait()
                // Haptic confirms the user-pull completed; the 30 s auto-refresh
                // never routes through here, so the device doesn't buzz unprompted.
                feedback.dataLoad(viewModel.lastRefreshHadError ? .failed : .success)
            },
            makeStopPreview: { stopID in
                AnyView(
                    StopViewControllerPreview(stopID: stopID, application: application)
                        .frame(width: 320, height: 400)
                )
            }
        )
    }

    private var navigationHandler: BookmarksNavigationHandler {
        Self.makeNavigationHandler(
            application: application,
            viewModel: viewModel,
            actions: actions,
            coordinator: coordinator,
            feedback: feedback,
            onEdit: { editingBookmark = $0 },
            onTrackFailure: { isShowingTrackError = true }
        )
    }

    var body: some View {
        NavigationStack {
            BookmarksListView(viewModel: viewModel, navigation: navigationHandler)
                .environment(\.obaFormatters, application.formatters)
                .navigationTitle(Text(Strings.bookmarks))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenu
                    }
                }
        }
        .searchSheetBackground()
        .onAppear { viewModel.start() }
        // Stops the 30 s poll when the sheet goes away. The tab does the same on
        // `viewWillDisappear`.
        .onDisappear { viewModel.deactivate() }
        .sheet(item: $editingBookmark) { bookmark in
            BookmarkEditorHost(application: application, bookmark: bookmark) {
                editingBookmark = nil
                viewModel.rebuildSections()
            }
        }
        .alert(
            OBALoc("live_activity.error.title", value: "Unable to Start Tracking", comment: "Alert title when Live Activity fails to start"),
            isPresented: $isShowingTrackError
        ) {
            Button(Strings.ok, role: .cancel) { }
        } message: {
            Text(OBALoc("live_activity.error.message", value: "Please check your Live Activities settings in Settings.", comment: "Alert message for Live Activity error. \"Settings\" is the iOS Settings app."))
        }
    }

    /// Mirrors the tab's `rebuildSortMenu`, including which item is checked.
    private var sortMenu: some View {
        Menu {
            Picker(Strings.sort, selection: sortSelection) {
                Label(
                    OBALoc("bookmarks_controller.sort_menu.sort_by_group", value: "Sort by Group", comment: "A menu item that allows the user to sort their bookmarks into groups."),
                    systemImage: "folder"
                )
                .tag(true)

                Label(
                    OBALoc("bookmarks_controller.sort_menu.sort_by_distance", value: "Sort by Distance", comment: "A menu item that allows the user to sort their bookmarks by distance from the user."),
                    systemImage: "location.circle"
                )
                .tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Label(Strings.sort, systemImage: "arrow.up.arrow.down.circle")
        }
    }

    private var sortSelection: Binding<Bool> {
        Binding(
            get: { viewModel.sortByGroup },
            set: { viewModel.updateSortType(byGroup: $0) }
        )
    }
}
```

- [ ] **Step 5: Wire the route in the factory**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`, the dispatch loses its placeholder branch for index routes entirely:

```swift
        case .bookmarksAll:
            bookmarksAllView()
```

and add the builder:

```swift
    /// `AppSheetRoute.bookmarksAll` — the home sheet's "Bookmarks" header.
    func bookmarksAllView() -> BookmarksSheetView {
        BookmarksSheetView(application: application)
    }
```

`indexPlaceholderView` keeps its definition — `unimplementedView` still calls it on the release path — but update the doc comment once more, since no route dispatches to it directly any more:

```swift
    /// Visible "coming soon" body used by `unimplementedView` in release builds.
    /// No route dispatches here directly: every index route now has a real view.
```

- [ ] **Step 6: Run the tests and verify they pass**

```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/BookmarksSheetViewTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: 5 new tests PASS, whole suite PASSES.

- [ ] **Step 7: Verify all three screens by hand**

In the Simulator: open the home sheet, drag it up, and tap each of the three section headers. Each opens its index over the map. In each: tap a row → the stop details sheet stacks on top; dismiss it → the index is still there with its state intact; dismiss the index → the home sheet's preview sections reflect anything you changed. On Nearby and Recents, type in the search field. On Recents, swipe a row and use Delete All. On Bookmarks, collapse a group, pull to refresh, and change the sort.

- [ ] **Step 8: Lint and commit**

```bash
scripts/swiftlint.sh
git add OBAKit/Sheet/Content/Home/Index/BookmarksSheetView.swift OBAKit/Sheet/Content/Home/Index/BookmarkEditorHost.swift OBAKitTests/Sheet/Home/BookmarksSheetViewTests.swift OBAKit/Sheet/DI/AppSheetViewFactory.swift OBAKitTests/Sheet/AppSheetViewFactoryTests.swift
git commit -m "feat: add the bookmarks index sheet"
```

---

## Verification

After Task 7, the whole feature is in. Final gate:

```bash
scripts/generate_project OneBusAway
scripts/swiftlint.sh
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

All of `OBAKitTests` must pass, with zero new warnings — the concurrency diagnostic groups are errors, so a data-race warning would already have failed the build.
