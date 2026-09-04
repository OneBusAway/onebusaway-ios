//
//  NearbyStopsIndexSectionTests.swift
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
final class NearbyStopsIndexSectionTests: OBATestCase {

    /// Every stop lands in exactly one section, and that section's direction is
    /// the stop's own. Asserted structurally rather than against hard-coded
    /// directions so the test survives a fixture refresh.
    @Test func `Sections group every stop under its own direction`() throws {
        let stops = try Fixtures.loadSomeStops()

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: nil)

        #expect(sections.reduce(0) { $0 + $1.stops.count } == stops.count)
        for section in sections {
            #expect(section.stops.allSatisfy { $0.direction == section.direction })
        }
    }

    /// Sections are ordered by `Direction`'s own ordering (n, ne, e, … unknown),
    /// so the list doesn't reshuffle between loads.
    @Test func `Sections are ordered by direction`() throws {
        let stops = try Fixtures.loadSomeStops()

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: nil)

        #expect(sections.map(\.direction) == sections.map(\.direction).sorted())
    }

    /// No empty sections: a direction whose stops are all filtered out is
    /// dropped rather than rendered as a bare header.
    @Test func `Sections are never empty`() throws {
        let stops = try Fixtures.loadSomeStops()

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: nil)

        #expect(!sections.isEmpty)
        #expect(sections.allSatisfy { !$0.stops.isEmpty })
    }

    /// A blank or whitespace-only filter is treated as no filter at all —
    /// `.searchable` hands us "" the moment the field is focused.
    @Test func `Blank filter matches everything`() throws {
        let stops = try Fixtures.loadSomeStops()

        let unfiltered = NearbyStopsIndexSection.sections(stops: stops, filter: nil)
        let blank = NearbyStopsIndexSection.sections(stops: stops, filter: "   ")

        #expect(blank.map(\.id) == unfiltered.map(\.id))
        #expect(blank.reduce(0) { $0 + $1.stops.count } == stops.count)
    }

    /// A filter naming one stop narrows the result to stops that match it.
    @Test func `Filter narrows results to matching stops`() throws {
        let stops = try Fixtures.loadSomeStops()
        let target = try #require(stops.first)

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: target.name)
        let matched = sections.flatMap(\.stops)

        #expect(matched.contains { $0.id == target.id })
        #expect(matched.allSatisfy { $0.matchesQuery(target.name) })
        #expect(matched.count < stops.count)
    }

    /// A filter that matches nothing yields no sections, which is what drives
    /// the view's "no results" empty state.
    @Test func `Filter matching nothing yields no sections`() throws {
        let stops = try Fixtures.loadSomeStops()

        let sections = NearbyStopsIndexSection.sections(stops: stops, filter: "zzzzz-no-such-stop")

        #expect(sections.isEmpty)
    }
}
