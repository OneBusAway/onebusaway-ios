# Home Sheet Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate the SwiftUI home sheet with Nearby Stops, Recent Stops, and Bookmarks preview sections — four items each, each header's chevron pushing the corresponding index route.

**Architecture:** `HomeSheetViewModel` composes three purpose-built section models, each wired to the data source the UIKit experience already uses. Five shared utilities are extracted first (Tasks 1–5), each additive and defaulted so existing callers are untouched. Nearby and Recent cost zero network requests; Bookmarks costs at most four, once per activation, with no polling timer.

**Tech Stack:** Swift 6 language mode, SwiftUI, Combine, MapKit, Swift Testing (`@Suite(.serialized)`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-13-home-sheet-sections-design.md`

## Global Constraints

- **Do not build any index screen.** `.nearbyAll`, `.recentStopsAll`, `.bookmarksAll` render the existing "coming soon" placeholder. Out of scope.
- **Regenerate the project after adding files:** `scripts/generate_project OneBusAway`. XcodeGen picks new files up by directory glob; a new file is invisible to the build until this runs.
- **Build/test destination is `platform=iOS Simulator,name=iPhone 16,OS=26.0`** — not iPhone 17 Pro.
- **Never erase or reset the simulator.**
- **Swift 6 language mode with main-actor default isolation.** The five concurrency diagnostic groups are escalated to errors — a data-race warning fails the build. CI fails PRs that add strict-concurrency warnings. `OBAKitCore` pins `SWIFT_DEFAULT_ACTOR_ISOLATION` back to `nonisolated`, so anything added there needs explicit isolation.
- **Tests are Swift Testing**, not XCTest: `@Suite(.serialized)`, `final class X: OBATestCase`, `override init() async throws`, teardown in `isolated deinit`, `#expect`. Test names are backtick-quoted sentences.
- **Section item limit is 4**, defined once as `HomeSheetSection.itemLimit`.
- **Section order is fixed:** Nearby → Recent → Bookmarks, with no promotion or reflow when an earlier section is empty.
- **Commit messages are a single line, imperative mood.** No `Co-Authored-By`, no Claude/AI attribution anywhere — not in commits, PR bodies, or code comments.
- **Do not run `git push`, open PRs, or file issues.** Committing locally per task is expected; anything outward-facing is not.

## Reference Commands

```bash
# Regenerate the Xcode project (required after adding any file)
scripts/generate_project OneBusAway

# Build for testing
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'

# Run one suite
xcodebuild test-without-building -only-testing:OBAKitTests/SUITE_NAME \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'

# Lint
scripts/swiftlint.sh
```

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `OBAKitCore/Models/REST/References/Stop+Distance.swift` | Cosine-scaled squared distance + nearest-N selection |
| `OBAKit/Sheet/Content/Home/HomeSheetSection.swift` | Section identity + the shared item limit |
| `OBAKit/Sheet/Content/Home/HomeSectionHeader.swift` | Title + chevron header, one button |
| `OBAKit/Sheet/Content/Home/HomeNearbyStopsSectionModel.swift` | Nearest-4 from `MapStopsObserver` |
| `OBAKit/Sheet/Content/Home/HomeRecentStopsSectionModel.swift` | First 4 region-filtered recent stops |
| `OBAKit/Sheet/Content/Home/HomeBookmarksSectionModel.swift` | First 4 bookmarks by `sortOrder` + scoped arrivals |
| `OBAKitTests/Modeling/StopDistanceTests.swift` | Task 1 tests |
| `OBAKitTests/Bookmarks/BookmarkDataLoaderTests.swift` | Task 4 tests |
| `OBAKitTests/Sheet/Home/HomeSectionModelTests.swift` | Tasks 9–11 tests |
| `OBAKitTests/Sheet/Home/HomeSheetViewModelTests.swift` | Task 12 tests |

**Modified**

| File | Change |
|---|---|
| `OBAKit/Sheet/Root/MapStopsObserver.swift` | Prune folds onto `Stop.nearest`; publishes `viewportCenter` |
| `OBAKitCore/Models/UserData/UserDataStore.swift` | Adds `recentStops(in:)` |
| `OBAKit/Recent/RecentStopsViewModel.swift` | Refactored onto `recentStops(in:)` |
| `OBAKitCore/Strings/Strings.swift` | Adds `nearbyStops`, `bookmarks` |
| `OBAKit/Mapping/NearbyStopsListViewController.swift` | Uses `Strings.nearbyStops` |
| `OBAKit/Search/SearchInteractor.swift` | Uses `Strings.bookmarks` |
| `OBAKitCore/Bookmarks/BookmarkDataLoader.swift` | `bookmarkProvider` + `autoRefreshes` seams |
| `OBAKit/Search/SearchList/Models/SearchListRow.swift` | `.nearbyStop(id:)` kind + `stop(...)` factory |
| `OBAKit/Search/SearchList/SearchListRowView.swift` | Renders `.nearbyStop` |
| `OBAKit/Sheet/Content/Search/SearchResultRow.swift` | Stop branch delegates to the factory |
| `OBAKit/Sheet/Root/MapPanelRootController.swift` | Owns `MapStopsObserver` |
| `OBAKit/Sheet/Root/MapPanelRootView.swift` | Takes observer as `@ObservedObject` |
| `OBAKit/Sheet/DI/AppSheetViewFactory.swift` | Holds observer; index-route assert exemption |
| `OBAKit/Sheet/Content/Home/HomeSheetViewModel.swift` | Composes the three sections |
| `OBAKit/Sheet/Content/Home/HomeSheetView.swift` | Renders the three sections |
| `OBAKitTests/Sheet/MapStopsObserverTests.swift` | `observer.squaredDistance` → `Stop.squaredDistance` |
| `OBAKitTests/Search/SearchResultRowTests.swift` | Factory + kind-collision tests |
| `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift` | Index-route placeholder tests |
| `OBAKitTests/Modeling/UserData/RecentStopsTests.swift` | `recentStops(in:)` tests (create if absent) |

---

## Task 1: `Stop.nearest` distance utility

Extracts `MapStopsObserver`'s private ordering formula to `OBAKitCore` so the nearby section and the observer's cap-eviction share one definition.

**Files:**
- Create: `OBAKitCore/Models/REST/References/Stop+Distance.swift`
- Create: `OBAKitTests/Modeling/StopDistanceTests.swift`
- Modify: `OBAKit/Sheet/Root/MapStopsObserver.swift:181-221` (prune + `squaredDistance`)
- Modify: `OBAKitTests/Sheet/MapStopsObserverTests.swift:155,201`

**Interfaces:**
- Consumes: nothing.
- Produces: `Stop.squaredDistance(_ stop: Stop, to center: CLLocationCoordinate2D) -> Double` and `Stop.nearest(_ stops: [Stop], to center: CLLocationCoordinate2D, limit: Int) -> [Stop]`, both `public static` on `Stop`, both `nonisolated`.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Modeling/StopDistanceTests.swift`:

```swift
//
//  StopDistanceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class StopDistanceTests: OBATestCase {

    /// Stops are returned nearest-first, and the list is truncated to `limit`.
    @Test func `Nearest returns the closest stops in order`() throws {
        let stops = try Fixtures.loadSomeStops()
        let anchor = try #require(stops.first).location.coordinate

        let nearest = Stop.nearest(stops, to: anchor, limit: 3)

        #expect(nearest.count == 3)
        // The anchor stop is zero distance from itself, so it must come first.
        #expect(nearest.first?.id == stops.first?.id)

        let distances = nearest.map { Stop.squaredDistance($0, to: anchor) }
        #expect(distances == distances.sorted())
    }

    /// A limit larger than the input returns everything, still ordered.
    @Test func `Nearest returns everything when the limit exceeds the input`() throws {
        let stops = try Fixtures.loadSomeStops()
        let anchor = try #require(stops.first).location.coordinate

        let nearest = Stop.nearest(stops, to: anchor, limit: stops.count + 10)

        #expect(nearest.count == stops.count)
    }

    /// Degenerate inputs return empty rather than trapping.
    @Test func `Nearest returns empty for empty input or a non positive limit`() throws {
        let stops = try Fixtures.loadSomeStops()
        let anchor = try #require(stops.first).location.coordinate

        #expect(Stop.nearest([], to: anchor, limit: 4).isEmpty)
        #expect(Stop.nearest(stops, to: anchor, limit: 0).isEmpty)
        #expect(Stop.nearest(stops, to: anchor, limit: -1).isEmpty)
    }

    /// Longitude is scaled by cos(latitude), so a degree of longitude counts
    /// for less than a degree of latitude away from the equator. Without the
    /// scaling these two would compare equal.
    @Test func `Squared distance scales longitude by latitude`() throws {
        let stops = try Fixtures.loadSomeStops()
        let reference = try #require(stops.first)
        let anchor = reference.location.coordinate

        let latOffset = CLLocationCoordinate2D(latitude: anchor.latitude + 1, longitude: anchor.longitude)
        let lonOffset = CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude + 1)

        let latDistance = Stop.squaredDistance(reference, to: latOffset)
        let lonDistance = Stop.squaredDistance(reference, to: lonOffset)

        // Seattle is well north of the equator, so cos(lat) < 1.
        #expect(lonDistance < latDistance)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS with "type 'Stop' has no member 'nearest'".

- [ ] **Step 3: Write the implementation**

Create `OBAKitCore/Models/REST/References/Stop+Distance.swift`:

```swift
//
//  Stop+Distance.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

public extension Stop {

    /// Squared distance with longitude scaled by `cos(latitude)` so lat/lon
    /// degrees compare on a common metric scale. Ordering only — no sqrt, and
    /// the result is not meaningful as a real-world distance.
    nonisolated static func squaredDistance(_ stop: Stop, to center: CLLocationCoordinate2D) -> Double {
        let coordinate = stop.location.coordinate
        let dLat = coordinate.latitude - center.latitude
        let dLon = (coordinate.longitude - center.longitude) * cos(center.latitude * .pi / 180)
        return dLat * dLat + dLon * dLon
    }

    /// The `limit` stops closest to `center`, nearest first.
    ///
    /// Shared by `MapStopsObserver`'s cap eviction and the home sheet's nearby
    /// section so both order stops by exactly the same metric.
    nonisolated static func nearest(_ stops: [Stop], to center: CLLocationCoordinate2D, limit: Int) -> [Stop] {
        guard limit > 0 else { return [] }
        return stops
            .sorted { squaredDistance($0, to: center) < squaredDistance($1, to: center) }
            .prefix(limit)
            .map { $0 }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild test-without-building -only-testing:OBAKitTests/StopDistanceTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Fold `MapStopsObserver`'s prune onto the shared helper**

In `OBAKit/Sheet/Root/MapStopsObserver.swift`, delete the `squaredDistance(_:to:)` method entirely (it currently sits just below `pruneAccumulated`, documented as internal "so the cap-eviction tests can assert against this exact ordering" — that reason now lives on `Stop`). Replace the cap-eviction block inside `pruneAccumulated()`:

```swift
        // Count cap: keep the `renderCap` nearest to center, evict the rest.
        if accumulated.count > renderCap {
            let nearest = Stop.nearest(Array(accumulated.values), to: center, limit: renderCap)
            accumulated = Dictionary(nearest.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
```

- [ ] **Step 6: Update the observer's tests to the new call site**

In `OBAKitTests/Sheet/MapStopsObserverTests.swift`, at both line 155 and line 201, replace `observer.squaredDistance(` with `Stop.squaredDistance(`. The expression shape is otherwise unchanged, e.g.:

```swift
                Stop.squaredDistance($0, to: anchor.coordinate) < Stop.squaredDistance($1, to: anchor.coordinate)
```

- [ ] **Step 7: Run both suites to verify no regression**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/StopDistanceTests \
  -only-testing:OBAKitTests/MapStopsObserverTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS. The cap-eviction tests are the regression signal — they assert the exact ordering the observer used before.

- [ ] **Step 8: Commit**

```bash
git add OBAKitCore/Models/REST/References/Stop+Distance.swift \
        OBAKitTests/Modeling/StopDistanceTests.swift \
        OBAKit/Sheet/Root/MapStopsObserver.swift \
        OBAKitTests/Sheet/MapStopsObserverTests.swift
git commit -m "refactor: extract nearest-N stop selection to a shared Stop helper"
```

---

## Task 2: `UserDataStore.recentStops(in:)`

**Files:**
- Modify: `OBAKitCore/Models/UserData/UserDataStore.swift` (protocol ~line 130, implementation ~line 666)
- Modify: `OBAKit/Recent/RecentStopsViewModel.swift:28-47`
- Create or modify: `OBAKitTests/Modeling/UserData/RecentStopsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `UserDataStore.recentStops(in region: Region?) -> [Stop]`, returning `[]` for a nil region.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Modeling/UserData/RecentStopsTests.swift` (if the file already exists, append the two `@Test` methods to the existing suite instead of recreating it):

```swift
//
//  RecentStopsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class RecentStopsTests: OBATestCase {

    /// Only stops belonging to the supplied region come back, and the store's
    /// most-recently-used ordering is preserved.
    @Test func `Recent stops in region filters by region identifier`() throws {
        let stops = try Fixtures.loadSomeStops()
        let first = try #require(stops.first)
        let second = try #require(stops.dropFirst().first)

        let store = UserDefaultsStore(userDefaults: userDefaults)
        store.addRecentStop(first, region: Fixtures.pugetSoundRegion)
        store.addRecentStop(second, region: Fixtures.pugetSoundRegion)

        let recents = store.recentStops(in: Fixtures.pugetSoundRegion)

        // addRecentStop inserts at index 0, so the newest is first.
        #expect(recents.map(\.id) == [second.id, first.id])
    }

    /// A nil region yields an empty list rather than every stored stop.
    @Test func `Recent stops in region returns empty for a nil region`() throws {
        let stops = try Fixtures.loadSomeStops()
        let first = try #require(stops.first)

        let store = UserDefaultsStore(userDefaults: userDefaults)
        store.addRecentStop(first, region: Fixtures.pugetSoundRegion)

        #expect(store.recentStops(in: nil).isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS with "value of type 'UserDefaultsStore' has no member 'recentStops(in:)'".

- [ ] **Step 3: Add the protocol requirement and implementation**

In `OBAKitCore/Models/UserData/UserDataStore.swift`, add to the protocol next to the existing `var recentStops: [Stop] { get }` (~line 130):

```swift
    /// Recent stops belonging to `region`, most-recently-used first.
    /// Returns `[]` when `region` is nil.
    func recentStops(in region: Region?) -> [Stop]
```

And add the implementation next to the existing `recentStops` property (~line 666), mirroring `findBookmarks(in:)`:

```swift
    public func recentStops(in region: Region?) -> [Stop] {
        guard let region = region else { return [] }
        return recentStops.filter { $0.regionIdentifier == region.regionIdentifier }
    }
```

- [ ] **Step 4: Refactor `RecentStopsViewModel` onto it**

In `OBAKit/Recent/RecentStopsViewModel.swift`, replace the body of `loadData()` below the alarms lines. The nil-region warning stays here — it tracks view-model lifecycle (`didWarnNilRegion`), not store state:

```swift
    func loadData() {
        application.userDataStore.deleteExpiredAlarms()
        alarms = application.userDataStore.alarms
        guard let currentRegion = application.currentRegion else {
            // No current region (mid-region-change, first launch race, denied location).
            // The user sees a generic empty state — log once per VM so the condition is
            // observable without spamming on every viewWillAppear.
            if !didWarnNilRegion {
                Logger.warn("RecentStopsViewModel.loadData: currentRegion is nil; returning empty recent stops.")
                didWarnNilRegion = true
            }
            recentStops = []
            return
        }
        // Region resolved — re-arm the warn so a *later* region loss is still observable.
        didWarnNilRegion = false
        recentStops = application.userDataStore.recentStops(in: currentRegion)
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/RecentStopsTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS, 2 tests.

- [ ] **Step 6: Commit**

```bash
git add OBAKitCore/Models/UserData/UserDataStore.swift \
        OBAKit/Recent/RecentStopsViewModel.swift \
        OBAKitTests/Modeling/UserData/RecentStopsTests.swift
git commit -m "refactor: add UserDataStore.recentStops(in:) and adopt it in RecentStopsViewModel"
```

---

## Task 3: Shared section title strings

Two section titles are currently inline `OBALoc` calls. Moving them to `Strings` keeps the existing keys, so no translation is lost.

**Files:**
- Modify: `OBAKitCore/Strings/Strings.swift` (near `recentStops`, ~line 71)
- Modify: `OBAKit/Mapping/NearbyStopsListViewController.swift:42`
- Modify: `OBAKit/Search/SearchInteractor.swift:130`

**Interfaces:**
- Consumes: nothing.
- Produces: `Strings.nearbyStops: String`, `Strings.bookmarks: String`.

- [ ] **Step 1: Add the constants**

In `OBAKitCore/Strings/Strings.swift`, immediately after the existing `recentStops` declaration, add — keeping the keys, values, and comments byte-identical to the inline call sites so the `.strings` entries keep matching:

```swift
    public static let nearbyStops = OBALoc("nearby_stops_controller.title", value: "Nearby Stops", comment: "The title of the Nearby Stops controller.")

    public static let bookmarks = OBALoc("search_controller.bookmarks.header", value: "Bookmarks", comment: "Title of the Bookmarks search header")
```

- [ ] **Step 2: Update the nearby call site**

In `OBAKit/Mapping/NearbyStopsListViewController.swift`, in `Section.localizedTitle`, replace the `.nearbyStops` arm's inline `OBALoc(...)` with:

```swift
            case .nearbyStops:
                return Strings.nearbyStops
```

- [ ] **Step 3: Update the bookmarks call site**

In `OBAKit/Search/SearchInteractor.swift`, in `buildBookmarksSection(searchText:)`, replace the section's `title:` argument with `Strings.bookmarks`:

```swift
        return .init(
            id: .bookmarks,
            title: Strings.bookmarks,
            content: bookmarks
        )
```

- [ ] **Step 4: Verify the localization tests still pass**

`OBAKitTests/Strings/LocalizationTests.swift` guards that declared keys resolve. Run it plus the search suite:

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/LocalizationTests \
  -only-testing:OBAKitTests/SearchInteractorTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS. A failure here means a key or default value drifted from the original — re-diff against the inline versions.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Strings/Strings.swift \
        OBAKit/Mapping/NearbyStopsListViewController.swift \
        OBAKit/Search/SearchInteractor.swift
git commit -m "refactor: move nearby stops and bookmarks section titles into Strings"
```

---

## Task 4: `BookmarkDataLoader` scoping seam

Lets the home sheet reuse the loader for four bookmarks with no polling, while the Bookmarks tab keeps today's behaviour exactly.

**Files:**
- Modify: `OBAKitCore/Bookmarks/BookmarkDataLoader.swift:66-130`
- Create: `OBAKitTests/Bookmarks/BookmarkDataLoaderTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `BookmarkDataLoader.init(application:delegate:bookmarkProvider:autoRefreshes:)` where `bookmarkProvider` is `(@MainActor () -> [Bookmark])?` defaulting to `nil` and `autoRefreshes` is `Bool` defaulting to `true`. Existing members are unchanged: `loadData()`, `loadDataAndWait() async`, `cancelUpdates()`, `dataForKey(_: TripBookmarkKey) -> [ArrivalDeparture]`, `hasFetchedData(forStopID: StopID) -> Bool`, `isLoading`, `lastBatchHadError`.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Bookmarks/BookmarkDataLoaderTests.swift`:

```swift
//
//  BookmarkDataLoaderTests.swift
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
final class BookmarkDataLoaderTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Counts arrivals requests so the scoped-provider test can assert the
    /// loader fetched only the bookmarks it was handed.
    @MainActor
    private final class RecordingDelegate: NSObject, BookmarkDataDelegate {
        var updateCount = 0
        func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) { updateCount += 1 }
    }

    /// Builds real *trip* bookmarks — `isTripBookmark` requires a route short
    /// name, route id, and trip headsign, which only a decoded `ArrivalDeparture`
    /// supplies. A bookmark that isn't a trip bookmark is skipped by the loader
    /// without a request, which would silently zero out the counts below.
    @MainActor
    private func makeTripBookmarks(count: Int, application: Application) throws -> [Bookmark] {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)

        return (0..<count).map { index in
            let bookmark = Bookmark(
                name: "Bookmark \(index)",
                regionIdentifier: pugetSoundRegionIdentifier,
                arrivalDeparture: arrivalDeparture
            )
            bookmark.sortOrder = index
            application.userDataStore.add(bookmark, to: nil)
            return bookmark
        }
    }

    /// The provider — not the whole store — decides what gets fetched.
    @Test @MainActor
    func `Bookmark provider scopes fetches to the supplied bookmarks`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        var requestCount = 0
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            let matches = request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            if matches { requestCount += 1 }
            return matches
        }

        let all = try makeTripBookmarks(count: 6, application: application)
        let scoped = Array(all.prefix(2))

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(
            application: application,
            delegate: delegate,
            bookmarkProvider: { scoped },
            autoRefreshes: false
        )

        await loader.loadDataAndWait()

        // Six bookmarks exist; only the two handed to the provider are fetched.
        #expect(requestCount == 2)
    }

    /// With auto-refresh off, the loader installs no repeating timer.
    @Test @MainActor
    func `Auto refresh disabled installs no timer`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let bookmarks = try makeTripBookmarks(count: 1, application: application)
        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(
            application: application,
            delegate: delegate,
            bookmarkProvider: { bookmarks },
            autoRefreshes: false
        )

        await loader.loadDataAndWait()

        #expect(loader.hasScheduledRefresh == false)
    }

    /// The Bookmarks tab's construction is untouched: every region bookmark is
    /// fetched and the repeating timer is installed.
    @Test @MainActor
    func `Default initializer fetches all region bookmarks and schedules refresh`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        var requestCount = 0
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            let matches = request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            if matches { requestCount += 1 }
            return matches
        }

        _ = try makeTripBookmarks(count: 3, application: application)

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(application: application, delegate: delegate)

        await loader.loadDataAndWait()

        #expect(requestCount == 3)
        #expect(loader.hasScheduledRefresh)

        loader.cancelUpdates()
    }
}
```

> Every bookmark here shares one stop id. That is fine: `BookmarkDataLoader.startBatch`
> issues one fetch per *bookmark*, not per distinct stop, so the request counts below
> still measure what they claim to.

- [ ] **Step 2: Run the test to verify it fails**

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS — the initializer has no `bookmarkProvider` argument, and `hasScheduledRefresh` does not exist.

- [ ] **Step 3: Add the seams**

In `OBAKitCore/Bookmarks/BookmarkDataLoader.swift`, add two stored properties beside the existing ones and replace the initializer (~line 66):

```swift
    /// When set, supplies the bookmarks a batch should fetch instead of every
    /// bookmark in the current region. Lets a caller that only displays a few
    /// bookmarks — the home sheet's preview section — reuse this loader without
    /// paying for the whole set.
    private let bookmarkProvider: (@MainActor () -> [Bookmark])?

    /// When `false`, `startRefreshTimer()` is a no-op, so the loader fetches
    /// only when explicitly asked. Callers that display a handful of bookmarks
    /// outside a dedicated screen don't want a background 30-second cycle.
    private let autoRefreshes: Bool

    public init(
        application: CoreApplication,
        delegate: BookmarkDataDelegate,
        bookmarkProvider: (@MainActor () -> [Bookmark])? = nil,
        autoRefreshes: Bool = true
    ) {
        self.application = application
        self.delegate = delegate
        self.bookmarkProvider = bookmarkProvider
        self.autoRefreshes = autoRefreshes
    }
```

Guard the timer inside `startRefreshTimer()` rather than at its two call sites, so the invariant holds no matter who calls it (the method is `public`):

```swift
    public func startRefreshTimer() {
        timer?.invalidate()

        guard autoRefreshes else {
            timer = nil
            return
        }

        timer = Timer.scheduledMainActorTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] in
            self?.loadData()
        }
    }

    /// Whether a repeating refresh is currently armed. Exposed so callers that
    /// opted out of auto-refresh can assert they really did.
    @MainActor public var hasScheduledRefresh: Bool {
        timer?.isValid ?? false
    }
```

And route `eligibleBookmarks()` through the provider (~line 126):

```swift
    private func eligibleBookmarks() -> [Bookmark] {
        if let bookmarkProvider {
            return bookmarkProvider()
        }
        return application.userDataStore.bookmarks.filter {
            $0.regionIdentifier == application.regionsService.currentRegion?.id
        }
    }
```

`loadData()` and `loadDataAndWait()` are otherwise unchanged — they still call `startRefreshTimer()`, which now no-ops when auto-refresh is off.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/BookmarkDataLoaderTests \
  -only-testing:OBAKitTests/BookmarksViewModelTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS. `BookmarksViewModelTests` passing unchanged is the proof the tab's behaviour did not shift.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Bookmarks/BookmarkDataLoader.swift \
        OBAKitTests/Bookmarks/BookmarkDataLoaderTests.swift
git commit -m "feat: allow BookmarkDataLoader to scope fetches and skip auto-refresh"
```

---

## Task 5: Shared stop-row builder

Promotes the `Stop` branch buried in `SearchResultRow` to a named factory the home sections can call, and adds the one row kind they need.

**Files:**
- Modify: `OBAKit/Search/SearchList/Models/SearchListRow.swift:18-68` (Kind), plus a new extension
- Modify: `OBAKit/Search/SearchList/SearchListRowView.swift:26` (the `actionRow` arm)
- Modify: `OBAKit/Sheet/Content/Search/SearchResultRow.swift:90-154`
- Modify: `OBAKitTests/Search/SearchResultRowTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `SearchListRow.Kind.nearbyStop(id: String)` and `SearchListRow.stop(_ stop: Stop, application: Application, kind: Kind, onSelect: @escaping () -> Void) -> SearchListRow`.

- [ ] **Step 1: Write the failing test**

Append to the suite in `OBAKitTests/Search/SearchResultRowTests.swift`:

```swift
    /// The shared factory reproduces what the inline `Stop` branch produced,
    /// for whichever kind the caller asks for.
    @Test @MainActor
    func `Stop factory builds a row with the requested kind`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stop = try #require(try Fixtures.loadSomeStops().first)

        let row = SearchListRow.stop(
            stop,
            application: application,
            kind: .nearbyStop(id: stop.id),
            onSelect: {}
        )

        #expect(row.title == stop.name)
        #expect(row.accessory == .disclosureIndicator)
        if case .nearbyStop(let id) = row.kind {
            #expect(id == stop.id)
        } else {
            Issue.record("Expected a .nearbyStop kind, got \(row.kind)")
        }
    }

    /// A stop shown in both the nearby and recent sections must not produce two
    /// rows with the same `id`, or `ForEach` collapses them.
    @Test @MainActor
    func `Nearby and recent kinds yield distinct identifiers for one stop`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stop = try #require(try Fixtures.loadSomeStops().first)

        let nearby = SearchListRow.stop(stop, application: application, kind: .nearbyStop(id: stop.id), onSelect: {})
        let recent = SearchListRow.stop(stop, application: application, kind: .recentStop(id: stop.id), onSelect: {})

        #expect(nearby.id != recent.id)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS — no `.nearbyStop` case and no `SearchListRow.stop(...)`.

- [ ] **Step 3: Add the kind**

In `OBAKit/Search/SearchList/Models/SearchListRow.swift`, add to `enum Kind` beside `recentStop`:

```swift
        /// Carries the stop's id for the same reason `recentStop` does: two
        /// stops on opposite sides of a corner share a name.
        case nearbyStop(id: String)
```

and the matching arm in `stableIdentifier`:

```swift
            case .nearbyStop(let id):
                return "nearbyStop-\(id)"
```

- [ ] **Step 4: Add the factory**

Add to `SearchListRow.swift`, below the existing `// MARK: - Placemark Row Building` extension:

```swift
// MARK: - Stop Row Building

extension SearchListRow {

    /// The standard stop row: stop glyph, name, and a "distance • direction"
    /// subtitle. Shared by the search results sheet and the home sheet's nearby
    /// and recent sections so all three render stops identically.
    ///
    /// `kind` is a parameter rather than fixed because the caller owns row
    /// identity — the same stop can legitimately appear in two sections at once.
    @MainActor
    static func stop(
        _ stop: Stop,
        application: Application,
        kind: Kind,
        onSelect: @escaping () -> Void
    ) -> SearchListRow {
        SearchListRow(
            kind: kind,
            title: stop.name,
            subtitle: stopSubtitle(application, stop),
            icon: .uiImage(Icons.stop),
            accessory: .disclosureIndicator,
            action: onSelect
        )
    }

    /// Direction plus distance from the user, mirroring what the placemark rows
    /// in the search list already show. Distance is dropped when there's no fix.
    @MainActor
    static func stopSubtitle(_ application: Application, _ stop: Stop) -> String? {
        var parts: [String] = []

        if let currentLocation = application.locationService.currentLocation {
            let distance = currentLocation.distance(from: stop.location)
            parts.append(application.formatters.distanceFormatter.string(fromDistance: distance))
        }

        if let direction = Formatters.adjectiveFormOfCardinalDirection(stop.direction), !direction.isEmpty {
            parts.append(direction)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
```

- [ ] **Step 5: Delegate the search-results branch to the factory**

In `OBAKit/Sheet/Content/Search/SearchResultRow.swift`, replace the `case let stop as Stop:` arm of `row(for:application:onSelect:)` with:

```swift
        case let stop as Stop:
            return SearchListRow.stop(
                stop,
                application: application,
                kind: .searchResult(id: stop.id),
                onSelect: onSelect
            )
```

and delete the now-unused `private static func stopSubtitle(_:_:)` from the bottom of the file — it moved onto `SearchListRow`.

- [ ] **Step 6: Render the new kind**

In `OBAKit/Search/SearchList/SearchListRowView.swift`, add `.nearbyStop` to the `actionRow` arm of the `switch row.kind`:

```swift
        case .quickSearch, .recentStop, .nearbyStop, .bookmark, .placemark, .searchResult:
            actionRow
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/SearchResultRowTests \
  -only-testing:OBAKitTests/SearchResultsSheetViewTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS. `SearchResultsSheetViewTests` passing unchanged proves the delegation preserved the old row output.

- [ ] **Step 8: Commit**

```bash
git add OBAKit/Search/SearchList/Models/SearchListRow.swift \
        OBAKit/Search/SearchList/SearchListRowView.swift \
        OBAKit/Sheet/Content/Search/SearchResultRow.swift \
        OBAKitTests/Search/SearchResultRowTests.swift
git commit -m "refactor: extract a shared stop row builder and add a nearby stop kind"
```

---

## Task 6: `MapStopsObserver` viewport center and ownership move

The riskiest task in the plan — it touches the map root's construction path. Isolated deliberately so it can be reviewed and reverted on its own.

**Files:**
- Modify: `OBAKit/Sheet/Root/MapStopsObserver.swift:64-120`
- Modify: `OBAKit/Sheet/Root/MapPanelRootController.swift:26-48`
- Modify: `OBAKit/Sheet/Root/MapPanelRootView.swift:25,89-116`
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift:26-49`
- Modify: `OBAKitTests/Sheet/MapStopsObserverTests.swift`
- Modify: `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift` (factory helper gains the observer)

**Interfaces:**
- Consumes: nothing.
- Produces: `MapStopsObserver.viewportCenter: CLLocationCoordinate2D?` (`@Published private(set)`); `AppSheetViewFactory.stopsObserver: MapStopsObserver` and a new required `stopsObserver:` initializer parameter; `MapPanelRootView.init(application:factory:coordinator:searchDisplayModel:stopsObserver:)`.

- [ ] **Step 1: Write the failing test**

Append to `OBAKitTests/Sheet/MapStopsObserverTests.swift`:

```swift
    /// The settled viewport's center is published so consumers can sort by it.
    @Test @MainActor
    func `Update viewport publishes its center`() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let observer = MapStopsObserver(application: application)
        #expect(observer.viewportCenter == nil)

        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        observer.updateViewport(region)

        #expect(observer.viewportCenter?.latitude == region.center.latitude)
        #expect(observer.viewportCenter?.longitude == region.center.longitude)
    }

    /// Zooming out clears the center along with the stops, so a stale center
    /// can't outlive the render set it was ordering.
    @Test @MainActor
    func `Reset clears the viewport center`() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let observer = MapStopsObserver(application: application)
        observer.updateViewport(MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        ))
        #expect(observer.viewportCenter != nil)

        observer.reset()

        #expect(observer.viewportCenter == nil)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS — no `viewportCenter` member.

- [ ] **Step 3: Publish the viewport center**

In `OBAKit/Sheet/Root/MapStopsObserver.swift`, add beside the private `viewport` property:

```swift
    /// Center of the last settled viewport, published so the home sheet's
    /// nearby section can order stops by it. Nil until the first settle, and
    /// cleared on `reset()` so a stale center never outlives its render set.
    @Published private(set) var viewportCenter: CLLocationCoordinate2D?
```

Set it in `updateViewport(_:)`:

```swift
    func updateViewport(_ region: MKCoordinateRegion) {
        viewport = region
        viewportCenter = region.center
        if pruneAccumulated() {
            publish()
        }
    }
```

and clear it in `reset()`:

```swift
    func reset() {
        accumulated.removeAll()
        viewport = nil
        viewportCenter = nil
        guard !stops.isEmpty else { return }
        stops = []
    }
```

- [ ] **Step 4: Move ownership to the controller**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`, add the stored property beside `searchDisplayModel` and extend the initializer. Extend the existing initializer doc-comment to cover it — the same "must be the instance the hosting view observes" reasoning applies:

```swift
    let stopsObserver: MapStopsObserver
```

```swift
    init(
        application: Application,
        onPresentTrip: @escaping (ArrivalDeparture) -> Void,
        onPresentVehicleTrip: @escaping (VehicleStatus) -> Void,
        coordinator: SheetCoordinator<AppSheetRoute>,
        searchDisplayModel: MapSearchDisplayModel,
        stopsObserver: MapStopsObserver
    ) {
        self.application = application
        self.onPresentTrip = onPresentTrip
        self.onPresentVehicleTrip = onPresentVehicleTrip
        self.coordinator = coordinator
        self.searchDisplayModel = searchDisplayModel
        self.stopsObserver = stopsObserver
    }
```

In `OBAKit/Sheet/Root/MapPanelRootController.swift`, build the observer before the factory and thread it into both:

```swift
        let bridge = TripPresentationBridge()
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let displayModel = MapSearchDisplayModel()
        // Built here, not inside `MapPanelRootView`, because the factory is
        // constructed first and the home sheet's nearby section must observe
        // the same instance the map renders from. Same reasoning as
        // `displayModel` above.
        let stopsObserver = MapStopsObserver(application: application)
        let factory = AppSheetViewFactory(
            application: application,
            onPresentTrip: { [weak bridge] arrival in bridge?.present(arrival) },
            onPresentVehicleTrip: { [weak bridge] vehicleStatus in bridge?.present(vehicleStatus: vehicleStatus) },
            coordinator: coordinator,
            searchDisplayModel: displayModel,
            stopsObserver: stopsObserver
        )
        let rootView = MapPanelRootView(
            application: application,
            factory: factory,
            coordinator: coordinator,
            searchDisplayModel: displayModel,
            stopsObserver: stopsObserver
        )
```

In `OBAKit/Sheet/Root/MapPanelRootView.swift`, change the property wrapper and the initializer, mirroring how `searchDisplay` is already handled:

```swift
    @ObservedObject private var stopsObserver: MapStopsObserver
```

```swift
    init(
        application: Application,
        factory: AppSheetViewFactory,
        coordinator: SheetCoordinator<AppSheetRoute>,
        searchDisplayModel: MapSearchDisplayModel,
        stopsObserver: MapStopsObserver
    ) {
        _coordinator = StateObject(wrappedValue: coordinator)
        _searchDisplay = ObservedObject(wrappedValue: searchDisplayModel)
        _stopsObserver = ObservedObject(wrappedValue: stopsObserver)
```

and delete the old `_stopsObserver = StateObject(wrappedValue: MapStopsObserver(application: application))` line. Everything else in the initializer is unchanged.

- [ ] **Step 5: Update the factory test helper**

In `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`, extend `makeFactory` so every existing test keeps compiling:

```swift
    @MainActor
    private func makeFactory(
        application: Application,
        coordinator: SheetCoordinator<AppSheetRoute> = SheetCoordinator(root: .home),
        displayModel: MapSearchDisplayModel = MapSearchDisplayModel(),
        stopsObserver: MapStopsObserver? = nil
    ) -> AppSheetViewFactory {
        AppSheetViewFactory(
            application: application,
            onPresentTrip: { _ in },
            onPresentVehicleTrip: { _ in },
            coordinator: coordinator,
            searchDisplayModel: displayModel,
            stopsObserver: stopsObserver ?? MapStopsObserver(application: application)
        )
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/MapStopsObserverTests \
  -only-testing:OBAKitTests/AppSheetViewFactoryTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS.

- [ ] **Step 7: Verify the map still works on device**

Launch the app on the iPhone 16 simulator, confirm stop pins still appear when zoomed in, disappear when zoomed out, and that bookmark pins render at all zoom levels. The unit tests do not cover the SwiftUI wiring this task changed, so this manual check is the real gate.

- [ ] **Step 8: Commit**

```bash
git add OBAKit/Sheet/Root/MapStopsObserver.swift \
        OBAKit/Sheet/Root/MapPanelRootController.swift \
        OBAKit/Sheet/Root/MapPanelRootView.swift \
        OBAKit/Sheet/DI/AppSheetViewFactory.swift \
        OBAKitTests/Sheet/MapStopsObserverTests.swift \
        OBAKitTests/Sheet/AppSheetViewFactoryTests.swift
git commit -m "refactor: hoist MapStopsObserver to the panel root and publish its viewport center"
```

---

## Task 7: Index-route assert exemption

**Files:**
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift:64-103,173-205`
- Modify: `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`

**Interfaces:**
- Consumes: `makeFactory(...)` from Task 6.
- Produces: `AppSheetViewFactory.indexPlaceholderView(for:) -> some View`.

- [ ] **Step 1: Write the failing test**

Append to `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`:

```swift
    /// The three index routes are wired for navigation before their screens
    /// exist, so they must render a placeholder instead of tripping the
    /// debug assertion that guards genuinely unwired routes.
    @Test @MainActor
    func `Index routes render a placeholder without asserting`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let factory = makeFactory(application: application)

        // Reaching `unimplementedView` would call assertionFailure and trap the
        // test run, so simply building each view is the assertion.
        for route in [AppSheetRoute.nearbyAll, .recentStopsAll, .bookmarksAll] {
            _ = factory.indexPlaceholderView(for: route)
        }

        #expect(Bool(true))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS — no `indexPlaceholderView(for:)`.

- [ ] **Step 3: Split the placeholder out of the assert path**

In `AppSheetViewFactory`, move the three routes out of the `unimplementedView` arm of `view(for:)`:

```swift
        case .nearbyAll, .recentStopsAll, .bookmarksAll:
            indexPlaceholderView(for: route)

        // Wiring a push for one of these routes before its view exists will
        // trip the debug assertion in `unimplementedView(for:)` — register the
        // view here before reaching for `SheetCoordinator.push(...)`.
        case .tripPlanner, .tripDetails, .transitAlert, .settings:
            unimplementedView(for: route)
```

and add the placeholder builder beside `unimplementedView`:

```swift
    /// The home sheet's section headers navigate to these three routes before
    /// their index screens exist, so they render the "coming soon" placeholder
    /// in every configuration rather than asserting. `unimplementedView` stays
    /// armed for routes nobody has wired a push for yet — remove a route from
    /// here once its real view is registered above.
    func indexPlaceholderView(for route: AppSheetRoute) -> some View {
        VStack(spacing: 4) {
            Text(OBALoc(
                "app_sheet.unimplemented_route.placeholder",
                value: "This screen is coming soon.",
                comment: "Placeholder shown in release builds when a sheet route is pushed but has no view registered."
            ))
            .font(.headline)
            .foregroundStyle(.secondary)
            Text(route.id)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/AppSheetViewFactoryTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/DI/AppSheetViewFactory.swift \
        OBAKitTests/Sheet/AppSheetViewFactoryTests.swift
git commit -m "feat: render a placeholder for the three index routes instead of asserting"
```

---

## Task 8: `HomeSheetSection` and `HomeSectionHeader`

Defines the section identity and its shared item limit **before** the section
models, so Tasks 9–12 all reference one already-existing constant rather than
forward-declaring each other's symbols.

**Files:**
- Create: `OBAKit/Sheet/Content/Home/HomeSheetSection.swift`
- Create: `OBAKit/Sheet/Content/Home/HomeSectionHeader.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum HomeSheetSection: Hashable { case nearby, recent, bookmarks }` with `static let itemLimit = 4`; `HomeSectionHeader(title: String, onSeeAll: () -> Void)`.

- [ ] **Step 1: Define the section identity and limit**

Create `OBAKit/Sheet/Content/Home/HomeSheetSection.swift`:

```swift
//
//  HomeSheetSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The home sheet's content sections, in the order they render.
///
/// Order is fixed: an empty earlier section is omitted, never replaced by a
/// later one. Declared as its own type — rather than inline in the view model —
/// so each section model can reference `itemLimit` without depending on the
/// view model that composes them.
enum HomeSheetSection: Hashable {
    case nearby
    case recent
    case bookmarks

    /// How many items each section previews before the header's chevron takes
    /// over. Defined once so the three sections can't drift apart.
    static let itemLimit = 4
}
```

- [ ] **Step 2: Write the header view**

The header has no unit test — it is a pure layout view with no logic worth asserting, and the repo does not snapshot-test SwiftUI views. Its behaviour is covered where it is used, in Task 13.

Create `OBAKit/Sheet/Content/Home/HomeSectionHeader.swift`:

```swift
//
//  HomeSectionHeader.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A home sheet section header: title on the left, chevron on the right, the
/// whole row acting as one button into that section's full index.
///
/// One button rather than a label plus a separate chevron button, so the tap
/// target matches what the row looks like and VoiceOver reads one element.
struct HomeSectionHeader: View {
    let title: String
    let onSeeAll: () -> Void

    private let brandColor = Color(uiColor: ThemeColors.shared.brand)

    var body: some View {
        Button(action: onSeeAll) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(brandColor)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(OBALoc(
            "home_sheet.section_header.a11y_hint",
            value: "Shows all items in this section.",
            comment: "VoiceOver hint for a home sheet section header, which opens that section's full list."
        ))
        .accessibilityAddTraits(.isButton)
    }
}

#if DEBUG
#Preview {
    HomeSectionHeader(title: "Nearby Stops") { }
        .padding()
}
#endif
```

- [ ] **Step 3: Build to verify it compiles**

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add OBAKit/Sheet/Content/Home/HomeSheetSection.swift \
        OBAKit/Sheet/Content/Home/HomeSectionHeader.swift
git commit -m "feat: add the home sheet section identity and header"
```

---

## Task 9: `HomeNearbyStopsSectionModel`

**Files:**
- Create: `OBAKit/Sheet/Content/Home/HomeNearbyStopsSectionModel.swift`
- Create: `OBAKitTests/Sheet/Home/HomeSectionModelTests.swift`

**Interfaces:**
- Consumes: `Stop.nearest(_:to:limit:)` (Task 1); `MapStopsObserver.viewportCenter` (Task 6).
- Produces: `HomeNearbyStopsSectionModel(observer:limit:)` with `@Published private(set) var stops: [Stop]`.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Sheet/Home/HomeSectionModelTests.swift`:

```swift
//
//  HomeSectionModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class HomeSectionModelTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Nearby

    /// The section caps at its limit and orders by the observer's viewport center.
    @Test @MainActor
    func `Nearby section publishes the nearest stops up to the limit`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        clearStopCache(for: application)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)
        observer.updateViewport(region)

        let model = HomeNearbyStopsSectionModel(observer: observer, limit: 4)

        #expect(model.stops.count == 4)
        let expected = Stop.nearest(observer.stops, to: region.center, limit: 4).map(\.id)
        #expect(model.stops.map(\.id) == expected)
    }

    /// Zooming out resets the observer, and the section empties with it.
    @Test @MainActor
    func `Nearby section empties when the observer resets`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        clearStopCache(for: application)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)
        observer.updateViewport(region)

        let model = HomeNearbyStopsSectionModel(observer: observer, limit: 4)
        #expect(!model.stops.isEmpty)

        observer.reset()

        #expect(model.stops.isEmpty)
    }

    /// Before the first settle there is no center to sort by, so the section
    /// shows the observer's own ordering rather than nothing at all.
    @Test @MainActor
    func `Nearby section falls back to observer order before the first settle`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        clearStopCache(for: application)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)
        // Deliberately no updateViewport — viewportCenter stays nil.

        let model = HomeNearbyStopsSectionModel(observer: observer, limit: 4)

        #expect(model.stops.map(\.id) == observer.stops.prefix(4).map(\.id))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS — no `HomeNearbyStopsSectionModel`.

- [ ] **Step 3: Write the implementation**

Create `OBAKit/Sheet/Content/Home/HomeNearbyStopsSectionModel.swift`:

```swift
//
//  HomeNearbyStopsSectionModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import OBAKitCore

/// The home sheet's nearby-stops preview: the few stops closest to the map's
/// center.
///
/// Reads `MapStopsObserver` rather than subscribing to `MapRegionManager`
/// itself. The observer is already that manager's subscriber, and a second
/// delegate would redo the accumulate-and-prune work on every map settle for
/// the sake of four rows. This costs no network requests at all — it re-slices
/// stops the map has already loaded.
@MainActor
final class HomeNearbyStopsSectionModel: ObservableObject {

    @Published private(set) var stops: [Stop] = []

    private let observer: MapStopsObserver
    private let limit: Int
    private var cancellables = Set<AnyCancellable>()

    init(observer: MapStopsObserver, limit: Int = HomeSheetSection.itemLimit) {
        self.observer = observer
        self.limit = limit

        observer.$stops
            .combineLatest(observer.$viewportCenter)
            .sink { [weak self] stops, center in
                self?.rebuild(stops: stops, center: center)
            }
            .store(in: &cancellables)
    }

    /// `combineLatest` emits on subscribe, so the initial state is set by the
    /// sink above rather than duplicated here.
    private func rebuild(stops: [Stop], center: CLLocationCoordinate2D?) {
        guard let center else {
            // No settle yet. The observer's id ordering is arbitrary but stable,
            // which beats rendering an empty section for the frame or two before
            // the first camera settle lands.
            self.stops = Array(stops.prefix(limit))
            return
        }
        self.stops = Stop.nearest(stops, to: center, limit: limit)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/HomeSectionModelTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/Content/Home/HomeNearbyStopsSectionModel.swift \
        OBAKitTests/Sheet/Home/HomeSectionModelTests.swift
git commit -m "feat: add the home sheet nearby stops section model"
```

---

## Task 10: `HomeRecentStopsSectionModel`

**Files:**
- Create: `OBAKit/Sheet/Content/Home/HomeRecentStopsSectionModel.swift`
- Modify: `OBAKitTests/Sheet/Home/HomeSectionModelTests.swift`

**Interfaces:**
- Consumes: `UserDataStore.recentStops(in:)` (Task 2).
- Produces: `HomeRecentStopsSectionModel(application:limit:)` with `@Published private(set) var stops: [Stop]` and `func reload()`.

- [ ] **Step 1: Write the failing test**

Append to `HomeSectionModelTests`:

```swift
    // MARK: - Recent

    /// The section caps at its limit and preserves the store's MRU ordering.
    @Test @MainActor
    func `Recent section caps at the limit in most recently used order`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        // Added oldest-first; the store inserts each at index 0, so the last
        // one added is the first one out.
        for stop in stops.prefix(6) {
            application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        }

        let model = HomeRecentStopsSectionModel(application: application, limit: 4)

        #expect(model.stops.count == 4)
        let expected = application.userDataStore
            .recentStops(in: application.currentRegion)
            .prefix(4)
            .map(\.id)
        #expect(model.stops.map(\.id) == Array(expected))
    }

    /// `reload()` picks up a stop added after construction.
    @Test @MainActor
    func `Recent section reload picks up newly added stops`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        let model = HomeRecentStopsSectionModel(application: application, limit: 4)
        #expect(model.stops.isEmpty)

        let stop = try #require(stops.first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        model.reload()

        #expect(model.stops.map(\.id) == [stop.id])
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS — no `HomeRecentStopsSectionModel`.

- [ ] **Step 3: Write the implementation**

Create `OBAKit/Sheet/Content/Home/HomeRecentStopsSectionModel.swift`:

```swift
//
//  HomeRecentStopsSectionModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The home sheet's recent-stops preview.
///
/// Backed entirely by `UserDataStore`, so it costs no network requests. Recents
/// are already stored most-recently-used first, so there is nothing to sort.
@MainActor
final class HomeRecentStopsSectionModel: ObservableObject {

    @Published private(set) var stops: [Stop] = []

    private let application: Application
    private let limit: Int

    init(application: Application, limit: Int = HomeSheetSection.itemLimit) {
        self.application = application
        self.limit = limit
        reload()
    }

    /// Re-reads the store. Called on activation and on region change — a
    /// region switch changes which recents are current, and the store posts no
    /// notification for it.
    func reload() {
        stops = Array(
            application.userDataStore
                .recentStops(in: application.currentRegion)
                .prefix(limit)
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/HomeSectionModelTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/Content/Home/HomeRecentStopsSectionModel.swift \
        OBAKitTests/Sheet/Home/HomeSectionModelTests.swift
git commit -m "feat: add the home sheet recent stops section model"
```

---

## Task 11: `HomeBookmarksSectionModel`

**Files:**
- Create: `OBAKit/Sheet/Content/Home/HomeBookmarksSectionModel.swift`
- Modify: `OBAKitTests/Sheet/Home/HomeSectionModelTests.swift`

**Interfaces:**
- Consumes: `BookmarkDataLoader.init(application:delegate:bookmarkProvider:autoRefreshes:)` (Task 4).
- Produces: `HomeBookmarksSectionModel(application:limit:)` with `@Published private(set) var rows: [BookmarkRowViewModel]`, `func refreshSelection()`, and `@discardableResult func loadIfNeeded(now:staleAfter:) -> Bool`.

- [ ] **Step 1: Write the failing test**

Append to `HomeSectionModelTests`:

```swift
    // MARK: - Bookmarks

    @MainActor
    private func seedBookmarks(count: Int, application: Application) throws -> [Bookmark] {
        let stops = try Fixtures.loadSomeStops()
        // sortOrder is assigned in reverse so the test proves the model sorts
        // rather than accidentally matching insertion order.
        return (0..<count).map { index in
            let bookmark = Bookmark(
                name: "Bookmark \(index)",
                regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
                stop: stops[index % stops.count]
            )
            bookmark.sortOrder = count - index
            application.userDataStore.add(bookmark, to: nil)
            return bookmark
        }
    }

    /// The four shown are chosen by `sortOrder`, not by insertion order —
    /// `findBookmarks(in:)` returns raw persisted order, so the model must sort.
    @Test @MainActor
    func `Bookmarks section selects by sort order up to the limit`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 6, application: application)

        let model = HomeBookmarksSectionModel(application: application, limit: 4)

        #expect(model.rows.count == 4)
        let sortOrders = model.rows.map(\.bookmark.sortOrder)
        #expect(sortOrders == sortOrders.sorted())
    }

    /// Whole-stop bookmarks have no trip to fetch, so they never report as
    /// having loaded arrival data and never carry departures.
    @Test @MainActor
    func `Bookmarks section leaves stop bookmarks without arrival data`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 2, application: application)

        let model = HomeBookmarksSectionModel(application: application, limit: 4)

        for row in model.rows {
            #expect(row.isTripBookmark == false)
            #expect(row.arrivalDepartures.isEmpty)
            #expect(row.hasLoadedArrivalData == false)
        }
    }

    /// A second activation inside the staleness window does not re-fetch.
    @Test @MainActor
    func `Bookmarks section skips a repeat load inside the staleness window`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 2, application: application)

        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        let start = Date()

        #expect(model.loadIfNeeded(now: start, staleAfter: 30))
        #expect(model.loadIfNeeded(now: start.addingTimeInterval(5), staleAfter: 30) == false)
    }

    /// Once the window lapses, the next activation re-fetches.
    @Test @MainActor
    func `Bookmarks section reloads after the staleness window lapses`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 2, application: application)

        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        let start = Date()

        #expect(model.loadIfNeeded(now: start, staleAfter: 30))
        #expect(model.loadIfNeeded(now: start.addingTimeInterval(31), staleAfter: 30))
    }

    /// A changed selection re-fetches even inside the staleness window —
    /// otherwise a newly added bookmark would show blank until the window lapsed.
    @Test @MainActor
    func `Bookmarks section reloads when the selection changes`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 2, application: application)

        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        let start = Date()
        #expect(model.loadIfNeeded(now: start, staleAfter: 30))

        _ = try seedBookmarks(count: 1, application: application)

        #expect(model.loadIfNeeded(now: start.addingTimeInterval(1), staleAfter: 30))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS — no `HomeBookmarksSectionModel`.

