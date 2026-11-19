//
//  BookmarkArrivalsLoaderTests.swift
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
final class BookmarkArrivalsLoaderTests: OBATestCase {

    // `nonisolated`: recorded from `MockDataLoaderMatcher` closures, which run
    // wherever the request is issued (not necessarily the main actor). The
    // test target defaults to main-actor isolation, which would be wrong here
    // — see the same rationale on `MockDataLoader` itself.
    private nonisolated final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var paths = [String]()

        func record(_ path: String) {
            lock.lock(); defer { lock.unlock() }
            paths.append(path)
        }

        var all: [String] {
            lock.lock(); defer { lock.unlock() }
            return paths
        }
    }

    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"

    private func mockArrivals(_ dataLoader: MockDataLoader, log: RequestLog, failingStopID: String? = nil) {
        if let failingStopID {
            dataLoader.mock(data: Data("{}".utf8), statusCode: 500) { request in
                request.url?.path.contains(failingStopID) ?? false
            }
        }
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { [arrivalsPath] request in
            guard let path = request.url?.path, path.contains(arrivalsPath) else { return false }
            if let failingStopID, path.contains(failingStopID) { return false }
            log.record(path)
            return true
        }
    }

    @Test func `Two requests at one stop make one network call`() async {
        let dataLoader = MockDataLoader(testName: name)
        let log = RequestLog()
        mockArrivals(dataLoader, log: log)
        let service = buildRESTService(dataLoader: dataLoader)

        let requests = [
            BookmarkArrivalsRequest(stopID: "1_75414"),
            BookmarkArrivalsRequest(stopID: "1_75414", tripKey: TripBookmarkKey(stopID: "1_75414", routeShortName: "X", routeID: "1_X", tripHeadsign: "Y")),
            BookmarkArrivalsRequest(stopID: "1_10914")
        ]

        var delivered = [StopID]()
        for await (stopID, _) in BookmarkArrivalsLoader().arrivals(for: requests, using: service) {
            delivered.append(stopID)
        }

        #expect(log.all.count == 2)
        #expect(Set(delivered) == ["1_75414", "1_10914"])
        #expect(delivered.count == 2)
    }

    @Test func `No requests finishes immediately with no network calls`() async {
        let dataLoader = MockDataLoader(testName: name)
        let log = RequestLog()
        mockArrivals(dataLoader, log: log)

        var count = 0
        for await _ in BookmarkArrivalsLoader().arrivals(for: [], using: buildRESTService(dataLoader: dataLoader)) {
            count += 1
        }

        #expect(count == 0)
        #expect(log.all.isEmpty)
    }

    /// One stop failing must not cost the others their data.
    @Test func `A failing stop yields a failure and the rest still succeed`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, log: RequestLog(), failingStopID: "1_BROKEN")
        let service = buildRESTService(dataLoader: dataLoader)

        var results = [StopID: Bool]()
        let requests = [BookmarkArrivalsRequest(stopID: "1_BROKEN"), BookmarkArrivalsRequest(stopID: "1_75414")]
        for await (stopID, result) in BookmarkArrivalsLoader().arrivals(for: requests, using: service) {
            if case .success = result { results[stopID] = true } else { results[stopID] = false }
        }

        #expect(results == ["1_BROKEN": false, "1_75414": true])
    }

    // The fixture's departures are years old, so filtering by `.matching` on it
    // alone leaves an empty (and vacuously-passing) list — `temporalState`
    // reads `Date()`. Built instead from `Fixtures.arrivalDeparture`, whose
    // `.deferredToDate` decode lands in the 2050s (see its doc comment), so
    // these are genuinely upcoming, and out of order here so the sort is
    // actually exercised.
    @Test func `A stop request matches every upcoming departure, soonest first`() throws {
        let stopID = "1_10914"
        let now = Int(Date.timeIntervalSinceReferenceDate)
        let soonest = try Fixtures.arrivalDeparture(scheduledArrival: now + 60, scheduledDeparture: now + 60, stopID: stopID, tripID: "trip_soonest")
        let soon = try Fixtures.arrivalDeparture(scheduledArrival: now + 300, scheduledDeparture: now + 300, stopID: stopID, tripID: "trip_soon")
        let later = try Fixtures.arrivalDeparture(scheduledArrival: now + 900, scheduledDeparture: now + 900, stopID: stopID, tripID: "trip_later")

        let matched = BookmarkArrivalsRequest(stopID: stopID).matching([later, soon, soonest])

        #expect(matched.map(\.tripID) == ["trip_soonest", "trip_soon", "trip_later"])
        #expect(matched.allSatisfy { $0.temporalState != .past })
        #expect(matched.map(\.arrivalDepartureDate) == matched.map(\.arrivalDepartureDate).sorted())
    }

    @Test func `A trip request matches only its own trip key`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_10914.json").arrivalsAndDepartures
        let first = try #require(arrivals.first)
        let key = TripBookmarkKey(arrivalDeparture: first)

        let matched = BookmarkArrivalsRequest(stopID: first.stopID, tripKey: key).matching(arrivals)

        #expect(matched.isEmpty == false)
        #expect(matched.allSatisfy { TripBookmarkKey(arrivalDeparture: $0) == key })
    }

    @Test func `Departures by bookmark omits a bookmark whose stop failed`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let stops = try Fixtures.loadSomeStops()
        let good = Bookmark(name: "Good", regionIdentifier: pugetSoundRegionIdentifier, stop: stops[0])
        let bad = Bookmark(name: "Bad", regionIdentifier: pugetSoundRegionIdentifier, stop: stops[1])
        mockArrivals(dataLoader, log: RequestLog(), failingStopID: stops[1].id)

        let result = await BookmarkArrivalsLoader().departuresByBookmark(for: [good, bad], using: buildRESTService(dataLoader: dataLoader))

        #expect(result[good.id] != nil)
        #expect(result[bad.id] == nil)
    }

    @Test func `Departures by watch bookmark returns arrivals for watch bookmarks`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let stops = try Fixtures.loadSomeStops()
        let good = WatchBookmark(
            id: UUID(),
            name: "Good Watch",
            regionIdentifier: Int32(pugetSoundRegionIdentifier),
            stopID: stops[0].id,
            stopName: stops[0].name,
            latitude: stops[0].coordinate.latitude,
            longitude: stops[0].coordinate.longitude,
            isFavorite: false
        )
        let bad = WatchBookmark(
            id: UUID(),
            name: "Bad Watch",
            regionIdentifier: Int32(pugetSoundRegionIdentifier),
            stopID: stops[1].id,
            stopName: stops[1].name,
            latitude: stops[1].coordinate.latitude,
            longitude: stops[1].coordinate.longitude,
            isFavorite: false
        )
        mockArrivals(dataLoader, log: RequestLog(), failingStopID: stops[1].id)

        let result = await BookmarkArrivalsLoader().departuresByWatchBookmark(
            for: [good, bad],
            using: buildRESTService(dataLoader: dataLoader)
        )

        #expect(result[good.id] != nil)
        #expect(result[bad.id] == nil)
    }

    @Test func `TripBookmarkKey initialization from watch bookmark`() {
        let tripBookmark = WatchBookmark(
            id: UUID(),
            name: "Trip Bookmark",
            regionIdentifier: 1,
            stopID: "1_100",
            stopName: "Stop",
            latitude: 47.6,
            longitude: -122.3,
            isFavorite: true,
            routeID: "1_40",
            routeShortName: "40",
            tripHeadsign: "Downtown"
        )
        let key = TripBookmarkKey(watchBookmark: tripBookmark)
        #expect(key != nil)
        #expect(key?.stopID == "1_100")
        #expect(key?.routeID == "1_40")
        #expect(key?.routeShortName == "40")
        #expect(key?.tripHeadsign == "Downtown")

        let stopBookmark = WatchBookmark(
            id: UUID(),
            name: "Stop Bookmark",
            regionIdentifier: 1,
            stopID: "1_100",
            stopName: "Stop",
            latitude: 47.6,
            longitude: -122.3,
            isFavorite: false
        )
        #expect(TripBookmarkKey(watchBookmark: stopBookmark) == nil)
    }

    @Test func `Standalone service targets the region's base URL`() async {
        let service = RESTAPIService.standalone(region: Fixtures.pugetSoundRegion, apiKey: "key", appVersion: "1.0", uuid: "uuid")
        #expect(await service.configuration.baseURL == Fixtures.pugetSoundRegion.OBABaseURL)
        #expect(await service.configuration.regionIdentifier == Fixtures.pugetSoundRegion.regionIdentifier)
    }

    @Test func `Standalone service performs a single attempt against a loader that returns 500`() async {
        let mockLoader = MockDataLoader(testName: name)
        mockLoader.mock(data: Data("{}".utf8), statusCode: 500) { _ in true }
        let countingLoader = CountingDataLoader(mockLoader)

        let service = RESTAPIService.standalone(
            region: Fixtures.pugetSoundRegion,
            apiKey: "key",
            appVersion: "1.0",
            uuid: "uuid",
            dataLoader: countingLoader
        )
        #expect(service.retryPolicy == .disabled)

        do {
            _ = try await service.getStop(id: "1_75414")
            Issue.record("Expected request to fail with 500")
        } catch {
            // Expected
        }

        #expect(countingLoader.callCount == 1)
    }

    @Test func `BookmarkArrivalsRequest matching filters past departures and sorts upcoming arrivals soonest first`() throws {
        let now = Int(Date.timeIntervalSinceReferenceDate)
        let stopID = "1_100"

        let past = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: now - 3600,
            scheduledDeparture: now - 3600,
            stopSequence: 1,
            stopID: stopID,
            tripID: "trip_past"
        )
        let upcomingLater = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: now + 600,
            scheduledDeparture: now + 600,
            stopSequence: 2,
            stopID: stopID,
            tripID: "trip_later"
        )
        let upcomingSoon = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: now + 300,
            scheduledDeparture: now + 300,
            stopSequence: 3,
            stopID: stopID,
            tripID: "trip_soon"
        )

        #expect(past.temporalState == .past)
        #expect(upcomingLater.temporalState != .past)
        #expect(upcomingSoon.temporalState != .past)

        let request = BookmarkArrivalsRequest(stopID: stopID)
        let matched = request.matching([upcomingLater, past, upcomingSoon])

        #expect(matched.count == 2)
        #expect(matched.map(\.tripID) == ["trip_soon", "trip_later"])
        #expect(matched.first?.arrivalDepartureDate == upcomingSoon.arrivalDepartureDate)
        #expect(matched.last?.arrivalDepartureDate == upcomingLater.arrivalDepartureDate)
    }

    @Test func `BookmarkArrivalsRequest matching with non matching tripKey returns empty array`() throws {
        let now = Int(Date.timeIntervalSinceReferenceDate)
        let dep = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: now + 300,
            scheduledDeparture: now + 300,
            stopSequence: 1,
            stopID: "1_100"
        )

        let unmatchedKey = TripBookmarkKey(stopID: "1_100", routeShortName: "NonExistent", routeID: "1_999", tripHeadsign: "Nowhere")
        let request = BookmarkArrivalsRequest(stopID: "1_100", tripKey: unmatchedKey)

        let matched = request.matching([dep])
        #expect(matched.isEmpty)
    }
}
