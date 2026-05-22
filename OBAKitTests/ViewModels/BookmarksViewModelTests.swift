//
//  BookmarksViewModelTests.swift
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

// swiftlint:disable force_cast force_try

/// Tests for `BookmarksViewModel`. Verifies that the `sortByGroup` preference is read
/// from and written to UserDefaults under the documented key.
class BookmarksViewModelTests: OBATestCase {
    private let sortByGroupKey = "OBABookmarksController_SortBookmarksByGroup"
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

    // MARK: - Tests

    /// `init` defaults to `true` (set via `register(defaults:)`) on a clean UserDefaults.
    @MainActor
    func test_init_defaultsSortByGroupToTrue() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)

        expect(viewModel.sortByGroup).to(beTrue())
    }

    /// `init` reads the persisted value back out of UserDefaults.
    @MainActor
    func test_init_readsSortByGroupFromUserDefaults() {
        userDefaults.set(false, forKey: sortByGroupKey)

        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)

        expect(viewModel.sortByGroup).to(beFalse())
    }

    /// `updateSortType` writes the new value to UserDefaults under the documented key
    /// and updates the published property.
    @MainActor
    func test_updateSortType_persistsToUserDefaults() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)
        viewModel.updateSortType(byGroup: false)

        expect(viewModel.sortByGroup).to(beFalse())
        expect(self.userDefaults.bool(forKey: self.sortByGroupKey)).to(beFalse())
    }
}