- [ ] **Step 3: Write the implementation**

Create `OBAKit/Sheet/Content/Home/HomeBookmarksSectionModel.swift`:

```swift
//
//  HomeBookmarksSectionModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The home sheet's bookmarks preview: the first few bookmarks by the user's
/// own ordering, with live arrivals for those few only.
///
/// Reuses `BookmarkDataLoader` — the same loader the Bookmarks tab uses — but
/// scoped to the displayed bookmarks and with auto-refresh off, so this screen
/// costs at most `limit` requests per activation and installs no polling timer.
///
/// Subclasses `NSObject` to adopt `BookmarkDataDelegate`.
@MainActor
final class HomeBookmarksSectionModel: NSObject, ObservableObject, BookmarkDataDelegate {

    @Published private(set) var rows: [BookmarkRowViewModel] = []

    /// The bookmarks a fetch is scoped to. Read by the loader's provider.
    private(set) var selection: [Bookmark] = []

    private let application: Application
    private let limit: Int
    private var loader: BookmarkDataLoader!

    private var lastFetchDate: Date?
    private var lastFetchedRegionID: Int?

    init(application: Application, limit: Int = HomeSheetSection.itemLimit) {
        self.application = application
        self.limit = limit
        super.init()

        // The provider reads `selection` at fetch time rather than capturing a
        // snapshot, so `refreshSelection()` before a load is enough to rescope
        // the next batch.
        self.loader = BookmarkDataLoader(
            application: application,
            delegate: self,
            bookmarkProvider: { [weak self] in self?.selection ?? [] },
            autoRefreshes: false
        )

        refreshSelection()
    }

    isolated deinit {
        loader?.cancelUpdates()
    }

    /// Re-reads which bookmarks belong on screen and rebuilds the rows.
    ///
    /// `findBookmarks(in:)` returns raw persisted order — only `bookmarksInGroup`
    /// sorts — so the sort here is what makes the four shown match the user's
    /// Manage Bookmarks ordering.
    func refreshSelection() {
        selection = Array(
            application.userDataStore
                .findBookmarks(in: application.currentRegion)
                .sorted { $0.sortOrder < $1.sortOrder }
                .prefix(limit)
        )
        rebuildRows()
    }

    /// Fetches arrivals for the current selection, but only when something has
    /// actually changed: the data is stale, the region moved, or the displayed
    /// bookmarks differ. Returns whether a fetch was started.
    ///
    /// The sheet system tears sheet content down and rebuilds it without the
    /// user navigating anywhere, so activation can fire repeatedly per visit —
    /// this gate is what keeps that from becoming repeated network traffic.
    @discardableResult
    func loadIfNeeded(now: Date = Date(), staleAfter: TimeInterval = 30) -> Bool {
        let previousIDs = selection.map(\.id)
        refreshSelection()

        let regionID = application.currentRegion?.regionIdentifier
        let selectionChanged = previousIDs != selection.map(\.id)
        let regionChanged = regionID != lastFetchedRegionID
        let isStale = lastFetchDate.map { now.timeIntervalSince($0) > staleAfter } ?? true

        guard selectionChanged || regionChanged || isStale else { return false }

        lastFetchDate = now
        lastFetchedRegionID = regionID
        loader.loadData()
        return true
    }

    // MARK: - Row Building

    /// Rebuilds the row snapshots from the loader's current arrival data.
    ///
    /// `highlightedTripIDs` is always empty: the flash-on-change affordance
    /// belongs to the polling Bookmarks tab, and nothing polls here.
    private func rebuildRows() {
        rows = selection.map { bookmark in
            BookmarkRowViewModel(
                bookmark: bookmark,
                arrivalDepartures: arrivalDepartures(for: bookmark),
                highlightedTripIDs: [],
                hasLoadedArrivalData: loader.hasFetchedData(forStopID: bookmark.stopID)
            )
        }
    }

    private func arrivalDepartures(for bookmark: Bookmark) -> [ArrivalDeparture] {
        guard let key = TripBookmarkKey(bookmark: bookmark) else { return [] }
        return loader.dataForKey(key)
    }

    // MARK: - BookmarkDataDelegate

    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        rebuildRows()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/HomeSectionModelTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/Content/Home/HomeBookmarksSectionModel.swift \
        OBAKitTests/Sheet/Home/HomeSectionModelTests.swift
git commit -m "feat: add the home sheet bookmarks section model with scoped arrivals"
```

