//
//  EditBookmarkViewModelTests.swift
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

/// Tests for `EditBookmarkViewModel`. Covers initial state derivation, save outcome
/// routing (add vs edit, duplicate detection), persistence, and analytics emission.
@Suite(.serialized)
final class EditBookmarkViewModelTests: OBATestCase {
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
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    // MARK: - Initial State (Add Mode)

    @Test @MainActor
    func `Add mode initial name uses stop formatted title`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        #expect(vm.isAddMode)
        #expect(vm.initialName == Formatters.formattedTitle(stop: stop))
        #expect(vm.initialGroupID == nil)
        #expect(vm.initialIsFavorite)
    }

    @Test @MainActor
    func `Add mode initial name uses route and headsign for trip bookmark`() throws {
        let arrivalDep = try makeArrivalDeparture()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .arrivalDeparture(arrivalDep), bookmark: nil)

        #expect(vm.isAddMode)
        #expect(vm.initialName == arrivalDep.routeAndHeadsign)
    }

    // MARK: - Initial State (Edit Mode)

    @Test @MainActor
    func `Edit mode initial name uses bookmark name`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let bookmark = Bookmark(name: "My Custom Name", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)

        #expect(!vm.isAddMode)
        #expect(vm.initialName == "My Custom Name")
    }

    @Test @MainActor
    func `Edit mode initial group ID uses bookmark group ID`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let group = BookmarkGroup(name: "Commute", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: group)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)
        #expect(vm.initialGroupID == group.id)
    }

    // MARK: - bookmarkGroups

    @Test @MainActor
    func `Bookmark groups reflects data store`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let stop = try makeStop()
        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        #expect(vm.bookmarkGroups.isEmpty)

        let group = BookmarkGroup(name: "Commute", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        #expect(vm.bookmarkGroups.count == 1)
    }

    // MARK: - currentGroupID

    @Test @MainActor
    func `Current group ID returns nil in add mode`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        #expect(vm.currentGroupID() == nil)
    }

    @Test @MainActor
    func `Current group ID returns group ID for existing bookmark`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: group)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)

        #expect(vm.currentGroupID() == group.id)
    }

    @Test @MainActor
    func `Current group ID reflects live move diverging from initial group ID`() throws {
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
        #expect(vm.initialGroupID == groupA.id)

        // Simulate another screen moving the bookmark while this VM is alive.
        app.userDataStore.add(bookmark, to: groupB)

        #expect(vm.currentGroupID() == groupB.id)
        #expect(vm.initialGroupID == groupA.id)
    }

    // MARK: - prepareToSave (add mode)

    @Test @MainActor
    func `Prepare to save returns region unavailable when current region is unavailable`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplicationWithoutRegion(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "My Stop", isFavorite: true)

        guard case .regionUnavailable = outcome else {
            Issue.record("Expected .regionUnavailable, got \(outcome)")
            return
        }
    }

    @Test @MainActor
    func `Prepare to save returns ready for new stop bookmark`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "My Stop", isFavorite: true)

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            Issue.record("Expected .readyToSave, got \(outcome)")
            return
        }
        #expect(bookmark.name == "My Stop")
        #expect(isNew)
    }

    @Test @MainActor
    func `Prepare to save restores data object name when name is empty`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "   ", isFavorite: true)

        guard case .readyToSave(let bookmark, _) = outcome else {
            Issue.record("Expected .readyToSave"); return
        }
        #expect(bookmark.name == Formatters.formattedTitle(stop: stop))
    }

    @Test @MainActor
    func `Prepare to save returns duplicate when bookmark already exists`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let existing = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(existing, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true)

        guard case .duplicateRequiresConfirmation(let dup) = outcome else {
            Issue.record("Expected .duplicateRequiresConfirmation, got \(outcome)")
            return
        }
        #expect(dup.name == "Stop")
    }

    // MARK: - prepareToSave (edit mode)

    @Test @MainActor
    func `Prepare to save edit mode does not mutate bookmark until persist`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let bookmark = Bookmark(name: "Original", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        bookmark.isFavorite = true
        app.userDataStore.add(bookmark, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)
        let outcome = vm.prepareToSave(name: "Updated Name", isFavorite: false)

        guard case .readyToSave(let saved, let isNew) = outcome else {
            Issue.record("Expected .readyToSave, got \(outcome)")
            return
        }
        #expect(saved.name == "Original")
        #expect(saved.isFavorite)
        #expect(!isNew)

        vm.persist(saved, name: "Updated Name", isFavorite: false, to: nil, isNewBookmark: isNew)
        #expect(saved.name == "Updated Name")
        #expect(!saved.isFavorite)
    }

    @Test @MainActor
    func `Persist edit mode restores data object name when name is empty`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let bookmark = Bookmark(name: "Original", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)
        let outcome = vm.prepareToSave(name: "   ", isFavorite: true)

        guard case .readyToSave(let saved, let isNew) = outcome else {
            Issue.record("Expected .readyToSave"); return
        }
        vm.persist(saved, name: "   ", isFavorite: true, to: nil, isNewBookmark: isNew)
        #expect(saved.name == Formatters.formattedTitle(stop: stop))
    }

    @Test @MainActor
    func `Prepare to save edit mode does not check for duplicates`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        app.userDataStore.add(bookmark, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: bookmark)
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true)

        guard case .readyToSave(_, let isNew) = outcome else {
            Issue.record("Expected .readyToSave, got \(outcome)")
            return
        }
        #expect(!isNew)
    }

    // MARK: - persist

    @Test @MainActor
    func `Persist saves bookmark to data store`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Home", isFavorite: false)

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            Issue.record("Expected .readyToSave"); return
        }

        vm.persist(bookmark, name: "Home", isFavorite: false, to: nil, isNewBookmark: isNew)

        #expect(app.userDataStore.findBookmark(id: bookmark.id) != nil)
    }

    @Test @MainActor
    func `Persist saves to group when group ID is provided`() throws {
        let stop = try makeStop()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let group = BookmarkGroup(name: "Commute", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true)

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            Issue.record("Expected .readyToSave"); return
        }

        vm.persist(bookmark, name: "Stop", isFavorite: true, to: group.id, isNewBookmark: isNew)

        let inGroup = app.userDataStore.bookmarksInGroup(group)
        #expect(inGroup.contains { $0.id == bookmark.id })
    }

    @Test @MainActor
    func `Persist edit mode moves to new group`() throws {
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
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true)

        guard case .readyToSave(let saved, let isNew) = outcome else {
            Issue.record("Expected .readyToSave"); return
        }

        vm.persist(saved, name: "Stop", isFavorite: true, to: groupB.id, isNewBookmark: isNew)

        #expect(app.userDataStore.bookmarksInGroup(groupB).contains { $0.id == bookmark.id })
    }

    @Test @MainActor
    func `Persist reports analytics for new trip bookmark`() throws {
        let arrivalDep = try makeArrivalDeparture()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)

        let vm = EditBookmarkViewModel(application: app, source: .arrivalDeparture(arrivalDep), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Route", isFavorite: true)

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            Issue.record("Expected .readyToSave"); return
        }

        vm.persist(bookmark, name: "Route", isFavorite: true, to: nil, isNewBookmark: isNew)

        let addBookmarkEvents = analyticsMock.reportedEvents.filter { $0.label == AnalyticsLabels.addBookmark }
        #expect(addBookmarkEvents.count == 1)
        let expectedValue = AnalyticsLabels.addRemoveBookmarkValue(
            routeID: arrivalDep.routeID,
            headsign: arrivalDep.tripHeadsign,
            stopID: arrivalDep.stopID
        )
        #expect((addBookmarkEvents.first?.value as? String) == expectedValue)
    }

    @Test @MainActor
    func `Persist does not report analytics when editing existing trip bookmark`() throws {
        let arrivalDep = try makeArrivalDeparture()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)

        let existing = Bookmark(name: "Route", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep)
        app.userDataStore.add(existing, to: nil)

        let vm = EditBookmarkViewModel(application: app, source: .arrivalDeparture(arrivalDep), bookmark: existing)
        let outcome = vm.prepareToSave(name: "Updated Route", isFavorite: true)

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            Issue.record("Expected .readyToSave"); return
        }

        vm.persist(bookmark, name: "Updated Route", isFavorite: true, to: nil, isNewBookmark: isNew)

        #expect(analyticsMock.reportedEvents.filter { $0.label == AnalyticsLabels.addBookmark }.isEmpty)
    }

    @Test @MainActor
    func `Persist does not report analytics for stop bookmark`() throws {
        let stop = try makeStop()
        let analyticsMock = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, analytics: analyticsMock)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Stop", isFavorite: true)

        guard case .readyToSave(let bookmark, let isNew) = outcome else {
            Issue.record("Expected .readyToSave"); return
        }

        vm.persist(bookmark, name: "Stop", isFavorite: true, to: nil, isNewBookmark: isNew)

        let addBookmarkEvents = analyticsMock.reportedEvents.filter { $0.label == AnalyticsLabels.addBookmark }
        #expect(addBookmarkEvents.isEmpty)
    }
}
