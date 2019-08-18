//
//  AgencyVehicleModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit

class AgencyVehicleModelOperationTests: OBATestCase {
    func testSuccesfulVehicleRequest() {
        let apiPath = MatchingVehiclesOperation.buildAPIPath(regionID: obacoRegionID)

        stub(condition: isHost(self.obacoHost) && isPath(apiPath)) { _ in
            let foo = OHHTTPStubsResponse.JSONFile(named: "vehicles-query-1_1.json")
            return foo
        }

        waitUntil { done in
            let op = self.obacoModelService.getVehicles(matching: "1_1")
            op.completionBlock = {
                let matches = op.matchingVehicles
                expect(matches.count) == 29
                expect(matches.first!.agencyName) == "Metro Transit"
                expect(matches.first!.vehicleID) == "1_1156"
                done()
            }
        }
    }
}
