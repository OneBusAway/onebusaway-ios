//
//  AgenciesViewModelTests.swift
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

/// Tests for `AgenciesViewModel`. Covers the success path in `loadData()` (agencies sorted by name)
/// and the nil-`apiService` error path.
final class AgenciesViewModelTests: OBATestCase {
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

    @MainActor
    func test_init_emptyState() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgenciesViewModel(application: app)

        expect(viewModel.agencies).to(beEmpty())
    }

    @MainActor
    func test_loadData_success_populatesAgenciesSortedByName() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        // Wait briefly for the region to settle so apiService is non-nil.
        for _ in 0..<20 where app.apiService == nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let viewModel = AgenciesViewModel(application: app)
        _ = try await viewModel.loadData()

        expect(viewModel.agencies).toNot(beEmpty())

        let names = viewModel.agencies.map { $0.agency.name }
        expect(names) == names.sorted()
    }

    @MainActor
    func test_loadData_nilAPIService_throws() async {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        // LocationManagerMock is unauthorized and provides no location, so
        // regionsService.currentRegion stays nil and apiService is never set.
        let locManager = LocationManagerMock()
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
            // no fixedRegionName → currentRegion stays nil → apiService stays nil
        )

        let app = Application(config: config)
        expect(app.apiService).to(beNil())

        let viewModel = AgenciesViewModel(application: app)

        await expect {
            try await viewModel.loadData()
        }.to(throwError())
    }
}