---

## Task 12: `HomeSheetViewModel` composition

**Files:**
- Modify: `OBAKit/Sheet/Content/Home/HomeSheetViewModel.swift` (full rewrite)
- Create: `OBAKitTests/Sheet/Home/HomeSheetViewModelTests.swift`

**Interfaces:**
- Consumes: `HomeSheetSection` (Task 8) and all three section models (Tasks 9–11).
- Produces: `HomeSheetViewModel(application:stopsObserver:)`; `nearby`, `recent`, `bookmarks` child models; `func activate()`; `@Published private(set) var visibleSections: [HomeSheetSection]`.

- [ ] **Step 1: Write the failing test**

Create `OBAKitTests/Sheet/Home/HomeSheetViewModelTests.swift`:

```swift
//
//  HomeSheetViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class HomeSheetViewModelTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @MainActor
    private func makeViewModel(application: Application) -> HomeSheetViewModel {
        HomeSheetViewModel(
            application: application,
            stopsObserver: MapStopsObserver(application: application)
        )
    }

    /// With no data at all, every section is omitted — the view renders the
    /// all-empty state rather than three empty headers.
    @Test @MainActor
    func `Visible sections is empty when every section is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let viewModel = makeViewModel(application: application)

        #expect(viewModel.visibleSections.isEmpty)
    }

    /// An empty earlier section does not promote a later one — order is fixed.
    @Test @MainActor
    func `Visible sections keeps a fixed order when an earlier section is empty`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        // Seed recents only — nearby stays empty (no map settle) and bookmarks
        // stay empty (none stored).
        let stop = try #require(stops.first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let viewModel = makeViewModel(application: application)
        viewModel.activate()

        #expect(viewModel.visibleSections == [.recent])
    }

    /// Both populated sections appear, nearby-before-recent order intact.
    @Test @MainActor
    func `Visible sections lists nearby before recent`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        clearStopCache(for: application)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let observer = MapStopsObserver(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)
        observer.updateViewport(region)

        let viewModel = HomeSheetViewModel(application: application, stopsObserver: observer)
        viewModel.activate()

        #expect(viewModel.visibleSections == [.nearby, .recent])
    }

    /// Every section caps at the shared limit.
    @Test @MainActor
    func `Sections cap at the shared section limit`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        for stop in stops.prefix(HomeSheetSection.itemLimit + 3) {
            application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        }

        let viewModel = makeViewModel(application: application)
        viewModel.activate()

        #expect(viewModel.recent.stops.count == HomeSheetSection.itemLimit)
    }

    /// Two activations in quick succession issue one bookmark fetch.
    @Test @MainActor
    func `Activate twice in quick succession fetches bookmarks once`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        let bookmark = Bookmark(
            name: "Bookmark",
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: try #require(stops.first)
        )
        application.userDataStore.add(bookmark, to: nil)

        let viewModel = makeViewModel(application: application)
        let start = Date()

        #expect(viewModel.bookmarks.loadIfNeeded(now: start))
        #expect(viewModel.bookmarks.loadIfNeeded(now: start.addingTimeInterval(2)) == false)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: compile FAILS — `HomeSheetViewModel` has no `stopsObserver:` parameter and no `visibleSections`.

