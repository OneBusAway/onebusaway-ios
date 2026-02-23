//
//  StopCacheRepositoryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import CoreLocation
@testable import OBAKitCore

// swiftlint:disable force_try

class StopCacheRepositoryTests: XCTestCase {

    var database: StopCacheDatabase!
    var repository: StopCacheRepository!

    override func setUp() {
        super.setUp()
        database = try! StopCacheDatabase(inMemory: true)
        repository = StopCacheRepository(database: database)
    }

    override func tearDown() {
        repository = nil
        database = nil
        super.tearDown()
    }

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

    func test_saveAndRetrieveStops_roundTripsCorrectly() {
        let stop = makeStop(id: "1_75403", code: "75403", name: "E Pine St & 15th Ave", lat: 47.6153, lon: -122.3148, direction: "W", routeIDs: ["1_10", "1_49"])

        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)

        XCTAssertEqual(results.count, 1)

        let cached = results[0]
        XCTAssertEqual(cached.id, "1_75403")
        XCTAssertEqual(cached.code, "75403")
        XCTAssertEqual(cached.name, "E Pine St & 15th Ave")
        XCTAssertEqual(cached.location.coordinate.latitude, 47.6153, accuracy: 0.0001)
        XCTAssertEqual(cached.location.coordinate.longitude, -122.3148, accuracy: 0.0001)
        XCTAssertEqual(cached.direction, .w)
        XCTAssertEqual(cached.locationType, .stop)
        XCTAssertEqual(cached.routeIDs, ["1_10", "1_49"])
        XCTAssertEqual(cached.wheelchairBoarding, .unknown)
        XCTAssertEqual(cached.regionIdentifier, 1)
    }

    func test_saveStops_upsertsOnCompositeKey() {
        let original = makeStop(id: "1_100", name: "Original Name", lat: 47.6, lon: -122.3)
        repository.saveStops([original], regionId: 1)

        let updated = makeStop(id: "1_100", name: "Updated Name", lat: 47.6, lon: -122.3)
        repository.saveStops([updated], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Updated Name")
    }

    func test_sameStopId_differentRegions_storedSeparately() {
        let stop = makeStop(id: "1_100", name: "Seattle Stop", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        let sameIdDifferentRegion = makeStop(id: "1_100", name: "Tampa Stop", lat: 27.9, lon: -82.5)
        repository.saveStops([sameIdDifferentRegion], regionId: 2)

        let seattleResults = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(seattleResults.count, 1)
        XCTAssertEqual(seattleResults[0].name, "Seattle Stop")

        let tampaResults = repository.stopsInRegion(minLat: 27.0, maxLat: 28.0, minLon: -83.0, maxLon: -82.0, regionId: 2)
        XCTAssertEqual(tampaResults.count, 1)
        XCTAssertEqual(tampaResults[0].name, "Tampa Stop")
    }

    // MARK: - Bounding Box Query

    func test_stopsInRegion_onlyReturnsStopsWithinBounds() {
        let inside = makeStop(id: "inside", lat: 47.61, lon: -122.33)
        let outside = makeStop(id: "outside", lat: 48.50, lon: -121.00)

        repository.saveStops([inside, outside], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.5, maxLat: 47.7, minLon: -122.5, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "inside")
    }

    func test_stopsInRegion_returnsEmptyForNoMatches() {
        let stop = makeStop(id: "1_100", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 0.0, maxLat: 1.0, minLon: 0.0, maxLon: 1.0, regionId: 1)
        XCTAssertEqual(results.count, 0)
    }

    func test_stopsInRegion_filtersbyRegionId() {
        let stop = makeStop(id: "1_100", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        // Same bounding box, different region — should return nothing
        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 999)
        XCTAssertEqual(results.count, 0)
    }

    func test_stopsInRegion_includesStopsOnBoundary() {
        let edgeStop = makeStop(id: "edge", lat: 47.5, lon: -122.5)
        repository.saveStops([edgeStop], regionId: 1)

        // Query with bounds exactly matching the stop's coordinates
        let results = repository.stopsInRegion(minLat: 47.5, maxLat: 47.5, minLon: -122.5, maxLon: -122.5, regionId: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "edge")
    }

    // MARK: - Purge Stale Data

    func test_deleteStopsOlderThan_removesStaleEntries() {
        let stop = makeStop(id: "old_stop", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        // Delete stops older than 1 second in the future — should remove everything
        let futureDate = Date().addingTimeInterval(1)
        repository.deleteStopsOlderThan(futureDate, regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(results.count, 0)
    }

    func test_deleteStopsOlderThan_preservesFreshEntries() {
        let stop = makeStop(id: "fresh_stop", lat: 47.6, lon: -122.3)
        repository.saveStops([stop], regionId: 1)

        // Delete stops older than a date in the distant past — should keep everything
        let pastDate = Date(timeIntervalSince1970: 0)
        repository.deleteStopsOlderThan(pastDate, regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "fresh_stop")
    }

    func test_deleteStopsOlderThan_scopedToRegion() {
        let stop1 = makeStop(id: "1_100", lat: 47.6, lon: -122.3)
        let stop2 = makeStop(id: "2_100", lat: 27.9, lon: -82.5)

        repository.saveStops([stop1], regionId: 1)
        repository.saveStops([stop2], regionId: 2)

        let futureDate = Date().addingTimeInterval(1)
        repository.deleteStopsOlderThan(futureDate, regionId: 1)

        // Region 1 should be empty
        let region1Results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(region1Results.count, 0)

        // Region 2 should be untouched
        let region2Results = repository.stopsInRegion(minLat: 27.0, maxLat: 28.0, minLon: -83.0, maxLon: -82.0, regionId: 2)
        XCTAssertEqual(region2Results.count, 1)
    }

    // MARK: - Clear Cache

    func test_clearCache_removesAllStopsForRegion_andPreservesOtherRegions() {
        let region1Stops = (1...5).map { makeStop(id: "stop_\($0)", lat: 47.6 + Double($0) * 0.001, lon: -122.3) }
        repository.saveStops(region1Stops, regionId: 1)

        let region2Stop = makeStop(id: "region2_stop", lat: 27.9, lon: -82.5)
        repository.saveStops([region2Stop], regionId: 2)

        repository.clearCache(regionId: 1)

        let region1Results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(region1Results.count, 0)

        // Region 2 should be untouched
        let region2Results = repository.stopsInRegion(minLat: 27.0, maxLat: 28.0, minLon: -83.0, maxLon: -82.0, regionId: 2)
        XCTAssertEqual(region2Results.count, 1)
        XCTAssertEqual(region2Results[0].id, "region2_stop")
    }

    // MARK: - Direction Handling

    func test_stopWithNilDirection_roundTripsAsUnknown() {
        let stop = makeStop(id: "no_dir", direction: nil)
        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].direction, .unknown)
    }

    func test_allDirections_roundTripCorrectly() {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let expectedDirections: [Direction] = [.n, .ne, .e, .se, .s, .sw, .w, .nw]

        for (index, dir) in directions.enumerated() {
            let stop = makeStop(id: "dir_\(dir)", direction: dir)
            repository.saveStops([stop], regionId: 1)

            let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
            let match = results.first { $0.id == "dir_\(dir)" }
            XCTAssertNotNil(match, "Stop with direction \(dir) should exist in cache")
            XCTAssertEqual(match?.direction, expectedDirections[index], "Direction \(dir) should round-trip to \(expectedDirections[index])")
        }
    }

    // MARK: - Routes Safety

    func test_cachedStop_routesIsNotNil_afterRoundTrip() {
        let stop = makeStop(id: "1_100")
        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(results.count, 1)

        // Stop.routes is [Route]! — if this is nil, the next line would crash.
        XCTAssertNotNil(results[0].routes)
        // Accessing prioritizedRouteTypeForDisplay exercises routes.map internally.
        XCTAssertEqual(results[0].prioritizedRouteTypeForDisplay, .unknown)
    }

    func test_cachedStop_emptyRouteIDs_roundTripsCorrectly() {
        let stop = makeStop(id: "no_routes", routeIDs: [])
        repository.saveStops([stop], regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results[0].routes)
        XCTAssertEqual(results[0].routeIDs, [])
    }

    // MARK: - Corrupted Data

    func test_stopsInRegion_gracefullyHandlesCorruptedRouteIDs() throws {
        // Insert a record with invalid JSON in routeIDs directly via GRDB
        try database.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO cachedStop (id, regionId, code, name, latitude, longitude, direction, locationType, wheelchairBoarding, routeIDs, lastUpdated)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: ["corrupt_1", 1, "0000", "Corrupt Stop", 47.6, -122.3, "N", 0, "unknown", "NOT_VALID_JSON", Date().timeIntervalSince1970]
            )
        }

        // Also insert a valid stop
        let validStop = makeStop(id: "valid_1", lat: 47.6, lon: -122.3)
        repository.saveStops([validStop], regionId: 1)

        // The corrupted record should be silently filtered out by compactMap in stopsInRegion
        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "valid_1")
    }

    // MARK: - Nil Direction / WheelchairBoarding

    func test_stopWithNilDirectionAndWheelchairBoarding_roundTripsCorrectly() {
        // direction=nil and wheelchairBoarding=nil must not produce NSNull in
        // the JSON dictionary, which would break JSONDecoder's decodeIfPresent.
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
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "nil_fields")
        XCTAssertEqual(results[0].direction, .unknown)
    }

    // MARK: - Multiple Stops

    func test_saveMultipleStops_allPersisted() {
        let stops = (1...50).map {
            makeStop(id: "stop_\($0)", lat: 47.6 + Double($0) * 0.001, lon: -122.3)
        }
        repository.saveStops(stops, regionId: 1)

        let results = repository.stopsInRegion(minLat: 47.0, maxLat: 48.0, minLon: -123.0, maxLon: -122.0, regionId: 1)
        XCTAssertEqual(results.count, 50)
    }
}

// swiftlint:enable force_try
