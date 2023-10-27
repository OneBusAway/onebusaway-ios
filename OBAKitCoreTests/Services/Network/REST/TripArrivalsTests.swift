//
//  TripArrivalsTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import OBAKitCore

final class TripArrivalsTests: OBAKitCoreTestCase {
    let stopID = "1_10914"

    func testLoading() async throws {
        let data = try Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/arrival-and-departure-for-stop/\(stopID).json", with: data)

        let response = try await restAPIService.getTripArrivalDepartureAtStop(stopID: stopID, tripID: "trip123", serviceDate: Date(timeIntervalSince1970: 1234567890), vehicleID: "vehicle_123", stopSequence: 1)
        let arrivalDeparture = response.entry

        XCTAssertTrue(arrivalDeparture.arrivalEnabled)
        XCTAssertEqual(arrivalDeparture.blockTripSequence, 6)
        XCTAssertTrue(arrivalDeparture.departureEnabled)
        XCTAssertEqual(arrivalDeparture.distanceFromStop, -2089.5461, accuracy: 0.0001)
        XCTAssertNil(arrivalDeparture.frequency)

        XCTAssertEqual(arrivalDeparture.lastUpdated, Date(timeIntervalSinceReferenceDate: 562043622), "Expected lastUpdated date to be 2018-10-24T03:13:42Z")
        XCTAssertEqual(arrivalDeparture.numberOfStopsAway, -4)
        XCTAssertTrue(arrivalDeparture.predicted)

        XCTAssertEqual(arrivalDeparture.arrivalDepartureDate, Date(timeIntervalSinceReferenceDate: 562043400), "Expected arrivalDepartureDate to be 2018-10-24T03:10:00Z")
        XCTAssertEqual(arrivalDeparture.serviceDate, Date(timeIntervalSinceReferenceDate: 561970800), "Expected serviceDate to be 2018-10-23T07:00:00Z")
        XCTAssertEqual(arrivalDeparture.routeID, "MTS_10")
//        XCTAssertEqual(arrivalDeparture.route.id, "MTS_10")
//        XCTAssertEqual(arrivalDeparture.route.shortName, "10")

        XCTAssertEqual(arrivalDeparture.routeLongName, "Old Town - University/College")
        XCTAssertEqual(arrivalDeparture.routeShortName, "10")

//        XCTAssertEqual(arrivalDeparture.serviceAlerts.count, 1)
//
//        let situation = try XCTUnwrap(arrivalDeparture.serviceAlerts.first)
//        let situationSummary = try XCTUnwrap(situation.summary)
//        let firstConsequence = try XCTUnwrap(situation.consequences.first)

//        XCTAssertEqual(situationSummary.value, "Washington St. ramp from Pac Hwy Closed")
//        XCTAssertEqual(firstConsequence.condition, "detour")
//        XCTAssertNotNil(firstConsequence.conditionDetails?.diversionPath)

        XCTAssertEqual(arrivalDeparture.status, "default")
        XCTAssertEqual(arrivalDeparture.stopID, "MTS_11589")
//        XCTAssertEqual(arrivalDeparture.stop.id, "MTS_11589")
//        XCTAssertEqual(arrivalDeparture.stop.name, "Pacific Hwy & Sports Arena Bl")
        XCTAssertEqual(arrivalDeparture.stopSequence, 1)
        XCTAssertNil(arrivalDeparture.totalStopsInTrip)
        XCTAssertEqual(arrivalDeparture.tripHeadsign, "University & College")
        XCTAssertEqual(arrivalDeparture.tripID, "MTS_13405160")
//        XCTAssertEqual(arrivalDeparture.trip.id, "MTS_13405160")
//        XCTAssertNil(arrivalDeparture.trip.shortName)
        XCTAssertNotNil(arrivalDeparture.tripStatus)

        let tripStatus = try XCTUnwrap(arrivalDeparture.tripStatus)
        XCTAssertEqual(tripStatus.activeTripID, "MTS_13405160")
//        XCTAssertEqual(tripStatus.activeTrip.id, "MTS_13405160")
        XCTAssertEqual(arrivalDeparture.vehicleID, "MTS_806")
    }
}
