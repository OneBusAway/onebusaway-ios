//
//  StopCacheDatabase.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import GRDB

/// Manages the SQLite database used to cache transit stops for offline access and faster map rendering.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/62
public final class StopCacheDatabase: Sendable {

    /// The underlying GRDB database queue for serialized access.
    let dbQueue: DatabaseQueue

    /// Creates a persistent database at the specified path.
    /// If the database file is corrupted, it is deleted and recreated since this is a cache.
    /// - Parameter databasePath: The full path to the database file.
    ///   Defaults to `stop_cache.sqlite` in the app's Application Support directory.
    public init(databasePath: String? = nil) throws {
        let path: String
        if let databasePath {
            path = databasePath
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            path = appSupport.appendingPathComponent("stop_cache.sqlite").path
        }

        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: path)
        } catch {
            Logger.error("Cache database corrupted, recreating: \(error)")
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
            queue = try DatabaseQueue(path: path)
        }

        dbQueue = queue
        try Self.makeMigrator().migrate(dbQueue)
    }

    /// Creates an in-memory database for testing.
    public init(inMemory: Bool) throws {
        precondition(inMemory, "Use init(databasePath:) for persistent databases")
        dbQueue = try DatabaseQueue()
        try Self.makeMigrator().migrate(dbQueue)
    }

    /// Creates a database at `databasePath` migrated only through
    /// `lastMigration`, so tests can upgrade a real older schema.
    init(databasePath: String, migratingUpTo lastMigration: String) throws {
        dbQueue = try DatabaseQueue(path: databasePath)
        try Self.makeMigrator().migrate(dbQueue, upTo: lastMigration)
    }

    // MARK: - Migrations

    // swiftlint:disable:next function_body_length
    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // v1: Original schema with individual columns for every Stop field.
        // Kept so GRDB's migrator can track migration history correctly.
        migrator.registerMigration("v1_createCachedStops") { db in
            try db.create(table: "cachedStop", options: .ifNotExists) { t in
                t.column("id", .text).notNull()
                t.column("regionId", .integer).notNull()
                t.column("code", .text).notNull()
                t.column("name", .text).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("direction", .text)
                t.column("locationType", .integer).notNull()
                t.column("wheelchairBoarding", .text)
                t.column("routeIDs", .text).notNull()
                t.column("lastUpdated", .double).notNull()
                t.primaryKey(["regionId", "id"])
            }

            try db.create(
                index: "idx_cachedStop_location",
                on: "cachedStop",
                columns: ["regionId", "latitude", "longitude"],
                ifNotExists: true
            )

            try db.create(
                index: "idx_cachedStop_lastUpdated",
                on: "cachedStop",
                columns: ["regionId", "lastUpdated"],
                ifNotExists: true
            )
        }

        // v2: Replace individual columns with a single stopData blob.
        // This is a cache — dropping the table and recreating is safe.
        // Benefits:
        //   - Compile-time safety: no hardcoded CodingKeys dictionary
        //   - Preserves full Route objects for cached stops
        //   - Automatically adapts if Stop fields change
        migrator.registerMigration("v2_stopDataBlob") { db in
            try db.drop(table: "cachedStop")

            try db.create(table: "cachedStop") { t in
                t.column("id", .text).notNull()
                t.column("regionId", .integer).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("lastUpdated", .double).notNull()
                t.column("stopData", .blob).notNull()
                t.primaryKey(["regionId", "id"])
            }

            try db.create(
                index: "idx_cachedStop_location",
                on: "cachedStop",
                columns: ["regionId", "latitude", "longitude"]
            )

            try db.create(
                index: "idx_cachedStop_lastUpdated",
                on: "cachedStop",
                columns: ["regionId", "lastUpdated"]
            )
        }

        // v3: region stop sync (#1555). Columns are added rather than the table
        // rebuilt, so stops the map already cached survive the upgrade.
        //   - name, code: lookups by either needn't decode stopData.
        //   - cachedRoute: each route once per region. New stop blobs leave their
        //     routes out (see CachedStop); older blobs still embed them.
        //   - regionStopSync: what the last sync of each region did.
        migrator.registerMigration("v3_regionStopSync") { db in
            try db.alter(table: "cachedStop") { t in
                t.add(column: "name", .text)
                t.add(column: "code", .text)
            }
            try db.create(index: "idx_cachedStop_name", on: "cachedStop", columns: ["regionId", "name"])
            try db.create(index: "idx_cachedStop_code", on: "cachedStop", columns: ["regionId", "code"])

            try db.create(table: "cachedRoute") { t in
                t.column("id", .text).notNull()
                t.column("regionId", .integer).notNull()
                t.column("lastUpdated", .double).notNull()
                t.column("routeData", .blob).notNull()
                t.primaryKey(["regionId", "id"])
            }
            try db.create(index: "idx_cachedRoute_lastUpdated", on: "cachedRoute", columns: ["regionId", "lastUpdated"])

            try db.create(table: "regionStopSync") { t in
                t.primaryKey("regionId", .integer)
                t.column("outcome", .text).notNull()
                t.column("lastAttemptAt", .double).notNull()
                t.column("lastSuccessAt", .double)
                t.column("etag", .text)
                t.column("appVersion", .text).notNull()
            }
        }

        return migrator
    }
}
