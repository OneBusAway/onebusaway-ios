//
//  Agency.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// - SeeAlso: [OneBusAway Agency documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/elements/agency.html)
public struct Agency: Identifiable, Codable, Hashable {
    public let disclaimer: String?
    public let email: String?
    public let fareURL: URL?
    public let id: String
    public let language: String
    public let name: String
    public let phone: String
    public let isPrivateService: Bool
    public let timeZone: String
    public let agencyURL: URL

    internal enum CodingKeys: String, CodingKey {
        case disclaimer
        case email
        case fareURL = "fareUrl"
        case id
        case language = "lang"
        case name
        case phone
        case isPrivateService = "privateService"
        case timeZone = "timezone"
        case agencyURL = "url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        disclaimer = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .disclaimer))
        email = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .email))
        fareURL = try container.decodeGarbageURL(forKey: .fareURL)

        id = try container.decode(String.self, forKey: .id)
        language = try container.decode(String.self, forKey: .language)
        name = try container.decode(String.self, forKey: .name)
        phone = try container.decode(String.self, forKey: .phone)
        isPrivateService = try container.decode(Bool.self, forKey: .isPrivateService)
        timeZone = try container.decode(String.self, forKey: .timeZone)
        agencyURL = try container.decode(URL.self, forKey: .agencyURL)
    }
}
