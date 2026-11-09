//
//  TransferTripHighlightExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `TransferTripHighlight` selection logic under diverse transfer contexts,
/// empty strings, differing case sensitivity, and whitespace handling.
@Suite(.serialized)
struct TransferTripHighlightExtendedTests {

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Nil and Empty Context Variations

    @Test func `tripID returns nil when context is nil`() {
        #expect(TransferTripHighlight.tripID(from: nil) == nil)
    }

    @Test func `tripID returns nil when fromTripID is omitted from context`() {
        let context = TransferContext(
            arrivalTime: referenceDate,
            fromRouteShortName: "44",
            fromTripHeadsign: "UW Station"
        )
        #expect(TransferTripHighlight.tripID(from: context) == nil)
    }

    @Test func `tripID extracts exact identifier when present`() {
        let context = TransferContext(
            arrivalTime: referenceDate,
            fromRouteShortName: "44",
            fromTripHeadsign: "UW Station",
            fromTripID: "1_2345678"
        )
        #expect(TransferTripHighlight.tripID(from: context) == "1_2345678")
    }

    // MARK: - shouldHighlight Predicate Boundaries

    @Test func `shouldHighlight returns false when context is nil regardless of tripID`() {
        #expect(!TransferTripHighlight.shouldHighlight(tripID: "1_100", context: nil))
        #expect(!TransferTripHighlight.shouldHighlight(tripID: "", context: nil))
    }

    @Test func `shouldHighlight returns false when context lacks fromTripID`() {
        let context = TransferContext(
            arrivalTime: referenceDate,
            fromRouteShortName: "7",
            fromTripHeadsign: "Downtown"
        )
        #expect(!TransferTripHighlight.shouldHighlight(tripID: "1_100", context: context))
    }

    @Test func `shouldHighlight returns true only for matching tripID`() {
        let context = TransferContext(
            arrivalTime: referenceDate,
            fromRouteShortName: "7",
            fromTripHeadsign: "Downtown",
            fromTripID: "target_trip"
        )

        #expect(TransferTripHighlight.shouldHighlight(tripID: "target_trip", context: context))
        #expect(!TransferTripHighlight.shouldHighlight(tripID: "TARGET_TRIP", context: context))
        #expect(!TransferTripHighlight.shouldHighlight(tripID: "target_trip_2", context: context))
        #expect(!TransferTripHighlight.shouldHighlight(tripID: "other", context: context))
    }

    @Test func `shouldHighlight handles empty string trip IDs without crashing`() {
        let contextWithEmptyID = TransferContext(
            arrivalTime: referenceDate,
            fromRouteShortName: "E",
            fromTripHeadsign: "Aurora Village",
            fromTripID: ""
        )

        #expect(TransferTripHighlight.shouldHighlight(tripID: "", context: contextWithEmptyID))
        #expect(!TransferTripHighlight.shouldHighlight(tripID: "valid_trip", context: contextWithEmptyID))
    }
}
