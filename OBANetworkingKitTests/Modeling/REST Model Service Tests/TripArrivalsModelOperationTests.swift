//
//  TripArrivalsModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 11/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
import OBATestHelpers
import OBAModelKit
@testable import OBANetworkingKit

class TripArrivalsModelOperationTests: OBATestCase {
    let stopID = "1_10914"
    lazy var apiPath: String = TripArrivalDepartureOperation.buildAPIPath(stopID: stopID)

    func stubAPICall() {
        stub(condition: isHost(self.host) && isPath(self.apiPath)) { _ in
            return self.JSONFile(named: "arrival-and-departure-for-stop-MTS_11589.json")
        }
    }

    func testLoading_success() {
        stubAPICall()

        waitUntil { (done) in
            let op = self.restModelService.getTripArrivalDepartureAtStop(stopID: self.stopID, tripID: "trip123", serviceDate: 1234567890, vehicleID: "vehicle_123", stopSequence: 1)
            op.completionBlock = {
                let arrDep = op.arrivalDeparture!
                expect(arrDep.arrivalEnabled).to(beTrue())
                expect(arrDep.blockTripSequence) == 6
                expect(arrDep.departureEnabled).to(beTrue())
                expect(arrDep.distanceFromStop).to(beCloseTo(-2089.5461))
                expect(arrDep.frequency).to(beNil())

                expect(arrDep.lastUpdated) == Date.fromComponents(year: 2018, month: 10, day: 24, hour: 03, minute: 13, second: 42)

                expect(arrDep.numberOfStopsAway) == -4
                expect(arrDep.predicted).to(beTrue())

                expect(arrDep.arrivalDepartureDate) == Date.fromComponents(year: 2018, month: 10, day: 24, hour: 03, minute: 10, second: 00)

                expect(arrDep.route.id) == "MTS_10"
                expect(arrDep.route.shortName) == "10"

                expect(arrDep.routeLongName) == "Old Town - University/College"
                expect(arrDep.routeShortName) == "10"

                expect(arrDep.arrivalDepartureDate) == Date.fromComponents(year: 2018, month: 10, day: 24, hour: 03, minute: 10, second: 00)

                expect(arrDep.serviceDate) == Date.fromComponents(year: 2018, month: 10, day: 23, hour: 07, minute: 00, second: 00)

                expect(arrDep.situations.count) == 1
                let situation = arrDep.situations.first!
                expect(situation.summary.value) == "Washington St. ramp from Pac Hwy Closed"
                expect(situation.consequences.first!.condition) == "detour"
                expect(situation.consequences.first!.conditionDetails!.diversionPath).toNot(beNil())

                expect(arrDep.status) == "default"

                expect(arrDep.stop.id) == "MTS_11589"
                expect(arrDep.stop.name) == "Pacific Hwy & Sports Arena Bl"

                expect(arrDep.stopSequence) == 1

                expect(arrDep.totalStopsInTrip).to(beNil())

                expect(arrDep.tripHeadsign) == "University & College"

                expect(arrDep.trip.id) == "MTS_13405160"
                expect(arrDep.trip.shortName).to(beNil())

                expect(arrDep.tripStatus).toNot(beNil())
                let tripStatus = arrDep.tripStatus!
                expect(tripStatus.activeTrip.id) == "MTS_13405160"

                expect(arrDep.vehicleID) == "MTS_806"

                done()
            }
        }
    }
}
