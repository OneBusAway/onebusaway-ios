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
