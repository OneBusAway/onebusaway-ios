//
//  ScheduleForRouteViewModelTests.swift
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

class ScheduleForRouteViewModelTests: OBATestCase {
    let routeID = "1_100223"
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

    func stubScheduleForRoute(dataLoader: MockDataLoader) {
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/schedule-for-route/\(routeID).json",
            with: Fixtures.loadData(file: "schedule-for-route_1_100223.json")
        )
    }

    // MARK: - Initialization Tests

    @MainActor
    func test_init_setsRouteID() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.routeID) == routeID
    }

    @MainActor
    func test_init_setsInitialDate() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let testDate = Date(timeIntervalSince1970: 1733529600) // 2024-12-07

        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app, initialDate: testDate)

        expect(Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: testDate)).to(beTrue())
    }

    @MainActor
    func test_init_defaultsSelectedDirectionIndexToZero() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.selectedDirectionIndex) == 0
    }

    // MARK: - Route Name Tests

    @MainActor
    func test_routeName_beforeFetch_returnsRouteID() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.routeName) == routeID
    }

    // MARK: - Directions Tests

    @MainActor
    func test_directions_beforeFetch_isEmpty() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.directions).to(beEmpty())
    }

    @MainActor
    func test_currentDirection_beforeFetch_returnsNil() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.currentDirection).to(beNil())
    }

    // MARK: - Headsign Tests

    @MainActor
    func test_currentHeadsign_beforeFetch_isEmpty() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.currentHeadsign).to(beEmpty())
    }

    // MARK: - Stop Names and IDs Tests

    @MainActor
    func test_stopNames_beforeFetch_isEmpty() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.stopNames).to(beEmpty())
    }

    @MainActor
    func test_stopIDs_beforeFetch_isEmpty() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.stopIDs).to(beEmpty())
    }

    // MARK: - Departure Times Tests

    @MainActor
    func test_departureTimes_beforeFetch_isEmpty() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.departureTimes).to(beEmpty())
    }

    @MainActor
    func test_sortedDepartureTimes_beforeFetch_isEmpty() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.sortedDepartureTimes).to(beEmpty())
    }

    @MainActor
    func test_departureTimesDisplay_beforeFetch_isEmpty() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.departureTimesDisplay).to(beEmpty())
    }

    // MARK: - Time Formatting Tests

    @MainActor
    func test_formatTime_withDate_returnsFormattedString() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        // Create a date at 8:30 AM UTC (since tests run in UTC)
        let date = Date(timeIntervalSince1970: 30600) // 8:30 AM on Jan 1, 1970

        let result = viewModel.formatTime(date)

        expect(result).to(contain(":"))
        expect(result).toNot(equal("-"))
    }

    @MainActor
    func test_formatTime_nilDate_returnsDash() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        let result = viewModel.formatTime(nil)

        expect(result) == "-"
    }

    @MainActor
    func test_formatTimeAccessible_withDate_returnsReadableTime() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        let date = Date(timeIntervalSince1970: 30600) // 8:30 AM

        let result = viewModel.formatTimeAccessible(date)

        // 24-hour format contains colon but no AM/PM
        expect(result).to(contain(":"))
        expect(result).toNot(beEmpty())
        expect(result).toNot(equal("-"))

        // 24-hour format does not use AM/PM
        let noAMPM = !result.contains("AM") && !result.contains("PM")
        expect(noAMPM).to(beTrue())
    }

    @MainActor
    func test_formatTimeAccessible_nilDate_returnsNoDepartureText() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        let result = viewModel.formatTimeAccessible(nil)

        // Should return the localized "No departure" string
        expect(result).toNot(beEmpty())
        expect(result).toNot(equal("-"))
    }

    // MARK: - Loading State Tests

    @MainActor
    func test_isLoading_initiallyFalse() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.isLoading).to(beFalse())
    }

    @MainActor
    func test_error_initiallyNil() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.error).to(beNil())
    }

    @MainActor
    func test_scheduleData_initiallyNil() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        expect(viewModel.scheduleData).to(beNil())
    }
}
