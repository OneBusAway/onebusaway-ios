//
//  Stop.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable
import CoreLocation

public typealias StopID = String

@Codable
public struct Stop: Identifiable, Hashable {
    // MARK: - Definitions
    public enum WheelchairBoarding: String, Codable {
        case accessible
        case notAccessible
        case unknown
    }

    public enum Direction: String, Codable, Comparable {
        case n, ne, e, se, s, sw, w, nw, unknown

        public static func < (lhs: Direction, rhs: Direction) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    public enum LocationType: Int, Codable {
        /// Stop. A location where passengers board or disembark from a transit vehicle.
        case stop

        /// Station. A physical structure or area that contains one or more stop.
        case station

        /// Station Entrance/Exit. A location where passengers can enter or exit a station from the street. The stop entry must also specify a parent_station value referencing the stop ID of the parent station for the entrance.
        case stationEntrance

        case unknown
    }

    // MARK: - Properties

    /// The stop_code field contains a short piece of text or a number that uniquely identifies the stop for passengers.
    ///
    /// Stop codes are often used in phone-based transit information systems or printed on stop signage to
    /// make it easier for riders to get a stop schedule or real-time arrival information for a particular stop.
    /// The stop_code field contains short text or a number that uniquely identifies the stop for passengers.
    /// The stop_code can be the same as stop_id if it is passenger-facing. This field should be left blank
    /// for stops without a code presented to passengers.
    public let code: String

    @Default(Direction.unknown)
    public let direction: Direction

    /// The stop_id field contains an ID that uniquely identifies a stop, station, or station entrance.
    ///
    /// Multiple routes may use the same stop. The stop_id is used by systems as an internal identifier
    /// of this record (e.g., primary key in database), and therefore the stop_id must be dataset unique.
    public let id: StopID

    @CodedAt("lat")
    fileprivate let latitude: Double

    @CodedAt("lon")
    fileprivate let longitude: Double

    /// Identifies whether this stop represents a stop, station, or station entrance.
    @Default(LocationType.unknown)
    public let locationType: LocationType

    /// A human-readable name for this stop.
    public let name: String

    /// A list of route IDs served by this stop.
    ///
    /// Route IDs correspond to values in References.
    @CodedAt("routeIds")
    public let routeIDs: [RouteID]

    /// Denotes the availability of wheelchair boarding at this stop.
    @Default(WheelchairBoarding.unknown)
    public let wheelchairBoarding: WheelchairBoarding
}

extension Stop {
    /// The coordinates of the stop.
    public var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// A localized name for this stop including the direction, if available.
    /// Example: "E Pine St & 15th Ave (W)" for a westbound bus stop.
    public var nameWithLocalizedDirectionAbbreviation: String {
        if let direction = Formatters.directionAbbreviation(direction) {
            return "\(name) (\(direction))"
        } else {
            return name
        }
    }

    public var routes: [Route] {
        return []   // TODO: This
    }

    /// All unique route types at this Stop.
    public var routeTypes: Set<Route.RouteType> {
        return []   // TODO: This
//        return Set(routes.map { $0.routeType })
    }

    /// The route type that should be used to represent this Stop on a map.
    public var prioritizedRouteTypeForDisplay: Route.RouteType {
        let priorities: [Route.RouteType] = [.ferry, .lightRail, .subway, .rail, .bus]

        // swiftlint:disable for_where
        for t in priorities {
            if routeTypes.contains(t) {
                return t
            }
        }
        // swiftlint:enable for_where

        return .unknown
    }
}
