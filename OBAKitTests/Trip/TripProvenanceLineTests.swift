//
//  TripProvenanceLineTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

@Suite(.serialized)
struct TripProvenanceLineTests {

    @Test func `All three clauses join with the separator`() {
        let line = TripProvenanceLine.text(routeName: "RapidRide H", vehicleLabel: "Vehicle 6821", freshness: "position updated 12s ago")

        #expect(line == "RapidRide H · Vehicle 6821 · position updated 12s ago")
    }

    /// A trip with no live vehicle has no vehicle ID and no position age. The
    /// line must not come out with a dangling separator, which is what naive
    /// interpolation produces.
    @Test func `A missing clause takes its separator with it`() {
        #expect(TripProvenanceLine.text(routeName: "RapidRide H", vehicleLabel: nil, freshness: "position updated 12s ago")
                == "RapidRide H · position updated 12s ago")
        #expect(TripProvenanceLine.text(routeName: "RapidRide H", vehicleLabel: "Vehicle 6821", freshness: nil)
                == "RapidRide H · Vehicle 6821")
        #expect(TripProvenanceLine.text(routeName: nil, vehicleLabel: "Vehicle 6821", freshness: nil)
                == "Vehicle 6821")
    }

    /// Feeds send empty strings where they mean "absent" often enough that
    /// treating the two differently would put a stray separator on screen.
    @Test func `An empty clause counts as missing`() {
        #expect(TripProvenanceLine.text(routeName: "", vehicleLabel: "Vehicle 6821", freshness: "")
                == "Vehicle 6821")
    }

    @Test func `Nothing to report yields nothing rather than separators`() {
        #expect(TripProvenanceLine.text(routeName: nil, vehicleLabel: nil, freshness: nil) == nil)
        #expect(TripProvenanceLine.text(routeName: "", vehicleLabel: "", freshness: "") == nil)
    }
}
