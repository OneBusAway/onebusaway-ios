//
//  DestinationStopPickerControllerTests.swift
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

/// Records which `DestinationStopPickerDelegate` callback fired, for asserting
/// on the empty state's share-without-destination path.
private final class PickerDelegateRecorder: DestinationStopPickerDelegate {
    var selectedStopTime: TripStopTime?
    var didSkipDestination = false
    var didCancel = false

    func destinationStopPicker(
        _ controller: DestinationStopPickerController,
        didSelectStop stopTime: TripStopTime
    ) {
        selectedStopTime = stopTime
    }

    func destinationStopPickerDidSkipDestination(_ controller: DestinationStopPickerController) {
        didSkipDestination = true
    }

    func destinationStopPickerDidCancel(_ controller: DestinationStopPickerController) {
        didCancel = true
    }
}

@Suite(.serialized)
final class DestinationStopPickerControllerTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func makeArrivalDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    /// Builds a trip stop list that honors the fixture arrival's `stopSequence`
    /// of 3: the controller locates the boarding stop by sequence index, so it
    /// must sit at index 3, preceded by three placeholder stops.
    private func stopIDsWithBoarding(_ boardingStopID: String, forward: [String]) -> [String] {
        ["1_before_1", "1_before_2", "1_before_3", boardingStopID] + forward
    }

    /// Returns a minimal `RESTAPIResponse<TripDetails>` JSON payload.
    /// `stopIDs` maps directly to `schedule.stopTimes`; all stops are included in `references`.
    private func makeTripDetailsData(stopIDs: [String], tripID: String = "1_40984902") throws -> Data {
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
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Registers the stubs every test needs regardless of scenario. Kept separate from
    /// `createApplication` so `replaceMappedResponses`-based tests can re-register them
    /// atomically alongside their scenario-specific trip-details mock.
    private func registerBaseStubs(on dataLoader: MockDataLoader) {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let emptySurveys = Data(#"{"surveys":[]}"#.utf8)
        dataLoader.mock(data: emptySurveys) { $0.url?.path.contains("/surveys.json") ?? false }
    }

    private func createApplication(dataLoader: MockDataLoader) -> Application {
        registerBaseStubs(on: dataLoader)

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

    /// Unwraps the `.standard` empty data view model the controller currently vends, if any.
    private func standardEmptyData(
        _ controller: DestinationStopPickerController,
        _ listView: OBAListView
    ) -> OBAListView.StandardEmptyDataViewModel? {
        guard case .standard(let viewModel)? = controller.emptyData(for: listView) else { return nil }
        return viewModel
    }

    // MARK: - Tests

    /// When the trip has stops after the boarding stop, the controller should
    /// load into `.data` state and return one section containing only the forward stops.
    @Test @MainActor
    func `Successful load shows one section containing only the forward stops`() async throws {
        let arrivalDeparture = try makeArrivalDeparture()  // stopID = "1_10914"
        let forwardStopIDs = ["1_10915", "1_10916"]

        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: try makeTripDetailsData(stopIDs: stopIDsWithBoarding(arrivalDeparture.stopID, forward: forwardStopIDs))) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        controller.loadViewIfNeeded()

        let listView = OBAListView()
        await poll(
            until: { !controller.items(for: listView).isEmpty },
            "picker never entered the data state"
        )

        let sections = controller.items(for: listView)
        #expect(sections.count == 1, "Expected exactly one section of forward stops")
        #expect(
            sections.first?.contents.count == forwardStopIDs.count,
            "Section should contain only the \(forwardStopIDs.count) stops after the boarding stop"
        )
        #expect(standardEmptyData(controller, listView) == nil, "emptyData should be nil when stops are loaded")
    }

    /// Tapping a stop row must notify the delegate with that row's stop time —
    /// the feature's primary selection path.
    @Test @MainActor
    func `Selecting a stop row notifies the delegate with that stop time`() async throws {
        let arrivalDeparture = try makeArrivalDeparture()  // stopID = "1_10914"

        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: try makeTripDetailsData(stopIDs: stopIDsWithBoarding(arrivalDeparture.stopID, forward: ["1_10915", "1_10916"]))) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        let recorder = PickerDelegateRecorder()
        controller.delegate = recorder
        controller.loadViewIfNeeded()

        let listView = OBAListView()
        await poll(
            until: { !controller.items(for: listView).isEmpty },
            "picker never entered the data state"
        )

        let firstRow = try #require(controller.items(for: listView).first?.contents.first)
        firstRow.onSelectAction?(firstRow)

        #expect(recorder.selectedStopTime?.stopID == "1_10915", "Delegate must receive the tapped row's stop time")
        #expect(!recorder.didSkipDestination)
        #expect(!recorder.didCancel)
    }

    /// When the boarding stop is the last stop on the trip, there are no forward stops
    /// and the controller should enter `.empty` state — with a share button, so the
    /// empty state isn't a dead end.
    @Test @MainActor
    func `Boarding at the last stop shows the empty state with a destination-less share button`() async throws {
        let arrivalDeparture = try makeArrivalDeparture()

        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: try makeTripDetailsData(stopIDs: stopIDsWithBoarding(arrivalDeparture.stopID, forward: []))) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        controller.loadViewIfNeeded()

        let listView = OBAListView()
        await poll(
            until: { self.standardEmptyData(controller, listView)?.title == "No Stops Available" },
            "picker never entered the empty state"
        )

        #expect(controller.items(for: listView).isEmpty)
        let viewModel = try #require(standardEmptyData(controller, listView))
        #expect(viewModel.body == "There are no remaining stops on this trip.")
        #expect(
            viewModel.buttonConfig?.text == "Share Without Destination",
            "Empty state must offer a destination-less share instead of dead-ending"
        )
    }

    /// Tapping the empty state's share button must notify the delegate through the
    /// destination-less path — not the stop-selection or cancel paths.
    @Test @MainActor
    func `Empty state share button notifies the delegate to share without a destination`() async throws {
        let arrivalDeparture = try makeArrivalDeparture()

        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: try makeTripDetailsData(stopIDs: stopIDsWithBoarding(arrivalDeparture.stopID, forward: []))) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        let recorder = PickerDelegateRecorder()
        controller.delegate = recorder
        controller.loadViewIfNeeded()

        let listView = OBAListView()
        await poll(
            until: { self.standardEmptyData(controller, listView)?.buttonConfig != nil },
            "picker never entered the empty state"
        )

        let buttonConfig = try #require(standardEmptyData(controller, listView)?.buttonConfig)
        buttonConfig.action()

        #expect(recorder.didSkipDestination)
        #expect(recorder.selectedStopTime == nil)
        #expect(!recorder.didCancel)
    }

    /// When the stop at the arrival's `stopSequence` isn't the boarding stop, the
    /// controller must fail to an error — not silently show all stops, which would
    /// let a user generate a link with a behind-them destination.
    @Test @MainActor
    func `Missing boarding stop fails to an error instead of showing all stops`() async throws {
        let arrivalDeparture = try makeArrivalDeparture()  // stopID = "1_10914", stopSequence = 3

        let dataLoader = MockDataLoader(testName: name)
        // Index 3 exists but holds a different stop — the in-bounds mismatch case.
        dataLoader.mock(data: try makeTripDetailsData(stopIDs: ["1_other_a", "1_other_b", "1_other_c", "1_other_d", "1_other_e"])) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        controller.loadViewIfNeeded()

        let listView = OBAListView()
        await poll(
            until: { self.standardEmptyData(controller, listView)?.body == "Couldn't determine your boarding point on this trip." },
            "picker never entered the error state"
        )

        #expect(controller.items(for: listView).isEmpty, "No stop list may be shown when the boarding stop is unknown")
        let viewModel = try #require(standardEmptyData(controller, listView))
        #expect(viewModel.buttonConfig?.text == "Try Again", "Retry button should be offered on error")
    }

    /// A stop list shorter than the arrival's `stopSequence` must fail closed to
    /// an error — the out-of-bounds direction of the boarding-point guard. The
    /// boarding stop's ID is present in the list, so an ID search would have
    /// (wrongly) succeeded here.
    @Test @MainActor
    func `Stop list shorter than the boarding sequence fails to an error`() async throws {
        let arrivalDeparture = try makeArrivalDeparture()  // stopID = "1_10914", stopSequence = 3

        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: try makeTripDetailsData(stopIDs: ["1_x", arrivalDeparture.stopID])) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        controller.loadViewIfNeeded()

        let listView = OBAListView()
        await poll(
            until: { self.standardEmptyData(controller, listView)?.body == "Couldn't determine your boarding point on this trip." },
            "picker never entered the error state"
        )
        #expect(controller.items(for: listView).isEmpty, "No stop list may be shown when the sequence is out of bounds")
    }

    /// On a loop trip the boarding stop's ID appears more than once in the stop
    /// list. The controller must anchor on `stopSequence` — matching the first
    /// ID occurrence would offer stops the rider has already passed.
    @Test @MainActor
    func `Loop trip anchors on stopSequence, not the first matching stop ID`() async throws {
        let arrivalDeparture = try makeArrivalDeparture()  // stopID = "1_10914", stopSequence = 3
        let boarding = arrivalDeparture.stopID

        let dataLoader = MockDataLoader(testName: name)
        // The boarding stop ID also appears at index 1; the real boarding point is index 3.
        dataLoader.mock(data: try makeTripDetailsData(stopIDs: ["1_x", boarding, "1_y", boarding, "1_z"])) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        let recorder = PickerDelegateRecorder()
        controller.delegate = recorder
        controller.loadViewIfNeeded()

        let listView = OBAListView()
        await poll(
            until: { !controller.items(for: listView).isEmpty },
            "picker never entered the data state"
        )

        let rows = try #require(controller.items(for: listView).first?.contents)
        #expect(rows.count == 1, "Only the one stop after the sequence-3 boarding point may be offered")

        let firstRow = try #require(rows.first)
        firstRow.onSelectAction?(firstRow)
        #expect(recorder.selectedStopTime?.stopID == "1_z", "The offered stop must be the one after the rider's actual boarding point")
    }

    /// A network error should transition to `.error` state and surface a retry button.
    @Test @MainActor
    func `Network error shows the error state with a retry button`() async throws {
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

        let listView = OBAListView()
        await poll(
            until: { self.standardEmptyData(controller, listView)?.buttonConfig != nil },
            "picker never entered the error state"
        )

        #expect(controller.items(for: listView).isEmpty)
        let viewModel = try #require(standardEmptyData(controller, listView))
        // `ErrorClassifier` maps NSURLErrorNotConnectedToInternet to
        // `APIError.networkFailure`, whose message is the underlying error's
        // localizedDescription when no failing URL is attached.
        #expect(viewModel.body == "The Internet connection appears to be offline.")
        #expect(viewModel.buttonConfig?.text == "Try Again", "Retry button should be offered on network error")
    }

    /// The error state's Try Again button must actually reload: after swapping the
    /// failing mock for a good payload, tapping it should land the picker in `.data`.
    @Test @MainActor
    func `Retry button reloads and recovers once the network succeeds`() async throws {
        let arrivalDeparture = try makeArrivalDeparture()  // stopID = "1_10914"
        let forwardStopIDs = ["1_10915"]

        let dataLoader = MockDataLoader(testName: name)
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                                   userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: networkError) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        })
        let app = createApplication(dataLoader: dataLoader)

        let controller = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)
        controller.loadViewIfNeeded()

        let listView = OBAListView()
        await poll(
            until: { self.standardEmptyData(controller, listView)?.buttonConfig != nil },
            "picker never entered the error state"
        )
        let retryConfig = try #require(standardEmptyData(controller, listView)?.buttonConfig)

        let successData = try makeTripDetailsData(stopIDs: stopIDsWithBoarding(arrivalDeparture.stopID, forward: forwardStopIDs))
        dataLoader.replaceMappedResponses { loader in
            self.registerBaseStubs(on: loader)
            loader.mock(data: successData) { $0.url?.path.contains("/api/where/trip-details") ?? false }
        }
        retryConfig.action()

        await poll(
            until: { !controller.items(for: listView).isEmpty },
            "retry never reloaded the stop list"
        )
        #expect(
            controller.items(for: listView).first?.contents.count == forwardStopIDs.count,
            "Retry should reload and show the forward stops"
        )
    }
}
