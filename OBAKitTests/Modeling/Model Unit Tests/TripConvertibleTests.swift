//
//  TripConvertibleTests.swift
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

@Suite(.serialized)
final class TripConvertibleTests {

    // MARK: - Initializer with ArrivalDeparture

    @Test func `Initialize with ArrivalDeparture`() throws {
        let arrDep = try Fixtures.arrivalDeparture(
            stopSequence: 3,
            stopID: "1_100",
            routeID: "1_10",
            tripID: "1_trip_999",
            vehicleID: "1_coach_40"
        )

        let convertible = TripConvertible(arrivalDeparture: arrDep)

        #expect(convertible.arrivalDeparture === arrDep)
        #expect(convertible.vehicleStatus == nil)
        #expect(convertible.tripDetails == nil)

        #expect(convertible.tripID == "1_trip_999")
        #expect(convertible.vehicleID == "1_coach_40")
        #expect(convertible.serviceDate == arrDep.serviceDate)
        #expect(convertible.tripStatus == arrDep.tripStatus)
    }

    // MARK: - Initializer with TripDetails

    @Test func `Initialize with TripDetails`() throws {
        let data = Fixtures.loadData(file: "trip_details_1_18196913.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data)
        let details = response.entry

        let convertible = TripConvertible(tripDetails: details)

        #expect(convertible.tripDetails === details)
        #expect(convertible.arrivalDeparture == nil)
        #expect(convertible.vehicleStatus == nil)

        #expect(convertible.tripID == details.tripID)
        #expect(convertible.serviceDate == details.serviceDate)
        #expect(convertible.tripStatus == details.status)
        #expect(convertible.vehicleID == details.status?.vehicleID)
    }

    // MARK: - Initializer with VehicleStatus

    @Test func `Initialize with VehicleStatus having loaded trip`() throws {
        let data = Fixtures.loadData(file: "api_where_vehicle_1_4351.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<VehicleStatus>.self, from: data)
        let vehicle = response.entry

        // Pre-condition: trip must be loaded from references
        let trip = try #require(vehicle.trip)
        #expect(trip.id == "1_47649081")

        let convertible = try #require(TripConvertible(vehicleStatus: vehicle))

        #expect(convertible.vehicleStatus === vehicle)
        #expect(convertible.arrivalDeparture == nil)
        #expect(convertible.tripDetails == nil)

        #expect(convertible.tripID == "1_47649081")
        #expect(convertible.vehicleID == vehicle.vehicleID)
        #expect(convertible.serviceDate == vehicle.tripStatus.serviceDate)
        #expect(convertible.tripStatus == vehicle.tripStatus)
        #expect(convertible.trip == trip)
    }

    @Test func `Initialize with VehicleStatus without trip returns nil`() throws {
        // Build a VehicleStatus without loading references so vehicleStatus.trip is nil
        let vehicleData: [String: Any] = [
            "vehicleId": "1_9999",
            "lastUpdateTime": 1588888744000,
            "phase": "in_progress",
            "status": "SCHEDULED",
            "tripId": "1_isolated_trip",
            "tripStatus": [
                "activeTripId": "1_isolated_trip",
                "blockTripSequence": 1,
                "closestStop": "1_100",
                "closestStopTimeOffset": 0,
                "distanceAlongTrip": 100.0,
                "lastKnownDistanceAlongTrip": 0.0,
                "lastKnownOrientation": 0.0,
                "lastLocationUpdateTime": 1588888744000,
                "lastUpdateTime": 1588888744000,
                "nextStop": "1_101",
                "nextStopTimeOffset": 60,
                "orientation": 0.0,
                "phase": "in_progress",
                "predicted": true,
                "scheduleDeviation": 0,
                "scheduledDistanceAlongTrip": 100.0,
                "serviceDate": 1588834800000,
                "situationIds": [],
                "status": "SCHEDULED",
                "totalDistanceAlongTrip": 1000.0,
                "vehicleId": "1_9999"
            ]
        ]

        let vehicle = try Fixtures.dictionaryToModel(type: VehicleStatus.self, dictionary: vehicleData)
        #expect(vehicle.trip == nil)

        // Fails safely by returning nil per guard vehicleStatus.trip != nil
        let convertible = TripConvertible(vehicleStatus: vehicle)
        #expect(convertible == nil)
    }
}
