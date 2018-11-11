//
//  OBATestCase.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/14/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import OHHTTPStubs
import OBANetworkingKit

public class OBATestCase : XCTestCase {
    public override func setUp() {
        super.setUp()
        NSTimeZone.default = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
    }
    public override func tearDown() {
        super.tearDown()
        OHHTTPStubs.removeAllStubs()
        NSTimeZone.resetSystemTimeZone()
    }
}
