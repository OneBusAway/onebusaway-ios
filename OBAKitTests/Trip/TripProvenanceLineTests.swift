//
//  TripProvenanceLineTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
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

    // MARK: - Freshness

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func `A reported position says how old it is`() throws {
        let freshness = try #require(TripProvenanceLine.freshness(lastUpdate: now - 45, isEstimated: false, relativeTo: now))
        #expect(freshness.hasPrefix("position updated "))
    }

    /// The map marker can't take VoiceOver focus, so the card's line is where a
    /// rider hears that the bus on the map is an estimate.
    @Test func `An estimated position says it is estimated, and how old its fix is`() throws {
        let freshness = try #require(TripProvenanceLine.freshness(lastUpdate: now - 45, isEstimated: true, relativeTo: now))
        #expect(freshness.hasPrefix("estimated position, updated "))
        let reported = try #require(TripProvenanceLine.freshness(lastUpdate: now - 45, isEstimated: false, relativeTo: now))
        #expect(freshness.hasSuffix(String(reported.dropFirst("position updated ".count))))
    }

    @Test func `No update, no freshness`() {
        #expect(TripProvenanceLine.freshness(lastUpdate: nil, isEstimated: true, relativeTo: now) == nil)
    }

    // MARK: - Trip short name

    /// Sounder trips carry a train number; it sits between the route and the vehicle.
    /// The expected trip clause comes from the same localized key, so the test
    /// holds in any test-host language.
    @Test func `A trip short name shows between the route and the vehicle`() {
        let format = Bundle.obaKit.localizedString(forKey: "trip_page.trip_short_name_fmt", value: "MISSING", table: nil)
        #expect(format != "MISSING", "trip_page.trip_short_name_fmt is missing from the strings catalog")
        let line = TripProvenanceLine.text(
            routeName: "Sounder S Line",
            tripLabel: TripProvenanceLine.tripLabel(shortName: "1519"),
            vehicleLabel: "Vehicle 1402",
            freshness: nil
        )
        #expect(line == "Sounder S Line · \(String(format: format, "1519")) · Vehicle 1402")
    }

    /// Link and buses send no trip short name, and their line must not change.
    @Test func `A missing or blank trip short name adds nothing`() {
        #expect(TripProvenanceLine.tripLabel(shortName: nil) == nil)
        #expect(TripProvenanceLine.tripLabel(shortName: "") == nil)
        #expect(TripProvenanceLine.tripLabel(shortName: "  ") == nil)
        #expect(TripProvenanceLine.text(routeName: "1 Line", tripLabel: TripProvenanceLine.tripLabel(shortName: nil), vehicleLabel: "Vehicle 140", freshness: nil)
                == "1 Line · Vehicle 140")
    }
}
