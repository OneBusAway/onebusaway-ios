//
//  EpochWidthTests.swift
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

/// `Int` is 32 bits on `arm64_32` Apple Watches, and no simulator has that
/// width. These tests pin the *declared* type of every epoch-valued field,
/// which is the only thing a 64-bit test host can check.
@Suite struct EpochWidthTests {

    @Test func `currentTime is declared Int64`() throws {
        let data = Fixtures.loadData(file: "current_time.json")
        let response = try JSONDecoder.RESTDecoder().decode(CoreRESTAPIResponse.self, from: data)

        #expect(type(of: response.currentTime) == Int64?.self)
        #expect(response.currentTime == 1343587068277)
    }

    @Test func `lastLocationUpdateTime is declared Int64 and holds epoch milliseconds`() throws {
        let statusData: [String: Any] = [
            "activeTripId": "active_trip_123",
            "blockTripSequence": 3,
            "closestStop": "stop_closest",
            "closestStopTimeOffset": -120,
            "distanceAlongTrip": 2500.75,
            "lastKnownDistanceAlongTrip": 2480,
            "lastKnownLocation": ["lat": 47.6097, "lon": -122.3331],
            "lastKnownOrientation": 145.5,
            "lastLocationUpdateTime": 1588888744000,
            "lastUpdateTime": 1588888744000,
            "nextStop": "stop_next",
            "nextStopTimeOffset": 180,
            "orientation": 150.0,
            "phase": "IN_PROGRESS",
            "position": ["lat": 47.6098, "lon": -122.3332],
            "predicted": true,
            "scheduleDeviation": -45,
            "scheduledDistanceAlongTrip": 2545.75,
            "serviceDate": 1234512000,
            "situationIds": ["alert_trip_1"],
            "status": "default",
            "totalDistanceAlongTrip": 15000.0,
            "vehicleId": "vehicle_789"
        ]

        let status = try Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: statusData)

        #expect(type(of: status.lastLocationUpdateTime) == Int64.self)
        #expect(status.lastLocationUpdateTime == 1588888744000)
    }

    /// Passes before and after the change on a 64-bit host. It pins the
    /// seconds-versus-milliseconds heuristic across the type change.
    @Test func `Service alert time window accepts seconds and milliseconds`() throws {
        let json = Data(#"{"from": 1589553926433, "to": 1589553999}"#.utf8)
        let window = try JSONDecoder().decode(ServiceAlert.TimeWindow.self, from: json)

        #expect(window.from == Date(timeIntervalSince1970: 1589553926.433))
        #expect(window.to == Date(timeIntervalSince1970: 1589553999))
    }

    @Test func `Service alert time window without an end is open ended`() throws {
        let json = Data(#"{"from": 1589553926}"#.utf8)
        let window = try JSONDecoder().decode(ServiceAlert.TimeWindow.self, from: json)

        #expect(window.to == .distantFuture)
    }
}
