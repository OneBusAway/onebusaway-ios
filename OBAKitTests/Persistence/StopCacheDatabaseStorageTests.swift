//
//  StopCacheDatabaseStorageTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import GRDB
import Testing
@testable import OBAKitCore

/// Tests for `StopCacheDatabase` and `StopCacheRepository` multi-region isolation,
/// custom SQL queries, spatial bounding box filtering, and sync state persistence.
@MainActor
@Suite(.serialized)
final class StopCacheDatabaseStorageTests {

    private let database: StopCacheDatabase
    private let repository: StopCacheRepository
    private let testRegion1 = 1
    private let testRegion2 = 2

    init() {
        // Force-try safe for in-memory database creation in test harness
        database = try! StopCacheDatabase(inMemory: true)
        repository = StopCacheRepository(database: database)
    }

    // MARK: - Helpers

    private func makeStop(
        id: String,
        code: String = "1000",
        name: String = "Test Stop",
        lat: Double = 47.6097,
        lon: Double = -122.3331,
        direction: String = "N",
        routeIDs: [String] = ["1_10"]
    ) -> Stop {
        let dict: [String: Any] = [
            "id": id,
            "code": code,
            "name": name,
            "lat": lat,
            "lon": lon,
            "direction": direction,
            "locationType": 0,
            "routeIds": routeIDs,
            "wheelchairBoarding": "accessible"
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Stop.self, from: data)
    }

    // MARK: - Multi-Region Storage Isolation

    @Test func `Repository keeps identical stop IDs separate across distinct region IDs`() {
        let stop1 = makeStop(id: "shared_stop_1", name: "Region 1 Version")
        let stop2 = makeStop(id: "shared_stop_1", name: "Region 2 Version")

        repository.saveStops([stop1], regionId: testRegion1)
        repository.saveStops([stop2], regionId: testRegion2)

        let region1Stops = repository.stopsInRegion(
            minLat: 40.0,
            maxLat: 50.0,
            minLon: -130.0,
            maxLon: -120.0,
            regionId: testRegion1
        )
        let region2Stops = repository.stopsInRegion(
            minLat: 40.0,
            maxLat: 50.0,
            minLon: -130.0,
            maxLon: -120.0,
            regionId: testRegion2
        )

        #expect(region1Stops.count == 1)
        #expect(region2Stops.count == 1)
        #expect(region1Stops.first?.name == "Region 1 Version")
        #expect(region2Stops.first?.name == "Region 2 Version")
    }

    @Test func `clearCache for one region does not affect stops in another region`() {
        let stop1 = makeStop(id: "stop_reg_1", name: "Stop R1")
        let stop2 = makeStop(id: "stop_reg_2", name: "Stop R2")

        repository.saveStops([stop1], regionId: testRegion1)
        repository.saveStops([stop2], regionId: testRegion2)

        repository.clearCache(regionId: testRegion1)

        let region1Stops = repository.stopsInRegion(
            minLat: 40.0,
            maxLat: 50.0,
            minLon: -130.0,
            maxLon: -120.0,
            regionId: testRegion1
        )
        let region2Stops = repository.stopsInRegion(
            minLat: 40.0,
            maxLat: 50.0,
            minLon: -130.0,
            maxLon: -120.0,
            regionId: testRegion2
        )

        #expect(region1Stops.isEmpty)
        #expect(region2Stops.count == 1)
        #expect(region2Stops.first?.id == "stop_reg_2")
    }

    // MARK: - Bounding Box Queries

    @Test func `stopsInRegion filters out stops lying outside latitude boundary`() {
        let inside = makeStop(id: "inside", lat: 47.6062, lon: -122.3321)
        let northOutside = makeStop(id: "north", lat: 48.5000, lon: -122.3321)
        let southOutside = makeStop(id: "south", lat: 46.5000, lon: -122.3321)

        repository.saveStops([inside, northOutside, southOutside], regionId: testRegion1)

        let results = repository.stopsInRegion(
            minLat: 47.0,
            maxLat: 48.0,
            minLon: -123.0,
            maxLon: -122.0,
            regionId: testRegion1
        )

        #expect(results.count == 1)
        #expect(results.first?.id == "inside")
    }

    @Test func `stopsInRegion filters out stops lying outside longitude boundary`() {
        let inside = makeStop(id: "inside", lat: 47.6062, lon: -122.3321)
        let westOutside = makeStop(id: "west", lat: 47.6062, lon: -124.0000)
        let eastOutside = makeStop(id: "east", lat: 47.6062, lon: -121.0000)

        repository.saveStops([inside, westOutside, eastOutside], regionId: testRegion1)

        let results = repository.stopsInRegion(
            minLat: 47.0,
            maxLat: 48.0,
            minLon: -123.0,
            maxLon: -122.0,
            regionId: testRegion1
        )

        #expect(results.count == 1)
        #expect(results.first?.id == "inside")
    }

    // MARK: - Direct Database Table Inspection

    @Test func `StopCacheDatabase contains expected tables and schema structure`() throws {
        let tables: [String] = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
        }

