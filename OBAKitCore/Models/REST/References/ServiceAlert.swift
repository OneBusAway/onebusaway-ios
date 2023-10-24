//
//  ServiceAlert.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable

// swiftlint:disable nesting

/// An alert about transit service that affects one or more of the following:  `Agency`,  `Route`, `Stop`, or `Trip`.
///
/// - Note: The JSON data structure from which a `ServiceAlert` is created is called a "Situation". However, the feature
///         is referred to as a "Service Alert" pretty much everywhere else, and that is why it is referred to as such here.
@Codable
public struct ServiceAlert: Identifiable, Hashable {
    public let id: String

    public let activeWindows: Set<TimeWindow>

    @CodedAt("allAffects")
    public let affectedEntities: [AffectedEntity]

//    public private(set) var affectedAgencies: Set<Agency> = []
//    public private(set) var affectedRoutes: Set<Route> = []
//    public private(set) var affectedStops: Set<Stop> = []
//    public private(set) var affectedTrips: Set<Trip> = []

    public let consequences: [Consequence]

    @CodedAt("creationTime")
    public let createdAt: Date

    @CodedAt("description")
    public let situationDescription: TranslatedString?
    public let publicationWindows: [TimeWindow]
    public let reason: String
    public let severity: String
    public let summary: TranslatedString?

    @CodedAt("url")
    public let urlString: TranslatedString?

//    public private(set) var regionIdentifier: Int?

    // MARK: - HasReferences

//    public func loadReferences(_ references: References, regionIdentifier: Int?) {
//        affectedAgencies = Set<Agency>(affectedEntities.compactMap { references.agencyWithID($0.agencyID) })
//        affectedRoutes = Set<Route>(affectedEntities.compactMap { references.routeWithID($0.routeID) })
//        affectedStops = Set<Stop>(affectedEntities.compactMap { references.stopWithID($0.stopID) })
//        affectedTrips = Set<Trip>(affectedEntities.compactMap { references.tripWithID($0.tripID) })
//        self.regionIdentifier = regionIdentifier
//    }

    // MARK: - TimeWindow

    /// The range of `Date`s in which a `ServiceAlert` is in effect.
    public struct TimeWindow: Codable, Hashable, Comparable {
        public let from: Date
        public let to: Date

        public var interval: DateInterval {
            // Sometimes, `to` is equal to 1970, which will mess this up.
            if to < from {
                return DateInterval(start: from, end: from)
            } else {
                return DateInterval(start: from, end: to)
            }
        }

        enum CodingKeys: String, CodingKey {
            case from, to
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            from = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .from)))
            to = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .to)))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(from.timeIntervalSince1970, forKey: .from)
            try container.encode(to.timeIntervalSince1970, forKey: .to)
        }

        public static func < (lhs: ServiceAlert.TimeWindow, rhs: ServiceAlert.TimeWindow) -> Bool {
            return lhs.interval < rhs.interval
        }
    }

    // MARK: - AffectedEntity

    /// Models the agency, application, direction, route, stop, and/or trip affected by a `ServiceAlert`.
    @Codable
    public struct AffectedEntity: Hashable {

        @CodedAt("agencyId")
        public let agencyID: String?

        @CodedAt("applicationId")
        public let applicationID: String?

        @CodedAt("directionId")
        public let directionID: String?

        @CodedAt("routeId")
        public let routeID: String?

        @CodedAt("stopId")
        public let stopID: StopID?

        @CodedAt("tripId")
        public let tripID: String?
    }

    /// Models the particular details of a `Consequence`, which is part of a `ServiceAlert`.
    @Codable
    public struct ConditionDetails: Hashable {

        @CodedAt("diversionPath", "points")
        public let diversionPath: String

        @CodedAt("diversionStopIds")
        public let stopIDs: [String]
    }

    /// Models the effects of a `ServiceAlert`.
    @Codable
    public struct Consequence: Hashable {
        public let condition: String
        public let conditionDetails: ServiceAlert.ConditionDetails?
    }

    /// A `ServiceAlert`'s method of describing potentially-localized information.
    @Codable
    public struct TranslatedString: Hashable {
        public let lang: String
        public let value: String
    }
}

// swiftlint:enable nesting
