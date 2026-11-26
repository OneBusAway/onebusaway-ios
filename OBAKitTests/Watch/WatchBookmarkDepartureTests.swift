//
//  WatchBookmarkDepartureTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// A watch bookmark's next departure: live when the watch can reach the
/// server, saved when it can't.
@Suite(.serialized)
final class WatchBookmarkDepartureTests: OBATestCase {

    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"
    private let schedulePath = "/api/where/schedule-for-stop"
    private let fixtureFile = "arrivals-and-departures-for-stop-1_75414.json"
    private let scheduleFixture = "schedule-for-stop_1_75403.json"
    private let stopID = "1_75414"

    private var directory: URL!
    private var store: SavedArrivalsStore!

    override init() async throws {
        try await super.init()
        directory = FileManager.default.temporaryDirectory.appending(path: "WatchBookmarkDepartureTests-\(UUID().uuidString)")
        store = SavedArrivalsStore(directory: directory)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    private func stopBookmark() -> WatchBookmark {
        WatchBookmark(
            id: UUID(),
            name: "Stop",
            regionIdentifier: Int32(pugetSoundRegionIdentifier),
            stopID: stopID,
            stopName: "Stop",
            latitude: 47.6,
            longitude: -122.3,
            isFavorite: false
        )
    }

    /// Bookmarks the fixture's route 75 trips.
    private func tripBookmark() -> WatchBookmark {
        WatchBookmark(
            id: UUID(),
            name: "75",
            regionIdentifier: Int32(pugetSoundRegionIdentifier),
            stopID: stopID,
            stopName: "Stop",
            latitude: 47.6,
            longitude: -122.3,
            isFavorite: false,
            routeID: "1_100269",
            routeShortName: "75",
            tripHeadsign: "Northgate Lake City"
        )
    }

    private func mockArrivals(_ dataLoader: MockDataLoader, body: Data? = nil) {
        dataLoader.mock(data: body ?? Fixtures.loadData(file: fixtureFile)) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
        dataLoader.mock(data: Fixtures.loadData(file: scheduleFixture)) { [schedulePath] request in
            request.url?.path.contains(schedulePath) ?? false
        }
    }

    private func mockOffline(_ dataLoader: MockDataLoader) {
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: URLError(.notConnectedToInternet)) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        })
    }

    /// The fixture's one departure, copied to leave at each of `minutesFromNow`.
    private func arrivalsBody(departingInMinutes minutesFromNow: [Double]) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: Fixtures.loadData(file: fixtureFile)) as? [String: Any])
        var data = try #require(root["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        let template = try #require((entry["arrivalsAndDepartures"] as? [[String: Any]])?.first)
        let nowMS = Date().timeIntervalSince1970 * 1000
        let baseSequence = template["stopSequence"] as? Int ?? 0
        entry["arrivalsAndDepartures"] = minutesFromNow.enumerated().map { index, minutes in
            var departure = template
            departure["stopSequence"] = baseSequence + index
            let time = Int64(nowMS + minutes * 60_000)
            for key in ["predictedArrivalTime", "predictedDepartureTime", "scheduledArrivalTime", "scheduledDepartureTime"] {
                departure[key] = time
            }
            return departure
        }
        data["entry"] = entry
        root["data"] = data
        root["currentTime"] = Int64(nowMS)
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// The timetable fixture with its first route running as route 75 at
    /// `minutesFromNow`, and its second route's first trip 3 minutes from now.
    private func scheduleBody(departingInMinutes minutesFromNow: [Double]) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: Fixtures.loadData(file: scheduleFixture)) as? [String: Any])
        var data = try #require(root["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        var routes = try #require(entry["stopRouteSchedules"] as? [[String: Any]])
        let nowMS = Date().timeIntervalSince1970 * 1000

        func retimed(_ stopTime: [String: Any], minutes: Double, tripID: String) -> [String: Any] {
            var stopTime = stopTime
            stopTime["arrivalTime"] = Int64(nowMS + minutes * 60_000)
            stopTime["departureTime"] = Int64(nowMS + minutes * 60_000)
            stopTime["tripId"] = tripID
            return stopTime
        }

        var first = routes[0]
        var firstDirections = try #require(first["stopRouteDirectionSchedules"] as? [[String: Any]])
        let template = try #require((firstDirections[0]["scheduleStopTimes"] as? [[String: Any]])?.first)
        first["routeId"] = "1_100269"
        firstDirections[0]["tripHeadsign"] = "Northgate Lake City"
        firstDirections[0]["scheduleStopTimes"] = minutesFromNow.enumerated().map { retimed(template, minutes: $1, tripID: "scheduled_\($0)") }
        first["stopRouteDirectionSchedules"] = firstDirections
        routes[0] = first

        var second = routes[1]
        var secondDirections = try #require(second["stopRouteDirectionSchedules"] as? [[String: Any]])
        var secondTimes = try #require(secondDirections[0]["scheduleStopTimes"] as? [[String: Any]])
        secondTimes[0] = retimed(secondTimes[0], minutes: 3, tripID: "other_route")
        secondDirections[0]["scheduleStopTimes"] = secondTimes
        second["stopRouteDirectionSchedules"] = secondDirections
        routes[1] = second

        entry["stopRouteSchedules"] = routes
        data["entry"] = entry
        root["data"] = data
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// The departures the stream yields once every stop has reported.
    private func collectDepartures(for bookmarks: [WatchBookmark], using dataLoader: MockDataLoader) async -> [UUID: WatchBookmarkDeparture] {
        var result = [UUID: WatchBookmarkDeparture]()
        for await departures in BookmarkArrivalsLoader(savedArrivals: store)
            .nextDeparturesByWatchBookmark(for: bookmarks, using: buildRESTService(dataLoader: dataLoader)) {
            result = departures
        }
        return result
    }

    // MARK: - Tests

    @Test func `Online, the next departure is live and saved for later`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, body: try arrivalsBody(departingInMinutes: [-2, 4, 12]))
        let bookmark = stopBookmark()

        let result = await collectDepartures(for: [bookmark], using: dataLoader)

        let departure = try #require(result[bookmark.id])
        #expect((3...4).contains(try #require(departure.arrival).arrivalDepartureMinutes))
        #expect(departure.scheduledDeparture == nil)
        #expect(departure.savedAt == nil)
        #expect(store.load(stopID: stopID, regionID: pugetSoundRegionIdentifier) != nil)
    }

    @Test func `Offline, the next saved departure stands in, marked with its save time`() async throws {
        let savedAt = Date().addingTimeInterval(-600)
        store.save(try arrivalsBody(departingInMinutes: [-1, 6, 15]), stopID: stopID, regionID: pugetSoundRegionIdentifier, savedAt: savedAt)
        let dataLoader = MockDataLoader(testName: name)
        mockOffline(dataLoader)
        let bookmark = tripBookmark()

        let result = await collectDepartures(for: [bookmark], using: dataLoader)

        let departure = try #require(result[bookmark.id])
        // The one that left a minute ago is dropped.
        #expect((5...6).contains(try #require(departure.arrival).arrivalDepartureMinutes))
        #expect(departure.scheduledDeparture == nil)
        #expect(abs(try #require(departure.savedAt).timeIntervalSince(savedAt)) < 1)
    }

    @Test func `Offline with every saved departure gone, the bookmark's next timetable trip stands in`() async throws {
        let savedAt = Date().addingTimeInterval(-3600)
        store.save(try arrivalsBody(departingInMinutes: [-5]), stopID: stopID, regionID: pugetSoundRegionIdentifier, savedAt: savedAt)
        store.save(try scheduleBody(departingInMinutes: [-2, 8, 30]), kind: .schedule, stopID: stopID, regionID: pugetSoundRegionIdentifier, savedAt: savedAt)
        let dataLoader = MockDataLoader(testName: name)
        mockOffline(dataLoader)
        let trip = tripBookmark()
        let stop = stopBookmark()

        let result = await collectDepartures(for: [trip, stop], using: dataLoader)

        // The trip bookmark skips the other route's sooner trip.
        let tripDeparture = try #require(result[trip.id])
        #expect(tripDeparture.arrival == nil)
        #expect(tripDeparture.scheduledDeparture?.tripID == "scheduled_1")
        #expect(tripDeparture.savedAt != nil)

        // A whole-stop bookmark takes the stop's next trip on any route.
        let stopDeparture = try #require(result[stop.id])
        #expect(stopDeparture.scheduledDeparture?.tripID == "other_route")
    }

    @Test func `Offline with nothing saved, the bookmark has no departure`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockOffline(dataLoader)
        let bookmark = stopBookmark()

        let result = await collectDepartures(for: [bookmark], using: dataLoader)

        #expect(result[bookmark.id] == nil)
    }

    @Test func `A hung timetable download does not hold back the live departure`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: try arrivalsBody(departingInMinutes: [4])) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
        dataLoader.mock(hangs: { [schedulePath] request in
            request.url?.path.contains(schedulePath) ?? false
        })
        let bookmark = stopBookmark()

        let stream = BookmarkArrivalsLoader(savedArrivals: store)
            .nextDeparturesByWatchBookmark(for: [bookmark], using: buildRESTService(dataLoader: dataLoader))

        // The arrivals have landed, but the day's timetable download never
        // finishes, so the stream never ends: this first snapshot must already
        // carry the live departure. Letting `iterator` go out of scope ends
        // the iteration, which cancels the hung download.
        var iterator = stream.makeAsyncIterator()
        let snapshot = await iterator.next()
        let departures = try #require(snapshot)

        let departure = try #require(departures[bookmark.id])
        #expect((3...4).contains(try #require(departure.arrival).arrivalDepartureMinutes))
        #expect(departure.scheduledDeparture == nil)
        #expect(departure.savedAt == nil)
    }
}
