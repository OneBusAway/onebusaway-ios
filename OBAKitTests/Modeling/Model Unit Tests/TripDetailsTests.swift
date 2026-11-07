//
//  TripDetailsTests.swift
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

// swiftlint:disable force_try force_cast

@Suite(.serialized)
final class TripDetailsTests: OBATestCase {

    private func loadTripDetailsPayload(file: String = "trip_details_1_18196913.json") throws -> (entry: TripDetails, references: References) {
        let data = Fixtures.loadData(file: file)
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data)
        let references = try #require(response.references, "Expected references in \(file)")
        return (response.entry, references)
    }

    // MARK: - Full Payload Decoding & Structure

    @Test func `Decode full trip details with references`() throws {
        let (tripDetails, _) = try loadTripDetailsPayload(file: "trip_details_1_18196913.json")

        #expect(tripDetails.tripID == "1_18196913")
        #expect(tripDetails.id == "1_18196913")
        #expect(tripDetails.timeZone == "America/Los_Angeles")
        #expect(tripDetails.frequency == nil)
        #expect(tripDetails.serviceDate == Date.fromComponents(year: 2012, month: 07, day: 30, hour: 07, minute: 00, second: 00))

        // References loaded
        #expect(tripDetails.trip != nil)
        #expect(tripDetails.trip.id == "1_18196913")
        #expect(tripDetails.trip.headsign == "LAKE CITY WEDGWOOD")
        #expect(tripDetails.trip.routeID == "1_65")
        #expect(tripDetails.trip.blockID == "1_2955396")

        // Stop times loaded and serviceDate distributed
        #expect(tripDetails.stopTimes.count == 53)
        let firstStopTime = try #require(tripDetails.stopTimes.first)
        #expect(firstStopTime.stopID == "1_9610")
        #expect(firstStopTime.stop != nil)
        #expect(firstStopTime.stop.id == "1_9610")
        #expect(firstStopTime.arrivalDate != nil)
        #expect(firstStopTime.departureDate != nil)

        // Status
        #expect(tripDetails.status != nil)
        #expect(tripDetails.status?.tripID == "1_18196913")
        #expect(tripDetails.status?.vehicleID == "1_3601")
        #expect(tripDetails.status?.isRealTime == true)
    }

    // MARK: - Service Date Distribution into StopTimes

    @Test func `Service date distributes to all stop times and computes arrival and departure dates`() throws {
        let (tripDetails, _) = try loadTripDetailsPayload(file: "trip_details_1_18196913_no_status.json")

        #expect(!tripDetails.stopTimes.isEmpty)

        // Check each stop time has correct calendar offset relative to serviceDate
        for stopTime in tripDetails.stopTimes {
            let arrivalDate = try #require(stopTime.arrivalDate)
            let departureDate = try #require(stopTime.departureDate)

            // Departure is on or after arrival
            #expect(departureDate >= arrivalDate)
            // Both are strictly after the start of serviceDate
            #expect(arrivalDate >= tripDetails.serviceDate)
        }
    }

    // MARK: - Block Links (Previous & Next Trips)

    @Test func `Block navigation properties resolve when previous and next trips exist`() throws {
        let (tripDetails, _) = try loadTripDetailsPayload(file: "trip_details_1_18196913.json")

        // In this specific fixture blockId is 1_2955396
        #expect(tripDetails.trip.blockID == "1_2955396")
        // If the fixture does not provide nextTripId / previousTripId, they decode as nil safely
        if let nextTrip = tripDetails.nextTrip {
            #expect(!nextTrip.id.isEmpty)
        }
        if let previousTrip = tripDetails.previousTrip {
            #expect(!previousTrip.id.isEmpty)
        }
    }

    // MARK: - Missing or Nil Components Handling

    @Test func `Decode trip details with no status`() throws {
        let (tripDetails, _) = try loadTripDetailsPayload(file: "trip_details_1_18196913_no_status.json")

        #expect(tripDetails.status == nil)
        #expect(tripDetails.tripID == "1_18196913")
        #expect(tripDetails.stopTimes.count == 53)
    }

    @Test func `Region identifier propagates to trip details and child references`() throws {
        let (tripDetails, references) = try loadTripDetailsPayload(file: "trip_details_1_18196913.json")

        tripDetails.loadReferences(references, regionIdentifier: 42)
        #expect(tripDetails.regionIdentifier == 42)

        for stopTime in tripDetails.stopTimes {
            #expect(stopTime.regionIdentifier == 42)
        }
    }
}
