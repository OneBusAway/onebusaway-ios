//
//  ArrivalDepartureItemTransferTests.swift
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
final class ArrivalDepartureItemTransferTests: OBATestCase {

    /// Loads a real ArrivalDeparture from fixture data and verifies that
    /// creating an ArrivalDepartureItem with a TransferContext produces
    /// different minutes and temporal state than without one.
    @Test func `Arrival departure item with transfer context overrides minutes and temporal state`() {
        let stopArrivals = try! Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_75414.json"
        )
        let arrDep = stopArrivals.arrivalsAndDepartures.first!

        // Item without transfer context — minutes relative to now.
        let itemWithoutTransfer = ArrivalDepartureItem(
            arrivalDeparture: arrDep,
            isAlarmAvailable: false
        )

        // Transfer arrival set to 5 minutes after the departure's scheduled time,
        // so the transfer-relative minutes should be negative (departed before arrival).
        let transferArrival = arrDep.arrivalDepartureDate.addingTimeInterval(5 * 60)
        let context = TransferContext(
            arrivalTime: transferArrival,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )

        let itemWithTransfer = ArrivalDepartureItem(
            arrivalDeparture: arrDep,
            isAlarmAvailable: false,
            transferContext: context
        )

        // The transfer-relative minutes should be -5 (departed 5 min before rider arrives).
        #expect(itemWithTransfer.arrivalDepartureMinutes == -5)
        #expect(itemWithTransfer.temporalState == .past)

        // Without transfer context, minutes are relative to Date.now — they should differ.
        #expect(itemWithoutTransfer.arrivalDepartureMinutes != itemWithTransfer.arrivalDepartureMinutes, "Transfer context should produce different minutes than real-time minutes")
    }

    /// Verifies that a departure exactly at the transfer arrival time shows as .present / 0 min.
    @Test func `Arrival departure item with transfer context at arrival time`() {
        let stopArrivals = try! Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_75414.json"
        )
        let arrDep = stopArrivals.arrivalsAndDepartures.first!

        // Transfer arrival exactly at the departure time.
        let context = TransferContext(
            arrivalTime: arrDep.arrivalDepartureDate,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )

        let item = ArrivalDepartureItem(
            arrivalDeparture: arrDep,
            isAlarmAvailable: false,
            transferContext: context
        )

        #expect(item.arrivalDepartureMinutes == 0)
        #expect(item.temporalState == .present)
    }

    /// Verifies that a departure 10 minutes after transfer arrival shows as .future / 10 min.
    @Test func `Arrival departure item with transfer context future after arrival`() {
        let stopArrivals = try! Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_75414.json"
        )
        let arrDep = stopArrivals.arrivalsAndDepartures.first!

        // Transfer arrival 10 minutes before the departure.
        let transferArrival = arrDep.arrivalDepartureDate.addingTimeInterval(-10 * 60)
        let context = TransferContext(
            arrivalTime: transferArrival,
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )

        let item = ArrivalDepartureItem(
            arrivalDeparture: arrDep,
            isAlarmAvailable: false,
            transferContext: context
        )

        #expect(item.arrivalDepartureMinutes == 10)
        #expect(item.temporalState == .future)
    }
}
