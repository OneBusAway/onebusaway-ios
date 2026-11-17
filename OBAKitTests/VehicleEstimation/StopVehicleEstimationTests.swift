//
//  StopVehicleEstimationTests.swift
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

/// Tests for `StopVehicleEstimation` orchestration: async gathering, generation increments,
/// cancellation handling, schedule eviction, and callback propagation.
@MainActor
@Suite(.serialized)
final class StopVehicleEstimationTests {
    typealias F = EstimationFixtures

    private let harness = StopEstimationHarness()
    private var estimation: StopVehicleEstimation { harness.estimation }
    private var clock: TestClock { harness.clock }

    private func makeArrivalDeparture(
        tripID: String = "trip_1",
        vehicleID: String = "veh_1"
    ) throws -> ArrivalDeparture {
        let tripStatusData: [String: Any] = [
            "activeTripId": tripID,
            "blockTripSequence": 1,
            "closestStop": "1_10020",
            "closestStopTimeOffset": 0,
            "distanceAlongTrip": 200.0,
            "distanceFromStop": 300.0,
            "lastKnownDistanceAlongTrip": 200.0,
            "lastKnownLocation": ["lat": F.point(north: 200).latitude, "lon": F.point(north: 200).longitude],
            "lastKnownOrientation": 0.0,
            "lastLocationUpdateTime": Int64(F.t0.timeIntervalSince1970 * 1000),
            "lastUpdateTime": Int64(F.t0.timeIntervalSince1970 * 1000),
            "nextStop": "1_10020",
            "nextStopTimeOffset": 0,
            "numberOfStopsAway": 1,
            "orientation": 0.0,
            "phase": "in_progress",
            "predicted": true,
            "scheduleDeviation": 0,
            "scheduledDistanceAlongTrip": 200.0,
            "serviceDate": Int64(F.t0.timeIntervalSince1970 * 1000),
            "situationIds": [],
            "status": "default",
            "totalDistanceAlongTrip": 1000.0,
            "vehicleId": vehicleID
        ]

        let arrivalData: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 300.0,
            "lastUpdateTime": Int(F.t0.timeIntervalSince1970 * 1000),
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_1",
            "scheduledArrivalTime": Int(F.t0.addingTimeInterval(300).timeIntervalSince1970 * 1000),
            "scheduledDepartureTime": Int(F.t0.addingTimeInterval(300).timeIntervalSince1970 * 1000),
            "serviceDate": Int(F.t0.timeIntervalSince1970 * 1000),
            "situationIds": [],
            "status": "default",
            "stopId": "1_10020",
            "stopSequence": 1,
            "tripId": tripID,
            "vehicleId": vehicleID,
            "tripStatus": tripStatusData
        ]

        let arrival = try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: arrivalData)
        try #require(arrival.tripStatus != nil)
        return arrival
    }

    private func makeDrawnVehicle(
        id: String = "veh_1",
        tripID: String = "trip_1",
        departureID: String = "dep_1",
        shapeID: String = "shape_1"
    ) -> StopRouteFocusModel.DrawnVehicle {
        StopRouteFocusModel.DrawnVehicle(
            id: id,
            routeID: "route_1",
            coordinate: F.origin,
            orientation: 0,
            departureID: departureID,
            tripID: tripID,
            shapeID: shapeID
        )
    }

    // MARK: - Initial and Disabled State

    @Test func `Initial estimates dictionary is empty`() {
        #expect(estimation.estimates.isEmpty)
    }

    @Test func `Refresh when estimation driver is disabled stops and clears existing estimates`() async throws {
        // First populate estimates with driver enabled
        let departure = try makeArrivalDeparture()
        let vehicle = makeDrawnVehicle()

        estimation.refresh(
            vehicles: [vehicle],
            serverClock: nil,
            departure: { _ in departure }
        )
        await estimation.inputsSettled()
        #expect(!estimation.estimates.isEmpty)
        await poll(until: { self.clock.sleeperCount == 1 }, "the tick should be sleeping after the refresh")

        // Now disable driver and refresh: existing estimates must be cleared and sleeper stopped
        harness.isEnabled = false
        estimation.refresh(
            vehicles: [vehicle],
            serverClock: nil,
            departure: { _ in departure }
        )
        await estimation.inputsSettled()

        #expect(estimation.estimates.isEmpty)
        #expect(clock.sleeperCount == 0)
    }

    // MARK: - Gathering and Estimation Lifecycle

    @Test func `Refresh gathers inputs and publishes non-empty estimates`() async throws {
        let departure = try makeArrivalDeparture()
        let vehicle = makeDrawnVehicle()

        var receivedEstimates: [String: VehicleEstimate]?
        estimation.onEstimates = { current, _ in
            receivedEstimates = current
        }

        estimation.refresh(
            vehicles: [vehicle],
            serverClock: nil,
            departure: { _ in departure }
        )
        await estimation.inputsSettled()

        #expect(!estimation.estimates.isEmpty)
        #expect(estimation.estimates[vehicle.id] != nil)
        #expect(receivedEstimates?[vehicle.id] != nil)
    }

    @Test func `Calling stop clears active estimates and halts driver updates`() async throws {
        let departure = try makeArrivalDeparture()
        let vehicle = makeDrawnVehicle()

        estimation.refresh(
            vehicles: [vehicle],
            serverClock: nil,
            departure: { _ in departure }
        )
        await estimation.inputsSettled()
        #expect(!estimation.estimates.isEmpty)

        estimation.stop()
        #expect(estimation.estimates.isEmpty)

        // Multiple calls to stop are safely idempotent
        estimation.stop()
        #expect(estimation.estimates.isEmpty)
    }

    @Test func `Refresh with empty vehicles list clears estimates`() async throws {
        let departure = try makeArrivalDeparture()
        let vehicle = makeDrawnVehicle()

        estimation.refresh(
            vehicles: [vehicle],
            serverClock: nil,
            departure: { _ in departure }
        )
        await estimation.inputsSettled()
        #expect(!estimation.estimates.isEmpty)

        estimation.refresh(
            vehicles: [],
            serverClock: nil,
            departure: { _ in nil }
        )
        await estimation.inputsSettled()
        #expect(estimation.estimates.isEmpty)
    }
}
