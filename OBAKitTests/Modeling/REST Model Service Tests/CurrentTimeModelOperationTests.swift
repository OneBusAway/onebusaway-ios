//
//  CurrentTimeModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/30/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBAKit

class CurrentTimeModelOperationTests: OBATestCase {

    func testCurrentTime_success() {
        stub(condition: isHost(self.host) && isPath(CurrentTimeOperation.apiPath)) { _ in
            return self.JSONFile(named: "current_time.json")
        }

        let op = self.restModelService.getCurrentTime()
        waitUntil { (done) in
            op.completionBlock = {
                let date = op.currentTime!
                expect(date).to(beCloseTo(Date.fromComponents(year: 2012, month: 07, day: 29, hour: 18, minute: 37, second: 48), within: 1.0))
                done()
            }
        }
    }
}
