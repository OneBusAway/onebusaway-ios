//
//  CurrentTimeOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Quick
import Nimble
import OHHTTPStubs
@testable import OBANetworkingKit

class CurrentTimeOperationTests: OperationTest {

    private func testSuccessfulAPICall() {
        describe("A successful API call") {
            beforeSuite {
                stub(condition: isHost(self.host) && isPath(CurrentTimeOperation.apiPath)) { _ in
                    return OHHTTPStubsResponse(data: Data(), statusCode: 200, headers: ["Date": "October 2, 2018 19:42:00 PDT"])
                }
            }
            afterSuite { OHHTTPStubs.removeAllStubs() }

            it("has a currentTime value set") {
                waitUntil { done in
                    self.builder.getCurrentTime { op in
                        expect(op.currentTime).to(equal("October 2, 2018 19:42:00 PDT"))
                        done()
                    }
                }
            }
        }
    }

    override func spec() {
        testSuccessfulAPICall()
    }
}