- [ ] **Step 3: Rewrite the view model**

Replace the contents of `OBAKit/Sheet/Content/Home/HomeSheetViewModel.swift`:

```swift
//
//  HomeSheetViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import OBAKitCore

// MARK: - HomeSheetViewModel

/// Owns the home sheet's reactive content state: the search bar's placeholder
/// and the three preview sections.
///
/// Composes three child section models rather than talking to the data sources
/// itself, so each section's rules stay separately readable and testable.
@MainActor
final class HomeSheetViewModel: NSObject, ObservableObject, RegionsServiceDelegate {

    let nearby: HomeNearbyStopsSectionModel
    let recent: HomeRecentStopsSectionModel
    let bookmarks: HomeBookmarksSectionModel

    /// Published rather than computed so a region change repaints the search bar.
    /// The UIKit panel gets this from its own `RegionsServiceDelegate` callback
    /// (`MapFloatingPanelController.regionsService(_:updatedRegion:)`); a plain
    /// computed property would leave the placeholder naming the old region until
    /// something unrelated happened to invalidate the view.
    @Published private(set) var searchPlaceholder: String

    /// Sections that currently have something to show, in render order. Empty
    /// sections are dropped entirely — header included.
    @Published private(set) var visibleSections: [HomeSheetSection] = []

    private let application: Application
    private var cancellables = Set<AnyCancellable>()

    init(application: Application, stopsObserver: MapStopsObserver) {
        self.application = application
        self.searchPlaceholder = SearchPlaceholder.text(for: application)
        self.nearby = HomeNearbyStopsSectionModel(observer: stopsObserver)
        self.recent = HomeRecentStopsSectionModel(application: application)
        self.bookmarks = HomeBookmarksSectionModel(application: application)
        super.init()

        // `RegionsService` holds delegates weakly, so there's nothing to unregister.
        application.regionsService.addDelegate(self)

        // Recompute the visible set whenever any child's content changes. The
        // children publish values, not the section list, so this is the single
        // place the order and the omission rule live.
        nearby.$stops
            .combineLatest(recent.$stops, bookmarks.$rows)
            .sink { [weak self] nearbyStops, recentStops, bookmarkRows in
                self?.updateVisibleSections(
                    hasNearby: !nearbyStops.isEmpty,
                    hasRecent: !recentStops.isEmpty,
                    hasBookmarks: !bookmarkRows.isEmpty
                )
            }
            .store(in: &cancellables)
    }

    /// Called when the sheet's content appears. Idempotent: the sheet system
    /// tears content down and rebuilds it without the user navigating anywhere,
    /// so this can fire several times per visit. The store reads are cheap and
    /// unconditional; only the bookmark fetch is gated.
    func activate() {
        recent.reload()
        bookmarks.loadIfNeeded()
    }

    private func updateVisibleSections(hasNearby: Bool, hasRecent: Bool, hasBookmarks: Bool) {
        var sections: [HomeSheetSection] = []
        if hasNearby { sections.append(.nearby) }
        if hasRecent { sections.append(.recent) }
        if hasBookmarks { sections.append(.bookmarks) }
        guard sections != visibleSections else { return }
        visibleSections = sections
    }

    // MARK: - RegionsServiceDelegate

    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        searchPlaceholder = SearchPlaceholder.text(for: application)
        // Which recents and bookmarks are "current" changed, and neither store
        // posts a notification for it.
        recent.reload()
        bookmarks.loadIfNeeded()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests/HomeSheetViewModelTests \
  -only-testing:OBAKitTests/HomeSectionModelTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Sheet/Content/Home/HomeSheetViewModel.swift \
        OBAKitTests/Sheet/Home/HomeSheetViewModelTests.swift
git commit -m "feat: compose the three preview sections in HomeSheetViewModel"
```

