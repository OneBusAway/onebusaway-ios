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
/// indexed columns: `id`, `regionId`, `latitude`, `longitude`, `lastUpdated`.
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

    /// Creates a cache record from an API `Stop` model.
    /// Returns `nil` if the stop cannot be encoded, ensuring we never persist corrupted data.
    init?(stop: Stop, regionId: Int) {
        do {
            self.stopData = try JSONEncoder().encode(stop)
        } catch {
            Logger.error("Failed to encode stop \(stop.id) for caching: \(error)")
            return nil
        }

        self.id = stop.id
        self.regionId = regionId
        self.latitude = stop.location.coordinate.latitude
        self.longitude = stop.location.coordinate.longitude
        self.lastUpdated = Date().timeIntervalSince1970
    }

    /// Reconstructs an API `Stop` by decoding the stored JSON blob.
    /// Uses Stop's own Codable conformance — no manual key matching required.
    func toStop() -> Stop? {
        do {
            let stop = try JSONDecoder().decode(Stop.self, from: stopData)
            // Ensure routes is never nil to prevent force-unwrap crashes.
            // In production, API stops have routes populated via loadReferences()
            // before caching. But as a safety net (e.g., if a stop was cached before
            // loadReferences ran), we default to an empty array.
            if stop.routes == nil {
                stop.routes = []
            }
            return stop
        } catch {
            Logger.error("Failed to decode cached stop \(id): \(error)")
            return nil
        }
    }
}
