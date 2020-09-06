//
//  ServiceAlert.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// swiftlint:disable nesting

/// An alert about transit service that affects one or more of the following:  `Agency`,  `Route`, `Stop`, or `Trip`.
///
/// - Note: The JSON data structure from which a `ServiceAlert` is created is called a "Situation". However, the feature
///         is referred to as a "Service Alert" pretty much everywhere else, and that is why it is referred to as such here.
public class ServiceAlert: NSObject, Decodable, HasReferences {
    public let activeWindows: Set<TimeWindow>

    public let affectedEntities: [AffectedEntity]

    public private(set) var affectedAgencies: Set<Agency> = []
    public private(set) var affectedRoutes: Set<Route> = []
    public private(set) var affectedStops: Set<Stop> = []
    public private(set) var affectedTrips: Set<Trip> = []

    public let consequences: [Consequence]
    public let createdAt: Date
    public let situationDescription: TranslatedString?
    public let id: String
    public let publicationWindows: [TimeWindow]
    public let reason: String
    public let severity: String
    public let summary: TranslatedString
    public let urlString: TranslatedString?

    enum CodingKeys: String, CodingKey {
        case activeWindows
        case affectedEntities = "allAffects"
        case consequences
        case createdAt = "creationTime"
        case situationDescription = "description"
        case id
        case publicationWindows
        case reason
        case severity
        case summary
        case url
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        activeWindows = try container.decode(Set<TimeWindow>.self, forKey: .activeWindows)
        affectedEntities = try container.decode([AffectedEntity].self, forKey: .affectedEntities)
        consequences = try container.decode([Consequence].self, forKey: .consequences)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        situationDescription = try container.decodeIfPresent(TranslatedString.self, forKey: .situationDescription)
        id = try container.decode(String.self, forKey: .id)
        publicationWindows = try container.decode([TimeWindow].self, forKey: .publicationWindows)
        reason = try container.decode(String.self, forKey: .reason)
        severity = try container.decode(String.self, forKey: .severity)
        summary = try container.decode(TranslatedString.self, forKey: .summary)
        self.urlString = try container.decodeIfPresent(TranslatedString.self, forKey: .url)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? ServiceAlert else { return false }
        return
            activeWindows == rhs.activeWindows &&
            affectedEntities == rhs.affectedEntities &&
            consequences == rhs.consequences &&
            createdAt == rhs.createdAt &&
            situationDescription == rhs.situationDescription &&
            id == rhs.id &&
            publicationWindows == rhs.publicationWindows &&
            reason == rhs.reason &&
            severity == rhs.severity &&
            summary == rhs.summary &&
            urlString == rhs.urlString
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(activeWindows)
        hasher.combine(affectedEntities)
        hasher.combine(consequences)
        hasher.combine(createdAt)
        hasher.combine(situationDescription)
        hasher.combine(id)
        hasher.combine(publicationWindows)
        hasher.combine(reason)
        hasher.combine(severity)
        hasher.combine(summary)
        hasher.combine(urlString)
        return hasher.finalize()
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References) {
        affectedAgencies = Set<Agency>(affectedEntities.compactMap { references.agencyWithID($0.agencyID) })
        affectedRoutes = Set<Route>(affectedEntities.compactMap { references.routeWithID($0.routeID) })
        affectedStops = Set<Stop>(affectedEntities.compactMap { references.stopWithID($0.stopID) })
        affectedTrips = Set<Trip>(affectedEntities.compactMap { references.tripWithID($0.tripID) })
    }

    // MARK: - TimeWindow

    /// The range of `Date`s in which a `ServiceAlert` is in effect.
    public class TimeWindow: NSObject, Decodable, Comparable {
        public let from: Date
        public let to: Date

        public var interval: DateInterval {
            return DateInterval(start: from, end: to)
        }

