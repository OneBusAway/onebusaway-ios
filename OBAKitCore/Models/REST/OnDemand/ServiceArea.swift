//
//  ServiceArea.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// `[minLon, minLat, maxLon, maxLat]` on the wire (RFC 7946 order).
public struct BoundingBox: Hashable, Sendable {
    public let minLongitude: Double
    public let minLatitude: Double
    public let maxLongitude: Double
    public let maxLatitude: Double

    public init(minLongitude: Double, minLatitude: Double, maxLongitude: Double, maxLatitude: Double) {
        self.minLongitude = minLongitude
        self.minLatitude = minLatitude
        self.maxLongitude = maxLongitude
        self.maxLatitude = maxLatitude
    }

    public var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
    }
}

/// A zone an on-demand service covers (wiki §3.4 `serviceArea`).
///
/// `geometry` is endpoint policy (`geometryDetail=none|simplified|full`), so
/// `polygons` may be empty even for a real zone; `bbox` is always present.
/// Simplified geometry is for display only — containment and distance come
/// from the server as `distanceToArea`/`nearestPointOnBoundary`, never from
/// testing these polygons.
public struct ServiceArea: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let areaDescription: String?
    public let bbox: BoundingBox
    /// `polygons[p][ring][i]`: ring 0 is the exterior, rings 1… are holes.
    /// One element for a GeoJSON `Polygon`, several for a `MultiPolygon`,
    /// empty when the key was omitted or the type is unsupported.
    public let polygons: [[[CLLocationCoordinate2D]]]
    /// Meters from the query point to the nearest boundary; `0` inside.
    /// Non-nil only in `services-for-location` point mode.
    public let distanceToArea: Double?
    /// Closest boundary point; nil inside the area or outside point mode.
    public let nearestPointOnBoundary: CLLocationCoordinate2D?

    public var hasGeometry: Bool { !polygons.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id, name, bbox, geometry, distanceToArea, nearestPointOnBoundary
        case areaDescription = "description"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .name))
        areaDescription = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .areaDescription))

        let box = try container.decode([Double].self, forKey: .bbox)
        guard box.count == 4 else {
            throw DecodingError.dataCorruptedError(forKey: .bbox, in: container, debugDescription: "bbox must have four numbers, got \(box.count)")
        }
        bbox = BoundingBox(minLongitude: box[0], minLatitude: box[1], maxLongitude: box[2], maxLatitude: box[3])

        polygons = try container.decodeIfPresent(GeoJSONGeometry.self, forKey: .geometry)?.polygons ?? []
        distanceToArea = try container.decodeIfPresent(Double.self, forKey: .distanceToArea)

        if let point = try container.decodeIfPresent([Double].self, forKey: .nearestPointOnBoundary), point.count == 2 {
            nearestPointOnBoundary = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        } else {
            nearestPointOnBoundary = nil
        }
    }
}

/// The subset of GeoJSON geometry the contract allows: `Polygon` and
/// `MultiPolygon`, positions as `[lon, lat]`.
private struct GeoJSONGeometry: Decodable {
    let polygons: [[[CLLocationCoordinate2D]]]

    private enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "Polygon":
            polygons = [Self.rings(try container.decode([[[Double]]].self, forKey: .coordinates))]
        case "MultiPolygon":
            polygons = try container.decode([[[[Double]]]].self, forKey: .coordinates).map(Self.rings)
        default:
            polygons = []
        }
    }

    private static func rings(_ rings: [[[Double]]]) -> [[CLLocationCoordinate2D]] {
        rings.map { ring in
            ring.compactMap { position in
                position.count >= 2 ? CLLocationCoordinate2D(latitude: position[1], longitude: position[0]) : nil
            }
        }
    }
}
