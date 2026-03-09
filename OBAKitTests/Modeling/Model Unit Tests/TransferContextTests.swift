//
//  TransferContextTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class TransferContextTests: OBATestCase {

    // MARK: - minutesUntilDeparture

    func test_minutesUntilDeparture_futurePositive() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        // Departure 10 minutes after arrival
        let departureDate = arrivalTime.addingTimeInterval(10 * 60)
        XCTAssertEqual(context.minutesUntilDeparture(from: departureDate), 10)
    }

    func test_minutesUntilDeparture_pastNegative() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        // Departure 5 minutes before arrival
        let departureDate = arrivalTime.addingTimeInterval(-5 * 60)
        XCTAssertEqual(context.minutesUntilDeparture(from: departureDate), -5)
    }

    func test_minutesUntilDeparture_exactZero() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        XCTAssertEqual(context.minutesUntilDeparture(from: arrivalTime), 0)
    }

    // MARK: - temporalState

    func test_temporalState_future() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        let departureDate = arrivalTime.addingTimeInterval(5 * 60)
        XCTAssertEqual(context.temporalState(for: departureDate), .future)
    }

    func test_temporalState_past() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        let departureDate = arrivalTime.addingTimeInterval(-3 * 60)
        XCTAssertEqual(context.temporalState(for: departureDate), .past)
    }

    func test_temporalState_present() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        XCTAssertEqual(context.temporalState(for: arrivalTime), .present)
    }

    // MARK: - Edge cases

    func test_minutesUntilDeparture_roundsTowardZero() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        // 90 seconds = 1.5 minutes, Int truncation -> 1
        let departureDate = arrivalTime.addingTimeInterval(90)
        XCTAssertEqual(context.minutesUntilDeparture(from: departureDate), 1)
    }

    func test_minutesUntilDeparture_negativeFractionalRoundsTowardZero() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromRouteDisplay: "10 - Capitol Hill"
        )
        // -90 seconds = -1.5 minutes, Int truncation toward zero -> -1
        let departureDate = arrivalTime.addingTimeInterval(-90)
        XCTAssertEqual(context.minutesUntilDeparture(from: departureDate), -1)
    }

    func test_minutesUntilDeparture_largeOffset() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        // 2 hours after arrival
        let departureDate = arrivalTime.addingTimeInterval(120 * 60)
        XCTAssertEqual(context.minutesUntilDeparture(from: departureDate), 120)
    }

    // MARK: - Factory method

    func test_fromFactory_populatesFieldsCorrectly() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)

        // Use the Fixtures-loaded ArrivalDeparture to test the factory.
        let stopArrivals = try! Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_75414.json"
        )
        let arrDep = stopArrivals.arrivalsAndDepartures.first!

        let context = TransferContext.from(arrivalDeparture: arrDep, arrivalDate: arrivalTime)

        XCTAssertEqual(context.arrivalTime, arrivalTime)
        XCTAssertEqual(context.fromRouteShortName, arrDep.routeShortName)
        XCTAssertEqual(context.fromTripHeadsign, arrDep.tripHeadsign ?? "")
        // fromRouteDisplay is now computed from the component fields.
        let expectedDisplay = [arrDep.routeShortName, arrDep.tripHeadsign ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        XCTAssertEqual(context.fromRouteDisplay, expectedDisplay)
    }
}
