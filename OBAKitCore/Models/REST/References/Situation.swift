//
//  Situation.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public typealias ServiceAlert = Situation

/// An alert about transit service that affects one or more of the following:  `Agency`,  `Route`, `Stop`, or `Trip`.
public struct Situation: Identifiable, Codable, Hashable {
    public let id: String
    public let creationTime: Date
    public let description: TranslatedString?
    public let reason: String
    public let severity: String
    public let summary: TranslatedString?
    public let url: TranslatedString?
    public let consequences: [Consequence]
    
    internal enum CodingKeys: String, CodingKey {
        case id, creationTime, description, reason, severity, summary, url, consequences
    }
}

public struct TranslatedString: Codable, Hashable {
    public let lang: String
    public let value: String
}

public struct Consequence: Codable, Hashable {
    public struct Details: Codable, Hashable {
        enum CodingKeys: String, CodingKey {
            case diversionPath
            case diversionStopIDs = "diversionStopIds"
        }

        public let diversionPath: PolylineEntity
        public let diversionStopIDs: [String]
    }

    public let condition: String
    public let conditionDetails: Details?
}
