//
//  ShapeTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKitCore

final class ShapeTests: OBAKitCoreTestCase {
    let shapeID = "shape_1_20010002"

    func testLoading() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/shape/\(shapeID).json",
            with: try Fixtures.loadData(file: "shape_1_20010002.json")
        )

        let response = try await restAPIService.getShape(id: shapeID)
        let polyline = try XCTUnwrap(response.entry.polyline)
        XCTAssertEqual(polyline.coordinate.latitude, 47.6229, accuracy: 0.0001)
        XCTAssertEqual(polyline.coordinate.longitude, -122.3225, accuracy: 0.0001)
    }
}
