//
//  ServiceAlertViewModelExtendedTests.swift
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

/// Extended tests for `ServiceAlertViewModel` unread status transitions,
/// title resolution, and publisher emission.
@Suite(.serialized)
final class ServiceAlertViewModelExtendedTests: OBATestCase {

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

    private func loadServiceAlert() throws -> ServiceAlert {
        // Load a ServiceAlert from an arrivals-and-departures fixture whose
        // references section contains situations (ServiceAlert is Decodable;
        // AgencyAlert is a protobuf-backed NSObject and is not).
        let data = Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<ArrivalDeparture>.self, from: data)
        return try #require(response.references?.serviceAlerts.first)
    }

    @Test @MainActor
    func `ServiceAlertViewModel initial state before appear has nil renderedHTML`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let alert = try loadServiceAlert()

        let viewModel = ServiceAlertViewModel(serviceAlert: alert, application: app)

        #expect(viewModel.renderedHTML == nil)
    }

    @Test @MainActor
    func `Unread alert is marked read on viewDidAppear`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let alert = try loadServiceAlert()

        // Alert starts unread
        #expect(app.userDataStore.isUnread(serviceAlert: alert))

        let viewModel = ServiceAlertViewModel(serviceAlert: alert, application: app)
        viewModel.viewDidAppear()

        // viewDidAppear should mark it read
        #expect(!app.userDataStore.isUnread(serviceAlert: alert))
    }
}
