//
//  StopsForRoute.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable
import MapKit

extension Polyline {
    struct EncodedPolyline: HelperCoder {
        private struct RawPolyline: Codable {
            let points: String
        }

        func decode(from decoder: Decoder) throws -> [Polyline] {
            let container = try decoder.singleValueContainer()
            let rawPolylines = try container.decode([RawPolyline].self)
            return rawPolylines.map { Polyline(encodedPolyline: $0.points) }
        }

        func encode(_ value: [Polyline], to encoder: Encoder) throws {
            fatalError("\(#function) unimplemented.")
        }
    }
}

// swiftlint:disable nesting

/// Retrieve the set of stops serving a particular route, including groups by direction of travel.
///
/// The stops-for-route method first and foremost provides a method for retrieving the set of stops
/// that serve a particular route. In addition to the full set of stops, we provide various
/// “stop groupings” that are used to group the stops into useful collections. Currently, the main
/// grouping provided organizes the set of stops by direction of travel for the route. Finally,
/// this method also returns a set of polylines that can be used to draw the path traveled by the route.
@Codable
public struct StopsForRoute: Identifiable {
    public var id: String {
        return routeID
    }

    @CodedAt("routeId")
    public let routeID: String
//    public private(set) var route: Route!

    @CodedBy(Polyline.EncodedPolyline())
    public let polylines: [Polyline]

    @IgnoreCoding
    public lazy var mapRect: MKMapRect = {
        var bounds = MKMapRect.null
        for p in polylines {
            guard let mkPolyline = p.mkPolyline else { continue }
            bounds = bounds.union(mkPolyline.boundingMapRect)
        }
        return bounds
    }()

    @CodedAt("stopIds")
    public let stopIDs: [String]

//    public private(set) var regionIdentifier: Int?

    public let stopGroupings: [StopGrouping]

    // MARK: - HasReferences

//    public func loadReferences(_ references: References, regionIdentifier: Int?) {
//        route = references.routeWithID(routeID)!
//        stops = references.stopsWithIDs(stopIDs)
//        stopGroupings.loadReferences(references, regionIdentifier: regionIdentifier)
//        self.regionIdentifier = regionIdentifier
//    }

    // MARK: - Nested Types

    // MARK: - StopGrouping
    @Codable
    public struct StopGrouping/*, HasReferences*/ {
        public let ordered: Bool

        @CodedAt("type")
        public let groupingType: String
        public let stopGroups: [StopsForRoute.StopGroup]

//        public private(set) var regionIdentifier: Int?

//        public func loadReferences(_ references: References, regionIdentifier: Int?) {
//            stopGroups.loadReferences(references, regionIdentifier: regionIdentifier)
//            self.regionIdentifier = regionIdentifier
//        }
    }

    // MARK: - StopGroup
    @Codable
    public struct StopGroup: Identifiable/*, HasReferences*/ {
        public let id: String

        @CodedAt("name", "name") /* stopGroup.name.name <- yes, double */
        public let name: String

        @CodedAt("name", "type")
        public let groupingType: String

        @CodedBy(Polyline.EncodedPolyline())
        public let polylines: [Polyline]

        @CodedAt("stopIds")
        public let stopIDs: [String]
//        public private(set) var stops = [Stop]()

//        public private(set) var regionIdentifier: Int?
    }
}

// swiftlint:enable nesting
