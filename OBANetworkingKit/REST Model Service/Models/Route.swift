//
//  Route.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBARouteType)
public enum RouteType: Int, Decodable {
    /// Tram, Streetcar, Light rail. Any light rail or street level system within a metropolitan area.
    case lightRail = 0

    /// Subway, Metro. Any underground rail system within a metropolitan area.
    case subway = 1

    ///  Rail. Used for intercity or long-distance travel.
    case rail = 2

    /// Bus. Used for short- and long-distance bus routes.
    case bus = 3

    /// Ferry. Used for short- and long-distance boat service.
    case ferry = 4

    /// Cable car. Used for street-level cable cars where the cable runs beneath the car.
    case cableCar = 5

    /// Gondola, Suspended cable car. Typically used for aerial cable cars where the car is suspended from the cable.
    case gondola = 6

    /// Funicular. Any rail system designed for steep inclines.
    case funicular = 7

    /// An unknown route type. Shouldn't ever happen.
    case unknown = 999

    public init(from decoder: Decoder) throws {
        let val = try decoder.singleValueContainer().decode(Int.self)
        self = RouteType(rawValue: val) ?? .unknown
    }
}

public class Route: NSObject, Decodable {
    let agencyID: String
    let color: String
    let routeDescription: String
    let id: String
    let longName: String
    let shortName: String
    let textColor: String
    let routeType: RouteType
    let routeURL: URL

    private enum CodingKeys: String, CodingKey {
        case agencyID = "agencyId"
        case color
        case routeDescription = "description"
        case id
        case longName
        case shortName
        case textColor
        case routeType = "type"
        case routeURL = "url"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        agencyID = try container.decode(String.self, forKey: .agencyID)
        color = try container.decode(String.self, forKey: .color)
        routeDescription = try container.decode(String.self, forKey: .routeDescription)
        id = try container.decode(String.self, forKey: .id)
        longName = try container.decode(String.self, forKey: .longName)
        shortName = try container.decode(String.self, forKey: .shortName)
        textColor = try container.decode(String.self, forKey: .textColor)
        routeType = try container.decode(RouteType.self, forKey: .routeType)
        routeURL = try container.decode(URL.self, forKey: .routeURL)
    }
}
