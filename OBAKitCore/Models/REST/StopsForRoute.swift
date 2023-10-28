//
//  StopsForRoute.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit

// swiftlint:disable nesting

/// Retrieve the set of stops serving a particular route, including groups by direction of travel.
///
/// The stops-for-route method first and foremost provides a method for retrieving the set of stops
/// that serve a particular route. In addition to the full set of stops, we provide various
/// “stop groupings” that are used to group the stops into useful collections. Currently, the main
/// grouping provided organizes the set of stops by direction of travel for the route. Finally,
/// this method also returns a set of polylines that can be used to draw the path traveled by the route.
public struct StopsForRoute: Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case routeID = "routeId"
        case polylines
        case stopIDs = "stopIds"
        case stopGroupings
    }

    public var id: String {
        return routeID
    }

    public let routeID: String
    public let polylines: [PolylineEntity]
    public let stopIDs: [String]
    public let stopGroupings: [StopGrouping]

    public var mapRect: MKMapRect {
        return polylines.reduce(into: MKMapRect.null) { partialResult, polyline in
            if let boundingMapRect = polyline.polyline?.boundingMapRect {
                partialResult.union(boundingMapRect)
            }
        }
    }

    // MARK: - Nested Types

    // MARK: StopGrouping
    public struct StopGrouping: Codable {
        public let ordered: Bool
        public let groupingType: String
        public let stopGroups: [StopsForRoute.StopGroup]

        enum CodingKeys: String, CodingKey {
            case ordered, stopGroups
            case groupingType = "type"
        }
    }

    // MARK: - StopGroup
    public struct StopGroup: Identifiable, Codable {
        public let id: String

        public let name: String
        public let groupingType: String
        public let polylines: [PolylineEntity]
        public let stopIDs: [String]

        enum CodingKeys: String, CodingKey {
            case id, name, polylines
            case groupingType = "type"
            case stopIDs = "stopIds"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            id = try container.decode(String.self, forKey: .id)

            let nameContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .name)
            name = try nameContainer.decode(String.self, forKey: .name)
            groupingType = try nameContainer.decode(String.self, forKey: .groupingType)

            polylines = try container.decode([PolylineEntity].self, forKey: .polylines)
            stopIDs = try container.decode([String].self, forKey: .stopIDs)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)

            var nameContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .name)
            try nameContainer.encode(name, forKey: .name)
            try nameContainer.encode(groupingType, forKey: .groupingType)

            try container.encode(stopIDs, forKey: .stopIDs)
            try container.encode(polylines, forKey: .polylines)
        }
    }
}

// swiftlint:enable nesting
