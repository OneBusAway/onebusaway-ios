//
//  StopCacheRepository.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import GRDB

/// Provides read/write access to the cached stops database.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/62
public final class StopCacheRepository: @unchecked Sendable {

    private let database: StopCacheDatabase

    public init(database: StopCacheDatabase) {
        self.database = database
    }

    // MARK: - Read

    /// Fetches cached stops within the given coordinate bounds for a specific region.
    /// Uses a bounding-box query on lat/lon columns as described in the issue requirements.
    public func stopsInRegion(
        minLat: Double,
        maxLat: Double,
        minLon: Double,
        maxLon: Double,
        regionId: Int
    ) -> [Stop] {
        do {
            let cachedStops = try database.dbQueue.read { db in
                try CachedStop
                    .filter(CachedStop.Columns.regionId == regionId)
                    .filter(CachedStop.Columns.latitude >= minLat)
                    .filter(CachedStop.Columns.latitude <= maxLat)
                    .filter(CachedStop.Columns.longitude >= minLon)
                    .filter(CachedStop.Columns.longitude <= maxLon)
                    .fetchAll(db)
            }
            return cachedStops.compactMap { $0.toStop() }
        } catch {
            Logger.error("Failed to fetch cached stops in region \(regionId): \(error)")
            return []
        }
    }

    // MARK: - Write

    /// Saves an array of stops into the cache, upserting on the composite key (regionId, id).
    /// Stops that fail to encode are skipped rather than persisting corrupted data.
    /// All writes happen in a single transaction for atomicity.
    public func saveStops(_ stops: [Stop], regionId: Int) {
        do {
            try database.dbQueue.write { db in
                for stop in stops {
                    guard let record = CachedStop(stop: stop, regionId: regionId) else {
                        continue
                    }
                    try record.save(db)
                }
            }
        } catch {
            Logger.error("Failed to save \(stops.count) stops to cache for region \(regionId): \(error)")
        }
    }

    /// Deletes cached stops older than the given date for a specific region.
    public func deleteStopsOlderThan(_ date: Date, regionId: Int) {
        let timestamp = date.timeIntervalSince1970
        do {
            try database.dbQueue.write { db in
                _ = try CachedStop
                    .filter(CachedStop.Columns.regionId == regionId)
                    .filter(CachedStop.Columns.lastUpdated < timestamp)
                    .deleteAll(db)
            }
        } catch {
            Logger.error("Failed to purge stale stops for region \(regionId): \(error)")
        }
    }

    /// Deletes all cached stops for a specific region.
    public func clearCache(regionId: Int) {
        do {
            try database.dbQueue.write { db in
                _ = try CachedStop
                    .filter(CachedStop.Columns.regionId == regionId)
                    .deleteAll(db)
            }
        } catch {
            Logger.error("Failed to clear cache for region \(regionId): \(error)")
        }
    }
}

// MARK: - CachedStop Column Definitions

extension CachedStop {
    enum Columns {
        static let id = Column("id")
        static let regionId = Column("regionId")
        static let latitude = Column("latitude")
        static let longitude = Column("longitude")
        static let lastUpdated = Column("lastUpdated")
    }
}
