//
//  PersistenceTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB
import XCTest
import Foundation
@testable import OBAKitCore

final class PersistenceTests: OBAKitCorePersistenceTestCase {
    func testASDF() async throws {
        let routeID = "12345"
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/stops-for-route/\(routeID).json",
            with: try Fixtures.loadData(file: "stops-for-route-1_100002.json")
        )

        let response = try await restAPIService.getStopsForRoute(routeID: routeID)
        try await persistence.processReferences(response)

        let stopsForRoute = try await persistence.database.read { db in
            let route = try XCTUnwrap(try Route.fetchOne(db, id: "1_100002"), "Unable to fetch Route by ID.")
            return try route.stops.fetchAll(db)
        }
        XCTAssertEqual(stopsForRoute.count, 35)

        let routesForStop = try await persistence.database.read { db in
            let stop = try XCTUnwrap(try Stop.fetchOne(db, id: "1_1085"), "Unable to fetch Stop by ID.")
            return try stop.routes.fetchAll(db)
        }
        XCTAssertEqual(routesForStop.count, 8)

        let agencies = try await persistence.database.read { db in
            return try Agency.fetchAll(db)
        }
        XCTAssertEqual(agencies.count, 2)

        // Test agency relationship
        let route = try XCTUnwrap(routesForStop.first)
        let agency = try await persistence.database.read { db in
            try route.agency.fetchOne(db)
        }
        XCTAssertEqual(agency?.name, "Metro Transit")
    }

    func testTrip() async throws {
        let vehicleID = "1_1234"
        let tripID = "1_18196913"

        let data = try Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/trip-details/\(tripID).json", with: data)

        let response = try await restAPIService.getTrip(tripID: tripID, vehicleID: vehicleID, serviceDate: .now)
        try await persistence.processAPIResponse(response)

        let _tripDetails = try await persistence.database.read { db in
            try TripDetails.fetchOne(db, id: tripID)
        }

        let tripDetails = try XCTUnwrap(_tripDetails)

        let stopTimes = tripDetails.schedule.stopTimes
        XCTAssertEqual(stopTimes.count, 53)

        XCTAssertEqual(stopTimes.first?.arrival, 58862)
        XCTAssertEqual(stopTimes.first?.arrivalDate(relativeTo: tripDetails), Date(timeIntervalSinceReferenceDate: 365383262))
    }

    func testTripDetailRelations() async throws {
        let vehicleID = "1_1234"
        let tripID = "1_18196913"

        let data = try Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/trip-details/\(tripID).json", with: data)

        let response = try await restAPIService.getTrip(tripID: tripID, vehicleID: vehicleID, serviceDate: .now)
        try await persistence.processAPIResponse(response)

        let _tripDetails = try await persistence.database.read { db in
            try TripDetails.fetchOne(db, id: tripID)
        }
        let tripDetails = try XCTUnwrap(_tripDetails)

        // Test Trip relationships.
        struct Trips {
            var previousTrip: Trip?
            var currentTrip: Trip?
            var nextTrip: Trip?
        }

        let trips = try await persistence.database.read { db in
            return Trips(
                previousTrip: try tripDetails.previousTrip.fetchOne(db),
                currentTrip: try tripDetails.trip.fetchOne(db),
                nextTrip: try tripDetails.nextTrip.fetchOne(db)
            )
        }

        XCTAssertEqual(trips.previousTrip?.id, "1_18196851")
        XCTAssertEqual(trips.previousTrip?.headsign, "UNIVERSITY DISTRICT ROOSEVELT")

        XCTAssertEqual(trips.currentTrip?.id, "1_18196913")
        XCTAssertEqual(trips.currentTrip?.headsign, "LAKE CITY WEDGWOOD")

        XCTAssertEqual(trips.nextTrip?.id, "1_18196555")
        XCTAssertEqual(trips.nextTrip?.headsign, "UNIVERSITY DISTRICT WEDGWOOD")
    }
}
