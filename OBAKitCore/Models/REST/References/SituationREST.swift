//
//  SituationREST.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB
import MetaCodable

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

@Codable
struct AffectedEntityREST {
    @CodedAt("agencyId") @CodedBy(String.NillifyEmptyString())
    public let agencyID: Agency.ID?

    @CodedAt("applicationId") @CodedBy(String.NillifyEmptyString())
    public let applicationID: String?

    @CodedAt("directionId") @CodedBy(String.NillifyEmptyString())
    public let directionID: String?

    @CodedAt("routeId") @CodedBy(String.NillifyEmptyString())
    public let routeID: RouteID?

    @CodedAt("stopId") @CodedBy(String.NillifyEmptyString())
    public let stopID: StopID?

    @CodedAt("tripId") @CodedBy(String.NillifyEmptyString())
    public let tripID: TripIdentifier?
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
