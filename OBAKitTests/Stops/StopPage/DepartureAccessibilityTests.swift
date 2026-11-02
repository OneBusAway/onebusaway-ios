//
//  DepartureAccessibilityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class DepartureAccessibilityTests {

    private func makeArrivalDeparture(
        predicted: Bool,
        occupancy: ArrivalDeparture.OccupancyStatus? = nil
    ) -> ArrivalDeparture {
        ArrivalDeparture(
            routeID: "1_100",
            routeShortName: "10",
            tripID: "1_1000",
            serviceDate: Date(),
            stopID: "1_999",
            stopSequence: 1,
            blockTripSequence: 1,
            routeLongName: "Downtown",
            arrivalDepartureStatus: .departing,
            predicted: predicted,
            predictedDepartureDate: predicted ? Date().addingTimeInterval(300) : nil,
            scheduledDepartureDate: Date().addingTimeInterval(300),
            occupancyStatus: occupancy
        )
    }

    private var dummyTimeDisplay: DepartureTimeDisplay {
        DepartureTimeDisplay(
            scheduledTime: "10:30 AM",
            predictedTime: nil,
            accessibilityTimeDescription: "at 10:30 AM"
        )
    }

    @Test func testRealtimeWithKnownOccupancyIncludesOccupancy() {
        let departure = makeArrivalDeparture(predicted: true, occupancy: .manySeatsAvailable)
        let status = DepartureStatus(arrivalDeparture: departure)
        #expect(status.showsOccupancy)

        let label = DepartureAccessibility.label(
            identity: "Route 10 to Downtown departs in 5 minutes",
            departure: departure,
            status: status,
            timeDisplay: dummyTimeDisplay
        )

        #expect(label == "Route 10 to Downtown departs in 5 minutes, at 10:30 AM, Many seats available")
    }

    @Test func testScheduledOnlyOmitsOccupancyEvenWhenOccupancyIsPresent() {
        let departure = makeArrivalDeparture(predicted: false, occupancy: .standingRoomOnly)
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

    @Test func testRealtimeWithUnknownOrNilOccupancyOmitsOccupancy() {
        let departureWithUnknown = makeArrivalDeparture(predicted: true, occupancy: .unknown)
        let statusWithUnknown = DepartureStatus(arrivalDeparture: departureWithUnknown)

        let labelWithUnknown = DepartureAccessibility.label(
            identity: "Route 10 departs in 5 minutes",
            departure: departureWithUnknown,
            status: statusWithUnknown,
            timeDisplay: dummyTimeDisplay
        )
        #expect(labelWithUnknown == "Route 10 departs in 5 minutes, at 10:30 AM")

        let departureWithNil = makeArrivalDeparture(predicted: true, occupancy: nil)
        let statusWithNil = DepartureStatus(arrivalDeparture: departureWithNil)

        let labelWithNil = DepartureAccessibility.label(
            identity: "Route 10 departs in 5 minutes",
            departure: departureWithNil,
            status: statusWithNil,
            timeDisplay: dummyTimeDisplay
        )
        #expect(labelWithNil == "Route 10 departs in 5 minutes, at 10:30 AM")
    }

    @Test func testExtraClausesAreAppendedAtEnd() {
        let departure = makeArrivalDeparture(predicted: true, occupancy: .fewSeatsAvailable)
        let status = DepartureStatus(arrivalDeparture: departure)

        let label = DepartureAccessibility.label(
            identity: "Route 10 arrives now",
            departure: departure,
            status: status,
            timeDisplay: dummyTimeDisplay,
            extraClauses: ["Alarm set for 5 minutes before", "Likely missed"]
        )

        #expect(label == "Route 10 arrives now, at 10:30 AM, Few seats available, Alarm set for 5 minutes before, Likely missed")
    }
}
