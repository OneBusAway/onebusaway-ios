//
//  MapPanelViewModelTests.swift
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

/// Tests for `MapPanelViewModel`: nearby-stops publishing, alert reads from the store,
/// and the search-mode transitions that drive `requestedPanelDetent`.
class MapPanelViewModelTests: OBATestCase {
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

    // MARK: - Application Builder

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

    private func makeStop() throws -> Stop {
        let stopJSON = #"{"id":"1_TEST","code":"TEST","name":"Test Stop","lat":47.6,"lon":-122.3,"locationType":0,"routeIds":["1_R1"],"direction":""}"#
        return try JSONDecoder().decode(Stop.self, from: stopJSON.data(using: .utf8)!)
    }

    // MARK: - Nearby Stops

    /// `updateNearbyStops(_:)` publishes the new list on `$nearbyStops`.
    @MainActor
    func test_updateNearbyStops_publishes() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = MapPanelViewModel(application: app)
        expect(viewModel.nearbyStops).to(beEmpty())

        var emissions: [[Stop]] = []
        let cancellable = viewModel.$nearbyStops.sink { emissions.append($0) }
        defer { cancellable.cancel() }

        let stop = try makeStop()
        viewModel.updateNearbyStops([stop])

        expect(viewModel.nearbyStops.count) == 1
        expect(viewModel.nearbyStops.first?.id) == "1_TEST"
        // Initial empty value on subscription + the update.
        expect(emissions.count) == 2
        expect(emissions.last?.count) == 1
    }

    // MARK: - Alerts

    /// `refreshAlerts()` mirrors the alerts store's `recentHighSeverityAlerts`.
    /// With a fresh, unpopulated store both are empty — the assertion proves the VM reads
    /// through to the store rather than holding stale local state.
    @MainActor
    func test_refreshAlerts_readsFromStore() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = MapPanelViewModel(application: app)
        viewModel.refreshAlerts()

        expect(viewModel.highSeverityAlerts.count) == app.alertsStore.recentHighSeverityAlerts.count
        expect(viewModel.highSeverityAlerts).to(beEmpty())
    }

    // MARK: - Search Mode → Panel Detent

    /// `enterSearchMode()` requests the full detent; `exitSearchMode()` returns to the tip.
    @MainActor
    func test_searchMode_drivesRequestedPanelDetent() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = MapPanelViewModel(application: app)
        expect(viewModel.requestedPanelDetent) == .tip  // default

        var emissions: [PanelDetent] = []
        let cancellable = viewModel.$requestedPanelDetent.sink { emissions.append($0) }
        defer { cancellable.cancel() }

        viewModel.enterSearchMode()
        expect(viewModel.requestedPanelDetent) == .full

        viewModel.exitSearchMode()
        expect(viewModel.requestedPanelDetent) == .tip

        // Initial .tip + .full + .tip.
        expect(emissions) == [.tip, .full, .tip]
    }
}
