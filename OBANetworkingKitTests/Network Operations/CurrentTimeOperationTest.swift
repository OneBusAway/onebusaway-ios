//
//  CurrentTimeOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBANetworkingKit

class CurrentTimeTests: XCTestCase, OperationTest {
    override func tearDown() {
        super.tearDown()

        OHHTTPStubs.removeAllStubs()
    }

    func testSuccessfulAPICall() {
        stub(condition: isHost(self.host) && isPath(CurrentTimeOperation.apiPath)) { _ in
            return OHHTTPStubsResponse(data: Data(), statusCode: 200, headers: ["Date": "October 2, 2018 19:42:00 PDT"])
        }

        waitUntil { (done) in
            self.builder.getCurrentTime { op in
                expect(op.currentTime).to(equal("October 2, 2018 19:42:00 PDT"))
                done()
            }
        }
    }
}
