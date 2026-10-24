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
public final class StopCacheRepository: Sendable {

    private let database: StopCacheDatabase

    public init(database: StopCacheDatabase) {
        self.database = database
    }

    // MARK: - Read

    /// Fetches cached stops within the given coordinate bounds for a specific region.
    /// Uses a bounding-box query on lat/lon columns as described in the issue requirements.
    ///
    /// - Parameter limit: Returns at most this many stops, nearest the box's
    ///   centre first. With a whole region synced (#1555) a map-sized box can
    ///   hold hundreds of stops, and every one returned is decoded.
    public func stopsInRegion(
        minLat: Double,
        maxLat: Double,
        minLon: Double,
        maxLon: Double,
        regionId: Int,
        limit: Int? = nil
    ) -> [Stop] {
        do {
            let cachedStops = try database.dbQueue.read { db in
                var request = CachedStop
                    .filter(CachedStop.Columns.regionId == regionId)
                    .filter(CachedStop.Columns.latitude >= minLat)
                    .filter(CachedStop.Columns.latitude <= maxLat)
                    .filter(CachedStop.Columns.longitude >= minLon)
                    .filter(CachedStop.Columns.longitude <= maxLon)
                if let limit {
                    // Squared distance in degrees, with longitude scaled to a degree
                    // of latitude at the centre: plenty to rank stops a few km apart.
                    let centerLat = (minLat + maxLat) / 2
                    let centerLon = (minLon + maxLon) / 2
                    let scale = cos(centerLat * .pi / 180)
                    let dLat = CachedStop.Columns.latitude - centerLat
                    let dLon = (CachedStop.Columns.longitude - centerLon) * scale
                    request = request.order(dLat * dLat + dLon * dLon).limit(limit)
                }
                return try request.fetchAll(db)
            }
            return try stops(from: cachedStops, regionId: regionId)
        } catch {
            Logger.error("Failed to fetch cached stops in region \(regionId): \(error)")
            return []
        }
    }

    /// Decodes `cachedStops` and gives each stop its routes from `cachedRoute`,
    /// in a second short read so neither holds the shared queue for long.
    /// Every returned stop has non-nil `routes`.
    private func stops(from cachedStops: [CachedStop], regionId: Int) throws -> [Stop] {
        let stops = cachedStops.compactMap { $0.toStop() }
        let failedCount = cachedStops.count - stops.count
        if failedCount > 0 {
            Logger.warn("Failed to decode \(failedCount) of \(cachedStops.count) cached stops in region \(regionId)")
        }

        // Rows from before schema v3 embed their routes; only the rest need a lookup.
        let needingRoutes = stops.filter { $0.routes == nil }
        let routeIDs = Array(Set(needingRoutes.flatMap(\.routeIDs)))
        guard !routeIDs.isEmpty else {
            needingRoutes.forEach { $0.routes = [] }
            return stops
        }

        let cachedRoutes = try database.dbQueue.read { db in
            try CachedRoute
                .filter(CachedRoute.Columns.regionId == regionId)
                .filter(routeIDs.contains(CachedRoute.Columns.id))
                .fetchAll(db)
        }
        var routesByID = [RouteID: Route]()
        for cachedRoute in cachedRoutes {
            routesByID[cachedRoute.id] = cachedRoute.toRoute()
        }
        let missingCount = routeIDs.count - routesByID.count
        if missingCount > 0 {
            Logger.warn("\(missingCount) of \(routeIDs.count) routes of cached stops in region \(regionId) are missing or unreadable")
        }

        // Sorted by ID, as `Stop.loadReferences` leaves them.
        for stop in needingRoutes {
            stop.routes = stop.routeIDs.compactMap { routesByID[$0] }.sorted { $0.id < $1.id }
        }
        return stops
    }

    // MARK: - Write

    /// Saves an array of stops into the cache, upserting on the composite key (regionId, id).
    /// Stops that fail to encode are skipped rather than persisting corrupted data.
    /// All writes happen in a single transaction for atomicity.
    public func saveStops(_ stops: [Stop], regionId: Int) {
        do {
            try database.dbQueue.write { db in
                try write(stops, regionId: regionId, at: Date(), in: db)
            }
        } catch {
            Logger.error("Failed to save \(stops.count) stops to cache for region \(regionId): \(error)")
        }
    }

