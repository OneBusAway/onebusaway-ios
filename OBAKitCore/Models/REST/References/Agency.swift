//
//  Agency.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public class Agency: NSObject, Identifiable, Codable {
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

    private enum CodingKeys: String, CodingKey {
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

    public required init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(disclaimer, forKey: .disclaimer)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(fareURL?.absoluteString, forKey: .fareURL)
        try container.encode(id, forKey: .id)
        try container.encode(language, forKey: .language)
        try container.encode(name, forKey: .name)
        try container.encode(phone, forKey: .phone)
        try container.encode(isPrivateService, forKey: .isPrivateService)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(agencyURL, forKey: .agencyURL)
    }

    public override var debugDescription: String {
        var descriptionBuilder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        descriptionBuilder.add(key: "name", value: name)
        descriptionBuilder.add(key: "id", value: id)
        return descriptionBuilder.description
    }
}
