//
//  ManageBookmarksViewModelTests.swift
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

/// Tests for `ManageBookmarksViewModel`. Covers data access delegation, bookmark deletion
/// (with analytics), name persistence, transit-name restoration, and reorder logic.
@Suite(.serialized)
final class ManageBookmarksViewModelTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func createApplication(dataLoader: MockDataLoader, analytics: AnalyticsMock = AnalyticsMock()) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        locationService.startUpdates()

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: analytics,
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )

        return Application(config: config)
    }

    private func makeStop() throws -> Stop {
        try Fixtures.loadSomeStops().first!
    }

    private func makeArrivalDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    // MARK: - Data Access

    @Test @MainActor
    func `Bookmark groups reflects data store`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        #expect(vm.bookmarkGroups.isEmpty)

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        #expect(vm.bookmarkGroups.count == 1)
    }

    @Test @MainActor
    func `Bookmarks in group returns correct subset`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let group = BookmarkGroup(name: "Commute", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let grouped = Bookmark(name: "Stop A", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(grouped, to: group)

        let ungrouped = Bookmark(name: "Stop B", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(ungrouped, to: nil)

        #expect(vm.bookmarksInGroup(group).count == 1)
        #expect(vm.bookmarksInGroup(nil).count == 1)
    }

    @Test @MainActor
    func `Find group returns group by ID`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let group = BookmarkGroup(name: "Home", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        #expect(vm.findGroup(id: group.id) == group)
        #expect(vm.findGroup(id: UUID()) == nil)
    }

    @Test @MainActor
    func `Find bookmark returns by ID`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        #expect(vm.findBookmark(id: bookmark.id) != nil)
        #expect(vm.findBookmark(id: UUID()) == nil)
    }

    // MARK: - deleteBookmark

    @Test @MainActor
    func `Delete bookmark removes from data store`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.deleteBookmark(bookmark)

        #expect(app.userDataStore.findBookmark(id: bookmark.id) == nil)
    }

    @Test @MainActor
    func `Delete bookmark reports analytics for trip bookmark`() throws {
        let arrivalDep = try makeArrivalDeparture()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Route", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep)
        app.userDataStore.add(bookmark, to: nil)

        vm.deleteBookmark(bookmark)

        let removeEvents = analyticsMock.reportedEvents.filter { $0.label == AnalyticsLabels.removeBookmark }
        #expect(removeEvents.count == 1)
        let expectedValue = AnalyticsLabels.addRemoveBookmarkValue(
            routeID: bookmark.routeID!,
            headsign: bookmark.tripHeadsign,
            stopID: bookmark.stopID
        )
        #expect((removeEvents.first?.value as? String) == expectedValue)
    }

    @Test @MainActor
    func `Delete bookmark no analytics for stop bookmark`() throws {
        let stop = try makeStop()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.deleteBookmark(bookmark)

        #expect(analyticsMock.reportedEvents.isEmpty)
    }

    // MARK: - saveNameChange

    @Test @MainActor
    func `Save name change persists non empty name`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Old Name", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.saveNameChange(bookmarkID: bookmark.id, newName: "New Name")

        #expect(app.userDataStore.findBookmark(id: bookmark.id)?.name == "New Name")
    }

    @Test @MainActor
    func `Save name change ignores empty name`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Original", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.saveNameChange(bookmarkID: bookmark.id, newName: "   ")

        #expect(app.userDataStore.findBookmark(id: bookmark.id)?.name == "Original")
    }

    // MARK: - restoreTransitName

    @Test @MainActor
    func `Restore transit name restores stop formatted title for stop bookmark`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Override", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.restoreTransitName(for: bookmark)

        let expected = Formatters.formattedTitle(stop: stop)
        #expect(app.userDataStore.findBookmark(id: bookmark.id)?.name == expected)
    }

    @Test @MainActor
    func `Restore transit name restores trip name for trip bookmark`() throws {
        let arrivalDep = try makeArrivalDeparture()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Custom", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep)
        app.userDataStore.add(bookmark, to: nil)

        vm.restoreTransitName(for: bookmark)

        let expected = "\(arrivalDep.routeShortName) - \(arrivalDep.tripHeadsign!)"
        #expect(app.userDataStore.findBookmark(id: bookmark.id)?.name == expected)
    }

    // MARK: - moveBookmark

    @Test @MainActor
    func `Move bookmark moves bookmark to destination group`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.moveBookmark(bookmark, to: group, at: 0)

        #expect(vm.bookmarksInGroup(group).count == 1)
        #expect(vm.bookmarksInGroup(nil).isEmpty)
    }

    @Test @MainActor
    func `Move bookmark respects index parameter`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let first = Bookmark(name: "First", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        let second = Bookmark(name: "Second", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(first, to: group, index: 0)
        app.userDataStore.add(second, to: group, index: 1)

        let incoming = Bookmark(name: "Incoming", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(incoming, to: nil)

        vm.moveBookmark(incoming, to: group, at: 1)

        let bookmarks = vm.bookmarksInGroup(group)
        #expect(bookmarks.count == 3)
        #expect(bookmarks[1].id == incoming.id)
    }

    // MARK: - Rows

    /// Builds groups "Work" (bookmarks A, B) and "Home" (C), plus ungrouped D.
    @MainActor
    private func makeGroupedBookmarks(_ app: Application) throws -> (work: BookmarkGroup, home: BookmarkGroup, a: Bookmark, b: Bookmark, c: Bookmark, d: Bookmark) {
        let stop = try makeStop()
        let work = BookmarkGroup(name: "Work", sortOrder: 0)
        let home = BookmarkGroup(name: "Home", sortOrder: 1)
        app.userDataStore.replaceBookmarkGroups(with: [work, home])
        func make(_ name: String, _ group: BookmarkGroup?) -> Bookmark {
            let bookmark = Bookmark(name: name, regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
            app.userDataStore.add(bookmark, to: group)
            return bookmark
        }
        return (work, home, make("A", work), make("B", work), make("C", home), make("D", nil))
    }

    @MainActor
    private func rowSummary(_ vm: ManageBookmarksViewModel) -> [String] {
        vm.rows.map { row in
            switch row {
            case .header(_, let title): "[\(title)]"
            case .bookmark(let bookmark): bookmark.name
            }
        }
    }

    @Test @MainActor
    func `Rows list each group's header and bookmarks, then ungrouped`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        _ = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app, ungroupedTitle: "Bookmarks")

        #expect(rowSummary(vm) == ["[Work]", "A", "B", "[Home]", "C", "[Bookmarks]", "D"])
    }

    @Test @MainActor
    func `Move rows reorders within a group`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let fixture = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app, ungroupedTitle: "Bookmarks")

        // Drag B (row 2) above A (row 1).
        vm.moveRows(from: IndexSet(integer: 2), to: 1)

        #expect(vm.bookmarksInGroup(fixture.work).map(\.name) == ["B", "A"])
        #expect(rowSummary(vm) == ["[Work]", "B", "A", "[Home]", "C", "[Bookmarks]", "D"])
    }

    @Test @MainActor
    func `Move rows moves a bookmark into another group`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let fixture = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app, ungroupedTitle: "Bookmarks")

        // Drag A (row 1) to just below C (end of Home, before the ungrouped header at 5).
        vm.moveRows(from: IndexSet(integer: 1), to: 5)

        #expect(vm.bookmarksInGroup(fixture.work).map(\.name) == ["B"])
        #expect(vm.bookmarksInGroup(fixture.home).map(\.name) == ["C", "A"])
    }

    @Test @MainActor
    func `Move rows into the ungrouped section clears the group`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let fixture = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app, ungroupedTitle: "Bookmarks")

        // Drag C (row 4) to the very end.
        vm.moveRows(from: IndexSet(integer: 4), to: vm.rows.count)

        #expect(vm.bookmarksInGroup(fixture.home).isEmpty)
        #expect(vm.bookmarksInGroup(nil).map(\.name) == ["D", "C"])
    }

    @Test @MainActor
    func `Move rows above every header lands first in the first group`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let fixture = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app, ungroupedTitle: "Bookmarks")

        // Drag D (last row) to the very top, above the Work header.
        vm.moveRows(from: IndexSet(integer: 6), to: 0)

        #expect(vm.bookmarksInGroup(fixture.work).map(\.name) == ["D", "A", "B"])
        #expect(rowSummary(vm).first == "[Work]")
    }

    @Test @MainActor
    func `Move rows ignores header rows`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        _ = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app, ungroupedTitle: "Bookmarks")
        let before = rowSummary(vm)

        vm.moveRows(from: IndexSet(integer: 3), to: 0)

        #expect(rowSummary(vm) == before)
    }

    @Test @MainActor
    func `Delete rows deletes bookmarks and skips headers`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let fixture = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app, ungroupedTitle: "Bookmarks")

        vm.deleteRows(at: IndexSet([0, 1]))

        #expect(app.userDataStore.findBookmark(id: fixture.a.id) == nil)
        #expect(app.userDataStore.bookmarkGroups.count == 2)
        #expect(rowSummary(vm) == ["[Work]", "B", "[Home]", "C", "[Bookmarks]", "D"])
    }

    @Test @MainActor
    func `Restore empty bookmark names restores only blank rows`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let fixture = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app, ungroupedTitle: "Bookmarks")
        let editable = vm.rows.compactMap { row -> ManageBookmarksViewModel.EditableBookmark? in
            if case .bookmark(let bookmark) = row { bookmark } else { nil }
        }

        editable[0].name = "   "
        vm.restoreEmptyBookmarkNames()

        let restored = try #require(app.userDataStore.findBookmark(id: fixture.a.id))
        #expect(restored.name == Formatters.formattedTitle(stop: restored.stop))
        #expect(editable[0].name == restored.name)
        #expect(app.userDataStore.findBookmark(id: fixture.b.id)?.name == "B")
    }

    @Test @MainActor
    func `Reload rows keeps the same editable instance for a bookmark`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        _ = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app, ungroupedTitle: "Bookmarks")
        guard case .bookmark(let before) = vm.rows[1] else { Issue.record("expected a bookmark row"); return }

        vm.reloadRows()

        guard case .bookmark(let after) = vm.rows[1] else { Issue.record("expected a bookmark row"); return }
        #expect(before === after)
    }

    @Test @MainActor
    func `Save name change keeps the bookmark's position`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let fixture = try makeGroupedBookmarks(app)
        let vm = ManageBookmarksViewModel(application: app)

        vm.saveNameChange(bookmarkID: fixture.a.id, newName: "Renamed")

        #expect(vm.bookmarksInGroup(fixture.work).map(\.name) == ["Renamed", "B"])
    }
}
