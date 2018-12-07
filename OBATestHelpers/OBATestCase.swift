//
//  OBATestCase.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/14/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import OHHTTPStubs

open class OBATestCase : XCTestCase {
    open override func setUp() {
        super.setUp()
        NSTimeZone.default = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
    }

    open override func tearDown() {
        super.tearDown()
        OHHTTPStubs.removeAllStubs()
        NSTimeZone.resetSystemTimeZone()
    }
}
