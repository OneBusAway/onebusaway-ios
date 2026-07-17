//
//  ManageBookmarksViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `ManageBookmarksViewModel`. Covers data access delegation, bookmark deletion
/// (with analytics), name persistence, transit-name restoration, and reorder logic.
class ManageBookmarksViewModelTests: OBATestCase {
    var queue: OperationQueue!

    override func setUp() async throws {
        try await super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() async throws {
        try await super.tearDown()
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
        return try XCTUnwrap(stopArrivals.arrivalsAndDepartures.first)
    }

    // MARK: - Data Access

    @MainActor
    func test_bookmarkGroups_reflectsDataStore() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        expect(vm.bookmarkGroups).to(beEmpty())

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        expect(vm.bookmarkGroups).to(haveCount(1))
    }

    @MainActor
    func test_bookmarksInGroup_returnsCorrectSubset() throws {
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

        expect(vm.bookmarksInGroup(group)).to(haveCount(1))
        expect(vm.bookmarksInGroup(nil)).to(haveCount(1))
    }

    @MainActor
    func test_findGroup_returnsGroupByID() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let group = BookmarkGroup(name: "Home", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        expect(vm.findGroup(id: group.id)) == group
        expect(vm.findGroup(id: UUID())).to(beNil())
    }

    @MainActor
    func test_findBookmark_returnsByID() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        expect(vm.findBookmark(id: bookmark.id)).toNot(beNil())
        expect(vm.findBookmark(id: UUID())).to(beNil())
    }

    // MARK: - deleteBookmark

    @MainActor
    func test_deleteBookmark_removesFromDataStore() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.deleteBookmark(bookmark)

        expect(app.userDataStore.findBookmark(id: bookmark.id)).to(beNil())
    }

    @MainActor
    func test_deleteBookmark_reportsAnalyticsForTripBookmark() throws {
        let arrivalDep = try makeArrivalDeparture()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Route", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep)
        app.userDataStore.add(bookmark, to: nil)

        vm.deleteBookmark(bookmark)

        let removeEvents = analyticsMock.reportedEvents.filter { $0.label == AnalyticsLabels.removeBookmark }
        expect(removeEvents).to(haveCount(1))
        let expectedValue = AnalyticsLabels.addRemoveBookmarkValue(
            routeID: bookmark.routeID!,
            headsign: bookmark.tripHeadsign,
            stopID: bookmark.stopID
        )
        expect(removeEvents.first?.value as? String) == expectedValue
    }

    @MainActor
    func test_deleteBookmark_noAnalyticsForStopBookmark() throws {
        let stop = try makeStop()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.deleteBookmark(bookmark)

        expect(analyticsMock.reportedEvents).to(beEmpty())
    }

    // MARK: - saveNameChange

    @MainActor
    func test_saveNameChange_persistsNonEmptyName() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Old Name", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.saveNameChange(bookmarkID: bookmark.id, newName: "New Name")

        expect(app.userDataStore.findBookmark(id: bookmark.id)?.name) == "New Name"
    }

    @MainActor
    func test_saveNameChange_ignoresEmptyName() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Original", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.saveNameChange(bookmarkID: bookmark.id, newName: "   ")

        expect(app.userDataStore.findBookmark(id: bookmark.id)?.name) == "Original"
    }

    // MARK: - restoreTransitName

    @MainActor
    func test_restoreTransitName_restoresStopFormattedTitleForStopBookmark() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Override", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.restoreTransitName(for: bookmark)

        let expected = Formatters.formattedTitle(stop: stop)
        expect(app.userDataStore.findBookmark(id: bookmark.id)?.name) == expected
    }

    @MainActor
    func test_restoreTransitName_restoresTripNameForTripBookmark() throws {
        let arrivalDep = try makeArrivalDeparture()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let bookmark = Bookmark(name: "Custom", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep)
        app.userDataStore.add(bookmark, to: nil)

        vm.restoreTransitName(for: bookmark)

        let expected = "\(arrivalDep.routeShortName) - \(arrivalDep.tripHeadsign!)"
        expect(app.userDataStore.findBookmark(id: bookmark.id)?.name) == expected
    }

    // MARK: - moveBookmark

    @MainActor
    func test_moveBookmark_movesBookmarkToDestinationGroup() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageBookmarksViewModel(application: app)

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        vm.moveBookmark(bookmark, to: group, at: 0)

        expect(vm.bookmarksInGroup(group)).to(haveCount(1))
        expect(vm.bookmarksInGroup(nil)).to(beEmpty())
    }

    @MainActor
    func test_moveBookmark_respectsIndexParameter() throws {
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
        expect(bookmarks).to(haveCount(3))
        expect(bookmarks[1].id) == incoming.id
    }
}
