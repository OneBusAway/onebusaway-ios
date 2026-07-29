//
//  TransferContextTests.swift
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

// swiftlint:disable force_try

@Suite(.serialized)
final class TransferContextTests: OBATestCase {

    // MARK: - minutesUntilDeparture

    @Test func `Minutes until departure future positive`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        // Departure 10 minutes after arrival
        let departureDate = arrivalTime.addingTimeInterval(10 * 60)
        #expect(context.minutesUntilDeparture(from: departureDate) == 10)
    }

    @Test func `Minutes until departure past negative`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        // Departure 5 minutes before arrival
        let departureDate = arrivalTime.addingTimeInterval(-5 * 60)
        #expect(context.minutesUntilDeparture(from: departureDate) == -5)
    }

    @Test func `Minutes until departure exact zero`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        #expect(context.minutesUntilDeparture(from: arrivalTime) == 0)
    }

    // MARK: - temporalState

    @Test func `Temporal state future`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        let departureDate = arrivalTime.addingTimeInterval(5 * 60)
        #expect(context.temporalState(for: departureDate) == .future)
    }

    @Test func `Temporal state past`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        let departureDate = arrivalTime.addingTimeInterval(-3 * 60)
        #expect(context.temporalState(for: departureDate) == .past)
    }

    @Test func `Temporal state present`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        #expect(context.temporalState(for: arrivalTime) == .present)
    }

    // MARK: - Edge cases

    @Test func `Minutes until departure rounds toward zero`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        // 90 seconds = 1.5 minutes, Int truncation -> 1
        let departureDate = arrivalTime.addingTimeInterval(90)
        #expect(context.minutesUntilDeparture(from: departureDate) == 1)
    }

    @Test func `Minutes until departure negative fractional rounds toward zero`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        // -90 seconds = -1.5 minutes, Int truncation toward zero -> -1
        let departureDate = arrivalTime.addingTimeInterval(-90)
        #expect(context.minutesUntilDeparture(from: departureDate) == -1)
    }

    @Test func `Minutes until departure large offset`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        // 2 hours after arrival
        let departureDate = arrivalTime.addingTimeInterval(120 * 60)
        #expect(context.minutesUntilDeparture(from: departureDate) == 120)
    }

    // MARK: - Factory method

    @Test func `From factory populates fields correctly`() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)

        // Use the Fixtures-loaded ArrivalDeparture to test the factory.
        let stopArrivals = try! Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_75414.json"
        )
        let arrDep = stopArrivals.arrivalsAndDepartures.first!

        let context = TransferContext.from(arrivalDeparture: arrDep, arrivalDate: arrivalTime)

        #expect(context.arrivalTime == arrivalTime)
        #expect(context.fromRouteShortName == arrDep.routeShortName)
        #expect(context.fromTripHeadsign == (arrDep.tripHeadsign ?? ""))
        // fromRouteDisplay is now computed from the component fields.
        let expectedDisplay = [arrDep.routeShortName, arrDep.tripHeadsign ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        #expect(context.fromRouteDisplay == expectedDisplay)
    }
}
