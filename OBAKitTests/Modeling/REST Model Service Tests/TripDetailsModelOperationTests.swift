//
//  TripDetailsModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class TripDetailsModelOperationTests: OBATestCase {
    let vehicleID = "1_1234"
    let tripID = "1_18196913"
    lazy var vehicleTripAPIPath = "https://www.example.com/api/where/trip-for-vehicle/\(vehicleID).json"
    lazy var tripDetailsAPIPath = "https://www.example.com/api/where/trip-details/\(tripID).json"

    var dataLoader: MockDataLoader!

    override func setUp() {
        super.setUp()
        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    func checkExpectations(_ tripDetails: TripDetails) {
        expect(tripDetails).toNot(beNil())

        expect(tripDetails.frequency).to(beNil())

        expect(tripDetails.tripID) == self.tripID
        let trip = tripDetails.trip!
        expect(trip.headsign) == "LAKE CITY WEDGWOOD"

        expect(tripDetails.serviceDate) == Date.fromComponents(year: 2012, month: 07, day: 30, hour: 07, minute: 00, second: 00)
        expect(tripDetails.timeZone) == "America/Los_Angeles"

        expect(tripDetails.status).to(beNil())

        expect(tripDetails.stopTimes.count) == 53

        let stopTime = tripDetails.stopTimes.first!
        expect(stopTime.arrivalDate.timeIntervalSince1970) == 1343690462
        expect(stopTime.departureDate.timeIntervalSince1970) == 1343690462
        expect(stopTime.stopID) == "1_9610"

        expect(tripDetails.previousTrip!.id) == "1_18196851"
        expect(tripDetails.previousTrip!.headsign) == "UNIVERSITY DISTRICT ROOSEVELT"

        expect(tripDetails.nextTrip!.id) == "1_18196555"
        expect(tripDetails.nextTrip!.headsign) == "UNIVERSITY DISTRICT WEDGWOOD"

        expect(tripDetails.serviceAlerts.count) == 0
    }

    func testLoading_vehicleDetails_success() async throws {
        let data = Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(URLString: vehicleTripAPIPath, with: data)

        let trip = try await restService.getVehicleTrip(vehicleID: vehicleID).entry
        self.checkExpectations(trip)
    }

    func testLoading_tripDetails_success() async throws {
        let data = Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(URLString: tripDetailsAPIPath, with: data)

        let trip = try await restService.getTrip(tripID: tripID, vehicleID: "12345", serviceDate: Date()).entry
        self.checkExpectations(trip)
    }
}
