//
//  NextDeparturesCardKeyTests.swift
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
struct NextDeparturesCardKeyTests {

    // MARK: - Empty

    @Test func `Empty string cardKey parses to noBookmark and serializes to empty string`() {
        let key = NextDeparturesCardKey("")
        #expect(key == .noBookmark)
        #expect(key.cardKey == "")
        #expect(NextDeparturesCardKey(bookmarkID: nil) == .noBookmark)
        #expect(!key.isRefreshable)
    }

    // MARK: - Exact

    @Test func `Exact bookmark UUID parses to bookmark key and round-trips`() {
        let id = UUID()
        let key = NextDeparturesCardKey(id.uuidString)
        #expect(key == .bookmark(id))
        #expect(key.cardKey == id.uuidString)
        #expect(NextDeparturesCardKey(bookmarkID: id) == .bookmark(id))
        #expect(NextDeparturesCardKey(key.cardKey) == key)
        #expect(key.isRefreshable)
    }

    @Test func `Exact stop ID parses to stop key and round-trips`() {
        let stopEntityID = StopEntityMapping.identifier(regionID: 1, stopID: "1_75403")
        let key = NextDeparturesCardKey(stopEntityID)
        #expect(key == .stop(stopEntityID))
        #expect(key.cardKey == stopEntityID)
        #expect(NextDeparturesCardKey(stopEntityID: stopEntityID) == .stop(stopEntityID))
        #expect(NextDeparturesCardKey(key.cardKey) == key)
        #expect(key.isRefreshable)
    }

    // MARK: - Invalid

    @Test func `Invalid card key parses to invalid and serializes to empty string`() {
        let garbage = NextDeparturesCardKey("not-a-valid-card-key")
        #expect(garbage == .invalid)
        #expect(garbage.cardKey == "")
        #expect(!garbage.isRefreshable)

        let invalidStopKey = NextDeparturesCardKey(stopEntityID: "invalid_stop_key")
        #expect(invalidStopKey == .invalid)
        #expect(invalidStopKey.cardKey == "")
    }

    // MARK: - Round-trip

    @Test func `Round-trip cardKey matches original key for bookmark, stop, and noBookmark`() {
        let cases: [NextDeparturesCardKey] = [
            .bookmark(UUID()),
            .stop(StopEntityMapping.identifier(regionID: 1, stopID: "1_75403")),
            .noBookmark
        ]

        for original in cases {
            let serialized = original.cardKey
            let parsed = NextDeparturesCardKey(serialized)
            #expect(parsed == original)
        }
    }

    @Test func `Identifier and destination round-trip correctly`() {
        let testPairs = [
            (regionID: 1, stopID: "1_75403"),
            (regionID: 2, stopID: "2_1201"),
            (regionID: 1500, stopID: "40_stop_7")
        ]

        for pair in testPairs {
            let identifier = StopEntityMapping.identifier(regionID: pair.regionID, stopID: pair.stopID)
            let destination = StopEntityMapping.destination(fromIdentifier: identifier)
            #expect(destination == AppLinksRouter.StopDestination(stopID: pair.stopID, regionID: pair.regionID))
            #expect(destination?.regionID == pair.regionID)
            #expect(destination?.stopID == pair.stopID)

            if let destination, let regionID = destination.regionID {
                let recomputedIdentifier = StopEntityMapping.identifier(regionID: regionID, stopID: destination.stopID)
                #expect(recomputedIdentifier == identifier)
            }
        }
    }
}
