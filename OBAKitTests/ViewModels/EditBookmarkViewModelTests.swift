//
//  EditBookmarkViewModelTests.swift
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

// swiftlint:disable force_try

/// Tests for `EditBookmarkViewModel`. Covers initial state derivation, save outcome
/// routing (add vs edit, duplicate detection), persistence, and analytics emission.
class EditBookmarkViewModelTests: OBATestCase {
    var queue: OperationQueue!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func createApplicationWithoutRegion(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        // No startUpdates() and no fixedRegionName: currentLocation stays nil at RegionsService
        // init time, so currentRegion is never auto-selected and remains nil.
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader
        )
        return Application(config: config)
    }

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

    // MARK: - Initial State (Add Mode)

    @MainActor
    func test_addMode_initialName_usesStopFormattedTitle() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        expect(vm.isAddMode).to(beTrue())
        expect(vm.initialName) == Formatters.formattedTitle(stop: stop)
        expect(vm.initialGroupID) == ""
        expect(vm.initialIsFavorite).to(beTrue())
    }

    @MainActor
    func test_addMode_initialName_usesRouteAndHeadsignForTripBookmark() throws {
        let arrivalDep = try makeArrivalDeparture()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .arrivalDeparture(arrivalDep), bookmark: nil)

        expect(vm.isAddMode).to(beTrue())
        expect(vm.initialName) == arrivalDep.routeAndHeadsign
    }

    // MARK: - Initial State (Edit Mode)

    @MainActor
    func test_editMode_initialName_usesBookmarkName() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let bookmark = Bookmark(name: "My Custom Name", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)

        expect(vm.isAddMode).to(beFalse())
        expect(vm.initialName) == "My Custom Name"
    }

    @MainActor
    func test_editMode_initialGroupID_usesBookmarkGroupID() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let group = BookmarkGroup(name: "Commute", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: group)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)
        expect(vm.initialGroupID) == group.id.uuidString
    }

    // MARK: - bookmarkGroups

    @MainActor
    func test_bookmarkGroups_reflectsDataStore() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let stop = try makeStop()
        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        expect(vm.bookmarkGroups).to(beEmpty())

        let group = BookmarkGroup(name: "Commute", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        expect(vm.bookmarkGroups).to(haveCount(1))
    }

    // MARK: - currentGroupID

    @MainActor
    func test_currentGroupID_returnsEmptyInAddMode() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        expect(vm.currentGroupID()) == ""
    }

    @MainActor
    func test_currentGroupID_returnsGroupIDForExistingBookmark() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: group)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)

        expect(vm.currentGroupID()) == group.id.uuidString
    }

    // MARK: - prepareToSave (add mode)

    @MainActor
    func test_prepareToSave_returnsNil_whenCurrentRegionIsUnavailable() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplicationWithoutRegion(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "My Stop", isFavorite: true, selectedGroupID: "")

        expect(outcome).to(beNil())
    }

    @MainActor
    func test_prepareToSave_returnsReadyToSave_forNewStopBookmark() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "My Stop", isFavorite: true, selectedGroupID: "")

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            XCTFail("Expected .readyToSave, got \(String(describing: outcome))")
            return
        }
        expect(bookmark.name) == "My Stop"
        expect(isNew).to(beTrue())
    }

    @MainActor
    func test_prepareToSave_restoresDataObjectName_whenNameIsEmpty() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "   ", isFavorite: true, selectedGroupID: "")

        guard case .readyToSave(let bookmark, _) = outcome else {
            XCTFail("Expected .readyToSave"); return
        }
        expect(bookmark.name) == Formatters.formattedTitle(stop: stop)
    }

    @MainActor
    func test_prepareToSave_returnsDuplicateFound_whenBookmarkAlreadyExists() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let existing = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(existing, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true, selectedGroupID: "")

        guard case .duplicateFound(_, let isNew) = outcome else {
            XCTFail("Expected .duplicateFound, got \(String(describing: outcome))")
            return
        }
        expect(isNew).to(beTrue())
    }

    // MARK: - prepareToSave (edit mode)

    @MainActor
    func test_prepareToSave_editMode_mutatesExistingBookmark() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let bookmark = Bookmark(name: "Original", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)
        let outcome = vm.prepareToSave(name: "Updated Name", isFavorite: false, selectedGroupID: "")

        guard case .readyToSave(let saved, let isNew) = outcome else {
            XCTFail("Expected .readyToSave, got \(String(describing: outcome))")
            return
        }
        expect(saved.name) == "Updated Name"
        expect(saved.isFavorite).to(beFalse())
        expect(isNew).to(beFalse())
    }

    @MainActor
    func test_prepareToSave_editMode_restoresDataObjectName_whenNameIsEmpty() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let bookmark = Bookmark(name: "Original", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)
        let outcome = vm.prepareToSave(name: "   ", isFavorite: true, selectedGroupID: "")

        guard case .readyToSave(let saved, _) = outcome else {
            XCTFail("Expected .readyToSave"); return
        }
        expect(saved.name) == Formatters.formattedTitle(stop: stop)
    }

    @MainActor
    func test_prepareToSave_editMode_doesNotCheckForDuplicates() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true, selectedGroupID: "")

        guard case .readyToSave(_, let isNew) = outcome else {
            XCTFail("Expected .readyToSave (not .duplicateFound) in edit mode, got \(String(describing: outcome))")
            return
        }
        expect(isNew).to(beFalse())
    }

    // MARK: - persist

    @MainActor
    func test_persist_savesBookmarkToDataStore() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Home", isFavorite: false, selectedGroupID: "")

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            XCTFail("Expected .readyToSave"); return
        }

        vm.persist(bookmark, to: "", isNewBookmark: isNew)

        expect(app.userDataStore.findBookmark(id: bookmark.id)).toNot(beNil())
    }

    @MainActor
    func test_persist_savesToGroup_whenGroupIDIsProvided() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let group = BookmarkGroup(name: "Commute", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true, selectedGroupID: group.id.uuidString)

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            XCTFail("Expected .readyToSave"); return
        }

        vm.persist(bookmark, to: group.id.uuidString, isNewBookmark: isNew)

        let inGroup = app.userDataStore.bookmarksInGroup(group)
        expect(inGroup).to(containElementSatisfying { $0.id == bookmark.id })
    }

    @MainActor
    func test_persist_editMode_movesToNewGroup() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let groupA = BookmarkGroup(name: "Group A", sortOrder: 0)
        let groupB = BookmarkGroup(name: "Group B", sortOrder: 1)
        app.userDataStore.upsert(bookmarkGroup: groupA)
        app.userDataStore.upsert(bookmarkGroup: groupB)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: groupA)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true, selectedGroupID: groupB.id.uuidString)

        guard case .readyToSave(let saved, let isNew) = outcome else {
            XCTFail("Expected .readyToSave"); return
        }

        vm.persist(saved, to: groupB.id.uuidString, isNewBookmark: isNew)

        expect(app.userDataStore.bookmarksInGroup(groupB)).to(containElementSatisfying { $0.id == bookmark.id })
    }

    @MainActor
    func test_persist_reportsAnalyticsForNewTripBookmark() throws {
        let arrivalDep = try makeArrivalDeparture()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)

        let vm = EditBookmarkViewModel(application: app, source: .arrivalDeparture(arrivalDep), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Route", isFavorite: true, selectedGroupID: "")

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            XCTFail("Expected .readyToSave"); return
        }

        vm.persist(bookmark, to: "", isNewBookmark: isNew)

        let addBookmarkEvents = analyticsMock.reportedEvents.filter { $0.label == AnalyticsLabels.addBookmark }
        expect(addBookmarkEvents).to(haveCount(1))
    }

    @MainActor
    func test_persist_doesNotReportAnalyticsWhenEditingExistingTripBookmark() throws {
        let arrivalDep = try makeArrivalDeparture()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)

        let existing = Bookmark(name: "Route", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep)
        app.userDataStore.add(existing, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .arrivalDeparture(arrivalDep), bookmark: existing)
        let outcome = vm.prepareToSave(name: "Updated Route", isFavorite: true, selectedGroupID: "")

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            XCTFail("Expected .readyToSave"); return
        }

        vm.persist(bookmark, to: "", isNewBookmark: isNew)

        expect(analyticsMock.reportedEvents.filter { $0.label == AnalyticsLabels.addBookmark }).to(beEmpty())
    }

    @MainActor
    func test_persist_doesNotReportAnalyticsForStopBookmark() throws {
        let stop = try makeStop()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true, selectedGroupID: "")

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            XCTFail("Expected .readyToSave"); return
        }

        vm.persist(bookmark, to: "", isNewBookmark: isNew)

        let addBookmarkEvents = analyticsMock.reportedEvents.filter { $0.label == AnalyticsLabels.addBookmark }
        expect(addBookmarkEvents).to(beEmpty())
    }
}
