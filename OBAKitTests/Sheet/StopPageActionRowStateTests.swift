//
//  StopPageActionRowStateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

/// The action row's enabled and filled predicates, extracted from the view so
/// they can be asserted directly rather than through view inspection.
@Suite(.serialized)
struct StopPageActionRowStateTests {

    @Test func `A multi route stop can be filtered`() {
        let state = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(state.canFilter)
    }

    @Test func `A single route stop cannot be filtered`() {
        let state = StopPageActionRowState(routeCount: 1, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(!state.canFilter)
    }

    @Test func `A stop with no routes cannot be filtered`() {
        let state = StopPageActionRowState(routeCount: 0, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(!state.canFilter)
    }

    @Test func `The filter reads as on only when hidden routes are actually applied`() {
        let applied = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: true, isListFiltered: true, hasServiceAlerts: false)
        #expect(applied.isFilterOn)
        #expect(applied.filterSystemImage == "line.3.horizontal.decrease.circle.fill")

        let savedButOff = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: true, isListFiltered: false, hasServiceAlerts: false)
        #expect(!savedButOff.isFilterOn)
        #expect(savedButOff.filterSystemImage == "line.3.horizontal.decrease.circle")

        let noneHidden = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(!noneHidden.isFilterOn)
    }

    @Test func `Service alerts are reachable only when the stop has some`() {
        let withAlerts = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: true)
        #expect(withAlerts.canShowServiceAlerts)

        let without = StopPageActionRowState(routeCount: 3, hasHiddenRoutes: false, isListFiltered: true, hasServiceAlerts: false)
        #expect(!without.canShowServiceAlerts)
    }
}
