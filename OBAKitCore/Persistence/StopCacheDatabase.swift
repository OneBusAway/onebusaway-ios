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

    /// Default threshold of freelist pages before triggering incremental vacuum.
    static let defaultFreelistThreshold: Int = 50

    /// The underlying GRDB database queue for serialized access.
    let dbQueue: DatabaseQueue

    /// Identifies this database for the `auto_vacuum` retry cooldown: its file
    /// path, or a per-instance UUID for in-memory databases (which have no path).
    private let cooldownIdentity: String

    /// The store recording `auto_vacuum` upgrade failures for the retry cooldown.
    /// Injected so tests can pass an isolated suite instead of the process-wide
    /// `.standard` store: suites run concurrently, so a failure recorded by one
    /// test must not suppress upgrades in another. `UserDefaults` is thread-safe
    /// by design, which is why this is `nonisolated(unsafe)` on this `Sendable` class.
    nonisolated(unsafe) private let userDefaults: UserDefaults

    /// Creates a persistent database at the specified path.
    /// If the database file is corrupted, it is deleted and recreated since this is a cache.
    /// - Parameter databasePath: The full path to the database file.
    ///   Defaults to `stop_cache.sqlite` in the app's Application Support directory.
    public init(databasePath: String? = nil, userDefaults: UserDefaults = .standard) throws {
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

        let configuration = Self.makeConfiguration()
        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: path, configuration: configuration)
        } catch {
            Logger.error("Cache database corrupted, recreating: \(error)")
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
            queue = try DatabaseQueue(path: path, configuration: configuration)
        }

        dbQueue = queue
        cooldownIdentity = path
        self.userDefaults = userDefaults
        try Self.makeMigrator().migrate(dbQueue)
    }

    /// Creates an in-memory database for testing.
    public init(inMemory: Bool, userDefaults: UserDefaults = .standard) throws {
        precondition(inMemory, "Use init(databasePath:) for persistent databases")
        let queue = try DatabaseQueue(configuration: Self.makeConfiguration())
        dbQueue = queue
        cooldownIdentity = UUID().uuidString
        self.userDefaults = userDefaults
        try Self.makeMigrator().migrate(dbQueue)
    }

    /// Creates a database at `databasePath` migrated only through
    /// `lastMigration`, so tests can upgrade a real older schema.
    init(databasePath: String, migratingUpTo lastMigration: String, userDefaults: UserDefaults = .standard) throws {
        let queue = try DatabaseQueue(path: databasePath, configuration: Self.makeConfiguration())
        dbQueue = queue
        cooldownIdentity = databasePath
        self.userDefaults = userDefaults
        try Self.makeMigrator().migrate(dbQueue, upTo: lastMigration)
    }

    private static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
        }
        return configuration
    }

    /// How long to wait before retrying a failed `auto_vacuum` upgrade.
    /// A failed `VACUUM` writes a temporary copy of the whole database each
    /// time it runs, so retrying on every launch and region change is
    /// expensive when the failure persists (e.g. insufficient disk space).
    static let autoVacuumUpgradeRetryCooldown: TimeInterval = 24 * 60 * 60

    /// UserDefaults key prefix recording when the last `auto_vacuum` upgrade failed.
    /// The full key is scoped per database (see `lastAutoVacuumUpgradeFailureKey`),
    /// so a failure on one database does not block upgrades on another.
    static let lastAutoVacuumUpgradeFailureKeyPrefix = "OBAKitCore.StopCacheDatabase.lastAutoVacuumUpgradeFailure"

    /// UserDefaults key recording when the last `auto_vacuum` upgrade failed for
    /// this database. Scoped by `cooldownIdentity` so a failure on one database
    /// cannot block upgrades on a different database.
    var lastAutoVacuumUpgradeFailureKey: String {
        "\(Self.lastAutoVacuumUpgradeFailureKeyPrefix).\(cooldownIdentity)"
    }

    /// Upgrades a database created with `auto_vacuum = NONE` to `INCREMENTAL`.
    /// Runs outside transactions; catches and logs any failure (e.g. insufficient disk space)
    /// without throwing so the database remains fully functional.
    /// A failed upgrade is retried only after `autoVacuumUpgradeRetryCooldown`
    /// has passed, so a persistent failure doesn't rewrite a temporary copy
    /// of the whole database on every launch and region change. The cooldown is
    /// recorded per database, so a failure on one database doesn't block
    /// upgrades on another. The record lives in the injected `userDefaults`
    /// store (`.standard` in production), so tests can isolate it with a
    /// per-test suite instead of sharing process-wide state.
    func upgradeAutoVacuumIfNeeded() {
        if let lastFailure = userDefaults.object(forKey: lastAutoVacuumUpgradeFailureKey) as? Date,
           Date().timeIntervalSince(lastFailure) < Self.autoVacuumUpgradeRetryCooldown {
            return
        }
        do {
            let autoVacuum = try dbQueue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA auto_vacuum") ?? 0
            }
            if autoVacuum == 0 {
                try dbQueue.writeWithoutTransaction { db in
                    try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
                    try db.execute(sql: "VACUUM")
                }
            }
            // Success (or already upgraded): forget any recorded failure.
            userDefaults.removeObject(forKey: lastAutoVacuumUpgradeFailureKey)
        } catch {
            Logger.warn("Failed to upgrade auto_vacuum to INCREMENTAL: \(error)")
            userDefaults.set(Date(), forKey: lastAutoVacuumUpgradeFailureKey)
        }
    }

    /// The number of unused pages on the database freelist.
    var freelistCount: Int {
        do {
            return try dbQueue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0
            }
        } catch {
            Logger.error("Failed to read freelist count: \(error)")
            return 0
        }
    }

    /// Truncates up to `pages` unused pages from the freelist back to the operating system.
    /// If `pages` is nil, truncates all unused pages.
    func incrementalVacuum(pages: Int? = nil) throws {
        try dbQueue.writeWithoutTransaction { db in
            if let pages {
                try db.execute(sql: "PRAGMA incremental_vacuum(\(pages))")
            } else {
                try db.execute(sql: "PRAGMA incremental_vacuum")
            }
        }
    }

    /// Pages freed per `incremental_vacuum` chunk.
    static let incrementalVacuumChunkPages = 100

    /// Truncates unused pages back to the operating system in bounded chunks,
    /// releasing the database queue between chunks so other writers (e.g. the
    /// map's cache save) can interleave instead of waiting behind one long
    /// vacuum. Drains the freelist fully; each chunk frees at most
    /// `incrementalVacuumChunkPages` pages.
    func incrementalVacuumInChunks(pagesPerChunk: Int = incrementalVacuumChunkPages) throws {
        while freelistCount > 0 {
            let before = freelistCount
            try incrementalVacuum(pages: pagesPerChunk)
            // Stop if a chunk made no progress, so a freelist that can't
            // shrink further doesn't spin.
            if freelistCount >= before { break }
        }
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

        // v4: staged region sync rows. A sync writes these in short batches and
        // publishes their ID in regionStopSync only after every batch succeeds.
        migrator.registerMigration("v4_stagedRegionStopSync") { db in
            try db.alter(table: "regionStopSync") { t in
                t.add(column: "publishedSyncID", .text)
            }

            try db.create(table: "cachedStopSync") { t in
                t.column("syncID", .text).notNull()
                t.column("id", .text).notNull()
                t.column("regionId", .integer).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("lastUpdated", .double).notNull()
                t.column("stopData", .blob).notNull()
                t.column("name", .text)
                t.column("code", .text)
                t.primaryKey(["syncID", "regionId", "id"])
            }
            try db.create(index: "idx_cachedStopSync_location", on: "cachedStopSync", columns: ["syncID", "regionId", "latitude", "longitude"])

            try db.create(table: "cachedRouteSync") { t in
                t.column("syncID", .text).notNull()
                t.column("id", .text).notNull()
                t.column("regionId", .integer).notNull()
                t.column("lastUpdated", .double).notNull()
                t.column("routeData", .blob).notNull()
                t.primaryKey(["syncID", "regionId", "id"])
            }
        }

        return migrator
    }
}