---

## Task 13: Render the sections in `HomeSheetView`

**Files:**
- Modify: `OBAKit/Sheet/Content/Home/HomeSheetView.swift` (full rewrite)
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift:107-109` (`homeView()`)

**Interfaces:**
- Consumes: `HomeSheetViewModel` (Task 12), `HomeSectionHeader` (Task 8), `SearchListRow.stop(...)` (Task 5), `AppSheetViewFactory.stopsObserver` (Task 6), `indexPlaceholderView` routes (Task 7).
- Produces: nothing downstream.

- [ ] **Step 1: Wire the factory**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`, pass the observer through:

```swift
    func homeView() -> HomeSheetView {
        HomeSheetView(
            application: self.application,
            viewModel: HomeSheetViewModel(
                application: self.application,
                stopsObserver: self.stopsObserver
            )
        )
    }
```

- [ ] **Step 2: Rewrite the view**

Replace the contents of `OBAKit/Sheet/Content/Home/HomeSheetView.swift`:

```swift
//
//  HomeSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

struct HomeSheetView: View {
    @StateObject private var viewModel: HomeSheetViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>

    /// Needed by `SearchListRow.stop(...)` for distance formatting. Passed in
    /// rather than read from the environment: there is no `Application`
    /// environment key in this codebase, and adding one for a single consumer
    /// would be a wider change than this task warrants. `obaFormatters` (used by
    /// the bookmark rows below) does exist, and is injected from here.
    private let application: Application

    init(
        application: Application,
        viewModel: @autoclosure @escaping () -> HomeSheetViewModel
    ) {
        self.application = application
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchBarRow
                    .padding(.top, 16)

                if viewModel.visibleSections.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.visibleSections, id: \.self) { section in
                        sectionView(for: section)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .task {
            viewModel.activate()
        }
    }

    // MARK: - Search Bar

    private var searchBarRow: some View {
        Button {
            coordinator.push(.search)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(viewModel.searchPlaceholder)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background { Capsule().fill(Color(.tertiarySystemFill)) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionView(for section: HomeSheetSection) -> some View {
        switch section {
        case .nearby:
            stopSection(
                title: Strings.nearbyStops,
                stops: viewModel.nearby.stops,
                destination: .nearbyAll,
                kind: { .nearbyStop(id: $0.id) }
            )
        case .recent:
            stopSection(
                title: Strings.recentStops,
                stops: viewModel.recent.stops,
                destination: .recentStopsAll,
                kind: { .recentStop(id: $0.id) }
            )
        case .bookmarks:
            bookmarksSection
        }
    }

    /// Nearby and Recent render identically — same row builder, same layout —
    /// and differ only in title, data, destination, and row kind.
    private func stopSection(
        title: String,
        stops: [Stop],
        destination: AppSheetRoute,
        kind: @escaping (Stop) -> SearchListRow.Kind
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: title) {
                coordinator.push(destination)
            }
            ForEach(stops, id: \.id) { stop in
                SearchListRowView(
                    row: SearchListRow.stop(
                        stop,
                        application: application,
                        kind: kind(stop),
                        onSelect: { coordinator.push(.stopDetails(stopID: stop.id)) }
                    )
                )
            }
        }
        .padding(.horizontal, 12)
    }

    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: Strings.bookmarks) {
                coordinator.push(.bookmarksAll)
            }
            ForEach(viewModel.bookmarks.rows) { row in
                Group {
                    if row.isTripBookmark {
                        BookmarkCardView(row: row)
                    } else {
                        StopBookmarkRow(row: row)
                    }
                }
                .contentShape(.rect)
                .onTapGesture {
                    coordinator.push(.stopDetails(stopID: row.stopID))
                }
            }
        }
        .padding(.horizontal, 12)
        .environment(\.obaFormatters, application.formatters)
    }

    /// Shown only when all three sections are empty — a first launch, or a map
    /// parked at region-level zoom with no saved data. Reuses the nearby
    /// controller's copy, minus its "Search Wider Area" button: that drives
    /// `MapRegionManager.preferredLoadDataRegionFudgeFactor` and a timed reset
    /// the SwiftUI path has no equivalent plumbing for.
    private var emptyState: some View {
        EmptyStateView(
            title: OBALoc(
                "nearby_controller.empty_set.title",
                value: "No Nearby Stops",
                comment: "Title for the empty set indicator on the Nearby controller"
            ),
            description: OBALoc(
                "nearby_controller.empty_set.body",
                value: "Zoom out or pan around to find some stops.",
                comment: "Body for the empty set indicator on the Nearby controller."
            ),
            systemImage: "mappin.slash"
        )
        .padding(.top, 40)
    }
}
```

