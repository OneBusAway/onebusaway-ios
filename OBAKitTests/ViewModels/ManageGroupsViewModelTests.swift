//
//  ManageGroupsViewModelTests.swift
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

/// Tests for `ManageGroupsViewModel`. Covers group list access and the replace-all mutation.
class ManageGroupsViewModelTests: OBATestCase {
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

    private func createApplication(dataLoader: MockDataLoader) -> Application {
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
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )

        return Application(config: config)
    }

    // MARK: - bookmarkGroups

    @MainActor
    func test_bookmarkGroups_startsEmpty() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        expect(vm.bookmarkGroups).to(beEmpty())
    }

    @MainActor
    func test_bookmarkGroups_reflectsDataStore() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let group = BookmarkGroup(name: "Commute", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        expect(vm.bookmarkGroups).to(haveCount(1))
        expect(vm.bookmarkGroups.first?.name) == "Commute"
    }

    // MARK: - replaceGroups

    @MainActor
    func test_replaceGroups_updatesDataStore() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let old = BookmarkGroup(name: "Old Group", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: old)

        let newGroup1 = BookmarkGroup(name: "Alpha", sortOrder: 0)
        let newGroup2 = BookmarkGroup(name: "Beta", sortOrder: 1)
        vm.replaceGroups([newGroup1, newGroup2])

        expect(vm.bookmarkGroups).to(haveCount(2))
        expect(vm.bookmarkGroups.map(\.name)).to(contain("Alpha", "Beta"))
    }

    @MainActor
    func test_replaceGroups_withEmpty_clearsAllGroups() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        vm.replaceGroups([])

        expect(vm.bookmarkGroups).to(beEmpty())
    }

    @MainActor
    func test_replaceGroups_preservesExistingGroupIDs() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let existingID = UUID()
        let group = BookmarkGroup(name: "Original", id: existingID, sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let renamed = BookmarkGroup(name: "Renamed", id: existingID, sortOrder: 0)
        vm.replaceGroups([renamed])

        expect(vm.bookmarkGroups.first?.id) == existingID
        expect(vm.bookmarkGroups.first?.name) == "Renamed"
    }

    // MARK: - groups(from:)

    @MainActor
    func test_groupsFrom_convertsRowsToBookmarkGroups() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let rows: [(tag: String?, value: String?)] = [
            (tag: nil, value: "Alpha"),
            (tag: nil, value: "Beta")
        ]
        let groups = vm.groups(from: rows)

        expect(groups).to(haveCount(2))
        expect(groups[0].name) == "Alpha"
        expect(groups[0].sortOrder) == 0
        expect(groups[1].name) == "Beta"
        expect(groups[1].sortOrder) == 1
    }

    @MainActor
    func test_groupsFrom_skipsEmptyAndWhitespaceOnlyNames() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let rows: [(tag: String?, value: String?)] = [
            (tag: nil, value: "Valid"),
            (tag: nil, value: ""),
            (tag: nil, value: "   "),
            (tag: nil, value: nil)
        ]
        let groups = vm.groups(from: rows)

        expect(groups).to(haveCount(1))
        expect(groups[0].name) == "Valid"
    }

    @MainActor
    func test_groupsFrom_preservesExistingUUIDTags() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let existingID = UUID()
        let rows: [(tag: String?, value: String?)] = [
            (tag: existingID.uuidString, value: "Renamed Group")
        ]
        let groups = vm.groups(from: rows)

        expect(groups.first?.id) == existingID
        expect(groups.first?.name) == "Renamed Group"
    }

    @MainActor
    func test_groupsFrom_assignsFreshIDWhenTagIsNilOrInvalid() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let rows: [(tag: String?, value: String?)] = [
            (tag: nil, value: "New Group"),
            (tag: "not-a-uuid", value: "Another New Group")
        ]
        let groups = vm.groups(from: rows)

        expect(groups).to(haveCount(2))
        // IDs should be valid UUIDs (non-nil), just not the same as each other
        expect(groups[0].id) != groups[1].id
    }
}
