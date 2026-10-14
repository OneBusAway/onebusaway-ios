//
//  OnDemandEligibility.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The reserved `eligibility` object (wiki §4), absent from v1 servers. A
/// missing object means "no eligibility information published", never "open
/// to all"; the UI shows nothing for absent or `unknown`.
public struct OnDemandEligibility: Decodable, Hashable, Sendable {
    public enum Requirement: String, Decodable, Sendable {
        case open
        case certificationRequired
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Requirement(rawValue: raw) ?? .unknown
        }
    }

    public let requirement: Requirement
    public let infoURL: URL?

    private enum CodingKeys: String, CodingKey {
        case requirement
        case infoURL = "infoUrl"
    }

    public init(requirement: Requirement, infoURL: URL?) {
        self.requirement = requirement
        self.infoURL = infoURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requirement = try container.decodeIfPresent(Requirement.self, forKey: .requirement) ?? .unknown
        infoURL = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .infoURL)).flatMap(URL.init(string:))
    }
}
