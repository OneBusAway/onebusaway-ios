//
//  StopCacheRepositoryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import CoreLocation
@testable import OBAKitCore

// swiftlint:disable force_try

@MainActor
@Suite(.serialized)
final class StopCacheRepositoryTests {

    let database: StopCacheDatabase
    let repository: StopCacheRepository

    init() {
        database = try! StopCacheDatabase(inMemory: true)
        repository = StopCacheRepository(database: database)
    }

    // `tearDown` nilled both properties out. That was housekeeping XCTest
    // needed because it keeps test-case instances alive for the whole run;
    // Swift Testing releases the suite instance after each test, so letting
    // ARC do it is equivalent — and a `deinit` that only assigns nil to
    // properties of the object being destroyed is a no-op anyway.

    // MARK: - Helpers

    /// Creates a test Stop by decoding from a dictionary, matching the real Stop.init(from:) path.
    private func makeStop(
        id: String,
        code: String = "0000",
        name: String = "Test Stop",
        lat: Double = 47.6062,
        lon: Double = -122.3321,
        direction: String? = "N",
        locationType: Int = 0,
        routeIDs: [String] = ["1_100"],
        wheelchairBoarding: String = "unknown"
    ) -> Stop {
        var dict: [String: Any] = [
            "id": id,
            "code": code,
            "name": name,
            "lat": lat,
            "lon": lon,
            "locationType": locationType,
            "routeIds": routeIDs,
            "wheelchairBoarding": wheelchairBoarding
        ]
        if let direction {
            dict["direction"] = direction
        }

        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Stop.self, from: data)
    }

    // MARK: - Save and Retrieve

    @Test func `Save and retrieve stops round trips correctly`() {
        let stop = makeStop(id: "1_75403", code: "75403", name: "E Pine St & 15th Ave", lat: 47.6153, lon: -122.3148, direction: "W", routeIDs: ["1_10", "1_49"])

        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)

        #expect(results.count == 1)

        let cached = results[0]
        #expect(cached.id == "1_75403")
        #expect(cached.code == "75403")
        #expect(cached.name == "E Pine St & 15th Ave")
        expectClose(cached.location.coordinate.latitude, 47.6153, within: 0.0001)
        expectClose(cached.location.coordinate.longitude, -122.3148, within: 0.0001)
        #expect(cached.direction == .w)
        #expect(cached.locationType == .stop)
        #expect(cached.routeIDs == ["1_10", "1_49"])
        #expect(cached.wheelchairBoarding == .unknown)
        #expect(cached.regionIdentifier == 1)
    }

    @Test func `Save stops upserts on composite key`() {
        let original = makeStop(id: "1_100", name: "Original Name", lat: 47.6, lon: -122.3)
        repository.saveStops([original], regionId: 1)

        let updated = makeStop(id: "1_100", name: "Updated Name", lat: 47.6, lon: -122.3)
        repository.saveStops([updated], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 1)
        #expect(results[0].name == "Updated Name")
    }

    @Test func `Same stop id different regions stored separately`() {
        let stop = makeStop(id: "1_100", name: "Seattle Stop", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        let sameIdDifferentRegion = makeStop(id: "1_100", name: "Tampa Stop", lat: 27.9, lon: -82.5)
        repository.saveStops([sameIdDifferentRegion], regionId: 2)

        let seattleResults = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(seattleResults.count == 1)
        #expect(seattleResults[0].name == "Seattle Stop")

        let tampaResults = repository.stopsInRegion(minLat: 27.0, maxLat: 28.0, minLon: -83.0, maxLon: -82.0, regionId: 2)
        #expect(tampaResults.count == 1)
        #expect(tampaResults[0].name == "Tampa Stop")
    }

    // MARK: - Bounding Box Query

    @Test func `Stops in region only returns stops within bounds`() {
        let inside = makeStop(id: "inside", lat: 47.61, lon: -122.33)
        let outside = makeStop(id: "outside", lat: 48.50, lon: -121.00)

        repository.saveStops([inside, outside], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.5, maxLat: 47.7, minLon: -122.5, maxLon: -122.0, regionId: 1)
        #expect(results.count == 1)
        #expect(results[0].id == "inside")
    }

    @Test func `Stops in region returns empty for no matches`() {
        let stop = makeStop(id: "1_100", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 0.0, maxLat: 1.0, minLon: 0.0, maxLon: 1.0, regionId: 1)
        #expect(results.count == 0)
    }

    @Test func `Stops in region filters by region id`() {
        let stop = makeStop(id: "1_100", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        // Same bounding box, different region — should return nothing
        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 999)
        #expect(results.count == 0)
    }

    @Test func `Stops in region includes stops on boundary`() {
        let edgeStop = makeStop(id: "edge", lat: 47.5, lon: -122.5)
        repository.saveStops([edgeStop], regionId: 1)

        // Query with bounds exactly matching the stop's coordinates
        let results = repository.stopsInRegion(minLat: 47.5, maxLat: 47.5, minLon: -122.5, maxLon: -122.5, regionId: 1)
        #expect(results.count == 1)
        #expect(results[0].id == "edge")
    }

    // MARK: - Purge Stale Data

    @Test func `Delete stops older than removes stale entries`() {
        let stop = makeStop(id: "old_stop", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        // Delete stops older than 1 second in the future — should remove everything
        let futureDate = Date().addingTimeInterval(1)
        repository.deleteStopsOlderThan(futureDate, regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 0)
    }

    @Test func `Delete stops older than preserves fresh entries`() {
        let stop = makeStop(id: "fresh_stop", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        // Delete stops older than a date in the distant past — should keep everything
        let pastDate = Date(timeIntervalSince1970: 0)
        repository.deleteStopsOlderThan(pastDate, regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 1)
        #expect(results[0].id == "fresh_stop")
    }

    @Test func `Delete stops older than scoped to region`() {
        let stop1 = makeStop(id: "1_100", lat: 47.6, lon: -122.3)
        let stop2 = makeStop(id: "2_100", lat: 27.9, lon: -82.5)

        repository.saveStops([stop1], regionId: 1)
        repository.saveStops([stop2], regionId: 2)

        let futureDate = Date().addingTimeInterval(1)
        repository.deleteStopsOlderThan(futureDate, regionId: 1)

        // Region 1 should be empty
        let region1Results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(region1Results.count == 0)

        // Region 2 should be untouched
        let region2Results = repository.stopsInRegion(minLat: 27.0, maxLat: 28.0, minLon: -83.0, maxLon: -82.0, regionId: 2)
        #expect(region2Results.count == 1)
    }

    // MARK: - Clear Cache

    @Test func `Clear cache removes all stops for region and preserves other regions`() {
        let region1Stops = (1...5).map { makeStop(id: "stop_\($0)", lat: 47.6 + Double($0) * 0.001, lon: -122.3) }
        repository.saveStops(region1Stops, regionId: 1)

        let region2Stop = makeStop(id: "region2_stop", lat: 27.9, lon: -82.5)
        repository.saveStops([region2Stop], regionId: 2)

        repository.clearCache(regionId: 1)

        let region1Results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(region1Results.count == 0)

        // Region 2 should be untouched
        let region2Results = repository.stopsInRegion(minLat: 27.0, maxLat: 28.0, minLon: -83.0, maxLon: -82.0, regionId: 2)
        #expect(region2Results.count == 1)
        #expect(region2Results[0].id == "region2_stop")
    }

    // MARK: - Direction Handling

    @Test func `Stop with nil direction round trips as unknown`() {
        let stop = makeStop(id: "no_dir", direction: nil)
        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 1)
        #expect(results[0].direction == .unknown)
    }

    @Test func `All directions round trip correctly`() {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let expectedDirections: [Direction] = [.n, .ne, .e, .se, .s, .sw, .w, .nw]

        for (index, dir) in directions.enumerated() {
            let stop = makeStop(id: "dir_\(dir)", direction: dir)
            repository.saveStops([stop], regionId: 1)

            let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
            let match = results.first { $0.id == "dir_\(dir)" }
            #expect(match != nil, "Stop with direction \(dir) should exist in cache")
            #expect(match?.direction == expectedDirections[index], "Direction \(dir) should round-trip to \(expectedDirections[index])")
        }
    }

    // MARK: - Routes Safety

    @Test func `Cached stop routes is not nil after round trip`() {
        let stop = makeStop(id: "1_100")
        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 1)

        // Stop.routes is [Route]! — if this is nil, the next line would crash.
        #expect(results[0].routes != nil)
        // Accessing prioritizedRouteTypeForDisplay exercises routes.map internally.
        #expect(results[0].prioritizedRouteTypeForDisplay == .unknown)
    }

    @Test func `Cached stop empty route IDs round trips correctly`() {
        let stop = makeStop(id: "no_routes", routeIDs: [])
        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 1)
        #expect(results[0].routes != nil)
        #expect(results[0].routeIDs == [])
    }

    // MARK: - Corrupted Data

    @Test func `Stops in region gracefully handles corrupted stop data`() throws {
        // Insert a record with invalid blob data directly via GRDB
        try database.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO cachedStop (id, regionId, latitude, longitude, lastUpdated, stopData)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: ["corrupt_1", 1, 47.6, -122.3, Date().timeIntervalSince1970, Data("NOT_VALID_JSON".utf8)]
            )
        }

        // Also insert a valid stop
        let validStop = makeStop(id: "valid_1", lat: 47.6, lon: -122.3)
        repository.saveStops([validStop], regionId: 1)

        // The corrupted record should be silently filtered out by compactMap in stopsInRegion
        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 1)
        #expect(results[0].id == "valid_1")
    }

    // MARK: - Nil Direction / WheelchairBoarding

    @Test func `Stop with nil direction and wheelchair boarding round trips correctly`() {
        // direction=nil and wheelchairBoarding=nil should round-trip cleanly
        // through Stop's own Codable (no manual dictionary involved).
        let dict: [String: Any] = [
            "id": "nil_fields",
            "code": "0000",
            "name": "Nil Fields Stop",
            "lat": 47.6,
            "lon": -122.3,
            "locationType": 0,
            "routeIds": ["1_100"]
        ]
        // Explicitly omit direction and wheelchairBoarding
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let stop = try! JSONDecoder().decode(Stop.self, from: data)

        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 1)
        #expect(results[0].id == "nil_fields")
        #expect(results[0].direction == .unknown)
    }

    // MARK: - Routes Stored Once (#1555)

    private func makeRoute(id: String, shortName: String) -> Route {
        let dict: [String: Any] = ["agencyId": "1", "id": id, "shortName": shortName, "type": 3]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Route.self, from: data)
    }

    private func makeStop(id: String, routes: [Route]) -> Stop {
        let stop = makeStop(id: id, code: id, name: "Stop \(id)", routeIDs: routes.map(\.id))
        stop.routes = routes
        return stop
    }

    private func count(_ table: String) throws -> Int {
        try database.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") } ?? -1
    }

    /// A route serving many stops used to be stored once per stop, with its
    /// agency, which made a synced region several times larger.
    @Test func `A cached stop stores its routes once, outside its blob`() throws {
        let r10 = makeRoute(id: "1_10", shortName: "10")
        let r49 = makeRoute(id: "1_49", shortName: "49")
        repository.saveStops([makeStop(id: "1_a", routes: [r49]), makeStop(id: "1_b", routes: [r49, r10])], regionId: 1)

        #expect(try count("cachedRoute") == 2)
        let blobs = try database.dbQueue.read { try Data.fetchAll($0, sql: "SELECT stopData FROM cachedStop") }
        for blob in blobs {
            let json = try #require(try JSONSerialization.jsonObject(with: blob) as? [String: Any])
            #expect(json["routes"] == nil)
        }
        let names = try database.dbQueue.read { try String.fetchAll($0, sql: "SELECT name FROM cachedStop ORDER BY id") }
        let codes = try database.dbQueue.read { try String.fetchAll($0, sql: "SELECT code FROM cachedStop ORDER BY id") }
        #expect(names == ["Stop 1_a", "Stop 1_b"])
        #expect(codes == ["1_a", "1_b"])

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1).sorted { $0.id < $1.id }
        #expect(results.map { $0.routes.map(\.id) } == [["1_49"], ["1_10", "1_49"]])
        #expect(results.last?.routes.map(\.shortName) == ["10", "49"])
    }

    /// Recent stops and bookmarks encode stops too, and must keep their routes.
    @Test func `Stops encoded outside the cache keep their routes`() throws {
        let stop = makeStop(id: "1_a", routes: [makeRoute(id: "1_49", shortName: "49")])
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(stop)) as? [String: Any])
        #expect((json["routes"] as? [[String: Any]])?.count == 1)
    }

    @Test func `A stop cached before schema v3 still reads with its embedded routes`() throws {
        let stop = makeStop(id: "1_old", routes: [makeRoute(id: "1_49", shortName: "49")])
        try database.dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO cachedStop (id, regionId, latitude, longitude, lastUpdated, stopData) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: ["1_old", 1, 47.6062, -122.3321, Date().timeIntervalSince1970, try JSONEncoder().encode(stop)]
            )
        }

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.map { $0.routes.map(\.id) } == [["1_49"]])
    }

    @Test func `A stop whose route row is gone reads with no routes rather than nil`() throws {
        repository.saveStops([makeStop(id: "1_a", routes: [makeRoute(id: "1_49", shortName: "49")])], regionId: 1)
        try database.dbQueue.write { try $0.execute(sql: "DELETE FROM cachedRoute") }

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 1)
        #expect(results.first?.routes.isEmpty == true)
    }

    // MARK: - Region Sync Writes (#1555)

    @Test func `Synced stops and their routes carry the sync's start time`() throws {
        let syncStart = Date(timeIntervalSince1970: 1_790_000_000)
        try repository.writeSyncedStops([makeStop(id: "1_a", routes: [makeRoute(id: "1_49", shortName: "49")])], regionId: 1, syncedAt: syncStart)

        let stamps = try database.dbQueue.read {
            try Double.fetchAll($0, sql: "SELECT lastUpdated FROM cachedStop UNION ALL SELECT lastUpdated FROM cachedRoute")
        }
        #expect(stamps == [1_790_000_000, 1_790_000_000])
    }

    /// A complete sync deletes stops the server no longer lists: everything in
    /// the region older than the sync. Other regions are untouched.
    @Test func `A complete sync's sweep deletes only what it didn't write, in that region`() throws {
        let earlier = Date(timeIntervalSince1970: 1_790_000_000)
        let syncStart = Date(timeIntervalSince1970: 1_790_600_000)
        try repository.writeSyncedStops([makeStop(id: "1_gone", routes: [makeRoute(id: "1_old", shortName: "old")])], regionId: 1, syncedAt: earlier)
        try repository.writeSyncedStops([makeStop(id: "2_other", routes: [makeRoute(id: "2_r", shortName: "r")])], regionId: 2, syncedAt: earlier)
        try repository.writeSyncedStops([makeStop(id: "1_kept", routes: [makeRoute(id: "1_49", shortName: "49")])], regionId: 1, syncedAt: syncStart)

        try repository.deleteStops(regionId: 1, notWrittenSince: syncStart)

        let stops = try database.dbQueue.read { try String.fetchAll($0, sql: "SELECT id FROM cachedStop ORDER BY id") }
        let routes = try database.dbQueue.read { try String.fetchAll($0, sql: "SELECT id FROM cachedRoute ORDER BY id") }
        #expect(stops == ["1_kept", "2_other"])
        #expect(routes == ["1_49", "2_r"])
    }

    /// The issue's rule: the 30-day purge never evicts what a sync wrote within
    /// the last 30 days.
    @Test func `The 30-day purge keeps stops a recent sync wrote`() throws {
        let now = Date()
        try repository.writeSyncedStops([makeStop(id: "1_recent", routes: [])], regionId: 1, syncedAt: now.addingTimeInterval(-1 * 86_400))
        try repository.writeSyncedStops([makeStop(id: "1_stale", routes: [])], regionId: 1, syncedAt: now.addingTimeInterval(-31 * 86_400))

        repository.deleteStopsOlderThan(now.addingTimeInterval(-30 * 86_400), regionId: 1)

        let stops = try database.dbQueue.read { try String.fetchAll($0, sql: "SELECT id FROM cachedStop") }
        #expect(stops == ["1_recent"])
    }

    @Test func `Sync state round-trips, and clearing the cache forgets it`() throws {
        let state = RegionStopSyncState(
            regionId: 1,
            outcome: .complete,
            lastAttemptAt: Date(timeIntervalSince1970: 1_790_000_000),
            lastSuccessAt: Date(timeIntervalSince1970: 1_790_000_000),
            etag: "3f9a",
            appVersion: "26.5"
        )
        try repository.saveSyncState(state)
        #expect(try repository.syncState(regionId: 1) == state)
        #expect(try repository.syncState(regionId: 2) == nil)

        repository.clearCache(regionId: 1)
        #expect(try repository.syncState(regionId: 1) == nil)
    }

    // MARK: - Failable Init

    @Test func `Save stops persists all valid stops`() {
        // Verifies the failable CachedStop.init? doesn't accidentally skip valid stops.
        // Note: The encoding-failure path (init? returning nil) isn't practically testable
        // because Stop always encodes successfully. The read-side filtering of corrupted
        // data is covered by test_stopsInRegion_gracefullyHandlesCorruptedStopData.
        let stops = (1...5).map { makeStop(id: "stop_\($0)", lat: 47.6 + Double($0) * 0.001, lon: -122.3) }
        repository.saveStops(stops, regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 5)
    }

    // MARK: - Multiple Stops

    @Test func `Save multiple stops all persisted`() {
        let stops = (1...50).map {
            makeStop(id: "stop_\($0)", lat: 47.6 + Double($0) * 0.001, lon: -122.3)
        }
        repository.saveStops(stops, regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        #expect(results.count == 50)
    }
}

// swiftlint:enable force_try
