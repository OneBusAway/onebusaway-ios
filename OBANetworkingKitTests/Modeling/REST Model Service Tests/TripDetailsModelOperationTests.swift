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
@testable import OBANetworkingKit

class TripDetailsModelOperationTests: OBATestCase {
    let vehicleID = "1_1234"
    lazy var apiPath = VehicleTripOperation.buildAPIPath(vehicleID: vehicleID)

    func stubVehicle11234() {
        stub(condition: isHost(self.host) && isPath(apiPath)) { _ in
            return self.JSONFile(named: "trip_details_1_18196913.json")
        }
    }

    func testLoading_tripDetails_success() {
        stubVehicle11234()

        waitUntil { done in
            let op = self.restModelService.getTripDetails(vehicleID: self.vehicleID)
            op.completionBlock = {
                let tripDetails = op.tripDetails!
                expect(tripDetails).toNot(beNil())

                expect(tripDetails.frequency).to(beNil())
                expect(tripDetails.tripID) == "1_18196913"
                expect(tripDetails.serviceDate) == Date.fromComponents(year: 2012, month: 07, day: 30, hour: 07, minute: 00, second: 00)
                expect(tripDetails.timeZone) == "America/Los_Angeles"

                expect(tripDetails.status).to(beNil())

                expect(tripDetails.stopTimes.count) == 53

                let stopTime = tripDetails.stopTimes.first!
                expect(stopTime.arrival) == 58862
                expect(stopTime.departure) == 58862
                expect(stopTime.stopID) == "1_9610"

                expect(tripDetails.previousTripID) == "1_18196851"
                expect(tripDetails.nextTripID) == "1_18196555"

                expect(tripDetails.situationIDs.count) == 0

                done()
            }
        }
    }
}
