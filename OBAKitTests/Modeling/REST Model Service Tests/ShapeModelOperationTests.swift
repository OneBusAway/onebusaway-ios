//
//  ShapeModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class ShapeModelOperationTests: OBATestCase {
    let shapeID = "shape_1_20010002"

    func testLoading_success() {
        let dataLoader = restService.dataLoader as! MockDataLoader

        let data = Fixtures.loadData(file: "shape_1_20010002.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/shape/\(shapeID).json", with: data)

        let op = restService.getShape(id: shapeID)
        waitUntil { (done) in
            op.complete { result in
                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    let polyline = response.entry.polyline!
                    let coordinate = polyline.coordinate
                    expect(coordinate.latitude).to(beCloseTo(47.6229))
                    expect(coordinate.longitude).to(beCloseTo(-122.3225))
                    done()
                }
            }
        }
    }
}
