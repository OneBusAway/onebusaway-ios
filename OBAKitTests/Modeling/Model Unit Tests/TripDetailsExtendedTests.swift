//
//  TripDetailsExtendedTests.swift
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
final class TripDetailsExtendedTests: OBATestCase {

    private func loadTripDetailsPayload(file: String) throws -> (entry: TripDetails, references: References) {
        let data = Fixtures.loadData(file: file)
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data)
        let references = try #require(response.references, "Expected references in \(file)")
        return (response.entry, references)
    }

    // MARK: - Stop Times Sequence Ordering and Dates

    @Test func `Stop times are ordered sequentially and retain non-decreasing arrival timestamps`() throws {
        let (tripDetails, _) = try loadTripDetailsPayload(file: "trip_details_1_18196913.json")
        let stopTimes = tripDetails.stopTimes

        #expect(stopTimes.count > 1)

        for index in 0..<(stopTimes.count - 1) {
            let current = stopTimes[index]
            let next = stopTimes[index + 1]

            let currentArrival = try #require(current.arrivalDate)
            let currentDeparture = try #require(current.departureDate)
            let nextArrival = try #require(next.arrivalDate)

            // Current departure cannot precede current arrival
            #expect(currentDeparture >= currentArrival)
            // Next stop arrival should be after or at least equal to current stop departure
            #expect(nextArrival >= currentDeparture)
        }
    }

    // MARK: - Block Chain Continuity

    @Test func `Trip block identifier remains consistent across linked trips`() throws {
        let (tripDetails, references) = try loadTripDetailsPayload(file: "trip_details_1_18196913.json")
        tripDetails.loadReferences(references, regionIdentifier: 1)

        let rootTrip = try #require(tripDetails.trip)
        let blockID = rootTrip.blockID

        let previousTrip = try #require(tripDetails.previousTrip)
        #expect(previousTrip.blockID == blockID)

        let nextTrip = try #require(tripDetails.nextTrip)
        #expect(nextTrip.blockID == blockID)
    }

    // MARK: - Stop Time Lookup

    @Test func `First and terminal stops in trip details have valid non-empty stop IDs`() throws {
        let (tripDetails, references) = try loadTripDetailsPayload(file: "trip_details_1_18196913.json")
        tripDetails.loadReferences(references, regionIdentifier: 1)

        let firstStop = try #require(tripDetails.stopTimes.first)
        let lastStop = try #require(tripDetails.stopTimes.last)

        #expect(!firstStop.stopID.isEmpty)
        #expect(!lastStop.stopID.isEmpty)
        #expect(firstStop.stop != nil)
        #expect(lastStop.stop != nil)
    }
}
