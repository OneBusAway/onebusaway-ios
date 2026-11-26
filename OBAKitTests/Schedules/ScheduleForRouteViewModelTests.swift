//
//  ScheduleForRouteViewModelTests.swift
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
final class ScheduleForRouteViewModelTests: OBATestCase {
    let routeID = "1_100223"
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

    func stubScheduleForRoute(dataLoader: MockDataLoader) {
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/schedule-for-route/\(routeID).json",
            with: Fixtures.loadData(file: "schedule-for-route_1_100223.json")
        )
    }

    // MARK: - Initialization Tests

    @Test @MainActor
    func `Init sets route ID`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.routeID == routeID)
    }

    @Test @MainActor
    func `Init sets initial date`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let testDate = Date(timeIntervalSince1970: 1733529600) // 2024-12-07

        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app, initialDate: testDate)

        #expect(Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: testDate))
    }

    @Test @MainActor
    func `Init defaults selected direction index to zero`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.selectedDirectionIndex == 0)
    }

    // MARK: - Route Name Tests

    @Test @MainActor
    func `Route name before fetch returns route ID`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.routeName == routeID)
    }

    // MARK: - Directions Tests

    @Test @MainActor
    func `Directions before fetch is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.directions.isEmpty)
    }

    @Test @MainActor
    func `Current direction before fetch returns nil`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.currentDirection == nil)
    }

    // MARK: - Headsign Tests

    @Test @MainActor
    func `Current headsign before fetch is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.currentHeadsign.isEmpty)
    }

    // MARK: - Stop Names and IDs Tests

    @Test @MainActor
    func `Stop names before fetch is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.stopNames.isEmpty)
    }

    @Test @MainActor
    func `Stop IDs before fetch is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.stopIDs.isEmpty)
    }

    // MARK: - Departure Times Tests

    @Test @MainActor
    func `Departure times before fetch is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.departureTimes.isEmpty)
    }

    @Test @MainActor
    func `Sorted departure times before fetch is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.sortedDepartureTimes.isEmpty)
    }

    @Test @MainActor
    func `Departure times display before fetch is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.departureTimesDisplay.isEmpty)
    }

    // MARK: - Time Formatting Tests

    @Test @MainActor
    func `Format time with date returns formatted string`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        // A 24-hour locale, so the expected shape doesn't depend on the host's settings.
        viewModel.timeFormatter.locale = Locale(identifier: "en_GB")

        // Create a date at 8:30 AM UTC (since tests run in UTC)
        let date = Date(timeIntervalSince1970: 30600) // 8:30 AM on Jan 1, 1970

        let result = viewModel.formatTime(date)

        #expect(result.contains(":"))
        #expect(result != "-")
        #expect(!result.contains("AM"))
        #expect(!result.contains("PM"))
        #expect(result.count == 5)
    }

    @Test @MainActor
    func `Format time midnight returns 0000`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        // Construct midnight using the same timezone the formatter uses.
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let date = calendar.startOfDay(for: Date())

        viewModel.timeFormatter.locale = Locale(identifier: "en_GB")
        #expect(viewModel.formatTime(date) == "00:00")
    }

    @Test @MainActor
    func `Format time noon returns 1200`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        // Construct noon using the same timezone the formatter uses.
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

        viewModel.timeFormatter.locale = Locale(identifier: "en_GB")
        #expect(viewModel.formatTime(date) == "12:00")
    }

    @Test @MainActor
    func `Format time follows a 12-hour locale`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let date = calendar.date(bySettingHour: 13, minute: 5, second: 0, of: Date())!

        viewModel.timeFormatter.locale = Locale(identifier: "en_US")
        // The formatter separates the day period with a narrow no-break space.
        let result = viewModel.formatTime(date).replacingOccurrences(of: "\u{202F}", with: " ")
        #expect(result == "1:05 PM")
    }

    @Test @MainActor
    func `Format time nil date returns dash`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        let result = viewModel.formatTime(nil)

        #expect(result == "-")
    }

    @Test @MainActor
    func `Format time accessible with date returns readable time`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        let date = Date(timeIntervalSince1970: 30600) // 8:30 AM

        let result = viewModel.formatTimeAccessible(date)

        // Locale-aware format contains colon and readable time
        #expect(result.contains(":"))
        #expect(!result.isEmpty)
        #expect(result != "-")
    }

    @Test @MainActor
    func `Format time accessible nil date returns no departure text`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        let result = viewModel.formatTimeAccessible(nil)

        // Should return the localized "No departure" string
        #expect(!result.isEmpty)
        #expect(result != "-")
    }

    // MARK: - Loading State Tests

    @Test @MainActor
    func `Is loading initially false`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(!viewModel.isLoading)
    }

    @Test @MainActor
    func `Error initially nil`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.error == nil)
    }

    @Test @MainActor
    func `Schedule data initially nil`() {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.scheduleData == nil)
    }

    /// `.task(id:)` cancels the in-flight fetch when the date changes.
    /// `URLSession` throws `URLError.cancelled`, which must not become the
    /// visible error or the replacement fetch shows "Unable to load".
    @Test @MainActor
    func `Cancelled fetch does not set error`() async {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        let task = Task { await viewModel.fetchSchedule() }
        task.cancel()
        await task.value

        #expect(viewModel.error == nil)
        #expect(viewModel.scheduleData == nil)
    }

    // MARK: - Content State

    @Test @MainActor
    func `A loaded route schedule shows the timetable`() async {
        let dataLoader = MockDataLoader(testName: name)
        // `stubScheduleForRoute` matches one exact URL, without the query a real fetch sends.
        dataLoader.mock(data: Fixtures.loadData(file: "schedule-for-route_1_100223.json")) { [routeID] request in
            request.url?.path.contains("/schedule-for-route/\(routeID).json") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        await viewModel.fetchSchedule()

        guard case .content = viewModel.contentState else {
            Issue.record("Expected the timetable, got \(viewModel.contentState)")
            return
        }
    }

    @Test @MainActor
    func `A route schedule that fails to load shows the error`() async {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Data(), statusCode: 500) { [routeID] request in
            request.url?.path.contains("/schedule-for-route/\(routeID).json") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        await viewModel.fetchSchedule()

        guard case .failed = viewModel.contentState else {
            Issue.record("Expected the error, got \(viewModel.contentState)")
            return
        }
    }

    @Test @MainActor
    func `Fetch schedule formats date parameter in formatters timeZone`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "schedule-for-route_1_100223.json")) { [routeID] request in
            request.url?.path.contains("/schedule-for-route/\(routeID).json") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        app.formatters.timeZone = losAngeles

        // 2025-12-06 04:00:00 UTC → 2025-12-05 20:00:00 PST (previous calendar day in LA vs UTC).
        let instant = Date(timeIntervalSince1970: 1_764_993_600)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app, initialDate: instant)

        await viewModel.fetchSchedule()

        let requestURL = try #require(dataLoader.recordedRequestURLs.last { $0.path.contains("/schedule-for-route/\(routeID).json") })
        let dateParam = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "date" }?.value
        #expect(dateParam == "2025-12-05")
    }

    // MARK: - Formatter Time Zone Tests

    /// Changing the formatter time zone bumps `formattersTimeZoneGeneration`,
    /// which the schedule views include in the `.task(id:)` identity so the
    /// schedule refetches in the new zone (#1978).
    @Test @MainActor
    func `Formatter time zone change bumps the generation`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForRoute(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = ScheduleForRouteViewModel(routeID: routeID, application: app)

        #expect(viewModel.formattersTimeZoneGeneration == 0)

        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let newZone = app.formatters.timeZone == losAngeles ? newYork : losAngeles
        app.formatters.timeZone = newZone

        // The time-zone sink receives on the main queue, so the bump lands
        // asynchronously; wait for it instead of asserting immediately.
        let deadline = Date().addingTimeInterval(2)
        while viewModel.formattersTimeZoneGeneration == 0 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.formattersTimeZoneGeneration == 1)

        // Assigning the same zone again must not bump it.
        app.formatters.timeZone = newZone
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.formattersTimeZoneGeneration == 1)
    }
}
