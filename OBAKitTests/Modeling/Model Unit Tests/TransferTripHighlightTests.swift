//
//  TransferTripHighlightTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct TransferTripHighlightTests {

    @Test func `Trip ID from nil context is nil`() {
        #expect(TransferTripHighlight.tripID(from: nil) == nil)
    }

    @Test func `Trip ID from context without trip ID is nil`() {
        let context = TransferContext(
            arrivalTime: Date(),
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill"
        )
        #expect(TransferTripHighlight.tripID(from: context) == nil)
    }

    @Test func `Trip ID from context with trip ID returns that ID`() {
        let context = TransferContext(
            arrivalTime: Date(),
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromTripID: "trip_42"
        )
        #expect(TransferTripHighlight.tripID(from: context) == "trip_42")
    }

    @Test func `Should highlight matching trip ID`() {
        let context = TransferContext(
            arrivalTime: Date(),
            fromRouteShortName: "10",
            fromTripHeadsign: "Capitol Hill",
            fromTripID: "trip_42"
        )
        #expect(TransferTripHighlight.shouldHighlight(tripID: "trip_42", context: context))
        #expect(!TransferTripHighlight.shouldHighlight(tripID: "other", context: context))
        #expect(!TransferTripHighlight.shouldHighlight(tripID: "trip_42", context: nil))
    }
}