> `\.obaFormatters` is declared in `OBAKitCore/SwiftUI/Environment/OBAFormattersKey.swift`
> and is what `BookmarkCardView` / `StopBookmarkRow` read. There is deliberately no
> `Application` environment key — do not add one.

- [ ] **Step 3: Build and run the full suite**

```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
xcodebuild test-without-building -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

Expected: the whole `OBAKitTests` target passes. Any failure outside the new suites is a regression from Tasks 1–7 and must be fixed before committing.

- [ ] **Step 4: Lint**

```bash
scripts/swiftlint.sh
```

Expected: no new violations. `HomeSheetView.body` is close to the type-check budget that already forced `buildSheetContent` out of `MapPanelRootView.body` — if the compiler reports "unable to type-check this expression in reasonable time", extract `sectionView(for:)`'s callers into a separate `@ViewBuilder` computed property rather than simplifying the layout.

- [ ] **Step 5: Verify on the simulator**

Launch on the iPhone 16 simulator and confirm:
- Dragging the home sheet up reveals the sections in order: Nearby, Recent, Bookmarks.
- Each section shows at most four rows.
- Tapping a row opens that stop's detail sheet.
- Tapping a section header opens the "coming soon" placeholder — and does **not** trap in a debug build.
- Panning the map re-orders the Nearby section.
- With no bookmarks and no recents, only the empty state shows.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Sheet/Content/Home/HomeSheetView.swift \
        OBAKit/Sheet/DI/AppSheetViewFactory.swift
git commit -m "feat: render nearby, recent, and bookmark sections on the home sheet"
```

---

## Verification Checklist

Run after Task 13, before considering the work done.

- [ ] Full `OBAKitTests` target passes on iPhone 16 / iOS 26.
- [ ] `scripts/swiftlint.sh` reports no new violations.
- [ ] `BookmarksViewModelTests`, `MapStopsObserverTests`, `SearchResultsSheetViewTests`, and `SearchInteractorTests` all pass **unchanged in behaviour** — they are the regression signal that the five extractions preserved the UIKit paths.
- [ ] Instrument or log-check that opening the home sheet issues **at most four** `arrivals-and-departures-for-stop` requests and **zero** additional `stops-for-location` requests.
- [ ] Re-opening the home sheet within 30 seconds issues **no** further arrivals requests.
- [ ] No `Co-Authored-By` or AI attribution in any commit message on the branch.
