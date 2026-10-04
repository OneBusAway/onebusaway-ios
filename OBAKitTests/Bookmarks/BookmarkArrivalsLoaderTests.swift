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

    @Test func `Standalone service targets the region's base URL`() async {
        let service = RESTAPIService.standalone(region: Fixtures.pugetSoundRegion, apiKey: "key", appVersion: "1.0", uuid: "uuid")
        #expect(await service.configuration.baseURL == Fixtures.pugetSoundRegion.OBABaseURL)
        #expect(await service.configuration.regionIdentifier == Fixtures.pugetSoundRegion.regionIdentifier)
    }
}
