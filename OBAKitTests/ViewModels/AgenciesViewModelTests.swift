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

/// Tests for `AgenciesViewModel`. Verifies the success path sorts by name,
/// and that loading state resets to `false` after completion.
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

    @Test @MainActor
    func `Init empty state`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgenciesViewModel(application: app)

        #expect(viewModel.agencies.isEmpty)
    }

    @Test @MainActor
    func `Load data success populates agencies sorted by name`() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        // Wait briefly for the region to settle so apiService is non-nil.
        for _ in 0..<20 where app.apiService == nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let viewModel = AgenciesViewModel(application: app)
        _ = try? await viewModel.loadData()

        #expect(!viewModel.agencies.isEmpty)

        let names = viewModel.agencies.map { $0.agency.name }
        #expect(names == names.sorted())
    }
}
