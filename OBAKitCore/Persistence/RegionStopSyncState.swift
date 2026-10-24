//
//  RegionStopSyncState.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import GRDB

/// What happened the last time a region's stops were synced from
/// `stops-for-agency` (#1555). One row per region.
public struct RegionStopSyncState: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "regionStopSync"

    public enum Outcome: String, Codable, Sendable {
        /// Every agency's stops were written, and stops the server no longer
        /// lists were deleted.
        case complete

        /// Some agencies failed. What arrived was written; nothing was deleted.
        case partial

        /// Nothing usable arrived: agencies-with-coverage failed, or the first
        /// agency failed without proving the endpoint is missing.
        case failed

        /// The first agency's answer was an HTML page: the server lacks the endpoint.
        case unsupported

        /// A maglev server with more than one agency. maglev lists a stop shared
        /// by two agencies twice, under two IDs, so the map would show both.
        case skippedMultiAgency
    }

    public let regionId: Int
    public let outcome: Outcome
    public let lastAttemptAt: Date

    /// When a sync last completed, or a conditional request last confirmed
    /// nothing changed. Nil until the first complete sync.
    public let lastSuccessAt: Date?

    /// maglev's feed fingerprint from the last complete sync, sent back as
    /// `If-None-Match`. Always nil for Java servers, whose ETag changes on
    /// every response.
    public let etag: String?

    /// The app version that recorded this, so an update re-probes a server
    /// recorded as unsupported.
    public let appVersion: String

    // Seconds since 1970, like `cachedStop.lastUpdated`, rather than GRDB's
    // millisecond date strings.
    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSince1970
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSince1970
    }

    public init(regionId: Int, outcome: Outcome, lastAttemptAt: Date, lastSuccessAt: Date?, etag: String?, appVersion: String) {
        self.regionId = regionId
        self.outcome = outcome
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.etag = etag
        self.appVersion = appVersion
    }
}
