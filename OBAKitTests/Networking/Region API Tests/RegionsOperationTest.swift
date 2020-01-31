//
//  RegionsOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/17/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit
@testable import OBAKitCore

class RegionsOperationTest: OBATestCase {
    func testSuccessfulRegionsRequest() {
        stub(condition: isHost(self.regionsHost) && isPath(self.regionsPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "regions-v3.json")
        }

        waitUntil { done in
            let op = self.regionsAPIService.getRegions(apiPath: self.regionsAPIPath)
            op.completionBlock = {
                let entries = op.entries!
                expect(entries).toNot(beNil())
                expect(entries.count) == 12

                done()
            }
        }
    }
}
