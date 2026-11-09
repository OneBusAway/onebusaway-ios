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

/// Tests for `StopCacheDatabaseStorage` database pruning, agency isolation, and bulk operations.
///
/// Validates cache retrieval accuracy, isolated table operations across multiple transit agencies,
/// record overwrites, and cache clearing behavior.
@Suite(.serialized)
final class StopCacheDatabasePruningTests: OBATestCase {

    private var storage: StopCacheDatabaseStorage!
    private var tempDirectory: URL!

    override init() async throws {
        try await super.init()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let dbPath = tempDirectory.appendingPathComponent("test_stop_cache.sqlite").path
        storage = try StopCacheDatabaseStorage(path: dbPath)
    }

    deinit {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
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

    @Test func `storage persists stops and retrieves matching record`() throws {
        let route = try makeRoute(id: "1_10", shortName: "10")
        let stop = try makeStop(id: "1_1001", name: "Downtown Transit Tunnel")
        stop.routes = [route]

        try storage.storeStops([stop], for: 1)

        let cached = try storage.stop(id: "1_1001", regionIdentifier: 1)
        #expect(cached != nil)
        #expect(cached?.id == "1_1001")
        #expect(cached?.name == "Downtown Transit Tunnel")
        #expect(cached?.routes.first?.shortName == "10")
    }

    @Test func `storage updates existing stop record with updated route definitions`() throws {
        let route1 = try makeRoute(id: "1_10", shortName: "10")
        let stopInitial = try makeStop(id: "1_1001", name: "Initial Name")
        stopInitial.routes = [route1]
        try storage.storeStops([stopInitial], for: 1)

        let route2 = try makeRoute(id: "1_44", shortName: "44")
        let stopUpdated = try makeStop(id: "1_1001", name: "Updated Name", routeIDs: ["1_10", "1_44"])
        stopUpdated.routes = [route1, route2]
        try storage.storeStops([stopUpdated], for: 1)

        let retrieved = try storage.stop(id: "1_1001", regionIdentifier: 1)
        #expect(retrieved?.name == "Updated Name")
        #expect(retrieved?.routes.count == 2)
    }

    // MARK: - Region Isolation

    @Test func `stops stored in region 1 are isolated from region 2 queries`() throws {
        let route = try makeRoute(id: "1_10", shortName: "10")
        let stop = try makeStop(id: "stop_shared_id", name: "Region 1 Stop")
        stop.routes = [route]

        try storage.storeStops([stop], for: 1)

        #expect(try storage.stop(id: "stop_shared_id", regionIdentifier: 1) != nil)
        #expect(try storage.stop(id: "stop_shared_id", regionIdentifier: 2) == nil)
    }

    // MARK: - Bulk Operations and Cache Clear

    @Test func `storeStops handles bulk batch insertions cleanly`() throws {
        var stops: [Stop] = []
        for index in 1...25 {
            let route = try makeRoute(id: "1_\(index)", shortName: "\(index)")
            let stop = try makeStop(id: "1_stop_\(index)", name: "Stop \(index)", routeIDs: ["1_\(index)"])
            stop.routes = [route]
            stops.append(stop)
        }

        try storage.storeStops(stops, for: 1)

        for index in 1...25 {
            let found = try storage.stop(id: "1_stop_\(index)", regionIdentifier: 1)
            #expect(found != nil)
            #expect(found?.name == "Stop \(index)")
        }
    }

    @Test func `clearCache deletes all cached stops for specific region`() throws {
        let route = try makeRoute(id: "1_10", shortName: "10")
        let stopReg1 = try makeStop(id: "stop_reg1", name: "Region 1")
        stopReg1.routes = [route]
        let stopReg2 = try makeStop(id: "stop_reg2", name: "Region 2")
        stopReg2.routes = [route]

        try storage.storeStops([stopReg1], for: 1)
        try storage.storeStops([stopReg2], for: 2)

        try storage.clearCache(for: 1)

        #expect(try storage.stop(id: "stop_reg1", regionIdentifier: 1) == nil)
        #expect(try storage.stop(id: "stop_reg2", regionIdentifier: 2) != nil)
    }
}