        #expect(tables.contains("cachedStop"))
        #expect(tables.contains("regionStopSync"))
        #expect(tables.contains("cachedRoute"))
    }

    @Test func `writeSyncedStops upserts and keeps previously written stops`() throws {
        let now = Date()
        let initialStops = [
            makeStop(id: "s1", name: "Initial 1"),
            makeStop(id: "s2", name: "Initial 2")
        ]
        try repository.writeSyncedStops(initialStops, regionId: testRegion1, syncedAt: now)

        let countBefore = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cachedStop WHERE regionId = ?", arguments: [testRegion1])
        }
        #expect(countBefore == 2)

        // Add 3 new stops and overwrite
        let newStops = [
            makeStop(id: "s3", name: "New 3"),
            makeStop(id: "s4", name: "New 4"),
            makeStop(id: "s5", name: "New 5")
        ]
        try repository.writeSyncedStops(newStops, regionId: testRegion1, syncedAt: now)

        let countAfter = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cachedStop WHERE regionId = ?", arguments: [testRegion1])
        }
        #expect(countAfter == 5)
    }

    // MARK: - RegionStopSyncState Database CRUD

    @Test func `RegionStopSyncState updates existing record rather than inserting duplicate`() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let state1 = RegionStopSyncState(
            regionId: testRegion1,
            outcome: .partial,
            lastAttemptAt: now,
            lastSuccessAt: nil,
            etag: nil,
            appVersion: "26.0"
        )
        try repository.saveSyncState(state1)

        let state2 = RegionStopSyncState(
            regionId: testRegion1,
            outcome: .complete,
            lastAttemptAt: now.addingTimeInterval(3600),
            lastSuccessAt: now.addingTimeInterval(3600),
            etag: "etag_xyz",
            appVersion: "26.0"
        )
        try repository.saveSyncState(state2)

        let fetched = try repository.syncState(regionId: testRegion1)
        #expect(fetched?.outcome == .complete)
        #expect(fetched?.etag == "etag_xyz")

        let totalRows = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM regionStopSync WHERE regionId = ?", arguments: [testRegion1])
        }
        #expect(totalRows == 1)
    }

    // MARK: - Pagination and Cursor Querying

    @Test func `stops with cursor pagination iterates in ascending StopID order`() throws {
        let stops = [
            makeStop(id: "stop_01", name: "Alpha"),
            makeStop(id: "stop_02", name: "Beta"),
            makeStop(id: "stop_03", name: "Gamma"),
            makeStop(id: "stop_04", name: "Delta"),
            makeStop(id: "stop_05", name: "Epsilon")
        ]
        repository.saveStops(stops, regionId: testRegion1)

        // Read page 1 with limit 2
        let page1 = repository.stops(regionId: testRegion1, after: nil, limit: 2)
        #expect(page1.stops.count == 2)
        #expect(page1.stops.map(\.id) == ["stop_01", "stop_02"])
        #expect(page1.cursor == "stop_02")

        // Read page 2 with limit 2 starting after cursor
        let page2 = repository.stops(regionId: testRegion1, after: page1.cursor, limit: 2)
        #expect(page2.stops.count == 2)
        #expect(page2.stops.map(\.id) == ["stop_03", "stop_04"])
        #expect(page2.cursor == "stop_04")

        // Read page 3 (last element)
        let page3 = repository.stops(regionId: testRegion1, after: page2.cursor, limit: 2)
        #expect(page3.stops.count == 1)
        #expect(page3.stops.map(\.id) == ["stop_05"])
        #expect(page3.cursor == nil)
    }

    @Test func `clearCache purges stops, associated routes, and sync state atomically`() throws {
        let stops = [makeStop(id: "clear_1", routeIDs: ["r_100"])]
        repository.saveStops(stops, regionId: testRegion1)

        let state = RegionStopSyncState(
            regionId: testRegion1,
            outcome: .complete,
            lastAttemptAt: Date(),
            lastSuccessAt: Date(),
            etag: "test_etag",
            appVersion: "1.0"
        )
        try repository.saveSyncState(state)

        // Verify data exists
        #expect(try repository.syncState(regionId: testRegion1) != nil)

        // Clear cache
        repository.clearCache(regionId: testRegion1)

        // Verify everything cleared for region 1
        #expect(try repository.syncState(regionId: testRegion1) == nil)
        let stopCount = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cachedStop WHERE regionId = ?", arguments: [testRegion1])
        }
        #expect(stopCount == 0)

        let routeCount = try database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cachedRoute WHERE regionId = ?", arguments: [testRegion1])
        }
        #expect(routeCount == 0)
    }

    @Test func `deleteStopsOlderThan purges expired records while retaining fresh records`() throws {
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = Date(timeIntervalSince1970: 1_700_100_000)

        try repository.writeSyncedStops([makeStop(id: "old_stop")], regionId: testRegion1, syncedAt: past)
        try repository.writeSyncedStops([makeStop(id: "fresh_stop")], regionId: testRegion1, syncedAt: recent)

        let cutoff = Date(timeIntervalSince1970: 1_700_050_000)
        repository.deleteStopsOlderThan(cutoff, regionId: testRegion1)

        let surviving = repository.stopsInRegion(
            minLat: 40.0,
            maxLat: 50.0,
            minLon: -130.0,
            maxLon: -120.0,
            regionId: testRegion1
        )
        #expect(surviving.count == 1)
        #expect(surviving.first?.id == "fresh_stop")
    }
}
