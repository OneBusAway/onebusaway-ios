//
//  DestinationArrivalTests.swift
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

/// `DestinationArrival.estimate` turns a departure from a bookmark's origin
/// plus its trip's schedule into an arrival at the bookmark's destination (#1080).
struct DestinationArrivalTests {

    /// Service date for every schedule below. `Fixtures.arrivalDeparture` takes
    /// seconds since the 2001 reference date, so times are built the same way.
    private let serviceDate = Date(timeIntervalSinceReferenceDate: 1_700_000_000)

    /// Builds a trip's stop times, one stop every 10 minutes from the service date.
    private func stopTimes(_ stopIDs: [String]) throws -> [TripStopTime] {
        try stopIDs.enumerated().map { index, stopID in
            let seconds = index * 600
            let stopTime = try Fixtures.dictionaryToModel(
                type: TripStopTime.self,
                dictionary: ["stopId": stopID, "arrivalTime": seconds, "departureTime": seconds]
            )
            stopTime.serviceDate = serviceDate
            return stopTime
        }
    }

    /// Seconds-since-reference-date for the stop at `index` in `stopTimes(_:)`.
    private func scheduledTime(atIndex index: Int) -> Int {
        Int(serviceDate.timeIntervalSinceReferenceDate) + index * 600
    }

    private func origin(stopID: String, stopSequence: Int, delay: Int?) throws -> ArrivalDeparture {
        let scheduled = scheduledTime(atIndex: stopSequence)
        return try Fixtures.arrivalDeparture(
            predicted: delay != nil,
            scheduledArrival: scheduled,
            predictedArrival: delay.map { scheduled + $0 },
            scheduledDeparture: scheduled,
            predictedDeparture: delay.map { scheduled + $0 },
            stopSequence: stopSequence,
            stopID: stopID
        )
    }

    @Test func `A late trip arrives late at the destination by the same amount`() throws {
        let schedule = try stopTimes(["a", "b", "origin", "d", "home"])
        let departure = try origin(stopID: "origin", stopSequence: 2, delay: 300)

        let arrival = try #require(DestinationArrival.estimate(origin: departure, stopTimes: schedule, destinationStopID: "home"))

        let scheduledArrival = Date(timeIntervalSinceReferenceDate: TimeInterval(scheduledTime(atIndex: 4)))
        #expect(arrival.scheduledArrivalDate == scheduledArrival)
        #expect(arrival.arrivalDate == scheduledArrival.addingTimeInterval(300))
        #expect(arrival.isRealTime)
    }

    @Test func `An early trip arrives early at the destination`() throws {
        let schedule = try stopTimes(["a", "b", "origin", "d", "home"])
        let departure = try origin(stopID: "origin", stopSequence: 2, delay: -120)

        let arrival = try #require(DestinationArrival.estimate(origin: departure, stopTimes: schedule, destinationStopID: "home"))

        #expect(arrival.arrivalDate == arrival.scheduledArrivalDate.addingTimeInterval(-120))
    }

    @Test func `Without real-time data the scheduled arrival is used`() throws {
        let schedule = try stopTimes(["a", "b", "origin", "d", "home"])
        let departure = try origin(stopID: "origin", stopSequence: 2, delay: nil)

        let arrival = try #require(DestinationArrival.estimate(origin: departure, stopTimes: schedule, destinationStopID: "home"))

        #expect(arrival.arrivalDate == arrival.scheduledArrivalDate)
        #expect(arrival.isRealTime == false)
    }

    @Test func `A trip that never visits the destination has no arrival`() throws {
        let schedule = try stopTimes(["a", "b", "origin", "d"])
        let departure = try origin(stopID: "origin", stopSequence: 2, delay: 0)

        #expect(DestinationArrival.estimate(origin: departure, stopTimes: schedule, destinationStopID: "home") == nil)
    }

    /// The destination must be downstream: a stop the bus has already passed
    /// is not somewhere this departure can take the rider.
    @Test func `A destination before the origin has no arrival`() throws {
        let schedule = try stopTimes(["home", "b", "origin", "d"])
        let departure = try origin(stopID: "origin", stopSequence: 2, delay: 0)

        #expect(DestinationArrival.estimate(origin: departure, stopTimes: schedule, destinationStopID: "home") == nil)
    }

    /// On a loop trip that visits the destination both before and after the
    /// origin, only the later visit is reachable.
    @Test func `A loop trip uses the visit to the destination after the origin`() throws {
        let schedule = try stopTimes(["a", "home", "origin", "d", "home"])
        let departure = try origin(stopID: "origin", stopSequence: 2, delay: 0)

        let arrival = try #require(DestinationArrival.estimate(origin: departure, stopTimes: schedule, destinationStopID: "home"))

        #expect(arrival.scheduledArrivalDate == Date(timeIntervalSinceReferenceDate: TimeInterval(scheduledTime(atIndex: 4))))
    }

    /// The origin is found by `stopSequence`, so a loop trip that visits the
    /// origin twice measures from the visit the rider is actually boarding.
    @Test func `A loop trip that revisits the origin measures from the boarding visit`() throws {
        let schedule = try stopTimes(["origin", "home", "b", "origin", "c"])
        let departure = try origin(stopID: "origin", stopSequence: 3, delay: 0)

        #expect(DestinationArrival.estimate(origin: departure, stopTimes: schedule, destinationStopID: "home") == nil)
    }

    /// If the sequence doesn't line up with the schedule, the first visit to
    /// the origin stop is used rather than giving up.
    @Test func `A stop sequence that disagrees with the schedule falls back to the origin's stop ID`() throws {
        let schedule = try stopTimes(["a", "origin", "home"])
        let departure = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: scheduledTime(atIndex: 1),
            scheduledDeparture: scheduledTime(atIndex: 1),
            stopSequence: 7,
            stopID: "origin"
        )

        let arrival = try #require(DestinationArrival.estimate(origin: departure, stopTimes: schedule, destinationStopID: "home"))

        #expect(arrival.scheduledArrivalDate == Date(timeIntervalSinceReferenceDate: TimeInterval(scheduledTime(atIndex: 2))))
    }
}
