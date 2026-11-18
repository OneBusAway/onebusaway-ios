//
//  TripPageAdjacentTripTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The trip page's "Starts as" and "Continues as" rows: the trips they name,
/// what a tap fetches, and where the fetched trip opens.
///
/// The details fixture is trip 1_18196913, whose vehicle runs 1_18196851
/// (route 67) before it and 1_18196555 (route 65) after it. The page is opened
/// from Route 49's departure at stop 1_10914, with vehicle 1_4559 and service
/// date 1541055600000, and serves those details for it. A request can only
/// carry that vehicle and date if it reads them from the trip the page shows.
@Suite(.serialized)
@MainActor
final class TripPageAdjacentTripTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private nonisolated static let previousTripID = "1_18196851"
    private nonisolated static let nextTripID = "1_18196555"

    // MARK: - Helpers

    /// Counts the errors the app is asked to show, rather than showing them.
    private final class DisplayErrorSpyApplication: Application {
        private(set) var displayErrorCallCount = 0

        override func displayError(_ error: Error) async {
            displayErrorCallCount += 1
        }
    }

    /// The trip details fixture, with `edit` applied to its `data` object.
    private static func tripDetailsPayload(editing edit: (inout [String: Any]) throws -> Void = { _ in }) throws -> Data {
        let fixture = Fixtures.loadData(file: "trip_details_1_18196913.json")
        var root = try #require(try JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        var payload = try #require(root["data"] as? [String: Any])
        try edit(&payload)
        root["data"] = payload
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// The fixture answering for `tripID`. Its references describe both adjacent
    /// trips, so either can stand as the entry's own trip.
    private static func tripDetailsPayload(forTripID tripID: String) throws -> Data {
        try tripDetailsPayload { payload in
            var entry = try #require(payload["entry"] as? [String: Any])
            entry["tripId"] = tripID
            payload["entry"] = entry
        }
    }

    private static func decodeTripDetails(_ data: Data) throws -> TripDetails {
        try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data).entry
    }

    private nonisolated static func isTripDetailsRequest(_ request: URLRequest, tripID: String) -> Bool {
        request.url.map { isTripDetailsURL($0, tripID: tripID) } ?? false
    }

    private nonisolated static func isTripDetailsURL(_ url: URL, tripID: String) -> Bool {
        url.path.hasSuffix("/api/where/trip-details/\(tripID).json")
    }

    /// Answers both adjacent trips with their own details. Register before
    /// `makeApplication`, whose stub answers every other trip's details:
    /// `MockDataLoader` serves the first stub that matches.
    private func stubAdjacentTrips(dataLoader: MockDataLoader) throws {
        for tripID in [Self.previousTripID, Self.nextTripID] {
            dataLoader.mock(data: try Self.tripDetailsPayload(forTripID: tripID)) {
                Self.isTripDetailsRequest($0, tripID: tripID)
            }
        }
    }

    /// Answers everything the page asks for before a tap: the details fixture
    /// for its own trip, an empty route line, and a failed arrival, which leaves
    /// the page on the departure it opened with.
    private func makeApplication(dataLoader: MockDataLoader, transport: URLDataLoader? = nil) -> DisplayErrorSpyApplication {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        dataLoader.mock(data: Data(#"{"surveys":[]}"#.utf8)) { $0.url?.path.contains("/surveys.json") ?? false }
        dataLoader.mock(data: Fixtures.loadData(file: "trip_details_1_18196913.json")) {
            $0.url?.path.contains("/api/where/trip-details") ?? false
        }
        dataLoader.mock(data: Data(), statusCode: 500) {
            $0.url?.path.contains("/api/where/arrival-and-departure-for-stop") ?? false
        }
        let emptyShape = Data(#"{"data":{"entry":{"length":0,"points":"","levels":""}},"code":200,"version":2,"text":"OK","currentTime":1700000000000}"#.utf8)
        dataLoader.mock(data: emptyShape) { $0.url?.path.contains("/api/where/shape") ?? false }

        let locationManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: LocationService(userDefaults: userDefaults, locationManager: locationManager),
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: transport ?? dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name,
            onDemandSupport: OnDemandSupport(),
            retryPolicy: .disabled
        )
        return DisplayErrorSpyApplication(config: config)
    }

    /// A page opened from Route 49's departure, with its trip's details loaded so
    /// both rows are showing.
    private func makeLoadedPage(application: Application) async throws -> TripPageViewController {
        let page = try TripPageFixture.makeOnScreenPage(application: application)
        page.viewModel.loadData()
        await page.viewModel.loadDataTask?.value
        try #require(page.viewModel.adjacentTrips.previous != nil)
        try #require(page.viewModel.adjacentTrips.next != nil)
        return page
    }

    private func requests(dataLoader: MockDataLoader, tripID: String) -> [URL] {
        dataLoader.recordedRequestURLs.filter { Self.isTripDetailsURL($0, tripID: tripID) }
    }

    // MARK: - Rows

    @Test func `The rows name the trips the vehicle runs before and after this one`() throws {
        let trips = TripAdjacentTrips(details: try Self.decodeTripDetails(Self.tripDetailsPayload()))

        #expect(trips.previous?.trip.id == Self.previousTripID)
        #expect(trips.previous?.title == "Starts as 67 - UNIVERSITY DISTRICT ROOSEVELT")
        #expect(trips.next?.trip.id == Self.nextTripID)
        #expect(trips.next?.title == "Continues as 65 - UNIVERSITY DISTRICT WEDGWOOD")
    }

    /// Each side stands alone: a trip the references don't describe gets no row,
    /// and the row on the other side still names its own trip.
    @Test func `A side with no trip gets no row, and the other side keeps its own`() throws {
        let unloaded = TripAdjacentTrips(details: nil)
        #expect(unloaded.previous == nil)
        #expect(unloaded.next == nil)

        let details = try Self.decodeTripDetails(Self.tripDetailsPayload { payload in
            var entry = try #require(payload["entry"] as? [String: Any])
            var schedule = try #require(entry["schedule"] as? [String: Any])
            schedule["previousTripId"] = "1_not_in_the_references"
            entry["schedule"] = schedule
            payload["entry"] = entry
        })
        let trips = TripAdjacentTrips(details: details)
        #expect(trips.previous == nil)
        #expect(trips.next?.trip.id == Self.nextTripID)
        #expect(trips.next?.title == "Continues as 65 - UNIVERSITY DISTRICT WEDGWOOD")
    }

    /// `OBALoc` falls back to its English `value:`, so the titles above read the
    /// same with the keys missing. Looked up with a sentinel fallback instead.
    @Test func `Both rows' strings are in the English catalog`() throws {
        let path = try #require(Bundle.obaKit.path(forResource: "en", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))

        #expect(bundle.localizedString(forKey: "trip_page.starts_as_fmt", value: "MISSING", table: nil) == "Starts as %@")
        #expect(bundle.localizedString(forKey: "trip_page.continues_as_fmt", value: "MISSING", table: nil) == "Continues as %@")
    }

    // MARK: - Tapping a row

    @Test func `Continues as fetches the next trip with this trip's vehicle and service date, and opens it`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        try stubAdjacentTrips(dataLoader: dataLoader)
        let page = try await makeLoadedPage(application: makeApplication(dataLoader: dataLoader))
        var opened: [TripConvertible] = []
        page.onSelectTrip = { opened.append($0) }

        page.rootView.actions.onSelectAdjacentTrip(.next)
        await page.viewModel.adjacentTripTask?.value

        let request = try #require(requests(dataLoader: dataLoader, tripID: Self.nextTripID).first)
        let query = (URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .reduce(into: [String: String]()) { $0[$1.name] = $1.value }
        #expect(query["vehicleId"] == "1_4559")
        #expect(query["serviceDate"] == "1541055600000")
        #expect(requests(dataLoader: dataLoader, tripID: Self.previousTripID).isEmpty)
        #expect(opened.map(\.tripID) == [Self.nextTripID])
        #expect(page.viewModel.loadingAdjacentTrip == nil)
    }

    @Test func `Starts as fetches and opens the previous trip`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        try stubAdjacentTrips(dataLoader: dataLoader)
        let page = try await makeLoadedPage(application: makeApplication(dataLoader: dataLoader))
        var opened: [TripConvertible] = []
        page.onSelectTrip = { opened.append($0) }

        page.rootView.actions.onSelectAdjacentTrip(.previous)
        await page.viewModel.adjacentTripTask?.value

        #expect(requests(dataLoader: dataLoader, tripID: Self.previousTripID).count == 1)
        #expect(requests(dataLoader: dataLoader, tripID: Self.nextTripID).isEmpty)
        #expect(opened.map(\.tripID) == [Self.previousTripID])
    }

    /// The row goes back to normal so the rider can try again, and the error
    /// goes to the app's toast, as the trip panel's did.
    @Test func `A trip that fails to load opens nothing, and the app says so`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Data(), statusCode: 500) { Self.isTripDetailsRequest($0, tripID: Self.nextTripID) }
        let application = makeApplication(dataLoader: dataLoader)
        let page = try await makeLoadedPage(application: application)
        var opened: [TripConvertible] = []
        page.onSelectTrip = { opened.append($0) }
        #expect(application.displayErrorCallCount == 0)

        page.rootView.actions.onSelectAdjacentTrip(.next)
        await page.viewModel.adjacentTripTask?.value

        #expect(requests(dataLoader: dataLoader, tripID: Self.nextTripID).count == 1)
        #expect(opened.isEmpty)
        #expect(application.displayErrorCallCount == 1)
        #expect(page.viewModel.loadingAdjacentTrip == nil)
    }

    /// The row shows a spinner while its trip loads. Another tap, on either row,
    /// would open a second trip over the first.
    @Test func `While a trip loads its row says so, and no other tap starts a second`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        try stubAdjacentTrips(dataLoader: dataLoader)
        let gate = GatedDataLoader(
            dataLoader,
            gating: { Self.isTripDetailsRequest($0, tripID: Self.nextTripID) },
            holdsAfterResponse: true
        )
        let page = try await makeLoadedPage(application: makeApplication(dataLoader: dataLoader, transport: gate))
        var opened: [TripConvertible] = []
        page.onSelectTrip = { opened.append($0) }

        page.rootView.actions.onSelectAdjacentTrip(.next)
        await gate.waitForRequest()
        #expect(page.viewModel.loadingAdjacentTrip == .next)

        page.rootView.actions.onSelectAdjacentTrip(.next)
        page.rootView.actions.onSelectAdjacentTrip(.previous)
        gate.releaseRequest()
        await page.viewModel.adjacentTripTask?.value

        #expect(requests(dataLoader: dataLoader, tripID: Self.nextTripID).count == 1)
        #expect(requests(dataLoader: dataLoader, tripID: Self.previousTripID).isEmpty)
        #expect(opened.map(\.tripID) == [Self.nextTripID])
        #expect(page.viewModel.loadingAdjacentTrip == nil)
    }

    /// A sheet opened over the trip's stops its work. A trip arriving after that
    /// would open over whatever the rider went to instead.
    @Test func `A page covered while its trip loads opens nothing`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        try stubAdjacentTrips(dataLoader: dataLoader)
        let gate = GatedDataLoader(
            dataLoader,
            gating: { Self.isTripDetailsRequest($0, tripID: Self.nextTripID) },
            holdsAfterResponse: true
        )
        let application = makeApplication(dataLoader: dataLoader, transport: gate)
        let page = try await makeLoadedPage(application: application)
        var opened: [TripConvertible] = []
        page.onSelectTrip = { opened.append($0) }

        page.rootView.actions.onSelectAdjacentTrip(.next)
        await gate.waitForRequest()
        let load = try #require(page.viewModel.adjacentTripTask)

        page.setCoveredBySheet(true)
        #expect(page.viewModel.loadingAdjacentTrip == nil)

        gate.releaseRequest()
        await load.value

        #expect(opened.isEmpty)
        #expect(application.displayErrorCallCount == 0)
    }

    // MARK: - Where the trip opens

    /// The map tab's stop sheet pushes the trip page bare, over the map tab's map,
    /// and sets no hook. The next trip goes on the same stack and draws on the
    /// same map.
    @Test func `With no host to ask, the trip opens as a bare page on this one's stack, drawing on the same map`() throws {
        let dataLoader = MockDataLoader(testName: name)
        try stubAdjacentTrips(dataLoader: dataLoader)
        let page = try TripPageFixture.makePage(application: makeApplication(dataLoader: dataLoader))
        let navigation = UINavigationController(rootViewController: page)
        var reported: [TripMapFocus?] = []
        page.onMapFocusChanged = { reported.append($0) }
        let convertible = TripConvertible(tripDetails: try Self.decodeTripDetails(Self.tripDetailsPayload(forTripID: Self.nextTripID)))

        page.openTrip(convertible)

        #expect(navigation.viewControllers.count == 2)
        let pushed = try #require(navigation.viewControllers.last as? TripPageViewController)
        #expect(pushed.viewModel.tripConvertible.tripID == Self.nextTripID)
        pushed.onMapFocusChanged?(pushed.mapFocus)
        #expect(reported.count == 1)
        #expect(reported.first.flatMap { $0 } === pushed.mapFocus)
    }
}
