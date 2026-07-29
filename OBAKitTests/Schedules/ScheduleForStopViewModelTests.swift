//
//  ScheduleForStopViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class ScheduleForStopViewModelTests: OBATestCase {
    let stopID = "1_75403"
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helper Methods

    func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)

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
            dataLoader: dataLoader
        )

        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        return Application(config: config)
    }

    func stubScheduleForStop(dataLoader: MockDataLoader) {
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/schedule-for-stop/\(stopID).json",
            with: Fixtures.loadData(file: "schedule-for-stop_1_75403.json")
        )
    }

    // MARK: - Initialization Tests

    @Test @MainActor
    func `Init sets stop ID`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        #expect(viewModel.stopID == stopID)
    }

    @Test @MainActor
    func `Init sets initial date`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let testDate = Date(timeIntervalSince1970: 1733529600) // 2024-12-07

        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app, initialDate: testDate)

        #expect(Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: testDate))
    }

    @Test @MainActor
    func `Init selected route ID is nil`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        #expect(viewModel.selectedRouteID == nil)
    }

    // MARK: - Stop Name Tests

    @Test @MainActor
    func `Stop name before fetch returns stop ID`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        #expect(viewModel.stopName == stopID)
    }

    // MARK: - Available Routes Tests

    @Test @MainActor
    func `Available routes before fetch is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        #expect(viewModel.availableRoutes.isEmpty)
    }

    // MARK: - Route Selection Tests

    @Test @MainActor
    func `Select route updates selected route ID`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        let testRouteID = "test_route_123"
        viewModel.selectRoute(testRouteID)

        #expect(viewModel.selectedRouteID == testRouteID)
    }

    @Test @MainActor
    func `Select route can be called multiple times`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        viewModel.selectRoute("route_1")
        #expect(viewModel.selectedRouteID == "route_1")

        viewModel.selectRoute("route_2")
        #expect(viewModel.selectedRouteID == "route_2")

        viewModel.selectRoute("route_3")
        #expect(viewModel.selectedRouteID == "route_3")
    }

    // MARK: - Loading State Tests

    @Test @MainActor
    func `Is loading initially false`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        #expect(!viewModel.isLoading)
    }

    @Test @MainActor
    func `Error initially nil`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        #expect(viewModel.error == nil)
    }

    @Test @MainActor
    func `Schedule data initially nil`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        #expect(viewModel.scheduleData == nil)
    }
}
