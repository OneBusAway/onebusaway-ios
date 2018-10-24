//
//  Situation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/23/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class Situation: NSObject, Decodable {
    let activeWindows: [TimeWindow]
    let affectedEntities: [AffectedEntity]
    let consequences: [Consequence]
    let createdAt: Date
    let situationDescription: TranslatedString
    let id: String
    let publicationWindows: [TimeWindow]
    let reason: String
    let severity: String
    let summary: TranslatedString
    let url: URL

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

        activeWindows = try container.decode([TimeWindow].self, forKey: .activeWindows)
        affectedEntities = try container.decode([AffectedEntity].self, forKey: .affectedEntities)
        consequences = try container.decode([Consequence].self, forKey: .consequences)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        situationDescription = try container.decode(TranslatedString.self, forKey: .situationDescription)
        id = try container.decode(String.self, forKey: .id)
        publicationWindows = try container.decode([TimeWindow].self, forKey: .publicationWindows)
        reason = try container.decode(String.self, forKey: .reason)
        severity = try container.decode(String.self, forKey: .severity)
        summary = try container.decode(TranslatedString.self, forKey: .summary)
        url = try container.decode(URL.self, forKey: .url)
    }
}

public class TimeWindow: NSObject, Decodable {
    let from: Int
    let to: Int

    enum CodingKeys: String, CodingKey {
        case from = "from"
        case to = "to"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(Int.self, forKey: .from)
        to = try container.decode(Int.self, forKey: .to)
    }
}

public class AffectedEntity: Codable {
    let agencyID: String
    let applicationID: String
    let directionID: String
    let routeID: String
    let stopID: String
    let tripID: String

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
        agencyID = try container.decode(String.self, forKey: .agencyID)
        applicationID = try container.decode(String.self, forKey: .applicationID)
        directionID = try container.decode(String.self, forKey: .directionID)
        routeID = try container.decode(String.self, forKey: .routeID)
        stopID = try container.decode(String.self, forKey: .stopID)
        tripID = try container.decode(String.self, forKey: .tripID)
    }
}

public class Consequence: Decodable {
    let condition: String
    let conditionDetails: ConditionDetails?

    enum CodingKeys: String, CodingKey {
        case condition = "condition"
        case conditionDetails = "conditionDetails"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        condition = try container.decode(String.self, forKey: .condition)
        conditionDetails = try container.decode(ConditionDetails.self, forKey: .conditionDetails)
    }
}

public class ConditionDetails: NSObject, Decodable {
    let diversionPath: String
    let stopIDs: [String]

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
}

public class TranslatedString: NSObject, Decodable {
    let lang: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case lang
        case value
    }

    init(lang: String, value: String) {
        self.lang = lang
        self.value = value
    }
}
