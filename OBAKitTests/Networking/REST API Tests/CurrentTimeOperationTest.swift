//
//  CurrentTimeOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit

class CurrentTimeTests: OBATestCase {
    func testSuccessfulAPICall() {
        stub(condition: isHost(self.host) && isPath(CurrentTimeOperation.apiPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "current_time.json")
        }

        waitUntil { (done) in
            let op = self.restService.getCurrentTime()
            op.completionBlock = {
                expect(op.currentTime!).to(beCloseTo(Date.fromComponents(year: 2012, month: 07, day: 29, hour: 18, minute: 37, second: 48), within: 1.0))
                done()
            }
        }
    }
}
