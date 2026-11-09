//
//  VehicleStatusModelExtendedTests.swift
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

/// Tests for `VehicleStatus` model JSON decoding, zero-timestamp edge-cases,
/// reference loading, and location coordinate parsing.
@Suite(.serialized)
final class VehicleStatusModelExtendedTests: OBATestCase {

    private func makeVehicleStatusJSON(
        vehicleID: String = "1_4321",
        lastUpdateTime: Int = 1541141749000,
        lastLocationUpdateTime: Int = 1541141749000,
        tripID: String = "1_40984902",
        phase: String = "in_progress",
        status: String = "default"
    ) -> Data {
        let dict: [String: Any] = [
            "vehicleId": vehicleID,
            "lastUpdateTime": lastUpdateTime,
            "lastLocationUpdateTime": lastLocationUpdateTime,
            "location": [
                "lat": 47.6097,
                "lon": -122.3331
            ],
            "tripId": tripID,
            "phase": phase,
            "status": status,
            "tripStatus": [
                "activeTripId": tripID,
                "blockTripSequence": 1,
                "serviceDate": 1541055600000,
                "scheduledDistanceAlongTrip": 1000.0,
                "totalDistanceAlongTrip": 5000.0,
                "distanceAlongTrip": 1200.0,
                "closestStop": "1_9650",
                "closestStopTimeOffset": 0,
                "lastKnownDistanceAlongTrip": 1200.0,
                "phase": phase,
                "status": status,
                "predicted": true,
                "lastUpdateTime": lastUpdateTime,
                "lastLocationUpdateTime": lastLocationUpdateTime
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Decoding and Fields

    @Test func `VehicleStatus decodes fields and coordinates accurately`() throws {
        let data = makeVehicleStatusJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let status = try decoder.decode(VehicleStatus.self, from: data)

        #expect(status.vehicleID == "1_4321")
        #expect(status.id == "1_4321")
        #expect(status.phase == "in_progress")
        #expect(status.status == "default")
        let location = try #require(status.location)
        #expect(abs(location.coordinate.latitude - 47.6097) < 0.0001)
        #expect(abs(location.coordinate.longitude - (-122.3331)) < 0.0001)
    }

    @Test func `VehicleStatus treats zero epoch lastLocationUpdateTime as nil`() throws {
        // Zero epoch indicates no location update received from vehicle yet
        let data = makeVehicleStatusJSON(lastLocationUpdateTime: 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let status = try decoder.decode(VehicleStatus.self, from: data)
        #expect(status.lastLocationUpdateTime == nil)
    }

    @Test func `VehicleStatus loadReferences populates trip and regionIdentifier`() throws {
        let data = makeVehicleStatusJSON(tripID: "1_trip_ref")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let status = try decoder.decode(VehicleStatus.self, from: data)
        #expect(status.trip == nil)
        #expect(status.regionIdentifier == nil)

        let referencesData: [String: Any] = [
            "agencies": [],
            "routes": [],
            "stops": [],
            "trips": [
                [
                    "id": "1_trip_ref",
                    "routeId": "1_10",
                    "serviceId": "s1",
                    "tripHeadsign": "Downtown",
                    "routeShortName": "10",
                    "tripShortName": "10",
                    "blockId": "b1",
                    "timeZone": "America/Los_Angeles"
                ]
            ]
        ]
        let references = try Fixtures.dictionaryToModel(type: References.self, dictionary: referencesData)
        status.loadReferences(references, regionIdentifier: 42)

        #expect(status.regionIdentifier == 42)
        #expect(status.trip != nil)
        #expect(status.trip?.id == "1_trip_ref")
        #expect(status.trip?.tripHeadsign == "Downtown")
    }
}
