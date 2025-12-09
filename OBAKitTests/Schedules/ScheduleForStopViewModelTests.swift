//
//  ScheduleForStopViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class ScheduleForStopViewModelTests: OBATestCase {
    let stopID = "1_75403"
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

    @MainActor
    func test_init_setsStopID() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        expect(viewModel.stopID) == stopID
    }

    @MainActor
    func test_init_setsInitialDate() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let testDate = Date(timeIntervalSince1970: 1733529600) // 2024-12-07

        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app, initialDate: testDate)

        expect(Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: testDate)).to(beTrue())
    }

    @MainActor
    func test_init_selectedRouteIDIsNil() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        expect(viewModel.selectedRouteID).to(beNil())
    }

    // MARK: - Stop Name Tests

    @MainActor
    func test_stopName_beforeFetch_returnsStopID() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        expect(viewModel.stopName) == stopID
    }

    // MARK: - Available Routes Tests

    @MainActor
    func test_availableRoutes_beforeFetch_isEmpty() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        expect(viewModel.availableRoutes).to(beEmpty())
    }

    // MARK: - Route Selection Tests

    @MainActor
    func test_selectRoute_updatesSelectedRouteID() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        let testRouteID = "test_route_123"
        viewModel.selectRoute(testRouteID)

        expect(viewModel.selectedRouteID) == testRouteID
    }

    @MainActor
    func test_selectRoute_canBeCalledMultipleTimes() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        viewModel.selectRoute("route_1")
        expect(viewModel.selectedRouteID) == "route_1"

        viewModel.selectRoute("route_2")
        expect(viewModel.selectedRouteID) == "route_2"

        viewModel.selectRoute("route_3")
        expect(viewModel.selectedRouteID) == "route_3"
    }

    // MARK: - Loading State Tests

    @MainActor
    func test_isLoading_initiallyFalse() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        expect(viewModel.isLoading).to(beFalse())
    }

    @MainActor
    func test_error_initiallyNil() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        expect(viewModel.error).to(beNil())
    }

    @MainActor
    func test_scheduleData_initiallyNil() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForStopViewModel(stopID: stopID, application: app)

        expect(viewModel.scheduleData).to(beNil())
    }
}
