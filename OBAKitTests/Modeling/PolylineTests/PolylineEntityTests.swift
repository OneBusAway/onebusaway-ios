//
//  PolylineEntityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class PolylineEntityTests {

    @Test func `Decode PolylineEntity from JSON dictionary`() throws {
        // Encoded polyline representing Seattle coordinates: (47.6062, -122.3321) to (47.6097, -122.3331)
        let samplePoints = "_it~FvgqiV_p@~h@"
        let dict: [String: Any] = [
            "points": samplePoints
        ]

        let entity = try Fixtures.dictionaryToModel(type: PolylineEntity.self, dictionary: dict)

        #expect(entity.points == samplePoints)
        let polyline = try #require(entity.polyline)
        #expect(polyline.pointCount > 0)
    }

    @Test func `Decode PolylineEntity from shape fixture`() throws {
        let data = Fixtures.loadData(file: "shape_1_20010002.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<PolylineEntity>.self, from: data)

        let entity = response.entry
        #expect(!entity.points.isEmpty)

        let polyline = try #require(entity.polyline)
        #expect(polyline.pointCount > 0)

        let coordinate = polyline.coordinate
        expectClose(coordinate.latitude, 47.6229, within: 0.01)
        expectClose(coordinate.longitude, -122.3225, within: 0.01)
    }

    @Test func `PolylineEntity with empty points produces nil or empty polyline safely`() throws {
        let emptyDict: [String: Any] = [
            "points": ""
        ]
        let emptyEntity = try Fixtures.dictionaryToModel(type: PolylineEntity.self, dictionary: emptyDict)
        #expect(emptyEntity.points.isEmpty)
        // Polyline("") coordinates decode as empty array, producing 0 point MKPolyline or nil
        let pointCount = emptyEntity.polyline?.pointCount ?? 0
        #expect(pointCount == 0)
    }

    @Test func `Decode failure when points key missing`() {
        let missingPoints: [String: Any] = [:]

        #expect(throws: (any Error).self) {
            try Fixtures.dictionaryToModel(type: PolylineEntity.self, dictionary: missingPoints)
        }
    }
}
