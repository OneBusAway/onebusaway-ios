//
//  StopCacheDatabasePruningTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `StopCacheDatabase` and `StopCacheRepository` pruning, multi-region isolation, and clearing.
@Suite(.serialized)
final class StopCacheDatabasePruningTests: OBATestCase {

    private var database: StopCacheDatabase!
    private var repository: StopCacheRepository!

    override init() async throws {
        try await super.init()
        database = try StopCacheDatabase(inMemory: true)
        repository = StopCacheRepository(database: database)
    }

    private func makeStop(id: String, name: String, routeIDs: [String] = ["1_10"]) throws -> Stop {
        let dict: [String: Any] = [
            "id": id,
            "name": name,
            "lat": 47.6097,
            "lon": -122.3331,
            "direction": "N",
            "code": "100",
            "locationType": 0,
            "routeIds": routeIDs,
            "staticRouteIds": routeIDs,
            "wheelchairBoarding": "UNKNOWN"
        ]
        return try Fixtures.dictionaryToModel(type: Stop.self, dictionary: dict)
    }

    private func makeRoute(id: String, shortName: String) throws -> Route {
        let dict: [String: Any] = [
            "id": id,
            "shortName": shortName,
            "agencyId": "1",
            "type": 3
        ]
        return try Fixtures.dictionaryToModel(type: Route.self, dictionary: dict)
    }

    // MARK: - Save, Read, and Update

    @Test func `repository persists stops and retrieves matching records in coordinate bounds`() throws {
        let route = try makeRoute(id: "1_10", shortName: "10")
        let stop = try makeStop(id: "1_1001", name: "Downtown Transit Tunnel")
        stop.routes = [route]

        repository.saveStops([stop], regionId: 1)

        let cached = repository.stopsInRegion(
            minLat: 47.0,
            maxLat: 48.0,
            minLon: -123.0,
            maxLon: -122.0,
            regionId: 1
        )
        #expect(!cached.isEmpty)
        #expect(cached.first?.id == "1_1001")
        #expect(cached.first?.name == "Downtown Transit Tunnel")
        #expect(cached.first?.routes?.first?.shortName == "10")
    }

    @Test func `repository updates existing stop record with updated route definitions`() throws {
        let route1 = try makeRoute(id: "1_10", shortName: "10")
        let stopInitial = try makeStop(id: "1_1001", name: "Initial Name")
        stopInitial.routes = [route1]
        repository.saveStops([stopInitial], regionId: 1)

        let route2 = try makeRoute(id: "1_44", shortName: "44")
        let stopUpdated = try makeStop(id: "1_1001", name: "Updated Name", routeIDs: ["1_10", "1_44"])
        stopUpdated.routes = [route1, route2]
        repository.saveStops([stopUpdated], regionId: 1)

        let retrieved = repository.stopsInRegion(
            minLat: 47.0,
            maxLat: 48.0,
            minLon: -123.0,
            maxLon: -122.0,
            regionId: 1
        )
        #expect(retrieved.first?.name == "Updated Name")
        #expect(retrieved.first?.routes?.count == 2)
    }

    // MARK: - Region Isolation

    @Test func `stops stored in region 1 are isolated from region 2 queries`() throws {
        let route = try makeRoute(id: "1_10", shortName: "10")
        let stop = try makeStop(id: "stop_shared_id", name: "Region 1 Stop")
        stop.routes = [route]

        repository.saveStops([stop], regionId: 1)

        let region1Stops = repository.stopsInRegion(
            minLat: 47.0,
            maxLat: 48.0,
            minLon: -123.0,
            maxLon: -122.0,
            regionId: 1
        )
        let region2Stops = repository.stopsInRegion(
            minLat: 47.0,
            maxLat: 48.0,
            minLon: -123.0,
            maxLon: -122.0,
            regionId: 2
        )

        #expect(!region1Stops.isEmpty)
        #expect(region2Stops.isEmpty)
    }

    // MARK: - Bulk Operations and Cache Clear

    @Test func `saveStops handles bulk batch insertions cleanly`() throws {
        var stops: [Stop] = []
        for index in 1...25 {
            let route = try makeRoute(id: "1_\(index)", shortName: "\(index)")
            let stop = try makeStop(id: "1_stop_\(index)", name: "Stop \(index)", routeIDs: ["1_\(index)"])
            stop.routes = [route]
            stops.append(stop)
        }

        repository.saveStops(stops, regionId: 1)

        let allStops = repository.stopsInRegion(
            minLat: 47.0,
            maxLat: 48.0,
            minLon: -123.0,
            maxLon: -122.0,
            regionId: 1
        )
        #expect(allStops.count == 25)
    }

    @Test func `clearCache deletes all cached stops for specific region`() throws {
        let route = try makeRoute(id: "1_10", shortName: "10")
        let stopReg1 = try makeStop(id: "stop_reg1", name: "Region 1")
        stopReg1.routes = [route]
        let stopReg2 = try makeStop(id: "stop_reg2", name: "Region 2")
        stopReg2.routes = [route]

        repository.saveStops([stopReg1], regionId: 1)
        repository.saveStops([stopReg2], regionId: 2)

        repository.clearCache(regionId: 1)

        let reg1Result = repository.stopsInRegion(
            minLat: 47.0,
            maxLat: 48.0,
            minLon: -123.0,
            maxLon: -122.0,
            regionId: 1
        )
        let reg2Result = repository.stopsInRegion(
            minLat: 47.0,
            maxLat: 48.0,
            minLon: -123.0,
            maxLon: -122.0,
            regionId: 2
        )

        #expect(reg1Result.isEmpty)
        #expect(!reg2Result.isEmpty)
    }
}
