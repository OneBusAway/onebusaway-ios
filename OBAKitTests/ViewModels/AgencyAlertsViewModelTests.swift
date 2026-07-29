//
//  AgencyAlertsViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import Combine
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `AgencyAlertsViewModel`. Verifies the share-activity helper,
/// `collapsedSections` round-trip, and the loading flag transitions on
/// `agencyAlertsUpdated()`.
@Suite(.serialized)
final class AgencyAlertsViewModelTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
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

    @Test @MainActor
    func `Init empty alerts and not loading`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)

        #expect(viewModel.alerts.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(viewModel.collapsedSections.isEmpty)
    }

    @Test @MainActor
    func `Reload server data sets is loading true`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.reloadServerData()

        #expect(viewModel.isLoading)
    }

    @Test @MainActor
    func `Agency alerts updated clears is loading`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.reloadServerData()
        viewModel.agencyAlertsUpdated()

        #expect(!viewModel.isLoading)
    }

    @Test @MainActor
    func `Collapsed sections survives refresh`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.collapsedSections = ["agency_1", "agency_2"]

        // Simulate a store-driven refresh cycle.
        viewModel.reloadServerData()
        viewModel.agencyAlertsUpdated()

        #expect(viewModel.collapsedSections == ["agency_1", "agency_2"])
    }

    @Test @MainActor
    func `Display error clears is loading`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.reloadServerData()
        viewModel.agencyAlertsStore(app.alertsStore, displayError: URLError(.badServerResponse))

        #expect(!viewModel.isLoading)
    }
}
