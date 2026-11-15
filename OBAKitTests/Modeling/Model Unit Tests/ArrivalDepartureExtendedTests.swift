//
//  ArrivalDepartureExtendedTests.swift
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
final class ArrivalDepartureExtendedTests: OBATestCase {

    private func makeArrivalDeparture(
        stopSequence: Int,
        totalStopsInTrip: Int? = nil,
        predicted: Bool = true,
        scheduledArrival: Date = Date(),
        scheduledDeparture: Date = Date(),
        predictedArrival: Date? = nil,
        predictedDeparture: Date? = nil,
        occupancy: String? = nil
    ) throws -> ArrivalDeparture {
        var dict: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 500.0,
            "lastUpdateTime": Int(Date().timeIntervalSince1970 * 1000),
            "numberOfStopsAway": 2,
            "predicted": predicted,
            "routeId": "route_10",
            "scheduledArrivalTime": Int(scheduledArrival.timeIntervalSince1970 * 1000),
            "scheduledDepartureTime": Int(scheduledDeparture.timeIntervalSince1970 * 1000),
            "serviceDate": Int(Date().timeIntervalSince1970 * 1000),
            "situationIds": [],
            "status": "default",
            "stopId": "stop_100",
            "stopSequence": stopSequence,
            "tripId": "trip_999",
            "vehicleId": "veh_1"
        ]

        if let totalStopsInTrip {
            dict["totalStopsInTrip"] = totalStopsInTrip
        }
        if let predictedArrival {
            dict["predictedArrivalTime"] = Int(predictedArrival.timeIntervalSince1970 * 1000)
        }
        if let predictedDeparture {
            dict["predictedDepartureTime"] = Int(predictedDeparture.timeIntervalSince1970 * 1000)
        }
        if let occupancy {
            dict["occupancyStatus"] = occupancy
        }

        let routeData: [String: Any] = [
            "id": "route_10",
            "shortName": "10",
            "longName": "Route 10",
            "type": 3
        ]
        let stopData: [String: Any] = [
            "id": "stop_100",
            "name": "Pine St & 4th Ave",
            "lat": 47.61,
            "lon": -122.33,
            "direction": "NB",
            "code": "100",
            "routeIds": ["route_10"]
        ]
        let tripData: [String: Any] = [
            "id": "trip_999",
            "routeId": "route_10",
            "tripHeadsign": "Downtown",
            "serviceId": "s1",
            "directionId": "0"
        ]

        let arrival = try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: dict)
        let route = try Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        let stop = try Fixtures.dictionaryToModel(type: Stop.self, dictionary: stopData)
        let trip = try Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)

        let references = References(agencies: [], routes: [route], situations: [], stops: [stop], trips: [trip])
        arrival.loadReferences(references, regionIdentifier: 1)
        return arrival
    }

    @Test func `Stop sequence 0 resolves to departing status`() throws {
        let departure = try makeArrivalDeparture(stopSequence: 0)
        #expect(departure.arrivalDepartureStatus == .departing)
    }

    @Test func `Stop sequence greater than 0 resolves to arriving status`() throws {
        let arrival = try makeArrivalDeparture(stopSequence: 3)
        #expect(arrival.arrivalDepartureStatus == .arriving)
    }

    @Test func `Last stop on trip resolution verifies boundary`() throws {
        let lastStopArrival = try makeArrivalDeparture(stopSequence: 9, totalStopsInTrip: 10)
        #expect(lastStopArrival.isLastStopOnTrip == true)

        let intermediateArrival = try makeArrivalDeparture(stopSequence: 4, totalStopsInTrip: 10)
        #expect(intermediateArrival.isLastStopOnTrip == false)

        let unknownTotalArrival = try makeArrivalDeparture(stopSequence: 4, totalStopsInTrip: nil)
        #expect(unknownTotalArrival.isLastStopOnTrip == nil)
    }

    @Test func `Predicted arrival scheduleStatus boundary early onTime delayed`() throws {
        let now = Date()
        let scheduled = now.addingTimeInterval(600) // 10 min away

        // 3 minutes early (-3.0 min deviation)
        let earlyArrival = try makeArrivalDeparture(
            stopSequence: 2,
            predicted: true,
            scheduledArrival: scheduled,
            predictedArrival: scheduled.addingTimeInterval(-180)
        )
        #expect(earlyArrival.scheduleStatus == .early)

        // 1 minute late (+1.0 min deviation -> within [-1.5, 1.5] on time window)
        let onTimeArrival = try makeArrivalDeparture(
            stopSequence: 2,
            predicted: true,
            scheduledArrival: scheduled,
            predictedArrival: scheduled.addingTimeInterval(60)
        )
        #expect(onTimeArrival.scheduleStatus == .onTime)

        // 5 minutes late (+5.0 min deviation -> delayed)
        let delayedArrival = try makeArrivalDeparture(
            stopSequence: 2,
            predicted: true,
            scheduledArrival: scheduled,
            predictedArrival: scheduled.addingTimeInterval(300)
        )
        #expect(delayedArrival.scheduleStatus == .delayed)
    }

    @Test func `Non-predicted arrival always returns unknown scheduleStatus`() throws {
        let nonPredicted = try makeArrivalDeparture(
            stopSequence: 2,
            predicted: false,
            scheduledArrival: Date().addingTimeInterval(600)
        )
        #expect(nonPredicted.scheduleStatus == .unknown)
    }

    @Test func `Occupancy status maps enum properly from raw strings`() throws {
        let fullOccupancy = try makeArrivalDeparture(stopSequence: 1, occupancy: "FULL")
        #expect(fullOccupancy.occupancyStatus == .full)

        let emptyOccupancy = try makeArrivalDeparture(stopSequence: 1, occupancy: "EMPTY")
        #expect(emptyOccupancy.occupancyStatus == .empty)

        let unknownOccupancy = try makeArrivalDeparture(stopSequence: 1, occupancy: "")
        #expect(unknownOccupancy.occupancyStatus == .unknown)
    }
}
