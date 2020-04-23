//
//  StopsForRoute.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import MapKit

/// Retrieve the set of stops serving a particular route, including groups by direction of travel.
///
/// The stops-for-route method first and foremost provides a method for retrieving the set of stops
/// that serve a particular route. In addition to the full set of stops, we provide various
/// “stop groupings” that are used to group the stops into useful collections. Currently, the main
/// grouping provided organizes the set of stops by direction of travel for the route. Finally,
/// this method also returns a set of polylines that can be used to draw the path traveled by the route.
public class StopsForRoute: NSObject, Decodable, HasReferences {

    let routeID: String
    public private(set) var route: Route!

    public let rawPolylines: [String]
    public lazy var polylines: [MKPolyline] = rawPolylines.compactMap { Polyline(encodedPolyline: $0).mkPolyline }

    public lazy var mapRect: MKMapRect = {
        var bounds = MKMapRect.null
        for p in polylines {
            bounds = bounds.union(p.boundingMapRect)
        }
        return bounds
    }()

    let stopIDs: [String]
    public private(set) var stops: [Stop]!

    public let stopGroupings: [StopGrouping]

    private enum CodingKeys: String, CodingKey {
        case routeID = "routeId"
        case rawPolylines = "polylines"
        case stopIDs = "stopIds"
        case stopGroupings
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        routeID = try container.decode(String.self, forKey: .routeID)
        rawPolylines = try container.decode([PolylineEntity].self, forKey: .rawPolylines).compactMap { $0.points }
        stopIDs = try container.decode([String].self, forKey: .stopIDs)
        stopGroupings = try container.decode([StopGrouping].self, forKey: .stopGroupings)
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References) {
        route = references.routeWithID(routeID)!
        stops = references.stopsWithIDs(stopIDs)
        stopGroupings.loadReferences(references)
    }
}

public class StopGrouping: NSObject, Decodable, HasReferences {
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

    public func loadReferences(_ references: References) {
        stopGroups.loadReferences(references)
    }
}

public class StopGroup: NSObject, Decodable, HasReferences {
    public let id: String
    public let name: String
    public let groupingType: String
    public let polylines: [String]

    let stopIDs: [String]
    public private(set) var stops = [Stop]()

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case groupingType = "type"
        case polylines
        case stopIDs = "stopIds"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)

        let nameContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .name)
        name = try nameContainer.decode(String.self, forKey: .name)
        groupingType = try nameContainer.decode(String.self, forKey: .groupingType)

        let polylineEntities = try container.decode([PolylineEntity].self, forKey: .polylines)
        polylines = polylineEntities.compactMap { $0.points }

        stopIDs = try container.decode([String].self, forKey: .stopIDs)
    }

    public func loadReferences(_ references: References) {
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

    public lazy var polyline: MKPolyline? = {
        let p = Polyline(encodedPolyline: points)
        return p.mkPolyline
    }()
}
