//
//  VehicleModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/19/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBANetworkingKit

class VehicleModelOperationTests: OBATestCase {

    let vehicleID = "40_11"

    func testLoadingVehicle_success() {
        let apiPath = RequestVehicleOperation.buildAPIPath(vehicleID: vehicleID)

        stub(condition: isHost(self.host) && isPath(apiPath)) { _ in
            return self.JSONFile(named: "vehicle_for_id_4011.json")
        }

        waitUntil { done in
            let op = self.restModelService.getVehicle(self.vehicleID)
            op.completionBlock = {
                expect(op.vehicles.count) == 1

                // abxoxo - todo test property values!  

                done()
            }
        }
    }
}
