//
//  AgencyAlertsViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import Combine
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `AgencyAlertsViewModel`. Verifies the share-activity helper,
/// `collapsedSections` round-trip, and the loading flag transitions on
/// `agencyAlertsUpdated()`.
final class AgencyAlertsViewModelTests: OBATestCase {
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

    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
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
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )

        return Application(config: config)
    }

    // MARK: - Tests

    @MainActor
    func test_init_emptyAlerts_andNotLoading() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)

        expect(viewModel.alerts).to(beEmpty())
        expect(viewModel.isLoading).to(beFalse())
        expect(viewModel.collapsedSections).to(beEmpty())
    }

    @MainActor
    func test_reloadServerData_setsIsLoadingTrue() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.reloadServerData()

        expect(viewModel.isLoading).to(beTrue())
    }

    @MainActor
    func test_agencyAlertsUpdated_clearsIsLoading() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.reloadServerData()
        viewModel.agencyAlertsUpdated()

        expect(viewModel.isLoading).to(beFalse())
    }

    @MainActor
    func test_collapsedSections_survivesRefresh() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.collapsedSections = ["agency_1", "agency_2"]

        // Simulate a store-driven refresh cycle.
        viewModel.reloadServerData()
        viewModel.agencyAlertsUpdated()

        expect(viewModel.collapsedSections) == ["agency_1", "agency_2"]
    }

    @MainActor
    func test_displayError_clearsIsLoading() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.reloadServerData()
        viewModel.agencyAlertsStore(app.alertsStore, displayError: URLError(.badServerResponse))

        expect(viewModel.isLoading).to(beFalse())
    }
}
