//
//  OnDemandLocationGroup.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A named set of stops an on-demand rule can start or end at (wiki §2.4).
/// Members also appear in `references.stops`.
public struct OnDemandLocationGroup: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String?
    public let stopIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name
        case stopIDs = "stopIds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .name))
        stopIDs = try container.decodeIfPresent([String].self, forKey: .stopIDs) ?? []
    }
}
