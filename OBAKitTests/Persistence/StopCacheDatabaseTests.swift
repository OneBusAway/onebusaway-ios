//
//  StopCacheDatabaseTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import GRDB
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class StopCacheDatabaseTests {

    private func makeTemporaryDatabasePath() -> String {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("test_stop_cache_\(UUID().uuidString).sqlite").path
    }

    private func cleanupDatabase(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: path + "-wal")
        try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    // MARK: - In-Memory Initialization

    @Test func `InMemory initialization executes all migrations`() throws {
        let database = try StopCacheDatabase(inMemory: true)

        let tables = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }

        #expect(tables.contains("cachedStop"))
        #expect(tables.contains("cachedRoute"))
        #expect(tables.contains("regionStopSync"))
        #expect(tables.contains("grdb_migrations"))
    }

    // MARK: - Persistent Initialization & Schema Integrity

    @Test func `Persistent initialization creates file and indexes`() throws {
        let path = makeTemporaryDatabasePath()
        defer { cleanupDatabase(at: path) }

        _ = try StopCacheDatabase(databasePath: path)
        #expect(FileManager.default.fileExists(atPath: path))

        // Open again to verify re-migration is a no-op and safe
        let database = try StopCacheDatabase(databasePath: path)

        let indexes = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'")
        }

        #expect(indexes.contains("idx_cachedStop_location"))
        #expect(indexes.contains("idx_cachedStop_lastUpdated"))
        #expect(indexes.contains("idx_cachedStop_name"))
        #expect(indexes.contains("idx_cachedStop_code"))
        #expect(indexes.contains("idx_cachedRoute_lastUpdated"))
    }

    // MARK: - Corrupted Database Auto-Recovery

    @Test func `Corrupted database file is automatically deleted and recreated`() throws {
        let path = makeTemporaryDatabasePath()
        defer { cleanupDatabase(at: path) }

        // Write non-SQLite garbage bytes
        let garbage = Data("This is definitely not an SQLite database file.".utf8)
        try garbage.write(to: URL(fileURLWithPath: path))
        #expect(FileManager.default.fileExists(atPath: path))

        // Initializing StopCacheDatabase should catch corruption, delete, and recreate
        let database = try StopCacheDatabase(databasePath: path)

        let tables = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }

        #expect(tables.contains("cachedStop"))
        #expect(tables.contains("cachedRoute"))
        #expect(tables.contains("regionStopSync"))
    }

    // MARK: - Stepwise Migration Verification

    @Test func `Stepwise migration through v1, v2, v3, and v4`() throws {
        let path = makeTemporaryDatabasePath()
        defer { cleanupDatabase(at: path) }

        // Migrate only up to v1
        let v1Db = try StopCacheDatabase(databasePath: path, migratingUpTo: "v1_createCachedStops")
        let v1Columns = try v1Db.dbQueue.read { db in
            try db.columns(in: "cachedStop").map(\.name)
        }
        #expect(v1Columns.contains("wheelchairBoarding"))
        #expect(v1Columns.contains("routeIDs"))
        #expect(!v1Columns.contains("stopData"))

        // Migrate up to v2
        let v2Db = try StopCacheDatabase(databasePath: path, migratingUpTo: "v2_stopDataBlob")
        let v2Columns = try v2Db.dbQueue.read { db in
            try db.columns(in: "cachedStop").map(\.name)
        }
        #expect(v2Columns.contains("stopData"))
        #expect(!v2Columns.contains("wheelchairBoarding"))
        #expect(!v2Columns.contains("name")) // Added in v3

        // Migrate all the way to v3
        let v3Db = try StopCacheDatabase(databasePath: path)
        let v3Columns = try v3Db.dbQueue.read { db in
            try db.columns(in: "cachedStop").map(\.name)
        }
        #expect(v3Columns.contains("stopData"))
        #expect(v3Columns.contains("name"))
        #expect(v3Columns.contains("code"))

        let tables = try v3Db.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        #expect(tables.contains("cachedStopSync"))
        #expect(tables.contains("cachedRouteSync"))
        let syncColumns = try v3Db.dbQueue.read { db in
            try db.columns(in: "regionStopSync").map(\.name)
        }
        #expect(syncColumns.contains("publishedSyncID"))
    }
}
