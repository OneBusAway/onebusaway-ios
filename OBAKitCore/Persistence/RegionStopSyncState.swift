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
struct RegionStopSyncState: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "regionStopSync"

    enum Outcome: String, Codable, Sendable {
        /// Every agency's stops were written, and stops the server no longer
        /// lists were deleted.
        case complete

        /// Some agencies failed. What arrived was written; nothing was deleted.
        case partial

        /// Nothing usable arrived: agencies-with-coverage failed or listed no
        /// agencies, every agency failed, or Low Data Mode refused the download.
        case failed

        /// The first agency's answer was an HTML page: the server lacks the endpoint.
        case unsupported

        /// A maglev server with more than one agency. maglev lists a stop shared
        /// by two agencies twice, under two IDs, so the map would show both.
        case skippedMultiAgency
    }

    let regionId: Int
    let outcome: Outcome
    let lastAttemptAt: Date

    /// When a full sync last completed. A 304 doesn't move it: the rows keep
    /// that sync's stamp, and a full sync must restamp them every week, well
    /// before the 30-day purge would remove them. Nil until the first one.
    let lastSuccessAt: Date?

    /// maglev's feed fingerprint from the last complete sync, sent back as
    /// `If-None-Match`. Always nil for Java servers, whose ETag changes on
    /// every response.
    let etag: String?

    /// The app version that recorded this, so an update re-probes a server
    /// recorded as unsupported.
    let appVersion: String

    // Seconds since 1970, like `cachedStop.lastUpdated`, rather than GRDB's
    // millisecond date strings.
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSince1970
    }

    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSince1970
    }
}
