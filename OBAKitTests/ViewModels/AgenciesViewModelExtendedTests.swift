//
//  AgenciesViewModelExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Extended tests for `AgenciesViewModel` loading states,
/// network error handling, and agency item transformations.
@Suite(.serialized)
final class AgenciesViewModelExtendedTests: OBATestCase {

    private var queue: OperationQueue!

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

    /// Creates an application whose agencies-with-coverage endpoint returns a network error.
    /// The region stub is registered so apiService is set, but no agencies stub is added —
    /// then the timeout catch-all fires for the agencies request.
    private func createApplicationFailingAgencies(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        // Intentionally omits stubAgenciesWithCoverage so the error stub below fires.

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
    func `AgenciesViewModel initial state has empty agencies list`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let vm = AgenciesViewModel(application: app)

        #expect(vm.agencies.isEmpty)
    }

    @Test @MainActor
    func `AgenciesViewModel loadData with failing network triggers completion`() async {
        let dataLoader = MockDataLoader(testName: name)

        // Register the timeout for all requests. createApplicationFailingAgencies
        // does NOT stub agencies-with-coverage, so this catch-all fires for it.
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: error) { _ in true })

        let app = createApplicationFailingAgencies(dataLoader: dataLoader)
        let vm = AgenciesViewModel(application: app)

        // Wait for apiService to be set before calling loadData().
        for _ in 0..<20 where app.apiService == nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        do {
            _ = try await vm.loadData()
            #expect(Bool(false), "loadData should have thrown an error on network failure")
        } catch {
            let caughtError = error as NSError
            #expect(caughtError.domain == NSURLErrorDomain)
            #expect(caughtError.code == NSURLErrorTimedOut)
        }
        #expect(vm.agencies.isEmpty)
    }
}
