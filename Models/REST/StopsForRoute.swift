//
//  StopsForRoute.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Retrieve the set of stops serving a particular route, including groups by direction of travel.
///
/// The stops-for-route method first and foremost provides a method for retrieving the set of stops
/// that serve a particular route. In addition to the full set of stops, we provide various
/// “stop groupings” that are used to group the stops into useful collections. Currently, the main
/// grouping provided organizes the set of stops by direction of travel for the route. Finally,
/// this method also returns a set of polylines that can be used to draw the path traveled by the route.
public class StopsForRoute: NSObject, Decodable {
    let routeID: String
    public let route: Route

    public let polylines: [String]

    let stopIDs: [String]
    public let stops: [Stop]

    public let stopGroupings: [StopGrouping]

    private enum CodingKeys: String, CodingKey {
        case routeID = "routeId"
        case polylines
        case stopIDs = "stopIds"
        case stopGroupings
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = decoder.references

        routeID = try container.decode(String.self, forKey: .routeID)
        route = references.routeWithID(routeID)!

        let rawPolylines = try container.decode([PolylineEntity].self, forKey: .polylines)
        polylines = rawPolylines.compactMap { $0.points }

        stopIDs = try container.decode([String].self, forKey: .stopIDs)
        stops = references.stopsWithIDs(stopIDs)

        stopGroupings = try container.decode([StopGrouping].self, forKey: .stopGroupings)
    }
}

public class StopGrouping: NSObject, Decodable {
    public let ordered: Bool
    public let groupingType: String
    public let stopGroups: [StopGroup]

    private enum CodingKeys: String, CodingKey {
        case ordered
        case groupingType = "type"
        case stopGroups
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ordered = try container.decode(Bool.self, forKey: .ordered)
        groupingType = try container.decode(String.self, forKey: .groupingType)
        stopGroups = try container.decode([StopGroup].self, forKey: .stopGroups)
    }
}

public class StopGroup: NSObject, Decodable {
    public let id: String
    public let name: String
    public let groupingType: String
    public let polylines: [String]

    let stopIDs: [String]
    public let stops: [Stop]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case groupingType = "type"
        case polylines
        case stopIDs = "stopIds"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = decoder.references

        id = try container.decode(String.self, forKey: .id)

        let nameContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .name)
        name = try nameContainer.decode(String.self, forKey: .name)
        groupingType = try nameContainer.decode(String.self, forKey: .groupingType)

        let polylineEntities = try container.decode([PolylineEntity].self, forKey: .polylines)
        polylines = polylineEntities.compactMap { $0.points }

        stopIDs = try container.decode([String].self, forKey: .stopIDs)
        stops = references.stopsWithIDs(stopIDs)
    }
}

public class PolylineEntity: NSObject, Decodable {
    public let points: String

    private enum CodingKeys: String, CodingKey {
        case points
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decode(String.self, forKey: .points)
    }
}
