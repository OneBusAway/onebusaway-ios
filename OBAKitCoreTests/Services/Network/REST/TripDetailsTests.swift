//
//  TripDetailsTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import OBAKitCore

final class TripDetailsTests: OBAKitCoreTestCase {
    let vehicleID = "1_1234"
    let tripID = "1_18196913"

    func testLoading_vehicleDetails() async throws {
        let data = try Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/trip-for-vehicle/\(vehicleID).json", with: data)
        let trip = try await restAPIService.getVehicleTrip(vehicleID: vehicleID).entry
        try checkExpectations(trip)
    }

    func testTripDetails() async throws {
        let data = try Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/trip-details/\(tripID).json", with: data)

        let trip = try await restAPIService.getTrip(tripID: tripID, vehicleID: vehicleID, serviceDate: .now).entry
        try checkExpectations(trip)
    }

    func checkExpectations(_ tripDetails: TripDetails) throws {
        XCTAssertNil(tripDetails.frequency)
        XCTAssertEqual(tripDetails.tripID, self.tripID)

        XCTAssertEqual(tripDetails.serviceDate, Date(timeIntervalSinceReferenceDate: 365324400))
        XCTAssertEqual(tripDetails.schedule.timeZone, "America/Los_Angeles")
        XCTAssertNil(tripDetails.status)
        XCTAssertEqual(tripDetails.schedule.stopTimes.count, 53)

        let stopTime = try XCTUnwrap(tripDetails.schedule.stopTimes.first)
        XCTAssertEqual(stopTime.arrival, 58862)
        XCTAssertEqual(stopTime.departure, 58862)

        XCTAssertEqual(stopTime.arrivalDate(relativeTo: tripDetails), Date(timeIntervalSince1970: 1343690462))
        XCTAssertEqual(stopTime.departureDate(relativeTo: tripDetails), Date(timeIntervalSince1970: 1343690462))

        XCTAssertEqual(stopTime.distanceAlongTrip, 0)
        XCTAssertEqual(stopTime.stopID, "1_9610")

        XCTAssertEqual(tripDetails.schedule.previousTripID, "1_18196851")
//        XCTAssertEqual(tripDetails.previousTrip?.headsign, "UNIVERSITY DISTRICT ROOSEVELT")

        XCTAssertEqual(tripDetails.schedule.nextTripID, "1_18196555")
//        XCTAssertEqual(tripDetails.nextTrip?.headsign, "UNIVERSITY DISTRICT WEDGWOOD")

//        XCTAssertEqual(tripDetails.situationIDs.count, 0)
//        XCTAssertEqual(tripDetails.serviceAlerts.count, 0)
    }
}
