//
//  VehicleTripOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit

// swiftlint:disable force_cast

class VehicleTripOperationTest: OBATestCase {

    func testAPIPath() {
        expect(VehicleTripOperation.buildAPIPath(vehicleID: "Hello/World")) == "/api/where/trip-for-vehicle/Hello%2FWorld.json"
    }

    func testSuccessfulStopsForRouteRequest() {
        let vehicleID = "1_2799"
        let apiPath = VehicleTripOperation.buildAPIPath(vehicleID: vehicleID)

        stub(condition: isHost(self.host) && isPath(apiPath)) { _ in
            return self.JSONFile(named: "trip-for-vehicle-1_2799.json")
        }

        waitUntil { done in
            let op = self.restService.getVehicleTrip(vehicleID: vehicleID)
            op.completionBlock = {
                expect(op.entries!.count) == 1

                let entry = op.entries!.first! as [AnyHashable: Any]
                expect(entry["status"]).toNot(beNil())

                let stops = op.references!["stops"] as! [Any]
                expect(stops.count) == 1

                done()
            }
        }
    }

}
