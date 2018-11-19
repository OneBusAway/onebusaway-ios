//
//  AgenciesWithCoverageOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import OBATestHelpers
@testable import OBANetworkingKit

class AgenciesWithCoverageOperationTest: OBATestCase {
    func testSuccessfulAgenciesRequest() {
        stub(condition: isHost(self.host) && isPath(AgenciesWithCoverageOperation.apiPath)) { _ in
            return self.JSONFile(named: "agencies_with_coverage.json")
        }

        waitUntil { done in
            let op = self.restService.getAgenciesWithCoverage()
            op.completionBlock = {
                let entries = op.entries!
                expect(entries).toNot(beNil())
                expect(entries.count) == 11

                let references = op.references!
                expect(references).toNot(beNil())

                let agencies = references["agencies"] as! [Any]
                expect(agencies.count) == 11

                done()
            }
        }
    }
}
