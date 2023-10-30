//
//  SituationREST.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB

/// Model for decoding Situation objects in the format of the REST API.
/// To insert a Situation into an SQLite database, use ``SituationREST.insert(into:)`` helper, which
/// creates a ``Situation`` struct and creates the necessary relationships.
///
/// In general, ``SituationREST`` is only for decoding from the OBA API. Use ``Situation`` for all other cases.
struct SituationREST: Decodable, Identifiable {
    // SituationREST is a separate data model from Situation because
    // some relationships are better represented as relation tables 
    // in the database for a nicer SQLite querying experience.
    //
    // Rather than having one "super" model that augment certain properties,
    // SituationREST is very clearly marked for only decoding REST responses.
    typealias ID = String

    let id: ID                              /* PRIMARY KEY: Text */
    let creationTime: Date                  /* Datetime */
    let description: TranslatedString?      /* JSON Text */
    let reason: String                      /* Text */
    let severity: String                    /* Text */
    let summary: TranslatedString?          /* JSON Text */
    let url: TranslatedString?              /* JSON Text */

    let allAffects: [AffectedEntityREST]    /* hasMany(AffectedSituationRelation) */
    let consequences: [Consequence]         /* JSON Text */

    let activeWindows: [TimeWindow]         /* hasMany(ActiveWindow) */
    let publicationWindows: [TimeWindow]    /* hasMany(PublicationWindow) */
}

struct AffectedEntityREST: Decodable {
    public let agencyID: Agency.ID?
    public let applicationID: String?
    public let directionID: String?
    public let routeID: RouteID?
    public let stopID: StopID?
    public let tripID: TripIdentifier?

    enum CodingKeys: String, CodingKey {
        case agencyID = "agencyId"
        case applicationID = "applicationId"
        case directionID = "directionId"
        case routeID = "routeId"
        case stopID = "stopId"
        case tripID = "tripId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        agencyID = String.nilifyBlankValue((try container.decode(String.self, forKey: .agencyID)))
        applicationID = String.nilifyBlankValue((try container.decode(String.self, forKey: .applicationID)))
        directionID = String.nilifyBlankValue((try container.decode(String.self, forKey: .directionID)))
        routeID = String.nilifyBlankValue((try container.decode(String.self, forKey: .routeID)))
        stopID = String.nilifyBlankValue((try container.decode(String.self, forKey: .stopID)))
        tripID = String.nilifyBlankValue((try container.decode(String.self, forKey: .tripID)))
    }
}

/// The range of `Date`s in which a `ServiceAlert` is in effect.
public struct TimeWindow: Decodable, Comparable, Hashable {
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

    // TimeWindow uses secondsSince1970 instead of milliseconds.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .from)))
        to = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .to)))
    }

    public static func < (lhs: TimeWindow, rhs: TimeWindow) -> Bool {
        return lhs.interval < rhs.interval
    }
}
