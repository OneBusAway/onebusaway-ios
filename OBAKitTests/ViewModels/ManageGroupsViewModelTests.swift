//
//  ManageGroupsViewModelTests.swift
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

/// Tests for `ManageGroupsViewModel`. Covers group list access and the replace-all mutation.
@Suite(.serialized)
final class ManageGroupsViewModelTests: OBATestCase {
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

    @Test @MainActor
    func `Bookmark groups starts empty`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        #expect(vm.bookmarkGroups.isEmpty)
    }

    @Test @MainActor
    func `Bookmark groups reflects data store`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let group = BookmarkGroup(name: "Commute", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        #expect(vm.bookmarkGroups.count == 1)
        #expect(vm.bookmarkGroups.first?.name == "Commute")
    }

    // MARK: - replaceGroups

    @Test @MainActor
    func `Replace groups updates data store`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let old = BookmarkGroup(name: "Old Group", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: old)

        let newGroup1 = BookmarkGroup(name: "Alpha", sortOrder: 0)
        let newGroup2 = BookmarkGroup(name: "Beta", sortOrder: 1)
        vm.replaceGroups([newGroup1, newGroup2])

        #expect(vm.bookmarkGroups.count == 2)
        let groupNames = vm.bookmarkGroups.map(\.name)
        #expect(groupNames.contains("Alpha"))
        #expect(groupNames.contains("Beta"))
    }

    @Test @MainActor
    func `Replace groups with empty clears all groups`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        vm.replaceGroups([])

        #expect(vm.bookmarkGroups.isEmpty)
    }

    @Test @MainActor
    func `Replace groups preserves existing group IDs`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let existingID = UUID()
        let group = BookmarkGroup(name: "Original", id: existingID, sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        let renamed = BookmarkGroup(name: "Renamed", id: existingID, sortOrder: 0)
        vm.replaceGroups([renamed])

        #expect(vm.bookmarkGroups.first?.id == existingID)
        #expect(vm.bookmarkGroups.first?.name == "Renamed")
    }

    // MARK: - groups(from:)

    @Test @MainActor
    func `Groups from converts rows to bookmark groups`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let rows: [(tag: String?, value: String?)] = [
            (tag: nil, value: "Alpha"),
            (tag: nil, value: "Beta")
        ]
        let groups = vm.groups(from: rows)

        #expect(groups.count == 2)
        #expect(groups[0].name == "Alpha")
        #expect(groups[0].sortOrder == 0)
        #expect(groups[1].name == "Beta")
        #expect(groups[1].sortOrder == 1)
    }

    @Test @MainActor
    func `Groups from skips empty and whitespace only names`() {
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

        #expect(groups.count == 1)
        #expect(groups[0].name == "Valid")
    }

    @Test @MainActor
    func `Groups from preserves existing UUID tags`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let existingID = UUID()
        let rows: [(tag: String?, value: String?)] = [
            (tag: existingID.uuidString, value: "Renamed Group")
        ]
        let groups = vm.groups(from: rows)

        #expect(groups.first?.id == existingID)
        #expect(groups.first?.name == "Renamed Group")
    }

    @Test @MainActor
    func `Groups from assigns fresh ID when tag is nil or invalid`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = ManageGroupsViewModel(application: app)

        let rows: [(tag: String?, value: String?)] = [
            (tag: nil, value: "New Group"),
            (tag: "not-a-uuid", value: "Another New Group")
        ]
        let groups = vm.groups(from: rows)

        #expect(groups.count == 2)
        // IDs should be valid UUIDs (non-nil), just not the same as each other
        #expect(groups[0].id != groups[1].id)
    }
}
