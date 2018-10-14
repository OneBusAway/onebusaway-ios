//
//  RequestVehicleOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBANetworkingKit

class RequestVehicleOperationSpec: OBATestCase {
    func testSuccessfulVehicleRequest() {
        let vehicleID = "4011"
        let apiPath = RequestVehicleOperation.buildAPIPath(vehicleID: vehicleID)

        stub(condition: isHost(self.host) && isPath(apiPath)) { _ in
            return self.JSONFile(named: "vehicle_for_id_4011.json")
        }

        waitUntil { done in
            self.builder.getVehicle(vehicleID) { op in
                expect(op.entries).toNot(beNil())
                expect(op.references).toNot(beNil())

                let entry = op.entries?.first as! [String: AnyObject]
                let lastUpdateTime = entry["lastUpdateTime"] as! Int
                expect(lastUpdateTime).to(equal(1538584269000))

                let references = op.references as! [String: AnyObject]
                let agencies = references["agencies"] as! [AnyObject]
                expect(agencies.count).to(equal(2))

                done()
            }
        }
    }
}
