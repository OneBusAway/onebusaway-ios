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
@testable import OBANetworkingKit

class AgenciesWithCoverageOperationTest: XCTestCase, OperationTest {
    // http://api.pugetsound.onebusaway.org/api/where/agencies-with-coverage.json?key=org.onebusaway.iphone&app_uid=BD88D98C-A72D-47BE-8F4A-C60467239736&app_ver=20181001.23&version=2

    override func tearDown() {
        super.tearDown()
        OHHTTPStubs.removeAllStubs()
    }

    func testSuccessfulAgenciesRequest() {
        stub(condition: isHost(self.host) && isPath(AgenciesWithCoverageOperation.apiPath)) { _ in
            return self.JSONFile(named: "agencies_with_coverage.json")
        }

        waitUntil { done in
            self.builder.getAgenciesWithCoverage { op in

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
