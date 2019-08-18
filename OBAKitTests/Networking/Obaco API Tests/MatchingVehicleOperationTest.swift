//
//  MatchingVehicleOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit

// swiftlint:disable force_cast force_try

class MatchingVehicleOperationTest: OBATestCase {

    func testSuccesfulVehicleRequest() {
        let apiPath = MatchingVehiclesOperation.buildAPIPath(regionID: obacoRegionID)

        stub(condition: isHost(self.obacoHost) && isPath(apiPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "vehicles-query-1_1.json")
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
