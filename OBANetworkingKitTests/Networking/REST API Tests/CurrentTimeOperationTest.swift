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

class CurrentTimeTests: OBATestCase {
    func testSuccessfulAPICall() {
        stub(condition: isHost(self.host) && isPath(CurrentTimeOperation.apiPath)) { _ in
            return self.JSONFile(named: "current_time.json")
        }

        waitUntil { (done) in
            self.restService.getCurrentTime { op in
                let op = op as! CurrentTimeOperation
                expect(op.currentTime!).to(beCloseTo(Date.fromComponents(year: 2012, month: 07, day: 29, hour: 18, minute: 37, second: 48), within: 1.0))
                done()
            }
        }
    }
}
