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

    // MARK: - Freshness

    /// Classifies a region from its last successful sync. Unsynced
    /// caches are expired so callers have one deterministic answer before
    /// deciding whether offline data may be used.
    public func cacheFreshness(regionId: Int, now: Date = Date()) -> StopCacheFreshness {
        do {
            return StopCacheFreshnessPolicy.classify(
                lastSuccessfulSyncAt: try syncState(regionId: regionId)?.lastSuccessAt,
                now: now
            )
        } catch {
            Logger.error("Failed to read cache freshness for region \(regionId): \(error)")
            return .expired
        }
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
                try visibleStops(
                    regionId: regionId,
                    minLat: minLat,
                    maxLat: maxLat,
                    minLon: minLon,
                    maxLon: maxLon,
                    limit: limit,
                    in: db
                )
            }
            return try stops(from: cachedStops, regionId: regionId)
        } catch {
            Logger.error("Failed to fetch cached stops in region \(regionId): \(error)")
            return []
        }
    }

    /// One page of `stops(regionId:after:limit:)`.
    public struct Page: Sendable {
        /// The page's stops that decoded. A corrupted row is left out.
        public let stops: [Stop]

        /// Pass as `after` for the next page; nil when there are no more rows.
        /// It is the id of the last row read, decoded or not, so a page of
        /// corrupted rows neither ends paging early nor re-reads itself.
        public let cursor: StopID?
    }

    /// Reads a region's cached stops in id order, `limit` rows at a time.
    ///
    /// Short pages keep each hold on the shared database queue brief, so the
    /// map's reads aren't stuck behind a scan of the whole region.
    public func stops(regionId: Int, after cursor: StopID?, limit: Int) -> Page {
        do {
            let cachedStops = try database.dbQueue.read { db in
                try visibleStops(regionId: regionId, after: cursor, limit: limit, in: db)
            }
            let nextCursor = cachedStops.count == limit ? cachedStops.last?.id : nil
            return Page(stops: try stops(from: cachedStops, regionId: regionId), cursor: nextCursor)
        } catch {
            Logger.error("Failed to fetch a page of cached stops in region \(regionId): \(error)")
            return Page(stops: [], cursor: nil)
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
            try visibleRoutes(routeIDs: routeIDs, regionId: regionId, in: db)
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

    private func visibleStops(
        regionId: Int,
        minLat: Double,
        maxLat: Double,
        minLon: Double,
        maxLon: Double,
        limit: Int?,
        in db: Database
    ) throws -> [CachedStop] {
        let publishedSyncID = try RegionStopSyncState.fetchOne(db, key: regionId)?.publishedSyncID
        var main = CachedStop
            .filter(CachedStop.Columns.regionId == regionId)
            .filter(CachedStop.Columns.latitude >= minLat)
            .filter(CachedStop.Columns.latitude <= maxLat)
            .filter(CachedStop.Columns.longitude >= minLon)
            .filter(CachedStop.Columns.longitude <= maxLon)
        if let publishedSyncID {
            main = main.filter(
                sql: "NOT EXISTS (SELECT 1 FROM cachedStopSync WHERE syncID = ? AND regionId = cachedStop.regionId AND id = cachedStop.id AND lastUpdated >= cachedStop.lastUpdated)",
                arguments: [publishedSyncID]
            )
        }
        let staged = try stagedStops(
            regionId: regionId,
            syncID: publishedSyncID,
            minLat: minLat,
            maxLat: maxLat,
            minLon: minLon,
            maxLon: maxLon,
            limit: limit,
            in: db
        )
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let scale = cos(centerLat * .pi / 180)
        if let limit {
            let dLat = CachedStop.Columns.latitude - centerLat
            let dLon = (CachedStop.Columns.longitude - centerLon) * scale
            main = main.order(dLat * dLat + dLon * dLon).limit(limit)
        }

        let mainRows = try main.fetchAll(db)
        var byID = Dictionary(uniqueKeysWithValues: mainRows.map { ($0.id, $0) })
        for row in staged {
            if let existing = byID[row.id] {
                if row.lastUpdated >= existing.lastUpdated {
                    byID[row.id] = row.cachedStop
                }
            } else {
                byID[row.id] = row.cachedStop
            }
        }
        return rankByDistance(Array(byID.values), centerLat: centerLat, centerLon: centerLon, scale: scale, limit: limit)
    }

    private func rankByDistance(_ stops: [CachedStop], centerLat: Double, centerLon: Double, scale: Double, limit: Int?) -> [CachedStop] {
        let sorted = stops.sorted {
            let lhs = ($0.latitude - centerLat) * ($0.latitude - centerLat) + (($0.longitude - centerLon) * scale) * (($0.longitude - centerLon) * scale)
            let rhs = ($1.latitude - centerLat) * ($1.latitude - centerLat) + (($1.longitude - centerLon) * scale) * (($1.longitude - centerLon) * scale)
            return lhs < rhs
        }
        return limit.map { Array(sorted.prefix($0)) } ?? sorted
    }

    private func stagedStops(regionId: Int, syncID: String?, minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, limit: Int?, in db: Database) throws -> [StagedCachedStop] {
        guard let syncID else { return [] }
        var request = StagedCachedStop
            .filter(StagedCachedStop.Columns.syncID == syncID)
            .filter(StagedCachedStop.Columns.regionId == regionId)
            .filter(StagedCachedStop.Columns.latitude >= minLat)
            .filter(StagedCachedStop.Columns.latitude <= maxLat)
            .filter(StagedCachedStop.Columns.longitude >= minLon)
            .filter(StagedCachedStop.Columns.longitude <= maxLon)
        if let limit {
            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2
            let scale = cos(centerLat * .pi / 180)
            let dLat = StagedCachedStop.Columns.latitude - centerLat
            let dLon = (StagedCachedStop.Columns.longitude - centerLon) * scale
            request = request.order(dLat * dLat + dLon * dLon).limit(limit)
        }
        return try request.fetchAll(db)
    }

    private func visibleStops(regionId: Int, after cursor: StopID?, limit: Int, in db: Database) throws -> [CachedStop] {
        let publishedSyncID = try RegionStopSyncState.fetchOne(db, key: regionId)?.publishedSyncID
        var main = CachedStop.filter(CachedStop.Columns.regionId == regionId)
        if let cursor { main = main.filter(CachedStop.Columns.id > cursor) }
        if let publishedSyncID {
            main = main.filter(
                sql: "NOT EXISTS (SELECT 1 FROM cachedStopSync WHERE syncID = ? AND regionId = cachedStop.regionId AND id = cachedStop.id AND lastUpdated >= cachedStop.lastUpdated)",
                arguments: [publishedSyncID]
            )
        }
        let mainRows = try main.order(CachedStop.Columns.id).limit(limit).fetchAll(db)
        var byID = Dictionary(uniqueKeysWithValues: mainRows.map { ($0.id, $0) })
        if let publishedSyncID {
            var staged = StagedCachedStop
                .filter(StagedCachedStop.Columns.syncID == publishedSyncID)
                .filter(StagedCachedStop.Columns.regionId == regionId)
            if let cursor { staged = staged.filter(StagedCachedStop.Columns.id > cursor) }
            for row in try staged.order(StagedCachedStop.Columns.id).limit(limit).fetchAll(db) {
                if let existing = byID[row.id] {
                    if row.lastUpdated >= existing.lastUpdated {
                        byID[row.id] = row.cachedStop
                    }
                } else {
                    byID[row.id] = row.cachedStop
                }
            }
        }
        return Array(byID.values.sorted { $0.id < $1.id }.prefix(limit))
    }

    private func visibleRoutes(routeIDs: [RouteID], regionId: Int, in db: Database) throws -> [CachedRoute] {
        let publishedSyncID = try RegionStopSyncState.fetchOne(db, key: regionId)?.publishedSyncID
        var byID = Dictionary(uniqueKeysWithValues: try CachedRoute
            .filter(CachedRoute.Columns.regionId == regionId)
            .filter(routeIDs.contains(CachedRoute.Columns.id))
            .fetchAll(db)
            .map { ($0.id, $0) })
        if let publishedSyncID {
            for row in try StagedCachedRoute
                .filter(StagedCachedRoute.Columns.syncID == publishedSyncID)
                .filter(StagedCachedRoute.Columns.regionId == regionId)
                .filter(routeIDs.contains(StagedCachedRoute.Columns.id))
                .fetchAll(db) {
                if let existing = byID[row.id] {
                    if row.lastUpdated >= existing.lastUpdated {
                        byID[row.id] = row.cachedRoute
                    }
                } else {
                    byID[row.id] = row.cachedRoute
                }
            }
        }
        return Array(byID.values)
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

    /// Writes all stops in one transaction for callers that already own the
    /// complete payload. Region syncs use `stageSyncedStops` instead, so each
    /// database hold stays short and publication remains atomic.
    ///
    /// Unlike `saveStops`, this throws: a sync that recorded itself complete
    /// after a failed write would then delete stops it never replaced.
    func writeSyncedStops(_ stops: [Stop], regionId: Int, syncedAt: Date) throws {
        try database.dbQueue.write { db in
            try write(stops, regionId: regionId, at: syncedAt, in: db)
        }
    }

    /// Writes one sync batch to its private snapshot. Each call owns only one
    /// short transaction; the snapshot is invisible until its ID is published
    /// in `RegionStopSyncState`.
    func stageSyncedStops(_ stops: [Stop], regionId: Int, syncID: String, syncedAt: Date) throws {
        try database.dbQueue.write { db in
            var routes = [RouteID: Route]()
            for stop in stops {
                guard let record = CachedStop(stop: stop, regionId: regionId, lastUpdated: syncedAt) else { continue }
                try StagedCachedStop(record: record, syncID: syncID).save(db)
                for route in stop.routes ?? [] { routes[route.id] = route }
            }
            for route in routes.values {
                guard let record = CachedRoute(route: route, regionId: regionId, lastUpdated: syncedAt) else { continue }
                try StagedCachedRoute(record: record, syncID: syncID).save(db)
            }
        }
    }

    /// Removes a snapshot that never reached the publication marker.
    func discardStagedStops(regionId: Int, syncID: String) throws {
        try database.dbQueue.write { db in
            _ = try StagedCachedStop
                .filter(StagedCachedStop.Columns.regionId == regionId)
                .filter(StagedCachedStop.Columns.syncID == syncID)
                .deleteAll(db)
            _ = try StagedCachedRoute
                .filter(StagedCachedRoute.Columns.regionId == regionId)
                .filter(StagedCachedRoute.Columns.syncID == syncID)
                .deleteAll(db)
        }
    }

    /// Copies staged stops and routes from a previous snapshot into the current snapshot
    /// in bounded batches for any stops and routes not already staged in `toSyncID`.
    func carryOverStagedStops(regionId: Int, fromSyncID: String, toSyncID: String, batchSize: Int = 500) throws {
        guard fromSyncID != toSyncID else { return }
        var hasMoreStops = true
        while hasMoreStops {
            hasMoreStops = try database.dbQueue.write { db in
                let rowids = try Int64.fetchAll(
                    db,
                    sql: """
                    SELECT s.rowid FROM cachedStopSync s
                    WHERE s.syncID = ? AND s.regionId = ?
                    AND NOT EXISTS (
                        SELECT 1 FROM cachedStopSync t
                        WHERE t.syncID = ? AND t.regionId = ? AND t.id = s.id
                    )
                    LIMIT ?
                    """,
                    arguments: [fromSyncID, regionId, toSyncID, regionId, batchSize]
                )
                guard !rowids.isEmpty else { return false }
                let placeholders = rowids.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO cachedStopSync (syncID, id, regionId, latitude, longitude, lastUpdated, stopData, name, code)
                    SELECT ?, id, regionId, latitude, longitude, lastUpdated, stopData, name, code
                    FROM cachedStopSync
                    WHERE rowid IN (\(placeholders))
                    """,
                    arguments: StatementArguments([toSyncID] + rowids.map { DatabaseValue(value: $0) })
                )
                return rowids.count == batchSize
            }
        }

        var hasMoreRoutes = true
        while hasMoreRoutes {
            hasMoreRoutes = try database.dbQueue.write { db in
                let rowids = try Int64.fetchAll(
                    db,
                    sql: """
                    SELECT r.rowid FROM cachedRouteSync r
                    WHERE r.syncID = ? AND r.regionId = ?
                    AND NOT EXISTS (
                        SELECT 1 FROM cachedRouteSync t
                        WHERE t.syncID = ? AND t.regionId = ? AND t.id = r.id
                    )
                    LIMIT ?
                    """,
                    arguments: [fromSyncID, regionId, toSyncID, regionId, batchSize]
                )
                guard !rowids.isEmpty else { return false }
                let placeholders = rowids.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO cachedRouteSync (syncID, id, regionId, lastUpdated, routeData)
                    SELECT ?, id, regionId, lastUpdated, routeData
                    FROM cachedRouteSync
                    WHERE rowid IN (\(placeholders))
                    """,
                    arguments: StatementArguments([toSyncID] + rowids.map { DatabaseValue(value: $0) })
                )
                return rowids.count == batchSize
            }
        }
    }

    /// Purges staged stops and routes for a region that belong to older superseded sync snapshots in bounded batches.
    func purgeSupersededStagedStops(regionId: Int, currentSyncID: String, batchSize: Int = 500) throws {
        var hasMoreStops = true
        while hasMoreStops {
            hasMoreStops = try database.dbQueue.write { db in
                let rowids = try Int64.fetchAll(
                    db,
                    sql: "SELECT rowid FROM cachedStopSync WHERE regionId = ? AND syncID != ? LIMIT ?",
                    arguments: [regionId, currentSyncID, batchSize]
                )
                guard !rowids.isEmpty else { return false }
                let placeholders = rowids.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM cachedStopSync WHERE rowid IN (\(placeholders))",
                    arguments: StatementArguments(rowids.map { DatabaseValue(value: $0) })
                )
                return rowids.count == batchSize
            }
        }

        var hasMoreRoutes = true
        while hasMoreRoutes {
            hasMoreRoutes = try database.dbQueue.write { db in
                let rowids = try Int64.fetchAll(
                    db,
                    sql: "SELECT rowid FROM cachedRouteSync WHERE regionId = ? AND syncID != ? LIMIT ?",
                    arguments: [regionId, currentSyncID, batchSize]
                )
                guard !rowids.isEmpty else { return false }
                let placeholders = rowids.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM cachedRouteSync WHERE rowid IN (\(placeholders))",
                    arguments: StatementArguments(rowids.map { DatabaseValue(value: $0) })
                )
                return rowids.count == batchSize
            }
        }

        var hasMoreLegacyStops = true
        while hasMoreLegacyStops {
            hasMoreLegacyStops = try database.dbQueue.write { db in
                let rowids = try Int64.fetchAll(
                    db,
                    sql: "SELECT rowid FROM cachedStop WHERE regionId = ? LIMIT ?",
                    arguments: [regionId, batchSize]
                )
                guard !rowids.isEmpty else { return false }
                let placeholders = rowids.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM cachedStop WHERE rowid IN (\(placeholders))",
                    arguments: StatementArguments(rowids.map { DatabaseValue(value: $0) })
                )
                return rowids.count == batchSize
            }
        }

        var hasMoreLegacyRoutes = true
        while hasMoreLegacyRoutes {
            hasMoreLegacyRoutes = try database.dbQueue.write { db in
                let rowids = try Int64.fetchAll(
                    db,
                    sql: "SELECT rowid FROM cachedRoute WHERE regionId = ? LIMIT ?",
                    arguments: [regionId, batchSize]
                )
                guard !rowids.isEmpty else { return false }
                let placeholders = rowids.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM cachedRoute WHERE rowid IN (\(placeholders))",
                    arguments: StatementArguments(rowids.map { DatabaseValue(value: $0) })
                )
                return rowids.count == batchSize
            }
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
    func deleteStops(regionId: Int, notWrittenSince syncStart: Date) throws {
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
            _ = try StagedCachedStop
                .filter(StagedCachedStop.Columns.regionId == regionId)
                .filter(StagedCachedStop.Columns.lastUpdated < timestamp)
                .deleteAll(db)
            _ = try StagedCachedRoute
                .filter(StagedCachedRoute.Columns.regionId == regionId)
                .filter(StagedCachedRoute.Columns.lastUpdated < timestamp)
                .deleteAll(db)

            if let syncState = try RegionStopSyncState.fetchOne(db, key: regionId),
               syncState.lastSuccessAt < date,
               syncState.publishedSyncID != nil {
                let unpState = RegionStopSyncState(
                    regionId: syncState.regionId,
                    outcome: syncState.outcome,
                    lastAttemptAt: syncState.lastAttemptAt,
                    lastSuccessAt: syncState.lastSuccessAt,
                    etag: syncState.etag,
                    appVersion: syncState.appVersion,
                    publishedSyncID: nil
                )
                try unpState.save(db)
            }
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
                _ = try StagedCachedStop
                    .filter(StagedCachedStop.Columns.regionId == regionId)
                    .deleteAll(db)
                _ = try StagedCachedRoute
                    .filter(StagedCachedRoute.Columns.regionId == regionId)
                    .deleteAll(db)
                _ = try RegionStopSyncState.deleteOne(db, key: regionId)
            }
        } catch {
            Logger.error("Failed to clear cache for region \(regionId): \(error)")
        }
    }

    // MARK: - Region Sync State

    /// What the last sync of `regionId` did, or nil if it was never synced.
    func syncState(regionId: Int) throws -> RegionStopSyncState? {
        try database.dbQueue.read { db in
            try RegionStopSyncState.fetchOne(db, key: regionId)
        }
    }

    func saveSyncState(_ state: RegionStopSyncState) throws {
        try database.dbQueue.write { db in
            try state.save(db)
        }
    }

    /// Publishes a complete staged snapshot by saving its marker.
    /// Superseded staged snapshots and legacy rows are cleaned up separately in batches.
    func publishCompleteSync(_ state: RegionStopSyncState) throws {
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

private struct StagedCachedStop: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cachedStopSync"

    let syncID: String
    let id: String
    let regionId: Int
    let latitude: Double
    let longitude: Double
    let lastUpdated: Double
    let stopData: Data
    let name: String?
    let code: String?

    init(record: CachedStop, syncID: String) {
        self.syncID = syncID
        id = record.id
        regionId = record.regionId
        latitude = record.latitude
        longitude = record.longitude
        lastUpdated = record.lastUpdated
        stopData = record.stopData
        name = record.name
        code = record.code
    }

    var cachedStop: CachedStop {
        CachedStop(id: id, regionId: regionId, latitude: latitude, longitude: longitude, lastUpdated: lastUpdated, stopData: stopData, name: name, code: code)
    }

    enum Columns {
        static let syncID = Column("syncID")
        static let id = Column("id")
        static let regionId = Column("regionId")
        static let latitude = Column("latitude")
        static let longitude = Column("longitude")
    }
}

private struct StagedCachedRoute: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cachedRouteSync"

    let syncID: String
    let id: String
    let regionId: Int
    let lastUpdated: Double
    let routeData: Data

    init(record: CachedRoute, syncID: String) {
        self.syncID = syncID
        id = record.id
        regionId = record.regionId
        lastUpdated = record.lastUpdated
        routeData = record.routeData
    }

    var cachedRoute: CachedRoute {
        CachedRoute(id: id, regionId: regionId, lastUpdated: lastUpdated, routeData: routeData)
    }

    enum Columns {
        static let syncID = Column("syncID")
        static let id = Column("id")
        static let regionId = Column("regionId")
    }
}
