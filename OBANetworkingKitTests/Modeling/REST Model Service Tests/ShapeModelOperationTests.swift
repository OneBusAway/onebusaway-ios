//
//  ShapeModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
@testable import OBANetworkingKit

class ShapeModelOperationTests: OBATestCase {
    let shapeID = "shape_1_20010002"
    func stubAPICall() {
        stub(condition: isHost(self.host) && isPath(ShapeOperation.buildAPIPath(shapeID: shapeID))) { _ in
            return self.JSONFile(named: "shape_1_20010002.json")
        }
    }

    func testLoading_success() {
        stubAPICall()

        waitUntil { (done) in
            let op = self.restModelService.getShape(id: self.shapeID)
            op.completionBlock = {
                expect(op.shape) == "afvaHbdpiV^?pIFdKDj@?L?xC@tC?f@?xB?`DBn@@rB?B?b@?t@@lC@^?h@?`DBZ?`DB~BHhB@?~A?z@@bD?~B@`C@bC?bC?vB@hC@bC?bC?jG@rA?n@?bC@nBD~@JlAJr@Lv@Rn@Vv@NVR`@^h@h@r@pAbAtC|BbChBdA?lA?`FBCzA?|BPn@j@nB|A~EzA|En@lBl@lBh@dB"
                done()
            }
        }
    }
}
