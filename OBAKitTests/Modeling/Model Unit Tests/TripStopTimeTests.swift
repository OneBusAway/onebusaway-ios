//
//  TripStopTimeTests.swift
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
final class TripStopTimeTests: OBATestCase {

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

    // MARK: - Decoding & Property Access

    @Test func `Decode TripStopTime from dictionary`() throws {
        let stopTime = try makeStopTime(arrival: 1800, departure: 1860, stopID: "1_500")

        #expect(stopTime.stopID == "1_500")
        #expect(stopTime.arrivalDate == nil, "arrivalDate must be nil until serviceDate is assigned")
        #expect(stopTime.departureDate == nil, "departureDate must be nil until serviceDate is assigned")
        #expect(stopTime.regionIdentifier == nil)
    }

    // MARK: - ServiceDate Calendar Calculation

    @Test func `Setting serviceDate populates arrivalDate and departureDate correctly`() throws {
        let stopTime = try makeStopTime(arrival: 7200, departure: 7260, stopID: "1_500")
        let baseDate = Date(timeIntervalSince1970: 1600000000) // Epoch reference

        stopTime.serviceDate = baseDate

        let expectedArrival = Calendar.current.date(byAdding: .second, value: 7200, to: baseDate)
        let expectedDeparture = Calendar.current.date(byAdding: .second, value: 7260, to: baseDate)

        #expect(stopTime.arrivalDate == expectedArrival)
        #expect(stopTime.departureDate == expectedDeparture)
    }

    // MARK: - Equality and Hashing

    @Test func `TripStopTime equality with identical attributes`() throws {
        let stopTime1 = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_10020")
        let stopTime2 = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_10020")

        #expect(stopTime1.isEqual(stopTime2))
        #expect(stopTime1.hash == stopTime2.hash)
    }

    @Test func `TripStopTime inequality with different stopID`() throws {
        let stopTime1 = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_10020")
        let stopTime2 = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_99999")

        #expect(!stopTime1.isEqual(stopTime2))
        #expect(stopTime1.hash != stopTime2.hash)
    }

    @Test func `TripStopTime inequality with different arrival or departure times`() throws {
        let stopTime1 = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_10020")
        let stopTime2 = try makeStopTime(arrival: 3700, departure: 3660, stopID: "1_10020")
        let stopTime3 = try makeStopTime(arrival: 3600, departure: 3760, stopID: "1_10020")

        #expect(!stopTime1.isEqual(stopTime2))
        #expect(!stopTime1.isEqual(stopTime3))
    }

    @Test func `TripStopTime equality with regionIdentifier`() throws {
        let stopTime1 = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_10020")
        let stopTime2 = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_10020")

        let stopDict: [String: Any] = [
            "id": "1_10020",
            "name": "Test Stop",
            "lat": 47.6,
            "lon": -122.3,
            "direction": "N",
            "code": "10020",
            "routeIds": ["1_100"]
        ]
        let referencesData: [String: Any] = [
            "stops": [stopDict]
        ]
        let references = try Fixtures.dictionaryToModel(type: References.self, dictionary: referencesData)

        stopTime1.loadReferences(references, regionIdentifier: 1)
        stopTime2.loadReferences(references, regionIdentifier: 2)

        #expect(!stopTime1.isEqual(stopTime2), "Different regionIdentifiers must result in inequality")
        #expect(stopTime1.hash != stopTime2.hash)

        // Matching region identifier
        let stopTime3 = try makeStopTime(arrival: 3600, departure: 3660, stopID: "1_10020")
        stopTime3.loadReferences(references, regionIdentifier: 1)
        #expect(stopTime1.isEqual(stopTime3))
        #expect(stopTime1.hash == stopTime3.hash)
    }

    @Test func `TripStopTime isEqual returns false for non-TripStopTime object`() throws {
        let stopTime = try makeStopTime()
        #expect(!stopTime.isEqual("string_object"))
        #expect(!stopTime.isEqual(nil))
    }
}
