//
//  Route.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import UIKit

public typealias RouteID = String

public enum RouteType: Int, Codable {
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

public class Route: NSObject, Codable, HasReferences {

    let agencyID: String
    public var agency: Agency!

    public let color: UIColor?
    public let routeDescription: String?
    public let id: RouteID
    public let longName: String?
    public let shortName: String
    public let textColor: UIColor?
    public let routeType: RouteType
    public let routeURL: URL?

    private enum CodingKeys: String, CodingKey {
        case agency
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

        // If we are decoding a Route that has been serialized internally (e.g. as
        // part of a Recent Stops list), then it should contain an agency.
        // However, if we are decoding data from the REST API, then it will not
        // have routes at this time. Instead, the agency will be loaded via the
        // `loadReferences()` method call, which is part of the HasReferences protocol.
        agency = try? container.decode(Agency.self, forKey: .agency)

        color = UIColor(hex: ModelHelpers.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .color)))

        routeDescription = ModelHelpers.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .routeDescription))
        id = try container.decode(RouteID.self, forKey: .id)
        longName = ModelHelpers.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .longName))
        shortName = try container.decode(String.self, forKey: .shortName)
        textColor = UIColor(hex: ModelHelpers.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .textColor)))
        routeType = try container.decode(RouteType.self, forKey: .routeType)
        routeURL = try? container.decodeIfPresent(URL.self, forKey: .routeURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agencyID, forKey: .agencyID)
        try container.encode(agency, forKey: .agency)
        try container.encodeIfPresent(color?.toHex, forKey: .color)
        try container.encodeIfPresent(routeDescription, forKey: .routeDescription)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(longName, forKey: .longName)
        try container.encode(shortName, forKey: .shortName)
        try container.encodeIfPresent(textColor?.toHex, forKey: .textColor)
        try container.encode(routeType, forKey: .routeType)
        try container.encodeIfPresent(routeURL, forKey: .routeURL)
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References) {
        agency = references.agencyWithID(agencyID)
    }

    // MARK: - CustomDebugStringConvertible

    public override var debugDescription: String {
        return String(format: "%@({id: %@, name: %@})", super.debugDescription, id, shortName)
    }

    // MARK: - Equatable and Hashable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Route else {
            return false
        }

        return
            agencyID == rhs.agencyID &&
            color == rhs.color &&
            routeDescription == rhs.routeDescription &&
            id == rhs.id &&
            longName == rhs.longName &&
            shortName == rhs.shortName &&
            textColor == rhs.textColor &&
            routeType == rhs.routeType &&
            routeURL == rhs.routeURL
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(agencyID)
        hasher.combine(color)
        hasher.combine(routeDescription)
        hasher.combine(id)
        hasher.combine(longName)
        hasher.combine(shortName)
        hasher.combine(textColor)
        hasher.combine(routeType)
        hasher.combine(routeURL)
        return hasher.finalize()
    }
}
