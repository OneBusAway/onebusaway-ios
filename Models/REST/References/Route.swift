//
//  Route.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import UIKit

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

@objc(OBARoute)
public class Route: NSObject, Decodable, HasReferences {
    let agencyID: String
    
    @objc public var agency: Agency!

    @objc public let color: UIColor?
    @objc public let routeDescription: String?
    @objc public let id: String
    @objc public let longName: String?
    @objc public let shortName: String
    @objc public let textColor: UIColor?
    @objc public let routeType: RouteType
    @objc public let routeURL: URL?

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
        color = Route.hexToColor(ModelHelpers.nilifyBlankValue(try container.decode(String.self, forKey: .color)))
        routeDescription = ModelHelpers.nilifyBlankValue(try container.decode(String.self, forKey: .routeDescription))
        id = try container.decode(String.self, forKey: .id)
        longName = ModelHelpers.nilifyBlankValue(try container.decode(String.self, forKey: .longName))
        shortName = try container.decode(String.self, forKey: .shortName)
        textColor = Route.hexToColor(ModelHelpers.nilifyBlankValue(try container.decode(String.self, forKey: .textColor)))
        routeType = try container.decode(RouteType.self, forKey: .routeType)
        routeURL = try? container.decode(URL.self, forKey: .routeURL)
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References) {
        agency = references.agencyWithID(agencyID)
    }

    // MARK: - Color Conversion

    // Adapted from https://cocoacasts.com/from-hex-to-uicolor-and-back-in-swift
    private class func hexToColor(_ hex: String?) -> UIColor? {
        guard let hex = hex else {
            return nil
        }

        let hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var rgb: UInt32 = 0

        guard
            hexSanitized.count == 6 || hexSanitized.count == 8,
            Scanner(string: hexSanitized).scanHexInt32(&rgb)
        else {
            return nil
        }

        let r, g, b, a: CGFloat

        if hexSanitized.count == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        }
        else {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        }

        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
