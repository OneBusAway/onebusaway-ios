//
//  DestinationStopPickerControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class DestinationStopPickerControllerTests: OBATestCase {
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

    // MARK: - Helpers

    private func makeArrivalDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try XCTUnwrap(stopArrivals.arrivalsAndDepartures.first)
    }

    /// Returns a minimal `RESTAPIResponse<TripDetails>` JSON payload.
    /// `stopIDs` maps directly to `schedule.stopTimes`; all stops are included in `references`.
    private func makeTripDetailsData(stopIDs: [String], tripID: String = "1_40984902") -> Data {
        let stopTimes: [[String: Any]] = stopIDs.enumerated().map { idx, id in
            ["stopId": id,
             "arrivalTime": 58862 + idx * 120,
             "departureTime": 58862 + idx * 120,
             "distanceAlongTrip": Double(idx) * 300.0,
             "stopHeadsign": ""]
        }
        let stops: [[String: Any]] = stopIDs.map { id in
            ["id": id, "lat": 47.656, "lon": -122.312, "name": "Stop \(id)",
             "code": id, "locationType": 0, "routeIds": [] as [String], "direction": "N"]
        }
        let trip: [String: Any] = [
            "id": tripID, "routeId": "1_100447", "routeShortName": "",
            "serviceId": "1_s", "shapeId": "", "timeZone": "",
            "tripHeadsign": "Test Destination", "tripShortName": "",
            "blockId": "1_b", "directionId": "1"
        ]
        let payload: [String: Any] = [
            "currentTime": 1_700_000_000_000, "text": "OK", "code": 200, "version": 2,
            "data": [
                "references": [
                    "agencies": [] as [[String: Any]],
                    "situations": [] as [[String: Any]],
                    "routes": [] as [[String: Any]],
                    "trips": [trip],
                    "stops": stops
                ],
                "entry": [
                    "tripId": tripID,
                    "serviceDate": 1_541_055_600_000,
                    "situationIds": [] as [String],
                    "schedule": [
                        "timeZone": "America/Los_Angeles",
                        "stopTimes": stopTimes
                    ]
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let emptySurveys = #"{"surveys":[]}"#.data(using: .utf8)!
        dataLoader.mock(data: emptySurveys) { $0.url?.path.contains("/surveys.json") ?? false }

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
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )

        return Application(config: config)
    }

    // MARK: - Tests

    /// When the trip has stops after the boarding stop, the controller should
    /// load into `.data` state and return one section containing only the forward stops.
    @MainActor
    func test_loadStopTimes_success_setsDataWithForwardStopsOnly() async throws {
        let arrivalDeparture = try makeArrivalDeparture()  // stopID = "1_10914"
        let forwardStopIDs = ["1_10915", "1_10916"]

        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: makeTripDetailsData(stopIDs: [arrivalDeparture.stopID] + forwardStopIDs)) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        controller.loadViewIfNeeded()
        try await Task.sleep(nanoseconds: 500_000_000)

        let sections = controller.items(for: OBAListView())
        XCTAssertEqual(sections.count, 1, "Expected exactly one section of forward stops")
        XCTAssertEqual(sections[0].contents.count, forwardStopIDs.count,
                       "Section should contain only the \(forwardStopIDs.count) stops after the boarding stop")
        XCTAssertNil(controller.emptyData(for: OBAListView()),
                     "emptyData should be nil when stops are loaded")
    }

    /// When the boarding stop is the last stop on the trip, there are no forward stops
    /// and the controller should enter `.empty` state.
    @MainActor
    func test_loadStopTimes_boardingIsLastStop_setsEmptyState() async throws {
        let arrivalDeparture = try makeArrivalDeparture()

        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: makeTripDetailsData(stopIDs: [arrivalDeparture.stopID])) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        controller.loadViewIfNeeded()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(controller.items(for: OBAListView()).isEmpty)
        let emptyData = try XCTUnwrap(controller.emptyData(for: OBAListView()))
        guard case .standard(let vm) = emptyData else {
            XCTFail("Expected .standard empty data"); return
        }
        XCTAssertEqual(vm.title, "No Stops Available")
        XCTAssertEqual(vm.body, "There are no remaining stops on this trip.")
        XCTAssertNil(vm.buttonConfig, "No retry button expected for empty state")
    }

    /// When the boarding stop ID isn't present in the trip's stop times, the controller
    /// must fail to an error — not silently show all stops, which would let a user
    /// generate a link with a behind-them destination.
    @MainActor
    func test_loadStopTimes_boardingStopNotFound_setsErrorState() async throws {
        let arrivalDeparture = try makeArrivalDeparture()  // stopID = "1_10914"

        let dataLoader = MockDataLoader(testName: name)
        // Trip whose stop list does NOT contain the boarding stop
        dataLoader.mock(data: makeTripDetailsData(stopIDs: ["1_other_a", "1_other_b"])) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        controller.loadViewIfNeeded()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(controller.items(for: OBAListView()).isEmpty)
        let emptyData = try XCTUnwrap(controller.emptyData(for: OBAListView()))
        guard case .standard(let vm) = emptyData else {
            XCTFail("Expected .standard empty data"); return
        }
        XCTAssertEqual(vm.body, "Couldn't determine your boarding point on this trip.",
                       "Should show the boarding-stop-not-found error, not a fallback stop list")
        XCTAssertNotNil(vm.buttonConfig, "Retry button should be offered on error")
        XCTAssertEqual(vm.buttonConfig?.text, "Try Again")
    }

    /// A network error should transition to `.error` state and surface a retry button.
    @MainActor
    func test_loadStopTimes_networkError_setsErrorStateWithRetry() async throws {
        let arrivalDeparture = try makeArrivalDeparture()

        let dataLoader = MockDataLoader(testName: name)
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                                   userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: networkError) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        })
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        controller.loadViewIfNeeded()
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(controller.items(for: OBAListView()).isEmpty)
        let emptyData = try XCTUnwrap(controller.emptyData(for: OBAListView()))
        guard case .standard(let vm) = emptyData else {
            XCTFail("Expected .standard empty data"); return
        }
        XCTAssertNotNil(vm.body, "Error message should be populated")
        XCTAssertNotNil(vm.buttonConfig, "Retry button should be offered on network error")
        XCTAssertEqual(vm.buttonConfig?.text, "Try Again")
    }
}
