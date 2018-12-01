//
//  TripDetailsModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/30/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import OBATestHelpers
import OBAModelKit
@testable import OBANetworkingKit

class TripDetailsModelOperationTests: OBATestCase {
    let vehicleID = "1_1234"
    let tripID = "1_18196913"
    lazy var vehicleTripAPIPath = VehicleTripOperation.buildAPIPath(vehicleID: vehicleID)
    lazy var tripDetailsAPIPath = TripDetailsOperation.buildAPIPath(tripID: tripID)

    func checkExpectations(_ tripDetails: TripDetails) {
        expect(tripDetails).toNot(beNil())

        expect(tripDetails.frequency).to(beNil())

        expect(tripDetails.tripID) == self.tripID
        let trip = tripDetails.trip
        expect(trip.headsign) == "LAKE CITY WEDGWOOD"

        expect(tripDetails.serviceDate) == Date.fromComponents(year: 2012, month: 07, day: 30, hour: 07, minute: 00, second: 00)
        expect(tripDetails.timeZone) == "America/Los_Angeles"

        expect(tripDetails.status).to(beNil())

        expect(tripDetails.stopTimes.count) == 53

        let stopTime = tripDetails.stopTimes.first!
        expect(stopTime.arrival) == 58862
        expect(stopTime.departure) == 58862
        expect(stopTime.stopID) == "1_9610"

        expect(tripDetails.previousTrip!.id) == "1_18196851"
        expect(tripDetails.previousTrip!.headsign) == "UNIVERSITY DISTRICT ROOSEVELT"

        expect(tripDetails.nextTrip!.id) == "1_18196555"
        expect(tripDetails.nextTrip!.headsign) == "UNIVERSITY DISTRICT WEDGWOOD"

        expect(tripDetails.situations.count) == 0
    }

    func testLoading_vehicleDetails_success() {
        stub(condition: isHost(self.host) && isPath(vehicleTripAPIPath)) { _ in
            return self.JSONFile(named: "trip_details_1_18196913.json")
        }

        waitUntil { done in
            let op = self.restModelService.getTripDetails(vehicleID: self.vehicleID)
            op.completionBlock = {
                self.checkExpectations(op.tripDetails!)
                done()
            }
        }
    }

    func testLoading_tripDetails_success() {
        stub(condition: isHost(self.host) && isPath(tripDetailsAPIPath)) { _ in
            return self.JSONFile(named: "trip_details_1_18196913.json")
        }

        waitUntil { done in
            let op = self.restModelService.getTripDetails(tripID: self.tripID, vehicleID: "12345", serviceDate: 1234567890)
            op.completionBlock = {
                self.checkExpectations(op.tripDetails!)
                done()
            }
        }
    }
}
