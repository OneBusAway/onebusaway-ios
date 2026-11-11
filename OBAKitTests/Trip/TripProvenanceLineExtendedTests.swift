//
//  TripProvenanceLineExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit

/// Extended tests for `TripProvenanceLine` edge cases, whitespace padding,
/// and multiple missing clause configurations.
@Suite(.serialized)
struct TripProvenanceLineExtendedTests {

    @Test func `Single route clause alone formats without separators`() {
        let line = TripProvenanceLine.text(routeName: "Line 1", vehicleLabel: nil, freshness: nil)
        #expect(line == "Line 1")
    }

    @Test func `Single vehicle label alone formats without separators`() {
        let line = TripProvenanceLine.text(routeName: nil, vehicleLabel: "Vehicle 4001", freshness: nil)
        #expect(line == "Vehicle 4001")
    }

    @Test func `Single freshness alone formats without separators`() {
        let line = TripProvenanceLine.text(routeName: nil, vehicleLabel: nil, freshness: "updated now")
        #expect(line == "updated now")
    }

    @Test func `Route name and freshness without vehicle label join cleanly`() {
        let line = TripProvenanceLine.text(routeName: "Route 44", vehicleLabel: nil, freshness: "5s ago")
        #expect(line == "Route 44 · 5s ago")
    }

    @Test func `Vehicle label and freshness without route name join cleanly`() {
        let line = TripProvenanceLine.text(routeName: nil, vehicleLabel: "Bus 1234", freshness: "10s ago")
        #expect(line == "Bus 1234 · 10s ago")
    }

    @Test func `Route name and vehicle label without freshness join cleanly`() {
        let line = TripProvenanceLine.text(routeName: "Route 70", vehicleLabel: "Coach 88", freshness: nil)
        #expect(line == "Route 70 · Coach 88")
    }

    @Test func `All empty strings return nil`() {
        let line = TripProvenanceLine.text(routeName: "", vehicleLabel: "", freshness: "")
        #expect(line == nil)
    }

    @Test func `Mixed empty strings and valid clauses omit empty clauses`() {
        let line1 = TripProvenanceLine.text(routeName: "Route 8", vehicleLabel: "", freshness: "just now")
        #expect(line1 == "Route 8 · just now")

        let line2 = TripProvenanceLine.text(routeName: "", vehicleLabel: "Van 12", freshness: "")
        #expect(line2 == "Van 12")
    }
}
