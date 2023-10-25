//
//  Situation.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable

public typealias ServiceAlert = Situation

/// An alert about transit service that affects one or more of the following:  `Agency`,  `Route`, `Stop`, or `Trip`.
@Codable
public struct Situation: Identifiable, Hashable {
    public let id: String
    public let creationTime: Date
    public let description: TranslatedString?
    public let reason: String
    public let severity: String
    public let summary: TranslatedString?
    public let url: TranslatedString?
    public let consequences: [Consequence]
}

@Codable
public struct TranslatedString: Hashable {
    public let lang: String
    public let value: String
}

@Codable
public struct Consequence: Hashable {
    @Codable
    public struct Details: Hashable {
        @CodedAt("diversionPath", "points")
        public let diversionPath: String

        @CodedAt("diversionStopIds")
        public let stopIDs: [String]
    }

    public let condition: String
    public let conditionDetails: Details?
}
