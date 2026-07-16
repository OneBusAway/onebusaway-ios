//
//  VehiclesViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `VehiclesViewModel`: fetch guards, feed status generation, agency
/// enable/disable filtering, and the auto-refresh lifecycle.
///
/// The per-agency GTFS-RT vehicle fetch uses `URLSession.shared` directly and cannot
/// be stubbed, so every test that performs a fetch first disables all agencies from
/// the fixture. That exercises the full pipeline — stubbed agencies-with-coverage
/// request, task group, skipped-status generation, published state transitions —
/// without any live network traffic.
class VehiclesViewModelTests: OBATestCase {
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

    /// Builds an `Application` locked to Puget Sound, mirroring `MapViewModelTests`.
    ///
    /// With `withRegion: false`, no region can ever resolve: the fixed region name
    /// matches nothing and the location manager is unauthorized, so location-based
    /// auto-selection cannot kick in asynchronously and re-enable network fetches.
    private func createApplication(dataLoader: MockDataLoader, withRegion: Bool = true) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager: LocationManager = withRegion
            ? MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
            : LocationManagerMock()
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
            fixedRegionName: withRegion ? Fixtures.pugetSoundRegion.name : "Nonexistent Region Name"
        )

        return Application(config: config)
    }

    /// Agency IDs from the agencies_with_coverage.json fixture.
    private func fixtureAgencyIDs() throws -> [String] {
        let data = Fixtures.loadData(file: "agencies_with_coverage.json")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataDict = json?["data"] as? [String: Any]
        let list = dataDict?["list"] as? [[String: Any]]
        return try XCTUnwrap(list?.compactMap { $0["agencyId"] as? String })
    }

    /// Disables every agency in the fixture so `fetchVehicles()` makes no live network calls.
    private func disableAllAgencies(in application: Application) throws {
        for agencyID in try fixtureAgencyIDs() {
            application.userDataStore.setAgencyEnabledForVehicleFeed(false, agencyID: agencyID)
        }
    }

    // MARK: - Initial State

    @MainActor
    func test_init_hasEmptyState() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let viewModel = VehiclesViewModel(application: app)

        expect(viewModel.vehicles).to(beEmpty())
        expect(viewModel.feedStatuses).to(beEmpty())
        expect(viewModel.isLoading).to(beFalse())
        expect(viewModel.error).to(beNil())
        expect(viewModel.lastUpdated).to(beNil())
    }

    // MARK: - Fetch Guards

    @MainActor
    func test_fetchVehicles_withoutCurrentRegion_isANoOp() async {
        let app = createApplication(dataLoader: MockDataLoader(testName: name), withRegion: false)
        let viewModel = VehiclesViewModel(application: app)

        await viewModel.fetchVehicles()

        expect(viewModel.vehicles).to(beEmpty())
        expect(viewModel.feedStatuses).to(beEmpty())
        expect(viewModel.lastUpdated).to(beNil())
        expect(viewModel.isLoading).to(beFalse())
    }

    // MARK: - Fetch

    @MainActor
    func test_fetchVehicles_allAgenciesDisabled_producesSkippedStatusesWithoutNetworkCalls() async throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        try disableAllAgencies(in: app)
        let viewModel = VehiclesViewModel(application: app)

        await viewModel.fetchVehicles()

        let agencyCount = try fixtureAgencyIDs().count
        expect(viewModel.feedStatuses.count) == agencyCount
        expect(viewModel.feedStatuses.allSatisfy(\.isSkipped)).to(beTrue())
        expect(viewModel.vehicles).to(beEmpty())
        expect(viewModel.error).to(beNil())
        expect(viewModel.lastUpdated).toNot(beNil())
        expect(viewModel.isLoading).to(beFalse())
    }

    @MainActor
    func test_fetchVehicles_sortsFeedStatusesByAgencyName() async throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        try disableAllAgencies(in: app)
        let viewModel = VehiclesViewModel(application: app)

        await viewModel.fetchVehicles()

        let names = viewModel.feedStatuses.map(\.agencyName)
        expect(names) == names.sorted()
    }

    @MainActor
    func test_agencyCounts_reflectDisabledAgencies() async throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        try disableAllAgencies(in: app)
        let viewModel = VehiclesViewModel(application: app)

        await viewModel.fetchVehicles()

        expect(viewModel.totalAgencyCount) == viewModel.feedStatuses.count
        expect(viewModel.enabledAgencyCount) == 0
        expect(viewModel.allAgenciesEnabled).to(beFalse())
    }

    // MARK: - Agency Filtering

    @MainActor
    func test_agencyEnabled_defaultsToTrueAndPersistsChanges() {
        // No-region app: the fetch spawned by setAgencyEnabled() no-ops safely.
        let app = createApplication(dataLoader: MockDataLoader(testName: name), withRegion: false)
        let viewModel = VehiclesViewModel(application: app)

        expect(viewModel.isAgencyEnabled("40")).to(beTrue())
        expect(viewModel.allAgenciesEnabled).to(beTrue())

        viewModel.setAgencyEnabled(false, agencyID: "40")

        expect(viewModel.isAgencyEnabled("40")).to(beFalse())
        expect(viewModel.allAgenciesEnabled).to(beFalse())
        expect(app.userDataStore.disabledVehicleFeedAgencyIDs) == ["40"]

        viewModel.setAgencyEnabled(true, agencyID: "40")

        expect(viewModel.isAgencyEnabled("40")).to(beTrue())
        expect(viewModel.allAgenciesEnabled).to(beTrue())
        expect(app.userDataStore.disabledVehicleFeedAgencyIDs).to(beEmpty())
    }

    // MARK: - Auto-Refresh Lifecycle

    @MainActor
    func test_startAutoRefresh_triggersAFetch_andStopCancels() async throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        try disableAllAgencies(in: app)
        let viewModel = VehiclesViewModel(application: app)

        viewModel.startAutoRefresh()

        await expect(viewModel.lastUpdated).toEventuallyNot(beNil())

        viewModel.stopAutoRefresh()

        // Stopping twice (or without having started) must be safe.
        viewModel.stopAutoRefresh()
    }

    @MainActor
    func test_stopAutoRefresh_withoutStart_isSafe() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name), withRegion: false)
        let viewModel = VehiclesViewModel(application: app)

        viewModel.stopAutoRefresh()
    }
}
