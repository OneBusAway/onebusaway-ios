//
//  StopCacheFreshnessPolicy.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Usability of a region's stop data at a particular point in time.
public enum StopCacheFreshness: String, Equatable, Sendable {
    case fresh
    case stale
    case expired
}

/// Shared cache-age policy. It is based on the last successful region sync,
/// not individual map rows, so viewport activity cannot make old data fresh.
public enum StopCacheFreshnessPolicy {
    /// A cache newer than this can be used without a refresh.
    public static let freshInterval: TimeInterval = 7 * 86_400

    /// A cache older than this is no longer usable offline.
    public static let expirationInterval: TimeInterval = 30 * 86_400

    /// Classifies a cache from its last successful region-sync timestamp.
    /// Exactly seven days is stale; exactly thirty days is still stale.
    public static func classify(lastSuccessfulSyncAt: Date?, now: Date) -> StopCacheFreshness {
        guard let lastSuccessfulSyncAt else { return .expired }

        let age = now.timeIntervalSince(lastSuccessfulSyncAt)
        if age < freshInterval {
            return .fresh
        }
        if age <= expirationInterval {
            return .stale
        }
        return .expired
    }
}
