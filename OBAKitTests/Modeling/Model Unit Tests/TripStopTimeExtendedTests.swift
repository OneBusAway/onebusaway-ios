//
//  TripStopTimeExtendedTests.swift
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
final class TripStopTimeExtendedTests: OBATestCase {

    private func makeStopTime(
        arrival: TimeInterval = 3600,
        departure: TimeInterval = 3660,
        stopID: String = "1_10020"
    ) throws -> TripStopTime {
        let dict: [String: Any] = [
            "arrivalTime": arrival,
            "departureTime": departure,
            "stopId": stopID
        ]
        return try Fixtures.dictionaryToModel(type: TripStopTime.self, dictionary: dict)
    }

    // MARK: - Layover Calculation

    @Test func `Layover duration between arrival and departure is accurately computed`() throws {
        let stopTime = try makeStopTime(arrival: 1000, departure: 1300, stopID: "1_200")
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        stopTime.serviceDate = baseDate

        let arrivalDate = try #require(stopTime.arrivalDate)
        let departureDate = try #require(stopTime.departureDate)

        let layover = departureDate.timeIntervalSince(arrivalDate)
        #expect(layover == 300)
    }

    // MARK: - Zero Layover (Instantaneous Departure)

    @Test func `Instantaneous departure sets arrivalDate equal to departureDate`() throws {
        let stopTime = try makeStopTime(arrival: 5000, departure: 5000, stopID: "1_200")
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        stopTime.serviceDate = baseDate

        let arrivalDate = try #require(stopTime.arrivalDate)
        let departureDate = try #require(stopTime.departureDate)

        #expect(arrivalDate == departureDate)
    }

    // MARK: - Midnight and Post-Midnight Service Day Bounds

    @Test func `Late night service times extending beyond 24 hours compute correct forward offsets`() throws {
        // 25 hours = 25 * 3600 = 90,000 seconds
        let stopTime = try makeStopTime(arrival: 90000, departure: 90120, stopID: "1_300")
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        stopTime.serviceDate = baseDate

        let arrivalDate = try #require(stopTime.arrivalDate)
        let departureDate = try #require(stopTime.departureDate)

        #expect(arrivalDate.timeIntervalSince(baseDate) == 90000)
        #expect(departureDate.timeIntervalSince(baseDate) == 90120)
    }

    // MARK: - Inequality and Distinction

    @Test func `Different stop times compare unequal via isEqual`() throws {
        let stopTimeA = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_100")
        let stopTimeB = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_101")
        let stopTimeC = try makeStopTime(arrival: 3601, departure: 3660, stopID: "1_100")

        #expect(!stopTimeA.isEqual(stopTimeB))
        #expect(!stopTimeA.isEqual(stopTimeC))
    }
}
