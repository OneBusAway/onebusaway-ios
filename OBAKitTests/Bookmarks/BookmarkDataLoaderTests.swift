//
//  BookmarkDataLoaderTests.swift
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

@Suite(.serialized)
final class BookmarkDataLoaderTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Thread-safe counter for tracking request counts.
    private final class RequestCounter {
        private let lock = NSLock()
        nonisolated(unsafe) private(set) var count: Int = 0

        nonisolated func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    /// Counts arrivals requests so the scoped-provider test can assert the
    /// loader fetched only the bookmarks it was handed.
    @MainActor
    private final class RecordingDelegate: NSObject, BookmarkDataDelegate {
        var updateCount = 0
        func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) { updateCount += 1 }
    }

    /// Builds real *trip* bookmarks — `isTripBookmark` requires a route short
    /// name, route id, and trip headsign, which only a decoded `ArrivalDeparture`
    /// supplies. A bookmark that isn't a trip bookmark is skipped by the loader
    /// without a request, which would silently zero out the counts below.
    ///
    /// Each bookmark gets its **own stop**. The loader fetches a stop once
    /// however many bookmarks share it, so bookmarks at a single stop would
    /// collapse into one request and the counts below would stop measuring
    /// what they are there to measure: which bookmarks were fetched.
    @MainActor
    private func makeTripBookmarks(count: Int, application: Application) throws -> [Bookmark] {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let stops = try Fixtures.loadSomeStops()
        try #require(stops.count >= count)

        return (0..<count).map { index in
            let bookmark = Bookmark(
                name: "Bookmark \(index)",
                regionIdentifier: pugetSoundRegionIdentifier,
                arrivalDeparture: arrivalDeparture,
                stop: stops[index]
            )
            bookmark.sortOrder = index
            application.userDataStore.add(bookmark, to: nil)
            return bookmark
        }
    }

    /// The provider — not the whole store — decides what gets fetched.
    @Test @MainActor
    func `Bookmark provider scopes fetches to the supplied bookmarks`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let requestCounter = RequestCounter()
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            let matches = request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            if matches { requestCounter.increment() }
            return matches
        }

        let all = try makeTripBookmarks(count: 6, application: application)
        let scoped = Array(all.prefix(2))

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(
            application: application,
            delegate: delegate,
            bookmarkProvider: { scoped },
            autoRefreshes: false
        )

        await loader.loadDataAndWait()

        // Six bookmarks exist; only the two handed to the provider are fetched.
        #expect(requestCounter.count == 2)
    }

    /// With auto-refresh off, the loader installs no repeating timer.
    @Test @MainActor
    func `Auto refresh disabled installs no timer`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let bookmarks = try makeTripBookmarks(count: 1, application: application)
        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(
            application: application,
            delegate: delegate,
            bookmarkProvider: { bookmarks },
            autoRefreshes: false
        )

        await loader.loadDataAndWait()

        #expect(loader.hasScheduledRefresh == false)
    }

    /// The Bookmarks tab's construction is untouched: every region bookmark is
    /// fetched and the repeating timer is installed.
    @Test @MainActor
    func `Default initializer fetches all region bookmarks and schedules refresh`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let requestCounter = RequestCounter()
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            let matches = request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            if matches { requestCounter.increment() }
            return matches
        }

        _ = try makeTripBookmarks(count: 3, application: application)

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(application: application, delegate: delegate)

        await loader.loadDataAndWait()

        #expect(requestCounter.count == 3)
        #expect(loader.hasScheduledRefresh)

        loader.cancelUpdates()
    }

    /// Two trip bookmarks at one stop are one request — and both still settle,
    /// or `loadDataAndWait()` would hang on the second bookmark's slot.
    @Test @MainActor
    func `Bookmarks sharing a stop are fetched once and both settle`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let requestCounter = RequestCounter()
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            let matches = request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            if matches { requestCounter.increment() }
            return matches
        }

        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_10914.json")
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let shared = (0..<2).map { index in
            Bookmark(name: "Shared \(index)", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture)
        }

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(application: application, delegate: delegate, bookmarkProvider: { shared }, autoRefreshes: false)

        await loader.loadDataAndWait()

        #expect(requestCounter.count == 1)
        #expect(loader.isLoading == false)
        #expect(loader.hasFetchedData(forStopID: arrivalDeparture.stopID))
        #expect(delegate.updateCount == 1)
    }

    /// A stop bookmark reserves a slot and never fetches; it must release it.
    @Test @MainActor
    func `A batch of only stop bookmarks completes without a request`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let stopBookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)

        let loader = BookmarkDataLoader(application: application, delegate: RecordingDelegate(), bookmarkProvider: { [stopBookmark] }, autoRefreshes: false)

        await loader.loadDataAndWait()

        #expect(loader.isLoading == false)
        #expect(loader.hasFetchedData(forStopID: stop.id) == false)
    }

    // MARK: - Destination Arrivals (#1080)

    /// The trip-details service date used by `makeTripDetailsData(stopIDs:)`.
    private static let tripServiceDate = Date(timeIntervalSince1970: 1_541_055_600)

    /// The 1_10914 arrivals fixture with its one departure moved 10 minutes
    /// into the future and running 2 minutes late. The fixture's own times are
    /// from 2018, and the loader only looks up schedules for upcoming departures.
    private func upcomingArrivalsData() throws -> Data {
        let data = Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        var payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payloadData = try #require(payload["data"] as? [String: Any])
        var entry = try #require(payloadData["entry"] as? [String: Any])
        let arrivals = try #require(entry["arrivalsAndDepartures"] as? [[String: Any]])

        let scheduled = Int((Date().timeIntervalSince1970 + 600) * 1000)
        entry["arrivalsAndDepartures"] = arrivals.map { arrival in
            var arrival = arrival
            arrival["scheduledArrivalTime"] = scheduled
            arrival["scheduledDepartureTime"] = scheduled
            arrival["predictedArrivalTime"] = scheduled + 120_000
            arrival["predictedDepartureTime"] = scheduled + 120_000
            arrival["predicted"] = true
            return arrival
        }
        payloadData["entry"] = entry
        payload["data"] = payloadData
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// A minimal trip-details payload whose schedule visits `stopIDs` in order,
    /// one stop every 2 minutes. Mirrors `DestinationStopPickerControllerTests`.
    private func makeTripDetailsData(stopIDs: [String], tripID: String = "1_40984902") throws -> Data {
        let stopTimes: [[String: Any]] = stopIDs.enumerated().map { idx, id in
            ["stopId": id, "arrivalTime": 58862 + idx * 120, "departureTime": 58862 + idx * 120,
             "distanceAlongTrip": Double(idx) * 300.0, "stopHeadsign": ""]
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
                    "serviceDate": Int(Self.tripServiceDate.timeIntervalSince1970 * 1000),
                    "situationIds": [] as [String],
                    "schedule": ["timeZone": "America/Los_Angeles", "stopTimes": stopTimes]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Schedules load after the batch completes, so tests wait for them.
    @MainActor
    private func waitForDestinationArrival(
        _ loader: BookmarkDataLoader,
        bookmark: Bookmark,
        destinationStopID: StopID
    ) async throws -> DestinationArrivalLookup {
        let tripKey = try #require(TripBookmarkKey(bookmark: bookmark))
        let departure = try #require(loader.dataForKey(tripKey).first)
        await poll(
            until: { loader.destinationArrival(for: departure, destinationStopID: destinationStopID) != .pending },
            "the trip schedule never loaded"
        )
        return loader.destinationArrival(for: departure, destinationStopID: destinationStopID)
    }

    /// Stubs upcoming arrivals at 1_10914 and a trip schedule that boards there
    /// (stop sequence 3) and later reaches `destinationStopID`. Returns a counter
    /// of trip-details requests.
    @MainActor
    private func stubDestinationTrip(on dataLoader: MockDataLoader, destinationStopID: StopID) throws -> RequestCounter {
        dataLoader.mock(data: try upcomingArrivalsData()) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let tripRequests = RequestCounter()
        let schedule = ["1_before_1", "1_before_2", "1_before_3", "1_10914", "1_middle", destinationStopID]
        dataLoader.mock(data: try makeTripDetailsData(stopIDs: schedule)) { request in
            let matches = request.url?.path.contains("/api/where/trip-details") ?? false
            if matches { tripRequests.increment() }
            return matches
        }
        return tripRequests
    }

    @MainActor
    private func makeDestinationBookmark(destination: Stop?) throws -> Bookmark {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_10914.json")
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        return Bookmark(name: "Commute", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture, destinationStop: destination)
    }

    @Test @MainActor
    func `A destination bookmark resolves the arrival at its destination`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let destination = try #require(try Fixtures.loadSomeStops().first)
        let tripRequests = try stubDestinationTrip(on: dataLoader, destinationStopID: destination.id)
        let bookmark = try makeDestinationBookmark(destination: destination)

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(application: application, delegate: delegate, bookmarkProvider: { [bookmark] }, autoRefreshes: false)

        await loader.loadDataAndWait()

        // The batch is done once the arrivals are in; the schedule loads after it.
        #expect(loader.isLoading == false)

        guard case .arrives(let arrival) = try await waitForDestinationArrival(loader, bookmark: bookmark, destinationStopID: destination.id) else {
            Issue.record("Expected an arrival at the destination")
            return
        }

        // The destination is the 6th stop: 58862 + 5 * 120 seconds into the
        // service day, shifted by the departure's 2-minute delay.
        let scheduledArrival = Calendar.current.date(byAdding: .second, value: 58862 + 5 * 120, to: Self.tripServiceDate)
        #expect(arrival.scheduledArrivalDate == scheduledArrival)
        #expect(arrival.arrivalDate == scheduledArrival?.addingTimeInterval(120))
        #expect(arrival.isRealTime)
        #expect(tripRequests.count == 1)
        // Once for the arrivals, once more when the schedule landed.
        #expect(delegate.updateCount == 2)
    }

    /// A trip's timetable doesn't change between refreshes, so it's fetched once.
    @Test @MainActor
    func `Trip schedules are cached across refreshes`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let destination = try #require(try Fixtures.loadSomeStops().first)
        let tripRequests = try stubDestinationTrip(on: dataLoader, destinationStopID: destination.id)
        let bookmark = try makeDestinationBookmark(destination: destination)

        let loader = BookmarkDataLoader(application: application, delegate: RecordingDelegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false)

        await loader.loadDataAndWait()
        _ = try await waitForDestinationArrival(loader, bookmark: bookmark, destinationStopID: destination.id)
        #expect(tripRequests.count == 1)

        await loader.loadDataAndWait()
        // A second fetch would be a request made by the refresh's schedule task;
        // give it time to happen before concluding it didn't.
        try await Task.sleep(for: .milliseconds(250))

        #expect(tripRequests.count == 1)
    }

    @Test @MainActor
    func `A trip that skips the destination is reported as not served`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let destination = try #require(try Fixtures.loadSomeStops().first)
        _ = try stubDestinationTrip(on: dataLoader, destinationStopID: "1_somewhere_else")
        let bookmark = try makeDestinationBookmark(destination: destination)

        let loader = BookmarkDataLoader(application: application, delegate: RecordingDelegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false)

        await loader.loadDataAndWait()

        let lookup = try await waitForDestinationArrival(loader, bookmark: bookmark, destinationStopID: destination.id)
        #expect(lookup == .notServed)
    }

    /// A trip whose details can't be fetched must stop reading as "loading", and
    /// recover on its own once the server answers again.
    @Test @MainActor
    func `A failed schedule fetch is unavailable and recovers on the next refresh`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let destination = try #require(try Fixtures.loadSomeStops().first)
        let bookmark = try makeDestinationBookmark(destination: destination)

        let arrivalsData = try upcomingArrivalsData()
        let tripData = try makeTripDetailsData(stopIDs: ["1_before_1", "1_before_2", "1_before_3", "1_10914", "1_middle", destination.id])
        let isArrivalsRequest: @Sendable (URLRequest) -> Bool = { $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false }
        let isTripRequest: @Sendable (URLRequest) -> Bool = { $0.url?.path.contains("/api/where/trip-details") ?? false }

        dataLoader.mock(data: arrivalsData, matcher: isArrivalsRequest)
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: networkError, matcher: isTripRequest))

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(application: application, delegate: delegate, bookmarkProvider: { [bookmark] }, autoRefreshes: false)

        await loader.loadDataAndWait()

        let failed = try await waitForDestinationArrival(loader, bookmark: bookmark, destinationStopID: destination.id)
        #expect(failed == .unavailable)
        // Once for the arrivals, once more so the card can drop its "Loading…" line.
        #expect(delegate.updateCount == 2)

        dataLoader.replaceMappedResponses { loader in
            self.stubRegions(dataLoader: loader)
            loader.mock(data: arrivalsData, matcher: isArrivalsRequest)
            loader.mock(data: tripData, matcher: isTripRequest)
        }
        await loader.loadDataAndWait()

        let tripKey = try #require(TripBookmarkKey(bookmark: bookmark))
        await poll(
            until: {
                guard let departure = loader.dataForKey(tripKey).first else { return false }
                if case .arrives = loader.destinationArrival(for: departure, destinationStopID: destination.id) { return true }
                return false
            },
            "the failed trip was never retried"
        )
    }

    /// Ordinary trip bookmarks pay nothing for the feature.
    @Test @MainActor
    func `A trip bookmark without a destination fetches no schedule`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let tripRequests = try stubDestinationTrip(on: dataLoader, destinationStopID: "1_unused")
        let bookmark = try makeDestinationBookmark(destination: nil)

        let loader = BookmarkDataLoader(application: application, delegate: RecordingDelegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false)

        await loader.loadDataAndWait()

        #expect(tripRequests.count == 0)
    }
}
