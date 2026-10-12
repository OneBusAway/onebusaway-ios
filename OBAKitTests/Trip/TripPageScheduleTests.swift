//
//  TripPageScheduleTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
@testable import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class TripPageScheduleTests: OBATestCase {

    private var queue: OperationQueue!
    private var window: UIWindow!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
        window?.rootViewController = nil
        window?.isHidden = true
    }

    private func makeHost(page: UIViewController) -> UIWindow {
        window?.rootViewController = nil
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = page
        window.isHidden = false
        self.window = window
        return window
    }

    private func makeApplication(dataLoader: MockDataLoader) -> Application {
        stubScheduleForStop(dataLoader: dataLoader)
        stubScheduleForRoute(dataLoader: dataLoader)
        stubArrivalsAndDepartures(dataLoader: dataLoader)
        stubStopsForLocation(dataLoader: dataLoader)
        stubTripEndpoints(dataLoader: dataLoader)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubAllAgenciesWithCoverage(dataLoader: dataLoader)
        return buildApplication(queue: queue, dataLoader: dataLoader)
    }

    private func stubAllAgenciesWithCoverage(dataLoader: MockDataLoader) {
        let coverageData = Fixtures.loadData(file: "agencies_with_coverage.json")
        dataLoader.mock(data: coverageData) { request in
            guard let path = request.url?.path else { return false }
            return path.hasSuffix("/agencies-with-coverage.json")
        }
    }

    private func stubScheduleForStop(dataLoader: MockDataLoader) {
        let scheduleData = Fixtures.loadData(file: "schedule-for-stop_1_75403.json")
        dataLoader.mock(data: scheduleData) { request in
            guard let path = request.url?.path else { return false }
            return path.contains("/schedule-for-stop/") && path.hasSuffix(".json")
        }
    }

    private func stubScheduleForRoute(dataLoader: MockDataLoader) {
        let scheduleData = Fixtures.loadData(file: "schedule-for-route_1_100223.json")
        dataLoader.mock(data: scheduleData) { request in
            guard let path = request.url?.path else { return false }
            return path.contains("/schedule-for-route/") && path.hasSuffix(".json")
        }
    }

    private func stubStopsForLocation(dataLoader: MockDataLoader) {
        let stopsData = Fixtures.loadData(file: "stops_for_location_seattle.json")
        dataLoader.mock(data: stopsData) { request in
            request.url?.path.contains("/stops-for-location") ?? false
        }
    }

    private func stubArrivalsAndDepartures(dataLoader: MockDataLoader) {
        let arrivalsData = Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        dataLoader.mock(data: arrivalsData) { request in
            request.url?.path.contains("/arrivals-and-departures-for-stop") ?? false
        }
    }

    private func stubTripEndpoints(dataLoader: MockDataLoader) {
        let tripData = Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(data: tripData) { request in
            request.url?.path.contains("/trip-details") ?? false
        }
        let arrivalData = Fixtures.loadData(file: "arrival-and-departure-for-stop-1_11420.json")
        dataLoader.mock(data: arrivalData) { request in
            request.url?.path.contains("/arrival-and-departure-for-stop") ?? false
        }
        let emptyShape = #"{"data":{"entry":{"length":0,"points":"","levels":""}},"code":200,"version":2,"text":"OK","currentTime":1700000000000}"#.data(using: .utf8)!
        dataLoader.mock(data: emptyShape) { request in
            request.url?.path.contains("/shape") ?? false
        }
    }

    private func makeDepartureWithRoute() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    private func makeSanDiegoRegion(for app: Application) async throws -> Region {
        if let existing = app.regionsService.find(id: 11) {
            return existing
        }
        let unsupportedRegionDict: [String: Any] = [
            "regionName": "San Diego",
            "id": 11,
            "obaBaseUrl": "https://realtime.sdmts.com/api/",
            "siriBaseUrl": "",
            "bounds": [
                ["lat": 32.7, "lon": -117.1, "latSpan": 0.5, "lonSpan": 0.5]
            ],
            "language": "en_US",
            "contactEmail": "test@example.com",
            "supportsObaDiscoveryApis": true,
            "supportsObaRealtimeApis": true,
            "supportsSiriRealtimeApis": false,
            "supportsEmbeddedSocial": false,
            "supportsOtpBikeshare": false,
            "active": true,
            "experimental": false,
            "obaVersionInfo": "2.0.0-SNAPSHOT|2|0|0|SNAPSHOT|abc"
        ]
        let unsupported = try Fixtures.dictionaryToModel(type: Region.self, dictionary: unsupportedRegionDict)
        try await app.regionsService.add(customRegion: unsupported)
        return unsupported
    }

    private func waitForPresentation(on controller: UIViewController) async -> UIViewController? {
        for _ in 0..<20 {
            if let presented = controller.presentedViewController { return presented }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return controller.presentedViewController
    }

    // MARK: - Factory Unit Tests

    @Test func `ScheduleViewControllerFactory creates route controller when supported`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = makeApplication(dataLoader: dataLoader)

        #expect(ScheduleViewControllerFactory.canPresentSchedule(stopID: nil, application: app))
        #expect(ScheduleViewControllerFactory.canPresentSchedule(stopID: "stop_1", application: app))

        let vc = ScheduleViewControllerFactory.makeScheduleViewController(
            routeID: "route_1",
            stopID: "stop_1",
            application: app
        )
        let routeVC = try #require(vc as? ScheduleForRouteViewController)
        #expect(routeVC.routeID == "route_1")
    }

    @Test func `ScheduleViewControllerFactory creates stop controller when unsupported and stop is available`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = makeApplication(dataLoader: dataLoader)
        app.regionsService.currentRegion = try await makeSanDiegoRegion(for: app)

        #expect(ScheduleViewControllerFactory.canPresentSchedule(stopID: "stop_1", application: app))

        let vc = ScheduleViewControllerFactory.makeScheduleViewController(
            routeID: "route_1",
            stopID: "stop_1",
            application: app
        )
        let stopVC = try #require(vc as? ScheduleForStopViewController)
        #expect(stopVC.stopID == "stop_1")
        #expect(stopVC.routeID == "route_1")
    }

    @Test func `ScheduleViewControllerFactory returns nil when unsupported and stop is nil`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = makeApplication(dataLoader: dataLoader)
        app.regionsService.currentRegion = try await makeSanDiegoRegion(for: app)

        #expect(!ScheduleViewControllerFactory.canPresentSchedule(stopID: nil, application: app))

        let vc = ScheduleViewControllerFactory.makeScheduleViewController(
            routeID: "route_1",
            stopID: nil,
            application: app
        )
        #expect(vc == nil)
    }

    // MARK: - Trip Page Schedule Presentation Tests

    @Test func `Supported region presents route schedule with routeID`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = makeApplication(dataLoader: dataLoader)
        let departure = try makeDepartureWithRoute()
        let page = TripPageViewController(application: app, arrivalDeparture: departure)
        _ = makeHost(page: page)

        #expect(page.rootView.actions.canSchedule)

        page.rootView.actions.onSchedule()

        let presented = await waitForPresentation(on: page)
        let scheduleVC = try #require(presented as? ScheduleForRouteViewController)
        #expect(scheduleVC.routeID == departure.routeID)
    }

    @Test func `Unsupported region with stop fallback presents stop schedule with stopID and routeID`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = makeApplication(dataLoader: dataLoader)
        let departure = try makeDepartureWithRoute()
        app.regionsService.currentRegion = try await makeSanDiegoRegion(for: app)

        let page = TripPageViewController(application: app, arrivalDeparture: departure)
        _ = makeHost(page: page)

        #expect(page.rootView.actions.canSchedule)

        page.rootView.actions.onSchedule()

        let presented = await waitForPresentation(on: page)
        let scheduleVC = try #require(presented as? ScheduleForStopViewController)
        #expect(scheduleVC.stopID == departure.stopID)
        #expect(scheduleVC.routeID == departure.routeID)
    }

    @Test func `Unsupported region without stop disables schedule and does not present`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = makeApplication(dataLoader: dataLoader)
        app.regionsService.currentRegion = try await makeSanDiegoRegion(for: app)

        let data = Fixtures.loadData(file: "trip_details_1_18196913.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data)
        let tripDetails = response.entry

        // Construct from TripDetails without arrival departure before details load into viewModel
        let page = TripPageViewController(application: app, tripConvertible: TripConvertible(tripDetails: tripDetails))

        // Before tripDetails load into viewModel, departure is nil and stopID is nil, so canSchedule is false
        #expect(!page.rootView.actions.canSchedule)

        _ = makeHost(page: page)
        page.rootView.actions.onSchedule()

        try? await Task.sleep(for: .milliseconds(100))
        #expect(page.presentedViewController == nil)
    }
}
