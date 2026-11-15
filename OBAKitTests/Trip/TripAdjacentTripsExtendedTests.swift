//
//  TripAdjacentTripsExtendedTests.swift
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
final class TripAdjacentTripsExtendedTests: OBATestCase {

    private func makeTrip(id: String, headsign: String, routeShortName: String = "10") throws -> Trip {
        let routeData: [String: Any] = [
            "id": "route_\(id)",
            "shortName": routeShortName,
            "longName": "Route \(routeShortName)",
            "type": 3
        ]
        let tripData: [String: Any] = [
            "id": id,
            "routeId": "route_\(id)",
            "tripHeadsign": headsign,
            "serviceId": "service_1",
            "directionId": "0"
        ]

        let route = try Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        let trip = try Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)
        let references = References(agencies: [], routes: [route], situations: [], stops: [], trips: [trip])
        trip.loadReferences(references, regionIdentifier: 1)
        return trip
    }

    private func makeTripDetails(
        tripID: String,
        previousTripID: String? = nil,
        nextTripID: String? = nil,
        availableTrips: [Trip] = []
    ) throws -> TripDetails {
        let stopTimes: [[String: Any]] = [
            [
                "arrivalTime": 1000,
                "departureTime": 1010,
                "stopId": "stop_1",
                "stopSequence": 0
            ]
        ]
        var schedule: [String: Any] = [
            "timeZone": "America/Los_Angeles",
            "stopTimes": stopTimes
        ]
        if let previousTripID {
            schedule["previousTripId"] = previousTripID
        }
        if let nextTripID {
            schedule["nextTripId"] = nextTripID
        }

        let tripData: [String: Any] = [
            "id": tripID,
            "routeId": "route_\(tripID)",
            "tripHeadsign": "Current Trip",
            "serviceId": "service_1",
            "directionId": "0"
        ]
        let currentTrip = try Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)
        let routeData: [String: Any] = [
            "id": "route_\(tripID)",
            "shortName": "44",
            "longName": "Route 44",
            "type": 3
        ]
        let route = try Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)

        let detailsData: [String: Any] = [
            "tripId": tripID,
            "serviceDate": 1600000000,
            "schedule": schedule,
            "situationIds": []
        ]

        let details = try Fixtures.dictionaryToModel(type: TripDetails.self, dictionary: detailsData)
        var allTrips = [currentTrip]
        allTrips.append(contentsOf: availableTrips)
        let references = References(agencies: [], routes: [route], situations: [], stops: [], trips: allTrips)
        details.loadReferences(references, regionIdentifier: 1)
        return details
    }

    @Test func `Nil details produces nil adjacent trip rows`() {
        let adjacent = TripAdjacentTrips(details: nil)

        #expect(adjacent.previous == nil)
        #expect(adjacent.next == nil)
        #expect(adjacent.row(.previous) == nil)
        #expect(adjacent.row(.next) == nil)
    }

    @Test func `Details with no adjacent trip IDs produces nil rows`() throws {
        let details = try makeTripDetails(tripID: "trip_standalone")
        let adjacent = TripAdjacentTrips(details: details)

        #expect(adjacent.previous == nil)
        #expect(adjacent.next == nil)
        #expect(adjacent.row(.previous) == nil)
        #expect(adjacent.row(.next) == nil)
    }

    @Test func `Adjacent trip IDs missing from references produce nil rows`() throws {
        let details = try makeTripDetails(
            tripID: "trip_unresolved",
            previousTripID: "prev_missing",
            nextTripID: "next_missing",
            availableTrips: []
        )
        let adjacent = TripAdjacentTrips(details: details)

        #expect(adjacent.previous == nil)
        #expect(adjacent.next == nil)
        #expect(adjacent.row(.previous) == nil)
        #expect(adjacent.row(.next) == nil)
    }

    @Test func `Previous and next rows resolve correctly when present in references`() throws {
        let prevTrip = try makeTrip(id: "prev_1", headsign: "Downtown Seattle", routeShortName: "10")
        let nextTrip = try makeTrip(id: "next_1", headsign: "Capitol Hill", routeShortName: "49")

        let details = try makeTripDetails(
            tripID: "trip_current",
            previousTripID: "prev_1",
            nextTripID: "next_1",
            availableTrips: [prevTrip, nextTrip]
        )
        let adjacent = TripAdjacentTrips(details: details)

        let prevRow = try #require(adjacent.previous)
        let nextRow = try #require(adjacent.next)

        #expect(prevRow.order == .previous)
        #expect(prevRow.trip.id == "prev_1")
        #expect(prevRow.title.contains("Downtown Seattle"))

        #expect(nextRow.order == .next)
        #expect(nextRow.trip.id == "next_1")
        #expect(nextRow.title.contains("Capitol Hill"))

        #expect(adjacent.row(.previous)?.trip.id == "prev_1")
        #expect(adjacent.row(.next)?.trip.id == "next_1")
    }

    @Test func `Row titles reflect startsAs and continuesAs localized formats`() throws {
        let prevTrip = try makeTrip(id: "prev_2", headsign: "Ballard", routeShortName: "44")
        let nextTrip = try makeTrip(id: "next_2", headsign: "UW Station", routeShortName: "44")

        let prevRow = TripAdjacentTrips.Row(order: .previous, trip: prevTrip)
        let nextRow = TripAdjacentTrips.Row(order: .next, trip: nextTrip)

        #expect(prevRow.order == .previous)
        #expect(prevRow.trip.id == "prev_2")
        #expect(prevRow.title.contains("Ballard"))

        #expect(nextRow.order == .next)
        #expect(nextRow.trip.id == "next_2")
        #expect(nextRow.title.contains("UW Station"))
    }
}
