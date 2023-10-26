//
//  Route.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import MetaCodable

public typealias RouteID = String

@Codable
public struct Route: Identifiable, Hashable {
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

    public let id: RouteID

    @CodedAt("agencyId")
    public let agencyID: Agency.ID
    
    @CodedAt("description")
    public let routeDescription: String?
    public let longName: String?
    public let shortName: String

    public let color: String?
    public let textColor: String?

    @CodedAt("type")
    public let routeType: Route.RouteType

    @CodedAt("url") @CodedBy(URL.DecodeGarbageURL())
    public let routeURL: URL?
}

// MARK: - [Route] Extensions

public extension Sequence where Element == Route {

    /// Performs a localized case insensitive sort on the receiver.
    ///
    /// - Returns: A localized, case-insensitive sorted Array.
    func localizedCaseInsensitiveSort() -> [Element] {
        return sorted { (s1, s2) -> Bool in
            return s1.shortName.localizedCaseInsensitiveCompare(s2.shortName) == .orderedAscending
        }
    }
}
