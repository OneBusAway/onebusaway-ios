//
//  SavedBookmarkDeparturesTests.swift
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

/// `departuresByBookmarkKeepingSaved`, which the home screen widget uses: per
/// bookmark departures, with saved ones standing in for a stop it can't reach.
@Suite(.serialized)
final class SavedBookmarkDeparturesTests: OBATestCase {

    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"
    private let schedulePath = "/api/where/schedule-for-stop"
    private let fixtureFile = "arrivals-and-departures-for-stop-1_75414.json"
    private let scheduleFixture = "schedule-for-stop_1_75403.json"

    private var directory: URL!
    private var store: SavedArrivalsStore!
    private var stopBookmark: Bookmark!
    private var tripBookmark: Bookmark!

    override init() async throws {
        try await super.init()
        directory = FileManager.default.temporaryDirectory.appending(path: "SavedBookmarkDeparturesTests-\(UUID().uuidString)")
        store = SavedArrivalsStore(directory: directory)

        // The fixture's one departure: route 75 (1_100269), "Northgate Lake City".
        let arrival = try #require(try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures.first)
        stopBookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: arrival.stop)
        tripBookmark = Bookmark(name: "Trip", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrival)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    /// The arrivals fixture with its one departure copied to leave at each of
    /// `minutesFromNow`.
    private func savedBody(departingInMinutes minutesFromNow: [Double]) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: Fixtures.loadData(file: fixtureFile)) as? [String: Any])
        var data = try #require(root["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        let template = try #require((entry["arrivalsAndDepartures"] as? [[String: Any]])?.first)
        let nowMS = Date().timeIntervalSince1970 * 1000
        let baseSequence = template["stopSequence"] as? Int ?? 0
        entry["arrivalsAndDepartures"] = minutesFromNow.enumerated().map { index, minutes in
            var departure = template
            departure["stopSequence"] = baseSequence + index
            for key in ["predictedArrivalTime", "predictedDepartureTime", "scheduledArrivalTime", "scheduledDepartureTime"] {
                departure[key] = Int64(nowMS + minutes * 60_000)
            }
            return departure
        }
        data["entry"] = entry
        root["data"] = data
        root["currentTime"] = Int64(nowMS)
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// The timetable fixture with its first route made the trip bookmark's,
    /// running at each of `minutesFromNow`, and the second route's first trip
    /// 3 minutes from now. Every other trip in the fixture has left.
    private func scheduleBody(departingInMinutes minutesFromNow: [Double]) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: Fixtures.loadData(file: scheduleFixture)) as? [String: Any])
        var data = try #require(root["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        var routes = try #require(entry["stopRouteSchedules"] as? [[String: Any]])
        let nowMS = Date().timeIntervalSince1970 * 1000

        func retimed(_ stopTime: [String: Any], minutes: Double) -> [String: Any] {
            var stopTime = stopTime
            stopTime["arrivalTime"] = Int64(nowMS + minutes * 60_000)
            stopTime["departureTime"] = Int64(nowMS + minutes * 60_000)
            return stopTime
        }

        var first = routes[0]
        var directions = try #require(first["stopRouteDirectionSchedules"] as? [[String: Any]])
        let template = try #require((directions[0]["scheduleStopTimes"] as? [[String: Any]])?.first)
        first["routeId"] = tripBookmark.routeID
        directions[0]["tripHeadsign"] = tripBookmark.tripHeadsign
        directions[0]["scheduleStopTimes"] = minutesFromNow.enumerated().map { index, minutes in
            var stopTime = retimed(template, minutes: minutes)
            stopTime["tripId"] = "trip_\(index)"
            return stopTime
        }
        first["stopRouteDirectionSchedules"] = directions
        routes[0] = first

        var second = routes[1]
        var secondDirections = try #require(second["stopRouteDirectionSchedules"] as? [[String: Any]])
        var secondTimes = try #require(secondDirections[0]["scheduleStopTimes"] as? [[String: Any]])
        secondTimes[0] = retimed(secondTimes[0], minutes: 3)
        secondDirections[0]["scheduleStopTimes"] = secondTimes
        second["stopRouteDirectionSchedules"] = secondDirections
        routes[1] = second

        entry["stopRouteSchedules"] = routes
        data["entry"] = entry
        root["data"] = data
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func offlineService() -> RESTAPIService {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: URLError(.notConnectedToInternet)) { _ in true })
        return buildRESTService(dataLoader: dataLoader)
    }

    // MARK: - Tests

    @Test func `Offline, saved departures stand in and departed ones are dropped`() async throws {
        let savedAt = Date().addingTimeInterval(-20 * 60)
        store.save(try savedBody(departingInMinutes: [-5, 10]), stopID: stopBookmark.stopID, regionID: pugetSoundRegionIdentifier, savedAt: savedAt)

        let result = await BookmarkArrivalsLoader(savedArrivals: store)
            .departuresByBookmarkKeepingSaved(for: [stopBookmark, tripBookmark], using: offlineService())

        #expect(result.departures[stopBookmark.id]?.count == 1)
        #expect(result.departures[tripBookmark.id]?.count == 1)
        #expect(result.departures.values.allSatisfy { $0.allSatisfy { $0.temporalState != .past } })
        #expect(abs(try #require(result.savedAt).timeIntervalSince(savedAt)) < 1)
        // Offline even with no timetable saved: an entry, but empty.
        #expect(result.scheduledDepartures[stopBookmark.id] == [])
        #expect(result.scheduledDepartures[tripBookmark.id] == [])
    }

    @Test func `Offline, a trip bookmark gets only its own route's timetable`() async throws {
        store.save(try savedBody(departingInMinutes: [-5]), stopID: stopBookmark.stopID, regionID: pugetSoundRegionIdentifier)
        store.save(try scheduleBody(departingInMinutes: [-1, 20, 40]), kind: .schedule, stopID: stopBookmark.stopID, regionID: pugetSoundRegionIdentifier)

        let result = await BookmarkArrivalsLoader(savedArrivals: store)
            .departuresByBookmarkKeepingSaved(for: [stopBookmark, tripBookmark], using: offlineService())

        #expect(result.departures[tripBookmark.id] == [])
        let tripTimetable = try #require(result.scheduledDepartures[tripBookmark.id])
        #expect(tripTimetable.map(\.tripID) == ["trip_1", "trip_2"])
        // The stop bookmark also gets the other route's trip, soonest first.
        let stopTimetable = try #require(result.scheduledDepartures[stopBookmark.id])
        #expect(stopTimetable.count == 3)
        #expect(stopTimetable.first?.routeID != tripBookmark.routeID)
    }

    @Test func `Live, nothing is marked saved and the response is saved`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: fixtureFile)) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
        dataLoader.mock(data: Fixtures.loadData(file: scheduleFixture)) { [schedulePath] request in
            request.url?.path.contains(schedulePath) ?? false
        }

        let result = await BookmarkArrivalsLoader(savedArrivals: store)
            .departuresByBookmarkKeepingSaved(for: [stopBookmark], using: buildRESTService(dataLoader: dataLoader))

        #expect(result.departures[stopBookmark.id] != nil)
        #expect(result.scheduledDepartures.isEmpty)
        #expect(result.savedAt == nil)
        #expect(store.load(stopID: stopBookmark.stopID, regionID: pugetSoundRegionIdentifier) != nil)
    }

    @Test func `Offline with nothing saved, the bookmark has no data`() async {
        let result = await BookmarkArrivalsLoader(savedArrivals: store)
            .departuresByBookmarkKeepingSaved(for: [stopBookmark], using: offlineService())

        #expect(result.departures[stopBookmark.id] == nil)
        #expect(result.scheduledDepartures[stopBookmark.id] == nil)
        #expect(result.savedAt == nil)
    }
}
