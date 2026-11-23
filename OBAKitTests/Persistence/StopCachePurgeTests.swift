//
//  StopCachePurgeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import GRDB
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class StopCachePurgeTests {
    @Test func `Age purge bounds transactions and preserves fresh rows and other regions`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)
        let tables = ["cachedStop", "cachedRoute", "cachedStopSync", "cachedRouteSync"]
        try database.dbQueue.write { db in
            for table in tables {
                let stopColumns = table.contains("Stop") ? ", latitude, longitude, stopData" : ", routeData"
                let stopValues = table.contains("Stop") ? ", 47.6, -122.3, X'00'" : ", X'00'"
                let syncColumn = table.hasSuffix("Sync") ? ", syncID" : ""
                let syncValue = table.hasSuffix("Sync") ? ", 'published'" : ""
                // More than two default batches in each table, plus cutoff and region sentinels.
                try db.execute(sql: """
                    WITH RECURSIVE rows(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM rows WHERE n < 1001)
                    INSERT INTO \(table) (id, regionId, lastUpdated\(stopColumns)\(syncColumn))
                    SELECT CAST(n AS TEXT), 1, 100\(stopValues)\(syncValue) FROM rows
                    """)
                for (id, region, timestamp) in [("boundary", 1, 200), ("fresh", 1, 300), ("other", 2, 100)] {
                    try db.execute(
                        sql: "INSERT INTO \(table) (id, regionId, lastUpdated\(stopColumns)\(syncColumn)) VALUES (?, ?, ?\(stopValues)\(syncValue))",
                        arguments: [id, region, timestamp]
                    )
                }
            }
        }
        try repository.saveSyncState(RegionStopSyncState(
            regionId: 1, outcome: .complete, lastAttemptAt: Date(timeIntervalSince1970: 300),
            lastSuccessAt: Date(timeIntervalSince1970: 300), etag: nil, appVersion: "test", publishedSyncID: "published"
        ))
        let observer = PurgeTransactionObserver()
        database.dbQueue.add(transactionObserver: observer)

        repository.deleteStopsOlderThan(Date(timeIntervalSince1970: 200), regionId: 1)

        let deletions = try database.dbQueue.read { db in
            for table in tables {
                let ids = try String.fetchAll(db, sql: "SELECT id FROM \(table) ORDER BY id")
                #expect(ids == ["boundary", "fresh", "other"])
            }
            return observer.committedDeletionCounts
        }
        #expect(deletions.reduce(0, +) == 4004)
        #expect(deletions.allSatisfy { $0 <= 500 })
        #expect(try repository.syncState(regionId: 1)?.publishedSyncID == "published")

        repository.deleteStopsOlderThan(Date(timeIntervalSince1970: 400), regionId: 1)

        #expect(try repository.syncState(regionId: 1)?.publishedSyncID == nil)
        try database.dbQueue.read { db in
            for table in tables {
                let ids = try String.fetchAll(db, sql: "SELECT id FROM \(table)")
                #expect(ids == ["other"])
            }
        }
    }

    @Test func `Age purge on non existent region commits no deletions and preserves row ids`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)

        let tables = ["cachedStop", "cachedRoute"]
        try database.dbQueue.write { db in
            for table in tables {
                let stopColumns = table.contains("Stop") ? ", latitude, longitude, stopData" : ", routeData"
                let stopValues = table.contains("Stop") ? ", 47.6, -122.3, X'00'" : ", X'00'"
                try db.execute(sql: "INSERT INTO \(table) (id, regionId, lastUpdated\(stopColumns)) VALUES ('stop_1', 1, 100\(stopValues))")
            }
        }

        let observer = PurgeTransactionObserver()
        database.dbQueue.add(transactionObserver: observer)

        // Purge region 999 where no data exists
        repository.deleteStopsOlderThan(Date(timeIntervalSince1970: 500), regionId: 999)

        try database.dbQueue.read { db in
            #expect(observer.committedDeletionCounts.isEmpty)
            for table in tables {
                let ids = try String.fetchAll(db, sql: "SELECT id FROM \(table)")
                #expect(ids == ["stop_1"])
            }
        }
    }

    @Test func `Age purge when publishedSyncID is absent deletes sync table rows but does not alter syncState`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)

        try database.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO cachedStopSync (id, regionId, lastUpdated, latitude, longitude, stopData, syncID)
                VALUES ('stop_orphan', 1, 100, 47.6, -122.3, X'00', 'staged_old')
                """)
        }

        let initialSyncState = RegionStopSyncState(
            regionId: 1, outcome: .partial, lastAttemptAt: Date(timeIntervalSince1970: 100),
            lastSuccessAt: nil, etag: "etag_val", appVersion: "26.5", publishedSyncID: nil
        )
        try repository.saveSyncState(initialSyncState)

        repository.deleteStopsOlderThan(Date(timeIntervalSince1970: 200), regionId: 1)

        let postSyncState = try repository.syncState(regionId: 1)
        #expect(postSyncState == initialSyncState)

        let remainingOrphans = try database.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM cachedStopSync WHERE regionId = 1")
        }
        #expect(remainingOrphans == 0)
    }

    @Test func `Prune inactive and retired regions (inactive region expired rows deleted, fresh rows kept; retired region completely cleared; active region preserved)`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)
        let tables = ["cachedStop", "cachedRoute", "cachedStopSync", "cachedRouteSync"]

        // Setup 3 regions:
        // Region 1: Active region (has expired row at 100, fresh row at 300)
        // Region 2: Inactive region (has expired row at 100, fresh row at 300)
        // Region 3: Retired region (has row at 100, row at 300)
        try database.dbQueue.write { db in
            for table in tables {
                let stopColumns = table.contains("Stop") ? ", latitude, longitude, stopData" : ", routeData"
                let stopValues = table.contains("Stop") ? ", 47.6, -122.3, X'00'" : ", X'00'"
                let syncColumn = table.hasSuffix("Sync") ? ", syncID" : ""
                let syncValue = table.hasSuffix("Sync") ? ", 'published'" : ""

                for (id, region, timestamp) in [
                    ("act_exp", 1, 100), ("act_fresh", 1, 300),
                    ("inact_exp", 2, 100), ("inact_fresh", 2, 300),
                    ("ret_exp", 3, 100), ("ret_fresh", 3, 300)
                ] {
                    try db.execute(
                        sql: "INSERT INTO \(table) (id, regionId, lastUpdated\(stopColumns)\(syncColumn)) VALUES (?, ?, ?\(stopValues)\(syncValue))",
                        arguments: [id, region, timestamp]
                    )
                }
            }
        }

        for regionId in [1, 2, 3] {
            try repository.saveSyncState(RegionStopSyncState(
                regionId: regionId, outcome: .complete, lastAttemptAt: Date(timeIntervalSince1970: 300),
                lastSuccessAt: Date(timeIntervalSince1970: 300), etag: nil, appVersion: "test", publishedSyncID: "published"
            ))
        }

        #expect(repository.cachedRegionIDs() == Set([1, 2, 3]))

        // Prune inactive regions with activeRegionID = 1, knownRegionIDs = [1, 2], cutoff = 200
        let cutoff = Date(timeIntervalSince1970: 200)
        _ = repository.pruneInactiveRegions(activeRegionID: 1, olderThan: cutoff, knownRegionIDs: [1, 2])

        // Retired region 3 is completely cleared (no rows in any table, sync state deleted)
        // Inactive region 2 expired row deleted, fresh row kept
        // Active region 1 preserved (both rows kept)
        try database.dbQueue.read { db in
            for table in tables {
                let r1IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 1 ORDER BY id")
                #expect(r1IDs == ["act_exp", "act_fresh"])

                let r2IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 2 ORDER BY id")
                #expect(r2IDs == ["inact_fresh"])

                let r3IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 3")
                #expect(r3IDs.isEmpty)
            }
        }
        #expect(try repository.syncState(regionId: 3) == nil)
        #expect(try repository.syncState(regionId: 2) != nil)
        #expect(try repository.syncState(regionId: 1) != nil)
        #expect(repository.cachedRegionIDs() == Set([1, 2]))

        // Calling pruneExpiredStops also prunes expired rows from active region if specified
        _ = repository.pruneExpiredStops(activeRegionID: 1, olderThan: cutoff, knownRegionIDs: [1, 2])
        try database.dbQueue.read { db in
            for table in tables {
                let r1IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 1 ORDER BY id")
                #expect(r1IDs == ["act_fresh"])
            }
        }
    }

    @Test func `Incremental vacuum trigger on page threshold`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)

        // Insert rows with sizable data to generate freelist pages when deleted
        let largeBlob = Data(repeating: 0x55, count: 4096)
        try database.dbQueue.write { db in
            for i in 1...100 {
                try db.execute(
                    sql: "INSERT INTO cachedStop (id, regionId, lastUpdated, latitude, longitude, stopData) VALUES (?, 1, 100, 47.6, -122.3, ?)",
                    arguments: ["stop_\(i)", largeBlob]
                )
            }
        }

        // Delete rows so pages are added to freelist
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM cachedStop WHERE regionId = 1")
        }

        let freelist = database.freelistCount
        #expect(freelist >= 50)

        // Freelist >= threshold (50) -> vacuum runs and returns true, freelist resets to 0
        let vacuumRan = repository.pruneExpiredStops(activeRegionID: 1, knownRegionIDs: [1], freelistPageThreshold: 50)
        #expect(vacuumRan == true)
        #expect(database.freelistCount == 0)

        // When freelist is 0, running again returns false (freelist < threshold)
        let secondRun = repository.pruneExpiredStops(activeRegionID: 1, knownRegionIDs: [1], freelistPageThreshold: 50)
        #expect(secondRun == false)
    }

    @Test func `File size bounded on disk`() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_stop_cache_shrink_\(UUID().uuidString).sqlite").path
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
            try? FileManager.default.removeItem(atPath: dbPath + "-wal")
            try? FileManager.default.removeItem(atPath: dbPath + "-shm")
        }

        let database = try StopCacheDatabase(databasePath: dbPath)
        let repository = StopCacheRepository(database: database)

        let largeBlob = Data(repeating: 0xAA, count: 65536)
        try database.dbQueue.write { db in
            for i in 1...20 {
                try db.execute(
                    sql: "INSERT INTO cachedStop (id, regionId, lastUpdated, latitude, longitude, stopData) VALUES (?, 1, 100, 47.6, -122.3, ?)",
                    arguments: ["blob_\(i)", largeBlob]
                )
            }
        }

        let sizeWithData = (try FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int64) ?? 0
        #expect(sizeWithData > 1_000_000)

        // Delete the large blobs
        repository.clearCache(regionId: 1)

        let freelistBeforeVacuum = database.freelistCount
        #expect(freelistBeforeVacuum > 0)

        // Incremental vacuum should reduce freelist to 0 and shrink file on disk
        try database.incrementalVacuum()

        let freelistAfterVacuum = database.freelistCount
        #expect(freelistAfterVacuum == 0)

        let sizeAfterVacuum = (try FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int64) ?? 0
        #expect(sizeAfterVacuum < sizeWithData)
    }

    @Test func `Existing database with auto_vacuum 0 is upgraded to incremental lazily outside init`() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_legacy_autovacuum_\(UUID().uuidString).sqlite").path
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
            try? FileManager.default.removeItem(atPath: dbPath + "-wal")
            try? FileManager.default.removeItem(atPath: dbPath + "-shm")
        }

        // Create an unconfigured database where auto_vacuum is 0
        let unconfiguredQueue = try DatabaseQueue(path: dbPath)
        try unconfiguredQueue.write { db in
            try db.execute(sql: "CREATE TABLE dummy (id INTEGER PRIMARY KEY)")
        }
        let initialAutoVacuum = try unconfiguredQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA auto_vacuum")
        }
        #expect(initialAutoVacuum == 0)

        // Opening through StopCacheDatabase does NOT run VACUUM during init
        let database = try StopCacheDatabase(databasePath: dbPath)
        let unvacuumedMode = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA auto_vacuum")
        }
        #expect(unvacuumedMode == 0)

        // Upgrading lazily (off main thread or during prune) upgrades auto_vacuum to incremental
        database.upgradeAutoVacuumIfNeeded()
        let upgradedAutoVacuum = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA auto_vacuum")
        }
        #expect(upgradedAutoVacuum == 2) // 2 = INCREMENTAL
    }

    @Test func `Active region missing from knownRegionIDs keeps its rows and is never retired`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)
        let tables = ["cachedStop", "cachedRoute", "cachedStopSync", "cachedRouteSync"]

        // Setup 3 regions:
        // Region 100: Active (e.g. custom region not present in knownRegionIDs list)
        // Region 200: Truly retired region (neither active nor in knownRegionIDs)
        // Region 300: Inactive known region
        try database.dbQueue.write { db in
            for table in tables {
                let stopColumns = table.contains("Stop") ? ", latitude, longitude, stopData" : ", routeData"
                let stopValues = table.contains("Stop") ? ", 47.6, -122.3, X'00'" : ", X'00'"
                let syncColumn = table.hasSuffix("Sync") ? ", syncID" : ""
                let syncValue = table.hasSuffix("Sync") ? ", 'published'" : ""

                for (id, region, timestamp) in [
                    ("act_exp", 100, 100), ("act_fresh", 100, 300),
                    ("ret_exp", 200, 100), ("ret_fresh", 200, 300),
                    ("known_exp", 300, 100), ("known_fresh", 300, 300)
                ] {
                    try db.execute(
                        sql: "INSERT INTO \(table) (id, regionId, lastUpdated\(stopColumns)\(syncColumn)) VALUES (?, ?, ?\(stopValues)\(syncValue))",
                        arguments: [id, region, timestamp]
                    )
                }
            }
        }

        for regionId in [100, 200, 300] {
            try repository.saveSyncState(RegionStopSyncState(
                regionId: regionId, outcome: .complete, lastAttemptAt: Date(timeIntervalSince1970: 300),
                lastSuccessAt: Date(timeIntervalSince1970: 300), etag: nil, appVersion: "test", publishedSyncID: "published"
            ))
        }

        #expect(repository.cachedRegionIDs() == Set([100, 200, 300]))

        // Prune inactive regions where activeRegionID is 100, but knownRegionIDs only has [300]
        let cutoff = Date(timeIntervalSince1970: 200)
        _ = repository.pruneInactiveRegions(activeRegionID: 100, olderThan: cutoff, knownRegionIDs: [300])

        // Retired region 200 was purged completely
        #expect(try repository.syncState(regionId: 200) == nil)

        // Known region 300 kept its fresh row, expired row was deleted
        #expect(try repository.syncState(regionId: 300) != nil)

        // Active region 100 was NOT retired even though missing from knownRegionIDs!
        // Both rows (exp and fresh) preserved under pruneInactiveRegions
        #expect(try repository.syncState(regionId: 100) != nil)
        try database.dbQueue.read { db in
            for table in tables {
                let r100IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 100 ORDER BY id")
                #expect(r100IDs == ["act_exp", "act_fresh"])

                let r200IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 200")
                #expect(r200IDs.isEmpty)

                let r300IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 300 ORDER BY id")
                #expect(r300IDs == ["known_fresh"])
            }
        }

        // Even with pruneExpiredStops, active region 100 only has expired rows pruned, NOT cleared
        _ = repository.pruneExpiredStops(activeRegionID: 100, olderThan: cutoff, knownRegionIDs: [300])
        #expect(try repository.syncState(regionId: 100) != nil)
        try database.dbQueue.read { db in
            for table in tables {
                let r100IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 100 ORDER BY id")
                #expect(r100IDs == ["act_fresh"])
            }
        }
    }

    @Test func `Untrusted regions list when knownRegionIDs is nil does not retire cached regions`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)
        let tables = ["cachedStop", "cachedRoute"]

        try database.dbQueue.write { db in
            for table in tables {
                let stopColumns = table.contains("Stop") ? ", latitude, longitude, stopData" : ", routeData"
                let stopValues = table.contains("Stop") ? ", 47.6, -122.3, X'00'" : ", X'00'"

                for (id, region, timestamp) in [
                    ("r1_fresh", 1, 300),
                    ("r2_fresh", 2, 300),
                    ("r3_fresh", 3, 300)
                ] {
                    try db.execute(
                        sql: "INSERT INTO \(table) (id, regionId, lastUpdated\(stopColumns)) VALUES (?, ?, ?\(stopValues))",
                        arguments: [id, region, timestamp]
                    )
                }
            }
        }

        for regionId in [1, 2, 3] {
            try repository.saveSyncState(RegionStopSyncState(
                regionId: regionId, outcome: .complete, lastAttemptAt: Date(timeIntervalSince1970: 300),
                lastSuccessAt: Date(timeIntervalSince1970: 300), etag: nil, appVersion: "test", publishedSyncID: nil
            ))
        }

        // When canTrustRegionsList is false, CoreApplication passes knownRegionIDs: nil
        _ = repository.pruneInactiveRegions(activeRegionID: 1, knownRegionIDs: nil)

        // All 3 regions kept intact; zero regions retired
        #expect(repository.cachedRegionIDs() == Set([1, 2, 3]))
        for regionId in [1, 2, 3] {
            #expect(try repository.syncState(regionId: regionId) != nil)
        }
    }

    @Test func `Custom region present in allRegions is preserved during prune`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)
        let tables = ["cachedStop", "cachedRoute"]

        // Region 1: Server region (active)
        // Region 999: Custom region (inactive, present in allRegions)
        // Region 888: Retired server region (not in allRegions)
        try database.dbQueue.write { db in
            for table in tables {
                let stopColumns = table.contains("Stop") ? ", latitude, longitude, stopData" : ", routeData"
                let stopValues = table.contains("Stop") ? ", 47.6, -122.3, X'00'" : ", X'00'"

                for (id, region, timestamp) in [
                    ("r1", 1, 300),
                    ("r999_exp", 999, 100), ("r999_fresh", 999, 300),
                    ("r888", 888, 300)
                ] {
                    try db.execute(
                        sql: "INSERT INTO \(table) (id, regionId, lastUpdated\(stopColumns)) VALUES (?, ?, ?\(stopValues))",
                        arguments: [id, region, timestamp]
                    )
                }
            }
        }

        for regionId in [1, 999, 888] {
            try repository.saveSyncState(RegionStopSyncState(
                regionId: regionId, outcome: .complete, lastAttemptAt: Date(timeIntervalSince1970: 300),
                lastSuccessAt: Date(timeIntervalSince1970: 300), etag: nil, appVersion: "test", publishedSyncID: nil
            ))
        }

        // allRegions has region 1 and custom region 999
        let allRegionIDs: Set<Int> = [1, 999]
        let cutoff = Date(timeIntervalSince1970: 200)
        _ = repository.pruneInactiveRegions(activeRegionID: 1, olderThan: cutoff, knownRegionIDs: allRegionIDs)

        // Custom region 999 is NOT retired: fresh data and syncState kept
        #expect(try repository.syncState(regionId: 999) != nil)
        try database.dbQueue.read { db in
            for table in tables {
                let r999IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 999 ORDER BY id")
                #expect(r999IDs == ["r999_fresh"])

                let r888IDs = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE regionId = 888")
                #expect(r888IDs.isEmpty)
            }
        }
        #expect(try repository.syncState(regionId: 888) == nil)
    }

    @Test func `Route-only region appears in cachedRegionIDs and is retired by prune`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)

        // Region 7 has only route rows (no stops); region 1 has stops and routes.
        try database.dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO cachedRoute (id, regionId, lastUpdated, routeData) VALUES ('r7', 7, 300, X'00')"
            )
            try db.execute(
                sql: "INSERT INTO cachedRouteSync (syncID, id, regionId, lastUpdated, routeData) VALUES ('published', 'r7s', 7, 300, X'00')"
            )
            try db.execute(
                sql: "INSERT INTO cachedStop (id, regionId, latitude, longitude, lastUpdated, stopData) VALUES ('s1', 1, 47.6, -122.3, 300, X'00')"
            )
            try db.execute(
                sql: "INSERT INTO cachedRoute (id, regionId, lastUpdated, routeData) VALUES ('r1', 1, 300, X'00')"
            )
        }

        // Without cachedRoute/cachedRouteSync in the union, region 7 would be invisible.
        #expect(repository.cachedRegionIDs() == Set([1, 7]))

        // Region 7 is not in knownRegionIDs, so the prune retires it.
        let cutoff = Date(timeIntervalSince1970: 200)
        _ = repository.pruneInactiveRegions(activeRegionID: 1, olderThan: cutoff, knownRegionIDs: [1])

        #expect(repository.cachedRegionIDs() == Set([1]))
        try database.dbQueue.read { db in
            let r7Routes = try String.fetchAll(db, sql: "SELECT id FROM cachedRoute WHERE regionId = 7")
            #expect(r7Routes.isEmpty)
            let r7StagedRoutes = try String.fetchAll(db, sql: "SELECT id FROM cachedRouteSync WHERE regionId = 7")
            #expect(r7StagedRoutes.isEmpty)
        }
    }

    @Test func `Clear that fails after the first batch leaves no sync state to trust`() throws {
        let database = try StopCacheDatabase(inMemory: true)
        let repository = StopCacheRepository(database: database)
        try database.dbQueue.write { db in
            // More than two default batches, so the clear needs a second batch.
            try db.execute(sql: """
                WITH RECURSIVE rows(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM rows WHERE n < 1001)
                INSERT INTO cachedStop (id, regionId, lastUpdated, latitude, longitude, stopData)
                SELECT CAST(n AS TEXT), 1, 100, 47.6, -122.3, X'00' FROM rows
                """)
            // Lets the first batch of 500 through, then fails the second.
            try db.execute(sql: """
                CREATE TEMP TRIGGER fail_second_batch BEFORE DELETE ON cachedStop
                WHEN (SELECT count(*) FROM cachedStop WHERE regionId = 1) <= 501
                BEGIN SELECT RAISE(ABORT, 'injected failure'); END
                """)
        }
        try repository.saveSyncState(RegionStopSyncState(
            regionId: 1, outcome: .complete, lastAttemptAt: Date(timeIntervalSince1970: 300),
            lastSuccessAt: Date(timeIntervalSince1970: 300), etag: nil, appVersion: "test", publishedSyncID: "published"
        ))

        repository.clearCache(regionId: 1)

        let remaining = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM cachedStop WHERE regionId = 1")
        }
        #expect(remaining == 501)
        #expect(try repository.syncState(regionId: 1) == nil)
    }

    @Test func `Failed auto_vacuum upgrade is not retried within the cooldown`() throws {
        let tempDir = FileManager.default.temporaryDirectory
        // An isolated suite, so this test neither reads nor writes the shared
        // `.standard` store other tests and the app use.
        let suiteName = UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let dbPath = tempDir.appendingPathComponent("test_autovacuum_cooldown_\(UUID().uuidString).sqlite").path
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
            try? FileManager.default.removeItem(atPath: dbPath + "-wal")
            try? FileManager.default.removeItem(atPath: dbPath + "-shm")
        }

        // Create an unconfigured database where auto_vacuum is 0
        let unconfiguredQueue = try DatabaseQueue(path: dbPath)
        try unconfiguredQueue.write { db in
            try db.execute(sql: "CREATE TABLE dummy (id INTEGER PRIMARY KEY)")
        }

        let database = try StopCacheDatabase(databasePath: dbPath, userDefaults: userDefaults)

        // A failure recorded just now: the upgrade is skipped, auto_vacuum stays 0.
        userDefaults.set(Date(), forKey: database.lastAutoVacuumUpgradeFailureKey)
        database.upgradeAutoVacuumIfNeeded()
        let stillUnupgraded = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA auto_vacuum")
        }
        #expect(stillUnupgraded == 0)

        // A failure on this database doesn't block a different database,
        // even though both share this test's store: the record is keyed per database.
        let otherDBPath = tempDir.appendingPathComponent("test_autovacuum_cooldown_other_\(UUID().uuidString).sqlite").path
        defer {
            try? FileManager.default.removeItem(atPath: otherDBPath)
            try? FileManager.default.removeItem(atPath: otherDBPath + "-wal")
            try? FileManager.default.removeItem(atPath: otherDBPath + "-shm")
        }
        let otherUnconfiguredQueue = try DatabaseQueue(path: otherDBPath)
        try otherUnconfiguredQueue.write { db in
            try db.execute(sql: "CREATE TABLE dummy (id INTEGER PRIMARY KEY)")
        }
        let otherDatabase = try StopCacheDatabase(databasePath: otherDBPath, userDefaults: userDefaults)
        otherDatabase.upgradeAutoVacuumIfNeeded()
        let otherUpgradedAutoVacuum = try otherDatabase.dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA auto_vacuum")
        }
        #expect(otherUpgradedAutoVacuum == 2) // 2 = INCREMENTAL

        // A failure recorded long ago: the cooldown has passed, the upgrade proceeds.
        userDefaults.set(
            Date().addingTimeInterval(-2 * StopCacheDatabase.autoVacuumUpgradeRetryCooldown),
            forKey: database.lastAutoVacuumUpgradeFailureKey
        )
        database.upgradeAutoVacuumIfNeeded()
        let upgradedAutoVacuum = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA auto_vacuum")
        }
        #expect(upgradedAutoVacuum == 2) // 2 = INCREMENTAL

        // A successful upgrade clears the recorded failure.
        #expect(userDefaults.object(forKey: database.lastAutoVacuumUpgradeFailureKey) == nil)
    }
}

/// Accessed only on the database queue, including when the test reads the counts.
nonisolated private final class PurgeTransactionObserver: TransactionObserver {
    var committedDeletionCounts: [Int] = []
    private var pendingDeletions = 0

    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        if case .delete = eventKind { return true }
        return false
    }

    func databaseDidChange(with event: DatabaseEvent) {
        pendingDeletions += 1
    }

    func databaseWillCommit() throws {}

    func databaseDidCommit(_ db: Database) {
        if pendingDeletions > 0 { committedDeletionCounts.append(pendingDeletions) }
        pendingDeletions = 0
    }

    func databaseDidRollback(_ db: Database) {
        pendingDeletions = 0
    }
}
