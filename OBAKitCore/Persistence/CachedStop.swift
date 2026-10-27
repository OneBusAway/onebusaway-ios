//
//  CachedStop.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import GRDB

/// A lightweight database record representing a cached transit stop.
///
/// Instead of duplicating every Stop field as individual columns (which is fragile
/// if Stop.CodingKeys change), we store the full JSON-encoded Stop as a blob.
/// Only the fields needed for spatial queries and cache management are kept as
/// indexed columns: `id`, `regionId`, `latitude`, `longitude`, `lastUpdated`,
/// plus `name` and `code` so lookups by either needn't decode the blob.
///
/// The blob leaves out `routes`: `CachedRoute` stores each route once per region,
/// and `StopCacheRepository` attaches them when it reads stops back (#1555).
/// Rows written before schema v3 still embed their routes and still decode.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/62
struct CachedStop: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cachedStop"

    let id: String
    let regionId: Int
    let latitude: Double
    let longitude: Double
    let lastUpdated: Double
    let stopData: Data

    /// Nil on rows written before schema v3, until the stop is saved again.
    let name: String?
    let code: String?

    /// Creates a cache record from an API `Stop` model.
    /// Returns `nil` if the stop cannot be encoded, ensuring we never persist corrupted data.
    /// - Parameter lastUpdated: When the stop was written. A region sync stamps
    ///   every row with the time it started, so a complete sync can find the rows
    ///   it didn't touch.
    init?(stop: Stop, regionId: Int, lastUpdated: Date = Date()) {
        let encoder = JSONEncoder()
        encoder.userInfo[Stop.omitsRoutesUserInfoKey] = true
        do {
            self.stopData = try encoder.encode(stop)
        } catch {
            Logger.error("Failed to encode stop \(stop.id) for caching: \(error)")
            return nil
        }

        self.id = stop.id
        self.regionId = regionId
        self.latitude = stop.location.coordinate.latitude
        self.longitude = stop.location.coordinate.longitude
        self.lastUpdated = lastUpdated.timeIntervalSince1970
        self.name = stop.name
        self.code = stop.code
    }

    /// Reconstructs an API `Stop` by decoding the stored JSON blob.
    /// Uses Stop's own Codable conformance — no manual key matching required.
    ///
    /// `routes` is nil unless the row predates schema v3 and embeds them.
    /// `StopCacheRepository` fills it in from `CachedRoute`; read stops through
    /// the repository, not this.
    func toStop() -> Stop? {
        do {
            let stop = try JSONDecoder().decode(Stop.self, from: stopData)
            // Restore region context from the indexed column. The blob may have
            // been encoded before loadReferences() set regionIdentifier, and
            // Stop.isEqual() / hash use regionIdentifier for identity.
            stop.regionIdentifier = regionId
            return stop
        } catch {
            Logger.error("Failed to decode cached stop \(id): \(error)")
            return nil
        }
    }
}