    /// Writes one batch of a region sync in a single transaction, stamping every
    /// row with `syncedAt`, the time the sync started;
    /// `deleteStops(regionId:notWrittenSince:)` relies on that stamp.
    ///
    /// Unlike `saveStops`, this throws: a sync that recorded itself complete
    /// after a failed write would then delete stops it never replaced.
    public func writeSyncedStops(_ stops: [Stop], regionId: Int, syncedAt: Date) throws {
        try database.dbQueue.write { db in
            try write(stops, regionId: regionId, at: syncedAt, in: db)
        }
    }

    /// Upserts each stop and, once per batch, each of their routes.
    private func write(_ stops: [Stop], regionId: Int, at date: Date, in db: Database) throws {
        var skippedStops = 0
        var routes = [RouteID: Route]()
        for stop in stops {
            guard let record = CachedStop(stop: stop, regionId: regionId, lastUpdated: date) else {
                skippedStops += 1
                continue
            }
            try record.save(db)
            for route in stop.routes ?? [] {
                routes[route.id] = route
            }
        }

        var skippedRoutes = 0
        for route in routes.values {
            guard let record = CachedRoute(route: route, regionId: regionId, lastUpdated: date) else {
                skippedRoutes += 1
                continue
            }
            try record.save(db)
        }

        if skippedStops > 0 || skippedRoutes > 0 {
            Logger.warn("Skipped \(skippedStops) of \(stops.count) stops and \(skippedRoutes) of \(routes.count) routes during cache save for region \(regionId) due to encoding failures")
        }
    }

    // MARK: - Delete

    /// Deletes cached stops and routes older than the given date for a specific region.
    /// A stop's routes are rewritten whenever the stop is, so no fresh stop loses its routes.
    public func deleteStopsOlderThan(_ date: Date, regionId: Int) {
        do {
            try deleteRows(regionId: regionId, olderThan: date)
        } catch {
            Logger.error("Failed to purge stale stops for region \(regionId): \(error)")
        }
    }

    /// After a complete sync, deletes the region's stops and routes the sync
    /// didn't write: those the server no longer lists. Stops the map saved
    /// during the sync are newer than `syncStart`, so they stay.
    public func deleteStops(regionId: Int, notWrittenSince syncStart: Date) throws {
        try deleteRows(regionId: regionId, olderThan: syncStart)
    }

    private func deleteRows(regionId: Int, olderThan date: Date) throws {
        let timestamp = date.timeIntervalSince1970
        try database.dbQueue.write { db in
            _ = try CachedStop
                .filter(CachedStop.Columns.regionId == regionId)
                .filter(CachedStop.Columns.lastUpdated < timestamp)
                .deleteAll(db)
            _ = try CachedRoute
                .filter(CachedRoute.Columns.regionId == regionId)
                .filter(CachedRoute.Columns.lastUpdated < timestamp)
                .deleteAll(db)
        }
    }

    /// Deletes all cached stops and routes for a specific region, and forgets its
    /// sync, so the next sync starts over instead of trusting an emptied cache.
    public func clearCache(regionId: Int) {
        do {
            try database.dbQueue.write { db in
                _ = try CachedStop
                    .filter(CachedStop.Columns.regionId == regionId)
                    .deleteAll(db)
                _ = try CachedRoute
                    .filter(CachedRoute.Columns.regionId == regionId)
                    .deleteAll(db)
                _ = try RegionStopSyncState.deleteOne(db, key: regionId)
            }
        } catch {
            Logger.error("Failed to clear cache for region \(regionId): \(error)")
        }
    }

    // MARK: - Region Sync State

    /// What the last sync of `regionId` did, or nil if it was never synced.
    public func syncState(regionId: Int) throws -> RegionStopSyncState? {
        try database.dbQueue.read { db in
            try RegionStopSyncState.fetchOne(db, key: regionId)
        }
    }

    public func saveSyncState(_ state: RegionStopSyncState) throws {
        try database.dbQueue.write { db in
            try state.save(db)
        }
    }
}

// MARK: - Column Definitions

extension CachedStop {
    enum Columns {
        static let id = Column("id")
        static let regionId = Column("regionId")
        static let latitude = Column("latitude")
        static let longitude = Column("longitude")
        static let lastUpdated = Column("lastUpdated")
    }
}

extension CachedRoute {
    enum Columns {
        static let id = Column("id")
        static let regionId = Column("regionId")
        static let lastUpdated = Column("lastUpdated")
    }
}
