//
//  MatchingVehicleOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import OBATestHelpers
@testable import OBANetworkingKit

class MatchingVehicleOperationTest: OBATestCase {

    func testSuccesfulVehicleRequest() {
        let apiPath = MatchingVehiclesOperation.buildAPIPath(regionID: obacoRegionID)

        stub(condition: isHost(self.obacoHost) && isPath(apiPath)) { _ in
            return self.JSONFile(named: "vehicles-query-1_1.json")
        }

        waitUntil { done in
            let op = self.obacoService.getVehicles(matching: "1_1")
            op.completionBlock = {
                let list = try! JSONSerialization.jsonObject(with: op.data!, options: []) as! [[String: Any]]
                expect(list.count) == 29
                expect((list.first!["name"] as! String)) == "Metro Transit"

                done()
            }
        }
    }
}
