//
//  RegionStopSyncPolicy.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// When a region's stops are due for another sync from `stops-for-agency` (#1555).
enum RegionStopSyncPolicy {

    enum Decision: Equatable, Sendable {
        case skip
        case full

        /// Ask the first agency with `If-None-Match`. maglev's ETag covers the
        /// whole feed, so a 304 means nothing in the region changed.
        case conditional(etag: String)
    }

    /// How long a complete sync stays fresh.
    static let fullSyncInterval: TimeInterval = 7 * 86_400

    /// How often maglev's feed fingerprint is checked between full syncs.
    static let conditionalCheckInterval: TimeInterval = 86_400

    /// The wait after a failed or partial sync before trying again.
    static let retryInterval: TimeInterval = 3_600

    /// How long a server recorded as lacking the endpoint is left alone, unless
    /// the app is updated first.
    static let reprobeInterval: TimeInterval = 7 * 86_400

    static func decision(for state: RegionStopSyncState?, now: Date, appVersion: String) -> Decision {
        guard let state else { return .full }
        let sinceAttempt = now.timeIntervalSince(state.lastAttemptAt)

        switch state.outcome {
        case .complete:
            let sinceSuccess = now.timeIntervalSince(state.lastSuccessAt ?? state.lastAttemptAt)
            if sinceSuccess >= fullSyncInterval {
                return .full
            }
            if let etag = state.etag, sinceAttempt >= conditionalCheckInterval {
                return .conditional(etag: etag)
            }
            return .skip
        case .partial, .failed:
            return sinceAttempt >= retryInterval ? .full : .skip
        case .unsupported, .skippedMultiAgency:
            return state.appVersion != appVersion || sinceAttempt >= reprobeInterval ? .full : .skip
        }
    }
}
