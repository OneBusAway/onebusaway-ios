//
//  Stop.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

public typealias StopID = String

public enum WheelchairBoarding: String, Decodable {
    case accessible
    case notAccessible
    case unknown

    public init(from decoder: Decoder) throws {
        let val = try decoder.singleValueContainer().decode(String.self)
        self = WheelchairBoarding(rawValue: val) ?? .unknown
    }
}

public enum Direction: Int, Comparable {
    case n, ne, e, se, s, sw, w, nw, unknown

    public static func < (lhs: Direction, rhs: Direction) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public enum StopLocationType: Int, Decodable {
    /// Stop. A location where passengers board or disembark from a transit vehicle.
    case stop

    /// Station. A physical structure or area that contains one or more stop.
    case station

    /// Station Entrance/Exit. A location where passengers can enter or exit a station from the street. The stop entry must also specify a parent_station value referencing the stop ID of the parent station for the entrance.
    case stationEntrance

    case unknown

    public init(from decoder: Decoder) throws {
        let val = try decoder.singleValueContainer().decode(Int.self)
        self = StopLocationType(rawValue: val) ?? .unknown
    }
}

public struct Stop: Identifiable, Codable, Hashable {

    /// The stop_code field contains a short piece of text or a number that uniquely identifies the stop for passengers.
    ///
    /// Stop codes are often used in phone-based transit information systems or printed on stop signage to
    /// make it easier for riders to get a stop schedule or real-time arrival information for a particular stop.
    /// The stop_code field contains short text or a number that uniquely identifies the stop for passengers.
    /// The stop_code can be the same as stop_id if it is passenger-facing. This field should be left blank
    /// for stops without a code presented to passengers.
    public let code: String

    internal let _direction: String?

    /// A cardinal direction: N, E, S, W.
    public var direction: Direction {
        guard let _direction = _direction else {
            return .unknown
        }

        switch _direction.lowercased() {
        case "n": return .n
        case "ne": return .ne
        case "e": return .e
        case "se": return .se
        case "s": return .s
        case "sw": return .sw
        case "w": return .w
        case "nw": return .nw
        default: return .unknown
        }
    }

    /// The stop_id field contains an ID that uniquely identifies a stop, station, or station entrance.
    ///
    /// Multiple routes may use the same stop. The stop_id is used by systems as an internal identifier
    /// of this record (e.g., primary key in database), and therefore the stop_id must be dataset unique.
    public let id: StopID

    /// The coordinates of the stop.
    public let location: CLLocation
    /// Identifies whether this stop represents a stop, station, or station entrance.
    public let locationType: StopLocationType

    /// A human-readable name for this stop.
    public let name: String

    /// A list of route IDs served by this stop.
    let routeIDs: [RouteID]

    /// Denotes the availability of wheelchair boarding at this stop.
    public let wheelchairBoarding: WheelchairBoarding
}

extension Stop {
    /// A localized name for this stop including the direction, if available.
    /// Example: "E Pine St & 15th Ave (W)" for a westbound bus stop.
    public var nameWithLocalizedDirectionAbbreviation: String {
        if let direction = Formatters.directionAbbreviation(direction) {
            return "\(name) (\(direction))"
        } else {
            return name
        }
    }

    /// All unique route types at this Stop.
    public var routeTypes: Set<Route.RouteType> {
        fatalError("PR-686 error: \(#function) unimplemented.")
//        return Set(routes.map { $0.routeType })
    }

    /// The route type that should be used to represent this Stop on a map.
    public var prioritizedRouteTypeForDisplay: Route.RouteType {
        fatalError("PR-686 error: \(#function) unimplemented.")
//        let priorities: [Route.RouteType] = [.ferry, .lightRail, .subway, .rail, .bus]
//
//        // swiftlint:disable for_where
//        for t in priorities {
//            if routeTypes.contains(t) {
//                return t
//            }
//        }
//        // swiftlint:enable for_where
//
//        return .unknown
    }

    internal enum CodingKeys: String, CodingKey {
        case code
        case direction
        case id
        case latitude = "lat"
        case longitude = "lon"
        case locationType
        case name
        case regionIdentifier
        case routes
        case routeIDs = "routeIds"
        case wheelchairBoarding
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        code = try container.decode(String.self, forKey: .code)
        _direction = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .direction))
        id = try container.decode(StopID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        location = CLLocation(latitude: lat, longitude: lon)

        locationType = try container.decode(StopLocationType.self, forKey: .locationType)
        routeIDs = try container.decode([String].self, forKey: .routeIDs)
        wheelchairBoarding = (try container.decodeIfPresent(WheelchairBoarding.self, forKey: .wheelchairBoarding)) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(_direction, forKey: .direction)
        try container.encode(id, forKey: .id)
        try container.encode(location.coordinate.latitude, forKey: .latitude)
        try container.encode(location.coordinate.longitude, forKey: .longitude)
        try container.encode(locationType.rawValue, forKey: .locationType)
        try container.encode(name, forKey: .name)
        try container.encode(routeIDs, forKey: .routeIDs)
        try container.encode(wheelchairBoarding.rawValue, forKey: .wheelchairBoarding)
    }
}
