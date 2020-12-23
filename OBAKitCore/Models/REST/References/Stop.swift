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

public class Stop: NSObject, Identifiable, Codable, HasReferences {

    /// The stop_code field contains a short piece of text or a number that uniquely identifies the stop for passengers.
    ///
    /// Stop codes are often used in phone-based transit information systems or printed on stop signage to
    /// make it easier for riders to get a stop schedule or real-time arrival information for a particular stop.
    /// The stop_code field contains short text or a number that uniquely identifies the stop for passengers.
    /// The stop_code can be the same as stop_id if it is passenger-facing. This field should be left blank
    /// for stops without a code presented to passengers.
    public let code: String

    private let _direction: String?

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
    ///
    /// Route IDs correspond to values in References.
    public let routeIDs: [String]

    /// A list of `Route`s served by this stop.
    public var routes: [Route]!

    /// All unique route types at this Stop.
    public lazy var routeTypes: Set<Route.RouteType> = {
        return Set(routes.map { $0.routeType })
    }()

    /// The route type that should be used to represent this Stop on a map.
    public var prioritizedRouteTypeForDisplay: Route.RouteType {
        let priorities: [Route.RouteType] = [.ferry, .lightRail, .subway, .rail, .bus]

        for t in priorities {
            if routeTypes.contains(t) {
                return t
            }
        }

        return .unknown
    }

    /// Denotes the availability of wheelchair boarding at this stop.
    public let wheelchairBoarding: WheelchairBoarding

    public private(set) var regionIdentifier: Int?

    private enum CodingKeys: String, CodingKey {
        case code
        case direction
        case id
        case lat
        case lon
        case locationType
        case name
        case regionIdentifier
        case routes
        case routeIDs = "routeIds"
        case wheelchairBoarding
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        code = try container.decode(String.self, forKey: .code)
        _direction = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .direction))
        id = try container.decode(StopID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        let lat = try container.decode(Double.self, forKey: .lat)
        let lon = try container.decode(Double.self, forKey: .lon)
        location = CLLocation(latitude: lat, longitude: lon)

        locationType = try container.decode(StopLocationType.self, forKey: .locationType)

        routeIDs = try container.decode([String].self, forKey: .routeIDs)

        if let encodedRoutes = try container.decodeIfPresent([Route].self, forKey: .routes) {
            // If we are decoding a Stop that has been serialized internally (e.g. as
            // part of a Recent Stops list), then it should contain a list of routes.
            // However, if we are decoding data from the REST API, then it will not
            // have routes at this time. Instead, routes will be loaded via the
            // `loadReferences()` method call, which is part of the HasReferences protocol.
            routes = encodedRoutes
        }

        regionIdentifier = try container.decodeIfPresent(Int.self, forKey: .regionIdentifier)

        wheelchairBoarding = (try container.decodeIfPresent(WheelchairBoarding.self, forKey: .wheelchairBoarding)) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(_direction, forKey: .direction)
        try container.encode(id, forKey: .id)
        try container.encode(location.coordinate.latitude, forKey: .lat)
        try container.encode(location.coordinate.longitude, forKey: .lon)
        try container.encode(locationType.rawValue, forKey: .locationType)
        try container.encode(name, forKey: .name)
        try container.encode(routeIDs, forKey: .routeIDs)
        try container.encodeIfPresent(regionIdentifier, forKey: .regionIdentifier)
        try container.encodeIfPresent(routes, forKey: .routes)
        try container.encode(wheelchairBoarding.rawValue, forKey: .wheelchairBoarding)
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References, regionIdentifier: Int?) {
        routes = references.routesWithIDs(routeIDs)
        self.regionIdentifier = regionIdentifier
    }

    // MARK: - CustomDebugStringConvertible

    public override var debugDescription: String {
        return String(format: "%@({id: %@, name: %@})", super.debugDescription, id, name)
    }

    // MARK: - Equatable and Hashable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Stop else {
            return false
        }

        return
            code == rhs.code &&
            direction == rhs.direction &&
            id == rhs.id &&
            location.coordinate.latitude == rhs.location.coordinate.latitude &&
            location.coordinate.longitude == rhs.location.coordinate.longitude &&
            locationType == rhs.locationType &&
            name == rhs.name &&
            regionIdentifier == rhs.regionIdentifier &&
            routeIDs == rhs.routeIDs &&
            wheelchairBoarding == rhs.wheelchairBoarding
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(code)
        hasher.combine(direction)
        hasher.combine(id)
        hasher.combine(location.coordinate.latitude)
        hasher.combine(location.coordinate.longitude)
        hasher.combine(locationType)
        hasher.combine(name)
        hasher.combine(regionIdentifier)
        hasher.combine(routeIDs)
        hasher.combine(wheelchairBoarding)
        return hasher.finalize()
    }
}
