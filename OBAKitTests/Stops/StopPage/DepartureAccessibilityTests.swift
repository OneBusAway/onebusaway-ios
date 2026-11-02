//
//  DepartureAccessibilityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class DepartureAccessibilityTests {

    private func makeArrivalDeparture(
        predicted: Bool,
        occupancy: ArrivalDeparture.OccupancyStatus? = nil
    ) throws -> ArrivalDeparture {
        var dictionary: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": 1_700_000_000,
            "numberOfStopsAway": 1,
            "predicted": predicted,
            "routeId": "1_100",
            "scheduledArrivalTime": 1_700_000_000,
            "scheduledDepartureTime": 1_700_000_000,
            "serviceDate": 1_700_000_000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "1_999",
            "stopSequence": 1,
            "tripId": "1_1000",
            "vehicleId": "vehicle_1"
        ]
        if let occupancy {
            dictionary["occupancyStatus"] = occupancy.rawValue
        }
        return try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: dictionary)
    }

    private var dummyTimeDisplay: DepartureTimeDisplay {
        DepartureTimeDisplay(
            scheduledTime: "10:30 AM",
            predictedTime: nil,
            accessibilityTimeDescription: "at 10:30 AM"
        )
    }

    @Test func testRealtimeWithKnownOccupancyIncludesOccupancy() throws {
        let departure = try makeArrivalDeparture(predicted: true, occupancy: .manySeatsAvailable)
        let status = DepartureStatus(arrivalDeparture: departure)
        #expect(status.showsOccupancy)

        let label = DepartureAccessibility.label(
            identity: "Route 10 to Downtown departs in 5 minutes",
            departure: departure,
            status: status,
            timeDisplay: dummyTimeDisplay
        )

        let expectedOccupancy = OccupancyBadge.localizedDescription(.manySeatsAvailable)
        #expect(label == "Route 10 to Downtown departs in 5 minutes, at 10:30 AM, \(expectedOccupancy)")
    }

    @Test func testScheduledOnlyOmitsOccupancyEvenWhenOccupancyIsPresent() throws {
        let departure = try makeArrivalDeparture(predicted: false, occupancy: .standingRoomOnly)
        let status = DepartureStatus(arrivalDeparture: departure)
        #expect(!status.showsOccupancy)

        let label = DepartureAccessibility.label(
            identity: "Route 10 to Downtown departs in 5 minutes",
            departure: departure,
            status: status,
            timeDisplay: dummyTimeDisplay
        )

        #expect(label == "Route 10 to Downtown departs in 5 minutes, at 10:30 AM")
    }

    @Test func testRealtimeWithUnknownOrNilOccupancyOmitsOccupancy() throws {
        let departureWithUnknown = try makeArrivalDeparture(predicted: true, occupancy: .unknown)
        let statusWithUnknown = DepartureStatus(arrivalDeparture: departureWithUnknown)

        let labelWithUnknown = DepartureAccessibility.label(
            identity: "Route 10 departs in 5 minutes",
            departure: departureWithUnknown,
            status: statusWithUnknown,
            timeDisplay: dummyTimeDisplay
        )
        #expect(labelWithUnknown == "Route 10 departs in 5 minutes, at 10:30 AM")

        let departureWithNil = try makeArrivalDeparture(predicted: true, occupancy: nil)
        let statusWithNil = DepartureStatus(arrivalDeparture: departureWithNil)

        let labelWithNil = DepartureAccessibility.label(
            identity: "Route 10 departs in 5 minutes",
            departure: departureWithNil,
            status: statusWithNil,
            timeDisplay: dummyTimeDisplay
        )
        #expect(labelWithNil == "Route 10 departs in 5 minutes, at 10:30 AM")
    }

    @Test func testExtraClausesAreAppendedAtEnd() throws {
        let departure = try makeArrivalDeparture(predicted: true, occupancy: .fewSeatsAvailable)
        let status = DepartureStatus(arrivalDeparture: departure)

        let label = DepartureAccessibility.label(
            identity: "Route 10 arrives now",
            departure: departure,
            status: status,
            timeDisplay: dummyTimeDisplay,
            extraClauses: ["Alarm set for 5 minutes before", "Likely missed"]
        )

        let expectedOccupancy = OccupancyBadge.localizedDescription(.fewSeatsAvailable)
        #expect(label == "Route 10 arrives now, at 10:30 AM, \(expectedOccupancy), Alarm set for 5 minutes before, Likely missed")
    }
}
