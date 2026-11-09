//
//  StopExtendedDomainTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `Stop` domain methods, location type mapping,
/// wheelchair accessibility enum parsing, and route list association.
@Suite(.serialized)
final class StopExtendedDomainTests: OBATestCase {

    private func makeStop(
        id: String,
        code: String = "100",
        name: String = "Test Stop",
        lat: Double = 47.6062,
        lon: Double = -122.3321,
        direction: String? = "NW",
        locationType: Int = 0,
        routeIDs: [String] = ["1_10", "1_49"],
        wheelchair: String = "accessible"
    ) throws -> Stop {
        var dict: [String: Any] = [
            "id": id,
            "code": code,
            "name": name,
            "lat": lat,
            "lon": lon,
            "locationType": locationType,
            "routeIds": routeIDs,
            "wheelchairBoarding": wheelchair
        ]
        if let direction {
            dict["direction"] = direction
        }

        return try Fixtures.dictionaryToModel(type: Stop.self, dictionary: dict)
    }

    // MARK: - Direction Parsing

    @Test func `Stop parses compound cardinal directions correctly`() throws {
        let nwStop = try makeStop(id: "s_nw", direction: "NW")
        #expect(nwStop.direction == .nw)

        let seStop = try makeStop(id: "s_se", direction: "SE")
        #expect(seStop.direction == .se)

        let nStop = try makeStop(id: "s_n", direction: "N")
        #expect(nStop.direction == .n)

        let nilStop = try makeStop(id: "s_nil", direction: nil)
        #expect(nilStop.direction == .unknown)
    }

    // MARK: - Wheelchair Accessibility

    @Test func `Stop parses wheelchair boarding statuses`() throws {
        let accessible = try makeStop(id: "s_acc", wheelchair: "accessible")
        #expect(accessible.wheelchairBoarding == .accessible)

        let notAccessible = try makeStop(id: "s_not", wheelchair: "notAccessible")
        #expect(notAccessible.wheelchairBoarding == .notAccessible)

        let unknown = try makeStop(id: "s_unk", wheelchair: "unknown")
        #expect(unknown.wheelchairBoarding == .unknown)
    }

    // MARK: - Location Types

    @Test func `Stop locationType enum cases are parsed from integer codes`() throws {
        let regularStop = try makeStop(id: "s_0", locationType: 0)
        #expect(regularStop.locationType == .stop)

        let station = try makeStop(id: "s_1", locationType: 1)
        #expect(station.locationType == .station)

        let entrance = try makeStop(id: "s_2", locationType: 2)
        #expect(entrance.locationType == .stationEntrance)
    }

    // MARK: - Stop Equality and Identity

    @Test func `Stop equality compares stop ID and core metadata`() throws {
        let stopA = try makeStop(id: "stop_1", name: "First Ave")
        let stopB = try makeStop(id: "stop_1", name: "First Ave")
        let stopC = try makeStop(id: "stop_2", name: "Second Ave")

        #expect(stopA == stopB)
        #expect(stopA.hash == stopB.hash)
        #expect(stopA != stopC)
    }
}
