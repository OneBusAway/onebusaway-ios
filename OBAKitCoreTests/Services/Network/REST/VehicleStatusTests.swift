//
//  VehicleStatusTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import OBAKitCore

final class VehicleStatusTests: OBAKitCoreTestCase {
    let vehicleID = "1_4351"
    lazy var apiPath = "https://www.example.com/api/where/vehicle/\(vehicleID).json"

    func testVehicleStatus() async throws {
        dataLoader.mock(URLString: apiPath, with: try Fixtures.loadData(file: "api_where_vehicle_1_4351.json"))

        let vehicle = try await restAPIService.getVehicle(vehicleID: vehicleID).entry
        XCTAssertEqual(vehicle.lastLocationUpdateTime, Date(timeIntervalSinceReferenceDate: 610581544), "Expected lastLocationUpdateTime to be 2020-05-07T21:59:04Z")
        XCTAssertEqual(vehicle.lastUpdateTime, Date(timeIntervalSinceReferenceDate: 610581544), "Expected lastUpdateTime to be 2020-05-07T21:59:04Z")

        let location = try XCTUnwrap(vehicle.location)
        XCTAssertEqual(location.latitude, 47.6195, accuracy: 0.0001)
        XCTAssertEqual(location.longitude, -122.3244, accuracy: 0.0001)
        XCTAssertEqual(vehicle.phase, "in_progress")
        XCTAssertEqual(vehicle.status, "SCHEDULED")
    }

    func testTripStatus() async throws {
        dataLoader.mock(URLString: apiPath, with: try Fixtures.loadData(file: "api_where_vehicle_1_4351.json"))

        let vehicle = try await restAPIService.getVehicle(vehicleID: vehicleID).entry
        XCTAssertEqual(vehicle.id, "1_4351")

        XCTAssertEqual(vehicle.tripID, "1_47649081")
        XCTAssertEqual(vehicle.phase, "in_progress")
        XCTAssertEqual(vehicle.status, "SCHEDULED")

        let tripStatus = vehicle.tripStatus
        XCTAssertEqual(tripStatus.activeTripID, "1_47649081")
        XCTAssertEqual(tripStatus.blockTripSequence, 19)
        XCTAssertEqual(tripStatus.closestStopID, "1_29266")
        XCTAssertEqual(tripStatus.closestStopTimeOffset, 23)
        XCTAssertEqual(tripStatus.distanceAlongTrip, 2277.5779, accuracy: 0.0001)
        XCTAssertEqual(tripStatus.lastKnownDistanceAlongTrip, 0)
        XCTAssertEqual(tripStatus.lastKnownOrientation, 0)
        XCTAssertEqual(tripStatus.lastLocationUpdateTime, 1588888744000)
        XCTAssertEqual(tripStatus.lastUpdate, Date(timeIntervalSince1970: 1588888744))
        XCTAssertEqual(tripStatus.nextStopID, "1_29266")
        XCTAssertEqual(tripStatus.nextStopTimeOffset, 23)
        XCTAssertEqual(tripStatus.orientation, 204.6164, accuracy: 0.0001)
        XCTAssertEqual(tripStatus.phase, "in_progress")
        XCTAssertTrue(tripStatus.isRealTime)
        XCTAssertEqual(tripStatus.scheduleDeviation, -116)
        XCTAssertEqual(tripStatus.scheduledDistanceAlongTrip, 2277.5779, accuracy: 0.0001)
        XCTAssertEqual(tripStatus.serviceDate, Date(timeIntervalSince1970: 1588834800))
        XCTAssertEqual(tripStatus.situationIDs.count, 1)
        XCTAssertEqual(tripStatus.statusModifier, .scheduled)
        XCTAssertEqual(tripStatus.totalDistanceAlongTrip, 3302.4674, accuracy: 0.0001)
        XCTAssertEqual(tripStatus.vehicleID, "1_4351")

        let lastKnownLocation = try XCTUnwrap(tripStatus.lastKnownLocation)
        XCTAssertEqual(lastKnownLocation.latitude, 47.61949539, accuracy: 0.000001)
        XCTAssertEqual(lastKnownLocation.longitude, -122.32442474, accuracy: 0.000001)

        let position = try XCTUnwrap(tripStatus.position)
        XCTAssertEqual(position.latitude, 47.6195, accuracy: 0.0001)
        XCTAssertEqual(position.longitude, -122.3244, accuracy: 0.0001)
    }

    func testVehicleFrequency() async throws {
        dataLoader.mock(URLString: "https://www.example.com/api/where/vehicle/\(vehicleID).json", with: try Fixtures.loadData(file: "frequency-vehicle.json"))

        let response = try await restAPIService.getVehicle(vehicleID: vehicleID)
        let frequency = try XCTUnwrap(response.entry.tripStatus.frequency)

        XCTAssertEqual(frequency.startTime, Date(timeIntervalSince1970: 1289579400))
        XCTAssertEqual(frequency.endTime, Date(timeIntervalSince1970: 1289602799))
        XCTAssertEqual(frequency.headway, 600)
    }
}
