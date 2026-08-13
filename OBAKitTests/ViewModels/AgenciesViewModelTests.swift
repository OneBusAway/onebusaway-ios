//
//  AgenciesViewModelTests.swift
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

/// Tests for `AgenciesViewModel`. Covers the success path in `loadData()` (agencies sorted by name)
/// and the nil-`apiService` error path.
@Suite(.serialized)
final class AgenciesViewModelTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func createApplication(
        dataLoader: MockDataLoader,
        locationManager: LocationManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        ),
        fixedRegionName: String? = Fixtures.pugetSoundRegion.name
    ) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locationService = LocationService(userDefaults: userDefaults, locationManager: locationManager)

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
            fixedRegionName: fixedRegionName
        )

        return Application(config: config)
    }

    @Test @MainActor
    func `Init empty state`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgenciesViewModel(application: app)

        #expect(viewModel.agencies.isEmpty)
    }

    @Test @MainActor
    func `Load data success populates agencies sorted by name`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        // Wait briefly for the region to settle so apiService is non-nil.
        for _ in 0..<20 where app.apiService == nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let viewModel = AgenciesViewModel(application: app)
        _ = try await viewModel.loadData()

        #expect(!viewModel.agencies.isEmpty)

        let names = viewModel.agencies.map { $0.agency.name }
        #expect(names == names.sorted())
    }

    @Test @MainActor
    func `Load data with nil API service throws`() async {
        let dataLoader = MockDataLoader(testName: name)
        // LocationManagerMock is unauthorized and provides no location, so
        // regionsService.currentRegion stays nil and apiService is never set.
        let app = createApplication(
            dataLoader: dataLoader,
            locationManager: LocationManagerMock(),
            fixedRegionName: nil
        )
        #expect(app.apiService == nil)

        let viewModel = AgenciesViewModel(application: app)

        let thrown = await #expect(throws: UnstructuredError.self) {
            try await viewModel.loadData()
        }
        #expect(thrown?.errorDescription == "No API Service")
    }
}
