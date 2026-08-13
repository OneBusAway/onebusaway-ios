//
//  VehiclesViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
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
@Suite(.serialized)
final class VehiclesViewModelTests: OBATestCase {
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
        return try #require(list?.compactMap { $0["agencyId"] as? String })
    }

    /// Disables every agency in the fixture so `fetchVehicles()` makes no live network calls.
    private func disableAllAgencies(in application: Application) throws {
        for agencyID in try fixtureAgencyIDs() {
            application.userDataStore.setAgencyEnabledForVehicleFeed(false, agencyID: agencyID)
        }
    }

    // MARK: - Initial State

    @Test @MainActor
    func `Init has empty state`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let viewModel = VehiclesViewModel(application: app)

        #expect(viewModel.vehicles.isEmpty)
        #expect(viewModel.feedStatuses.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(viewModel.error == nil)
        #expect(viewModel.lastUpdated == nil)
    }

    // MARK: - Fetch Guards

    @Test @MainActor
    func `Fetch vehicles without current region is a no op`() async {
        let app = createApplication(dataLoader: MockDataLoader(testName: name), withRegion: false)
        let viewModel = VehiclesViewModel(application: app)

        await viewModel.fetchVehicles()

        #expect(viewModel.vehicles.isEmpty)
        #expect(viewModel.feedStatuses.isEmpty)
        #expect(viewModel.lastUpdated == nil)
        #expect(!viewModel.isLoading)
    }

    // MARK: - Fetch

    @Test @MainActor
    func `Fetch vehicles all agencies disabled produces skipped statuses without network calls`() async throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        try disableAllAgencies(in: app)
        let viewModel = VehiclesViewModel(application: app)

        await viewModel.fetchVehicles()

        let agencyCount = try fixtureAgencyIDs().count
        #expect(viewModel.feedStatuses.count == agencyCount)
        // Spelled as a closure rather than `allSatisfy(\.isSkipped)`: inside the
        // #expect expansion the key-path-as-function conversion loses its
        // non-throwing signature, so `allSatisfy` reads as `rethrows`-that-throws
        // and the compiler demands a `try` the call does not need.
        #expect(viewModel.feedStatuses.allSatisfy { $0.isSkipped })
        #expect(viewModel.vehicles.isEmpty)
        #expect(viewModel.error == nil)
        #expect(viewModel.lastUpdated != nil)
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor
    func `Fetch vehicles sorts feed statuses by agency name`() async throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        try disableAllAgencies(in: app)
        let viewModel = VehiclesViewModel(application: app)

        await viewModel.fetchVehicles()

        let names = viewModel.feedStatuses.map(\.agencyName)
        #expect(names == names.sorted())
    }

    @Test @MainActor
    func `Agency counts reflect disabled agencies`() async throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        try disableAllAgencies(in: app)
        let viewModel = VehiclesViewModel(application: app)

        await viewModel.fetchVehicles()

        #expect(viewModel.totalAgencyCount == viewModel.feedStatuses.count)
        #expect(viewModel.enabledAgencyCount == 0)
        #expect(!viewModel.allAgenciesEnabled)
    }

    // MARK: - Agency Filtering

    @Test @MainActor
    func `Agency enabled defaults to true and persists changes`() {
        // No-region app: the fetch spawned by setAgencyEnabled() no-ops safely.
        let app = createApplication(dataLoader: MockDataLoader(testName: name), withRegion: false)
        let viewModel = VehiclesViewModel(application: app)

        #expect(viewModel.isAgencyEnabled("40"))
        #expect(viewModel.allAgenciesEnabled)

        viewModel.setAgencyEnabled(false, agencyID: "40")

        #expect(!viewModel.isAgencyEnabled("40"))
        #expect(!viewModel.allAgenciesEnabled)
        #expect(app.userDataStore.disabledVehicleFeedAgencyIDs == ["40"])

        viewModel.setAgencyEnabled(true, agencyID: "40")

        #expect(viewModel.isAgencyEnabled("40"))
        #expect(viewModel.allAgenciesEnabled)
        #expect(app.userDataStore.disabledVehicleFeedAgencyIDs.isEmpty)
    }

    // MARK: - Auto-Refresh Lifecycle

    @Test @MainActor
    func `Start auto refresh triggers a fetch and stop cancels`() async throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        try disableAllAgencies(in: app)
        let viewModel = VehiclesViewModel(application: app)

        viewModel.startAutoRefresh()

        // `startAutoRefresh` spawns a non-terminating fetch/sleep loop, so there is
        // no completion to await — this is the one place polling is the right tool.
        await poll(until: { viewModel.lastUpdated != nil }, "startAutoRefresh never fetched")

        viewModel.stopAutoRefresh()

        // Stopping twice (or without having started) must be safe.
        viewModel.stopAutoRefresh()
    }

    @Test @MainActor
    func `Stop auto refresh without start is safe`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name), withRegion: false)
        let viewModel = VehiclesViewModel(application: app)

        viewModel.stopAutoRefresh()
    }
}
