//
//  RegionsOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/17/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import OBATestHelpers
@testable import OBANetworkingKit

class RegionsOperationTest: OBATestCase {
    func testSuccessfulRegionsRequest() {
        stub(condition: isHost(self.regionsHost) && isPath(RegionsOperation.apiPath)) { _ in
            return self.JSONFile(named: "regions-v3.json")
        }

        waitUntil { done in
            let op = self.regionsAPIService.getRegions()
            op.completionBlock = {
                let entries = op.entries!
                expect(entries).toNot(beNil())
                expect(entries.count) == 12

                done()
            }
        }
    }
}