        enum CodingKeys: String, CodingKey {
            case from, to
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            from = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .from)))
            to = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .to)))
        }

        public override func isEqual(_ object: Any?) -> Bool {
            guard let rhs = object as? TimeWindow else { return false }
            return from == rhs.from && to == rhs.to
        }

        public static func < (lhs: ServiceAlert.TimeWindow, rhs: ServiceAlert.TimeWindow) -> Bool {
            return lhs.interval < rhs.interval
        }

        override public var hash: Int {
            var hasher = Hasher()
            hasher.combine(from)
            hasher.combine(to)
            return hasher.finalize()
        }
        
    }

    // MARK: - AffectedEntity

    /// Models the agency, application, direction, route, stop, and/or trip affected by a `ServiceAlert`.
    public class AffectedEntity: NSObject, Codable {
        public let agencyID: String?
        public let applicationID: String?
        public let directionID: String?
        public let routeID: String?
        public let stopID: StopID?
        public let tripID: String?

        enum CodingKeys: String, CodingKey {
            case agencyID = "agencyId"
            case applicationID = "applicationId"
            case directionID = "directionId"
            case routeID = "routeId"
            case stopID = "stopId"
            case tripID = "tripId"
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            agencyID = String.nilifyBlankValue((try container.decode(String.self, forKey: .agencyID)))
            applicationID = String.nilifyBlankValue((try container.decode(String.self, forKey: .applicationID)))
            directionID = String.nilifyBlankValue((try container.decode(String.self, forKey: .directionID)))
            routeID = String.nilifyBlankValue((try container.decode(String.self, forKey: .routeID)))
            stopID = String.nilifyBlankValue((try container.decode(String.self, forKey: .stopID)))
            tripID = String.nilifyBlankValue((try container.decode(String.self, forKey: .tripID)))
        }

        public override func isEqual(_ object: Any?) -> Bool {
            guard let rhs = object as? AffectedEntity else { return false }
            return
                agencyID == rhs.agencyID &&
                applicationID == rhs.applicationID &&
                directionID == rhs.directionID &&
                routeID == rhs.routeID &&
                stopID == rhs.stopID &&
                tripID == rhs.tripID
        }

        override public var hash: Int {
            var hasher = Hasher()
            hasher.combine(agencyID)
            hasher.combine(applicationID)
            hasher.combine(directionID)
            hasher.combine(routeID)
            hasher.combine(stopID)
            hasher.combine(tripID)
            return hasher.finalize()
        }
    }

    // MARK: - Consequence

    /// Models the effects of a `ServiceAlert`.
    public class Consequence: NSObject, Decodable {
        public let condition: String
        public let conditionDetails: ConditionDetails?

        enum CodingKeys: String, CodingKey {
            case condition, conditionDetails
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            condition = try container.decode(String.self, forKey: .condition)
            conditionDetails = try container.decode(ConditionDetails.self, forKey: .conditionDetails)
        }

        public override func isEqual(_ object: Any?) -> Bool {
            guard let rhs = object as? Consequence else { return false }
            return condition == rhs.condition && conditionDetails == rhs.conditionDetails
        }

        override public var hash: Int {
            var hasher = Hasher()
            hasher.combine(condition)
            hasher.combine(conditionDetails)
            return hasher.finalize()
        }
    }

    // MARK: - ConditionDetails

    /// Models the particular details of a `Consequence`, which is part of a `ServiceAlert`.
    public class ConditionDetails: NSObject, Decodable {
        public let diversionPath: String
        public let stopIDs: [String]

        enum CodingKeys: String, CodingKey {
            case diversionPath
            case points
            case stopIDs = "diversionStopIds"
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let diversionPathWrapper = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .diversionPath)

            diversionPath = try diversionPathWrapper.decode(String.self, forKey: .points)
            stopIDs = try container.decode([String].self, forKey: .stopIDs)
        }

        public override func isEqual(_ object: Any?) -> Bool {
            guard let rhs = object as? ConditionDetails else { return false }
            return diversionPath == rhs.diversionPath && stopIDs == rhs.stopIDs
        }

        override public var hash: Int {
            var hasher = Hasher()
            hasher.combine(diversionPath)
            hasher.combine(stopIDs)
            return hasher.finalize()
        }
    }

    // MARK: - TranslatedString

    /// A `ServiceAlert`'s method of describing potentially-localized information.
    public class TranslatedString: NSObject, Decodable {
        public let lang: String
        public let value: String

        enum CodingKeys: String, CodingKey {
            case lang, value
        }

        init(lang: String, value: String) {
            self.lang = lang
            self.value = value
        }

        public override func isEqual(_ object: Any?) -> Bool {
            guard let rhs = object as? TranslatedString else { return false }
            return lang == rhs.lang && value == rhs.value
        }

        override public var hash: Int {
            var hasher = Hasher()
            hasher.combine(lang)
            hasher.combine(value)
            return hasher.finalize()
        }
    }
}
