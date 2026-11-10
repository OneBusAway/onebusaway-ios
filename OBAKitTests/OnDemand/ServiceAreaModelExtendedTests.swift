//
//  ServiceAreaModelExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `ServiceArea` and `BoundingBox` GeoJSON polygon parsing, coordinate orders,
/// and bounding box centroid calculations.
@Suite(.serialized)
struct ServiceAreaModelExtendedTests {

    // MARK: - BoundingBox Centroid

    @Test func `BoundingBox calculates exact geographic center`() {
        let bbox = BoundingBox(
            minLongitude: -122.5,
            minLatitude: 47.0,
            maxLongitude: -122.0,
            maxLatitude: 48.0
        )

        let center = bbox.center
        #expect(abs(center.latitude - 47.5) < 0.0001)
        #expect(abs(center.longitude - (-122.25)) < 0.0001)
    }

    // MARK: - ServiceArea Decoding from Polygon GeoJSON

    @Test func `ServiceArea decodes Polygon GeoJSON coordinates in RFC 7946 lon-lat order`() throws {
        let json = """
        {
            "id": "zone_metro_center",
            "name": "Metro Center Zone",
            "description": "On-demand service zone",
            "bbox": [-122.4, 47.5, -122.2, 47.7],
            "geometry": {
                "type": "Polygon",
                "coordinates": [
                    [
                        [-122.4, 47.5],
                        [-122.2, 47.5],
                        [-122.2, 47.7],
                        [-122.4, 47.7],
                        [-122.4, 47.5]
                    ]
                ]
            },
            "distanceToArea": 0.0
        }
        """.data(using: .utf8)!

        let area = try JSONDecoder().decode(ServiceArea.self, from: json)
        #expect(area.id == "zone_metro_center")
        #expect(area.name == "Metro Center Zone")
        #expect(area.areaDescription == "On-demand service zone")
        #expect(area.hasGeometry == true)
        #expect(area.distanceToArea == 0.0)
        #expect(area.nearestPointOnBoundary == nil)

        #expect(area.polygons.count == 1) // 1 polygon
        #expect(area.polygons[0].count == 1) // 1 outer ring
        #expect(area.polygons[0][0].count == 5) // 5 vertices

        // Verify latitude and longitude conversion: GeoJSON [lon, lat] -> CLLocationCoordinate2D(lat, lon)
        let firstCoord = area.polygons[0][0][0]
        #expect(abs(firstCoord.latitude - 47.5) < 0.0001)
        #expect(abs(firstCoord.longitude - (-122.4)) < 0.0001)
    }

    @Test func `ServiceArea decodes MultiPolygon GeoJSON correctly`() throws {
        let json = """
        {
            "id": "multipolygon_zone",
            "bbox": [-122.5, 47.0, -121.5, 48.0],
            "geometry": {
                "type": "MultiPolygon",
                "coordinates": [
                    [
                        [
                            [-122.5, 47.0],
                            [-122.0, 47.0],
                            [-122.0, 47.5],
                            [-122.5, 47.0]
                        ]
                    ],
                    [
                        [
                            [-121.9, 47.6],
                            [-121.5, 47.6],
                            [-121.5, 48.0],
                            [-121.9, 47.6]
                        ]
                    ]
                ]
            }
        }
        """.data(using: .utf8)!

        let area = try JSONDecoder().decode(ServiceArea.self, from: json)
        #expect(area.id == "multipolygon_zone")
        #expect(area.polygons.count == 2)
        #expect(area.polygons[0].count == 1)
        #expect(area.polygons[1].count == 1)
    }

    @Test func `ServiceArea decodes nearestPointOnBoundary when provided`() throws {
        let json = """
        {
            "id": "outside_zone",
            "bbox": [-122.4, 47.5, -122.2, 47.7],
            "distanceToArea": 250.5,
            "nearestPointOnBoundary": [-122.3, 47.5]
        }
        """.data(using: .utf8)!

        let area = try JSONDecoder().decode(ServiceArea.self, from: json)
        #expect(area.distanceToArea == 250.5)
        #expect(area.nearestPointOnBoundary != nil)
        #expect(abs(area.nearestPointOnBoundary!.latitude - 47.5) < 0.0001)
        #expect(abs(area.nearestPointOnBoundary!.longitude - (-122.3)) < 0.0001)
    }

    @Test func `ServiceArea decoding fails when bbox has invalid length`() {
        let json = """
        {
            "id": "bad_bbox",
            "bbox": [-122.4, 47.5, -122.2]
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ServiceArea.self, from: json)
        }
    }
}
