//
//  VehicleFixTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct VehicleFixTests {

    private static func status(_ overrides: [String: Any] = [:]) throws -> TripStatus {
        var data: [String: Any] = [
            "activeTripId": "trip", "blockTripSequence": 0, "closestStop": "stop",
            "closestStopTimeOffset": 0, "distanceAlongTrip": 1240.0,
            "lastKnownLocation": ["lat": 47.61, "lon": -122.33],
            "lastLocationUpdateTime": 1_800_000_000_000, "lastUpdateTime": 1_800_000_005_000,
            "nextStopTimeOffset": 0, "orientation": 0.0, "phase": "in_progress",
            "predicted": true, "scheduleDeviation": 90, "scheduledDistanceAlongTrip": 1200.0,
            "serviceDate": 1000000000, "situationIds": [], "status": "SCHEDULED",
            "totalDistanceAlongTrip": 9000.0, "vehicleId": "1_4351"
        ]
        data.merge(overrides) { _, new in new }
        return try Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: data)
    }

    @Test func `A live status makes a fix at its location update time`() throws {
        let fix = try #require(VehicleFix(tripStatus: try Self.status(), tripID: "trip"))
        #expect(fix.tripID == "trip")
        #expect(fix.vehicleID == "1_4351")
        #expect(fix.fixTime == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(fix.coordinate.latitude == 47.61)
        #expect(fix.scheduleDeviation == 90)
    }

    @Test func `Without a location update time the last update stands in`() throws {
        let fix = try #require(VehicleFix(tripStatus: try Self.status(["lastLocationUpdateTime": 0]), tripID: "trip"))
        #expect(fix.fixTime == Date(timeIntervalSince1970: 1_800_000_005))
    }

    @Test func `A status that cannot anchor an estimate makes no fix`() throws {
        let unusable: [(String, [String: Any])] = [
            ("at null island", ["lastKnownLocation": ["lat": 0.0, "lon": 0.0]]),
            ("with no update time", ["lastLocationUpdateTime": 0, "lastUpdateTime": 0]),
            ("scheduled only", ["predicted": false]),
            ("canceled", ["status": "CANCELED"]),
            // Still finishing the block's previous trip: its distances are on a different shape.
            ("on another trip", ["activeTripId": "previous_trip"])
        ]
        for (name, overrides) in unusable {
            #expect(VehicleFix(tripStatus: try Self.status(overrides), tripID: "trip") == nil, "\(name)")
        }
    }

    @Test func `A status with no location makes no fix`() throws {
        var data: [String: Any] = [:]
        data["lastKnownLocation"] = NSNull()
        #expect(VehicleFix(tripStatus: try Self.status(data), tripID: "trip") == nil)
    }
}

@Suite(.serialized)
struct ClockSkewEstimatorTests {
    private func sample(deviceAheadBy offset: TimeInterval) -> ServerClockSample {
        let received = Date(timeIntervalSince1970: 1_800_000_000)
        return ServerClockSample(serverTime: received - offset, receivedAt: received)
    }

    @Test func `With no samples there is no correction`() {
        let skew = ClockSkewEstimator()
        let now = Date()
        #expect(skew.deviceOffset == 0)
        #expect(skew.serverNow(deviceNow: now) == now)
    }

    @Test func `The correction is the median of recent samples`() {
        var skew = ClockSkewEstimator(capacity: 5)
        [2, 3, 100, 4, 3].forEach { skew.record(sample(deviceAheadBy: $0)) }
        #expect(skew.deviceOffset == 3)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(skew.serverNow(deviceNow: now) == now - 3)
    }

    @Test func `Old samples age out`() {
        var skew = ClockSkewEstimator(capacity: 3)
        [50, 50, 50, 1, 1, 1].forEach { skew.record(sample(deviceAheadBy: $0)) }
        #expect(skew.deviceOffset == 1)
    }

    @Test func `An even count averages the middle two`() {
        var skew = ClockSkewEstimator(capacity: 5)
        [2, 4].forEach { skew.record(sample(deviceAheadBy: $0)) }
        #expect(skew.deviceOffset == 3)
    }
}
