//
//  ShapeModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
@testable import OBAKit

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
                expect(op.polyline).toNot(beNil())

                let coordinate = op.polyline!.coordinate
                expect(coordinate.latitude).to(beCloseTo(47.6229))
                expect(coordinate.longitude).to(beCloseTo(-122.3225))
                done()
            }
        }
    }
}
