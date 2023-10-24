//
//  SituationREST.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB

struct SituationREST: Decodable, Identifiable {
    typealias ID = String
    let id: ID                              /* PRIMARY KEY: Text */
    let creationTime: Date                  /* Datetime */
    let description: TranslatedString?      /* JSON Text */
    let reason: String                      /* Text */
    let severity: String                    /* Text */
    let summary: TranslatedString?          /* JSON Text */
    let url: TranslatedString?              /* JSON Text */

    let allAffects: [AffectedEntityREST]    /* hasMany() */
    let consequences: [Consequence]         /* JSON Text */

    let activeWindows: [TimeWindow]         /* hasMany(ActiveWindow.self) */
    let publicationWindows: [TimeWindow]    /* hasMany(PublicationWindow.self) */
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
public struct TimeWindow: Decodable {
    public let from: Date
    public let to: Date

    enum CodingKeys: String, CodingKey {
        case from, to
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .from)))
        to = Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self, forKey: .to)))
    }
}
