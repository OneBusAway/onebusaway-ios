//
//  ServiceKind.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// How an on-demand service is shaped (wiki §2.3). Classified by the server at
/// import; clients never infer it from `rules`.
public enum ServiceKind: String, Decodable, Sendable {
    case zone
    case zoneToZone
    case stopGroup
    case deviatedRoute
    /// Any value this build doesn't know — a newer server, or the wiki's own
    /// reserved fallback.
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ServiceKind(rawValue: raw) ?? .unknown
    }
}

/// Why `services-for-location` matched a service (wiki §3.4). Present only on
/// that endpoint's list elements.
public enum MatchReason: String, Decodable, Sendable {
    case areaContainsPoint
    case stopWithinRadius
    case areaNearby
    case areaIntersectsViewport
    case stopWithinViewport
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MatchReason(rawValue: raw) ?? .unknown
    }
}
