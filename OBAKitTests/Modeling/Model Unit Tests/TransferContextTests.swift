//
//  TransferContextTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKitCore

class TransferContextTests: XCTestCase {

    // MARK: - minutesUntilDeparture

    func test_minutesUntilDeparture_futurePositive() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromRouteDisplay: "10 - Capitol Hill"
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
            fromTripHeadsign: "Capitol Hill",
            fromRouteDisplay: "10 - Capitol Hill"
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
            fromTripHeadsign: "Capitol Hill",
            fromRouteDisplay: "10 - Capitol Hill"
        )
        XCTAssertEqual(context.minutesUntilDeparture(from: arrivalTime), 0)
    }

    // MARK: - temporalState

    func test_temporalState_future() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromRouteDisplay: "10 - Capitol Hill"
        )
        let departureDate = arrivalTime.addingTimeInterval(5 * 60)
        XCTAssertEqual(context.temporalState(for: departureDate), .future)
    }

    func test_temporalState_past() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromRouteDisplay: "10 - Capitol Hill"
        )
        let departureDate = arrivalTime.addingTimeInterval(-3 * 60)
        XCTAssertEqual(context.temporalState(for: departureDate), .past)
    }

    func test_temporalState_present() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromRouteDisplay: "10 - Capitol Hill"
        )
        XCTAssertEqual(context.temporalState(for: arrivalTime), .present)
    }

    // MARK: - Edge cases

    func test_minutesUntilDeparture_roundsTowardZero() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromRouteDisplay: "10 - Capitol Hill"
        )
        // 90 seconds = 1.5 minutes, Int truncation -> 1
        let departureDate = arrivalTime.addingTimeInterval(90)
        XCTAssertEqual(context.minutesUntilDeparture(from: departureDate), 1)
    }

    func test_minutesUntilDeparture_largeOffset() {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        let context = TransferContext(
            arrivalTime: arrivalTime,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromRouteDisplay: "10 - Capitol Hill"
        )
        // 2 hours after arrival
        let departureDate = arrivalTime.addingTimeInterval(120 * 60)
        XCTAssertEqual(context.minutesUntilDeparture(from: departureDate), 120)
    }
}
