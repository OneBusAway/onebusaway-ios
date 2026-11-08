//
//  ArrivalDeparturePipelineTests.swift
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
final class ArrivalDeparturePipelineTests {

    // MARK: - filteringImplausibleDates

    @Test func `filteringImplausibleDates drops pre-epoch sentinel entries`() throws {
        // Earliest plausible date is Date(timeIntervalSinceReferenceDate: 1.0)
        let validFuture = try Fixtures.arrivalDeparture(
            scheduledArrival: 1_700_000_000,
            scheduledDeparture: 1_700_000_000,
            stopID: "stop_1",
            tripID: "trip_valid"
        )

        // Unix epoch 0 (1970) is ~31 years before reference date (2001)
        let epochSentinel = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: 0,
            scheduledDeparture: 0,
            stopID: "stop_1",
            tripID: "trip_epoch"
        )

        let list = [epochSentinel, validFuture]
        let filtered = list.filteringImplausibleDates()

        #expect(filtered.count == 1)
        #expect(filtered.first?.tripID == "trip_valid")
    }

    @Test func `filteringImplausibleDates on empty list returns empty`() {
        let empty: [ArrivalDeparture] = []
        #expect(empty.filteringImplausibleDates().isEmpty)
    }

    // MARK: - filteringDuplicateVehicleReports

    @Test func `filteringDuplicateVehicleReports preserves newer lastUpdated timestamp`() throws {
        // Duplicate ID: same stop, trip, route, serviceDate, stopSequence, and status
        let older = try Fixtures.arrivalDeparture(
            scheduledArrival: 1_700_000_000,
            stopSequence: 1,
            stopID: "stop_1",
            routeID: "route_1",
            tripID: "trip_dup",
            vehicleID: "coach_ghost"
        )

        // Construct another entry with identical ID elements but higher lastUpdateTime
        let newerDict: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 50.0,
            "lastUpdateTime": 1_700_000_500, // Newer than 1_700_000_000
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_1",
            "scheduledArrivalTime": 1_700_000_000,
            "scheduledDepartureTime": 1_700_000_000,
            "serviceDate": 1_700_000_000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_1",
            "stopSequence": 1,
            "tripId": "trip_dup",
            "vehicleId": "coach_real"
        ]
        let newer = try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: newerDict)

        #expect(older.id == newer.id)
        #expect(newer.lastUpdated > older.lastUpdated)

        let list = [older, newer]
        let deduplicated = list.filteringDuplicateVehicleReports()

        #expect(deduplicated.count == 1)
        #expect(deduplicated[0].vehicleID == "coach_real")
        #expect(deduplicated[0].lastUpdated == newer.lastUpdated)
    }

    @Test func `filteringDuplicateVehicleReports keeps first occurrence when incoming is older`() throws {
        let newerDict: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 50.0,
            "lastUpdateTime": 1_700_000_500,
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_1",
            "scheduledArrivalTime": 1_700_000_000,
            "scheduledDepartureTime": 1_700_000_000,
            "serviceDate": 1_700_000_000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_1",
            "stopSequence": 1,
            "tripId": "trip_dup",
            "vehicleId": "coach_real"
        ]
        let newer = try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: newerDict)

        let older = try Fixtures.arrivalDeparture(
            scheduledArrival: 1_700_000_000,
            stopSequence: 1,
            stopID: "stop_1",
            routeID: "route_1",
            tripID: "trip_dup",
            vehicleID: "coach_ghost"
        )

        let list = [newer, older]
        let deduplicated = list.filteringDuplicateVehicleReports()

        #expect(deduplicated.count == 1)
        #expect(deduplicated[0].vehicleID == "coach_real")
    }

    @Test func `filteringDuplicateVehicleReports preserves distinct sequence and status`() throws {
        // Different stopSequence -> different IDs, should NOT be merged
        let seq1 = try Fixtures.arrivalDeparture(
            stopSequence: 1,
            stopID: "stop_loop",
            routeID: "route_1",
            tripID: "trip_loop"
        )
        let seq2 = try Fixtures.arrivalDeparture(
            stopSequence: 15,
            stopID: "stop_loop",
            routeID: "route_1",
            tripID: "trip_loop"
        )

        #expect(seq1.id != seq2.id)

        let list = [seq1, seq2]
        let deduplicated = list.filteringDuplicateVehicleReports()

        #expect(deduplicated.count == 2)
    }

    // MARK: - Terminal Duplicate Preference Matrix

    @Test func `filteringTerminalDuplicates prefers real-time over scheduled-only`() throws {
        // Both share (tripID, stopID, routeID)
        let scheduledOnly = try Fixtures.arrivalDeparture(
            predicted: false,
            stopSequence: 0,
            stopID: "terminal_stop",
            routeID: "route_1",
            tripID: "terminal_trip"
        )

        let realTime = try Fixtures.arrivalDeparture(
            predicted: true,
            stopSequence: 5,
            stopID: "terminal_stop",
            routeID: "route_1",
            tripID: "terminal_trip"
        )

        // Case A: scheduled first, then realtime -> candidate replaces existing
        let list1 = [scheduledOnly, realTime]
        let filtered1 = list1.filteringTerminalDuplicates()
        #expect(filtered1.count == 1)
        #expect(filtered1[0].predicted == true)

        // Case B: realtime first, then scheduled -> existing kept
        let list2 = [realTime, scheduledOnly]
        let filtered2 = list2.filteringTerminalDuplicates()
        #expect(filtered2.count == 1)
        #expect(filtered2[0].predicted == true)
    }

    @Test func `filteringTerminalDuplicates prefers departure over arrival when real-time tied`() throws {
        // Both predicted == true. Arrival (stopSequence > 0) vs Departure (stopSequence == 0).
        let arrival = try Fixtures.arrivalDeparture(
            predicted: true,
            stopSequence: 10,
            stopID: "terminal_stop",
            routeID: "route_1",
            tripID: "terminal_trip"
        )
        let departure = try Fixtures.arrivalDeparture(
            predicted: true,
            stopSequence: 0,
            stopID: "terminal_stop",
            routeID: "route_1",
            tripID: "terminal_trip"
        )

        #expect(arrival.arrivalDepartureStatus == .arriving)
        #expect(departure.arrivalDepartureStatus == .departing)

        // When arrival appears first, candidate departure replaces it
        let list = [arrival, departure]
        let filtered = list.filteringTerminalDuplicates()

        #expect(filtered.count == 1)
        #expect(filtered[0].arrivalDepartureStatus == .departing)
    }
}
