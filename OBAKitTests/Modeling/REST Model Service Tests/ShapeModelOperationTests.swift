//
//  ShapeModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import CoreLocation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class ShapeModelOperationTests: OBATestCase {
    let shapeID = "shape_1_20010002"

    func testLoading_success() async throws {
        let dataLoader = restService.dataLoader as! MockDataLoader

        let data = Fixtures.loadData(file: "shape_1_20010002.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/shape/\(shapeID).json", with: data)

        let response = try await restService.getShape(id: shapeID)
        let polyline = try XCTUnwrap(response.entry.polyline)
        let coordinate = polyline.coordinate
        expectClose(coordinate.latitude, 47.6229)
        expectClose(coordinate.longitude, -122.3225)
    }
}
