//
//  NearbyRouteDirectionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The grouping rules behind the watch's Nearby routes screen.
///
/// Fixture arrivals are from 2012–2018, so these feed `group` directly rather
/// than through `BookmarkArrivalsRequest.matching`, which would drop them as
/// past. The loader tests below cover only its error rules for the same reason.
@Suite(.serialized)
final class NearbyRouteDirectionsTests: OBATestCase {

    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"

    /// Route 10 in both directions: three "Capitol Hill Via 15th Ave E"
    /// (direction 0), two "Downtown Seattle" (direction 1).
    private let galerFixture = "arrivals_and_departures_for_stop_15th-galer.json"
    /// Routes 30 (direction 1) and 65 (direction 0), two departures each.
    private let routes30And65Fixture = "arrivals_and_departures_for_stop_1_10020.json"

    /// 15th Ave NE & NE Campus Pkwy, stop 1_10914 in the Seattle fixture.
    private let origin = CLLocation(latitude: 47.656422, longitude: -122.312164)

    // MARK: - Helpers

    /// Decodes an arrivals payload through the real service, so trips and
    /// routes are resolved from references exactly as in the app.
    private func arrivals(fixture: String, editing edit: ((inout [String: Any]) throws -> Void)? = nil) async throws -> [ArrivalDeparture] {
        var data = Fixtures.loadData(file: fixture)
        if let edit {
            var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            try edit(&json)
            data = try JSONSerialization.data(withJSONObject: json)
        }
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: data) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
        let service = buildRESTService(dataLoader: dataLoader)
        return try await service.getArrivalsAndDeparturesForStop(id: "any", minutesBefore: 0, minutesAfter: 60).entry.arrivalsAndDepartures
    }

    /// Applies `edit` to every `data.entry.arrivalsAndDepartures[]` element.
    private static func editArrivals(_ json: inout [String: Any], _ edit: (Int, inout [String: Any]) -> Void) throws {
        var data = try #require(json["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        var list = try #require(entry["arrivalsAndDepartures"] as? [[String: Any]])
        for index in list.indices { edit(index, &list[index]) }
        entry["arrivalsAndDepartures"] = list
        data["entry"] = entry
        json["data"] = data
    }

    /// Applies `edit` to every `data.references.trips[]` element.
    private static func editTrips(_ json: inout [String: Any], _ edit: (inout [String: Any]) -> Void) throws {
        var data = try #require(json["data"] as? [String: Any])
        var references = try #require(data["references"] as? [String: Any])
        var trips = try #require(references["trips"] as? [[String: Any]])
        for index in trips.indices { edit(&trips[index]) }
        references["trips"] = trips
        data["references"] = references
        json["data"] = data
    }

    /// Stops from the Seattle fixture, nearest to `origin` first.
    private func stopsByDistance() throws -> [Stop] {
        try Fixtures.loadSomeStops().sorted { $0.location.distance(from: origin) < $1.location.distance(from: origin) }
    }

    // MARK: - Grouping

    @Test func `One route in two directions is two cards, each with its own headsign`() async throws {
        let stop = try #require(try stopsByDistance().first)
        let arrivals = try await arrivals(fixture: galerFixture)

        let directions = NearbyRouteDirections.group(stops: [stop], arrivalsByStop: [stop.id: arrivals], origin: origin)

        #expect(directions.count == 2)
        #expect(Set(directions.map(\.route.shortName)) == ["10"])
        #expect(Set(directions.map(\.headsign)) == ["Capitol Hill Via 15th Ave E", "Downtown Seattle"])
        #expect(Set(directions.map(\.key.direction)) == ["id:0", "id:1"])

        let capitolHill = try #require(directions.first { $0.headsign == "Capitol Hill Via 15th Ave E" })
        #expect(capitolHill.nearestStop.departures.count == 3)
        let dates = capitolHill.nearestStop.departures.map(\.arrivalDepartureDate)
        #expect(dates == dates.sorted())
    }

    @Test func `Opposite finds the same route's other direction and nothing else`() async throws {
        let stop = try #require(try stopsByDistance().first)
        let galer = try await arrivals(fixture: galerFixture)
        let others = try await arrivals(fixture: routes30And65Fixture)

        let directions = NearbyRouteDirections.group(stops: [stop], arrivalsByStop: [stop.id: galer + others], origin: origin)
        #expect(directions.count == 4)

        let toDowntown = try #require(directions.first { $0.headsign == "Downtown Seattle" })
        let opposite = NearbyRouteDirections.opposite(of: toDowntown.key, in: directions)
        #expect(opposite?.headsign == "Capitol Hill Via 15th Ave E")

        let route30 = try #require(directions.first { $0.route.shortName == "30" })
        #expect(NearbyRouteDirections.opposite(of: route30.key, in: directions) == nil)
    }

    @Test func `A direction served at two stops lists them nearest first`() async throws {
        let stops = try stopsByDistance()
        let near = stops[0], far = stops[5]
        let arrivals = try await arrivals(fixture: galerFixture)

        // Passed farthest first, to prove the order is by distance, not input.
        let directions = NearbyRouteDirections.group(
            stops: [far, near],
            arrivalsByStop: [near.id: arrivals, far.id: arrivals],
            origin: origin
        )

        #expect(directions.count == 2)
        for direction in directions {
            #expect(direction.stops.map(\.stop.id) == [near.id, far.id])
            #expect(direction.stops[0].distance < direction.stops[1].distance)
        }
    }

    @Test func `Cards are ordered by their nearest stop's distance`() async throws {
        let stops = try stopsByDistance()
        let near = stops[0], far = stops[5]
        let galer = try await arrivals(fixture: galerFixture)
        let others = try await arrivals(fixture: routes30And65Fixture)

        let directions = NearbyRouteDirections.group(
            stops: [near, far],
            arrivalsByStop: [far.id: galer, near.id: others],
            origin: origin
        )

        #expect(directions.map(\.route.shortName).prefix(2).sorted() == ["30", "65"])
        #expect(directions.map(\.route.shortName).suffix(2) == ["10", "10"])
    }

    @Test func `Equal distance falls back to the soonest departure`() async throws {
        let stop = try #require(try stopsByDistance().first)
        let arrivals = try await arrivals(fixture: galerFixture)

        let directions = NearbyRouteDirections.group(stops: [stop], arrivalsByStop: [stop.id: arrivals], origin: origin)

        // The fixture's first departure is toward Capitol Hill.
        #expect(directions.first?.headsign == "Capitol Hill Via 15th Ave E")
    }

    @Test func `A stop without an entry, or with no arrivals, contributes nothing`() async throws {
        let stops = try stopsByDistance()
        let arrivals = try await arrivals(fixture: galerFixture)

        #expect(NearbyRouteDirections.group(stops: stops, arrivalsByStop: [:], origin: origin).isEmpty)
        #expect(NearbyRouteDirections.group(stops: stops, arrivalsByStop: [stops[0].id: []], origin: origin).isEmpty)

        let directions = NearbyRouteDirections.group(stops: stops, arrivalsByStop: [stops[3].id: arrivals], origin: origin)
        #expect(directions.allSatisfy { $0.stops.map(\.stop.id) == [stops[3].id] })
    }

    // MARK: - Headsigns

    @Test func `The most common headsign labels a direction, even over the soonest`() async throws {
        let stop = try #require(try stopsByDistance().first)
        // The first departure (toward Capitol Hill) becomes a variant; the
        // other two keep the fixture's headsign.
        let arrivals = try await arrivals(fixture: galerFixture) { json in
            try Self.editArrivals(&json) { index, arrival in
                if index == 0 { arrival["tripHeadsign"] = "Capitol Hill" }
            }
        }

        let directions = NearbyRouteDirections.group(stops: [stop], arrivalsByStop: [stop.id: arrivals], origin: origin)

        #expect(directions.count == 2, "a headsign variant must not split a direction")
        #expect(Set(directions.map(\.headsign)) == ["Capitol Hill Via 15th Ave E", "Downtown Seattle"])
    }

    @Test func `Without direction IDs, headsigns separate the directions`() async throws {
        let stop = try #require(try stopsByDistance().first)
        let arrivals = try await arrivals(fixture: galerFixture) { json in
            try Self.editTrips(&json) { $0.removeValue(forKey: "directionId") }
        }

        let directions = NearbyRouteDirections.group(stops: [stop], arrivalsByStop: [stop.id: arrivals], origin: origin)

        #expect(directions.count == 2)
        #expect(Set(directions.map(\.key.direction)) == ["headsign:Capitol Hill Via 15th Ave E", "headsign:Downtown Seattle"])
    }

    // MARK: - Loader

    @Test func `The loader throws only when every stop fails`() async throws {
        let stops = Array(try stopsByDistance().prefix(2))
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Data("{}".utf8), statusCode: 500) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
        let service = buildRESTService(dataLoader: dataLoader)

        await #expect(throws: (any Error).self) {
            _ = try await NearbyRoutesLoader().directions(at: stops, origin: self.origin, using: service)
        }
    }

    @Test func `A partial failure returns the stops that worked`() async throws {
        let stops = Array(try stopsByDistance().prefix(2))
        let failing = stops[1].id
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Data("{}".utf8), statusCode: 500) { request in
            request.url?.path.contains(failing) ?? false
        }
        dataLoader.mock(data: Fixtures.loadData(file: galerFixture)) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
        let service = buildRESTService(dataLoader: dataLoader)

        // Every fixture departure is past, so success is "no throw, empty list".
        let directions = try await NearbyRoutesLoader().directions(at: stops, origin: origin, using: service)
        #expect(directions.isEmpty)
    }
}
