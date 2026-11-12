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
        #expect(context.fromTripID == arrDep.tripID)
    }

    // MARK: - toStop

    /// Route 75 to Northgate Lake City, boarding at stop 1_75414.
    private func boardingDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_75414.json"
        )
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    @Test func `toStop builds the context for a stop after boarding`() throws {
        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)

        let context = try #require(TransferContext.toStop("1_75403", arrivalDate: arrivalTime, from: try boardingDeparture()))

        #expect(context.arrivalTime == arrivalTime)
        #expect(context.fromRouteShortName == "75")
        #expect(context.fromTripHeadsign == "Northgate Lake City")
        #expect(context.fromTripID == "1_39683959")
    }

    @Test func `toStop builds none for the boarding stop`() throws {
        let departure = try boardingDeparture()
        #expect(departure.stopID == "1_75414")

        #expect(TransferContext.toStop("1_75414", arrivalDate: Date(timeIntervalSince1970: 1_000_000), from: departure) == nil)
    }

    @Test func `toStop builds none without a departure`() {
        #expect(TransferContext.toStop("1_75403", arrivalDate: Date(timeIntervalSince1970: 1_000_000), from: nil) == nil)
    }

    @Test func `toStop builds none without an arrival time`() throws {
        #expect(TransferContext.toStop("1_75403", arrivalDate: nil, from: try boardingDeparture()) == nil)
    }

    @Test func `Init stores fromTripID`() {
        let context = TransferContext(
            arrivalTime: Date(timeIntervalSince1970: 1_000_000),
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromTripID: "1_trip_abc"
        )
        #expect(context.fromTripID == "1_trip_abc")
    }
}
