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
@testable import OBAKitCore

/// The action row's enabled and filled predicates, extracted from the view so
/// they can be asserted directly rather than through view inspection.
@Suite(.serialized)
struct StopPageActionRowStateTests {

    /// The loaded-stop case, which every filter and alert assertion assumes.
    /// `hasStop` is deliberately not defaulted on the type itself — a default of
    /// `true` there is exactly the bug this field exists to prevent.
    private func state(
        hasStop: Bool = true,
        routeCount: Int = 3,
        hasHiddenRoutes: Bool = false,
        isListFiltered: Bool = true,
        departureFilter: ArrivalDepartureFilter = .all,
        hasServiceAlerts: Bool = false
    ) -> StopPageActionRowState {
        StopPageActionRowState(
            hasStop: hasStop,
            routeCount: routeCount,
            hasHiddenRoutes: hasHiddenRoutes,
            isListFiltered: isListFiltered,
            departureFilter: departureFilter,
            hasServiceAlerts: hasServiceAlerts
        )
    }

    @Test func `A multi route stop can be filtered`() {
        #expect(state(routeCount: 3).canFilter)
    }

    @Test func `A single route stop cannot be filtered`() {
        #expect(!state(routeCount: 1).canFilter)
    }

    @Test func `A stop with no routes cannot be filtered`() {
        #expect(!state(routeCount: 0).canFilter)
    }

    @Test func `The route filter reads as on only when hidden routes are actually applied`() {
        #expect(state(hasHiddenRoutes: true, isListFiltered: true).isRouteFilterOn)
        #expect(!state(hasHiddenRoutes: true, isListFiltered: false).isRouteFilterOn)
        #expect(!state(hasHiddenRoutes: false, isListFiltered: true).isRouteFilterOn)
    }

    @Test func `The filter glyph fills when hidden routes are applied`() {
        let applied = state(hasHiddenRoutes: true, isListFiltered: true)
        #expect(applied.isFilterOn)
        #expect(applied.filterSystemImage == "line.3.horizontal.decrease.circle.fill")

        let savedButOff = state(hasHiddenRoutes: true, isListFiltered: false)
        #expect(!savedButOff.isFilterOn)
        #expect(savedButOff.filterSystemImage == "line.3.horizontal.decrease.circle")

        #expect(!state(hasHiddenRoutes: false, isListFiltered: true).isFilterOn)
    }

    /// The Departure Type filter carries a Settings-level default, so it can be
    /// holding rows back on a stop with no hidden routes at all. The bar button
    /// this row replaces fills its glyph for that case; the row has to as well,
    /// or the only filter in effect reads as "off".
    @Test func `The filter glyph fills for a non default departure type`() {
        for filter in [ArrivalDepartureFilter.estimatedOnly, .scheduledOnly] {
            let state = state(hasHiddenRoutes: false, isListFiltered: false, departureFilter: filter)
            #expect(state.isFilterOn)
            #expect(!state.isRouteFilterOn)
            #expect(state.filterSystemImage == "line.3.horizontal.decrease.circle.fill")
        }

        #expect(!state(departureFilter: .all).isFilterOn)
    }

    /// `isRouteFilterOn` is what checks one of the two route choices, so it must
    /// not move with the departure filter — otherwise picking "Scheduled Only"
    /// would check "Filtered Routes" on a stop with no hidden routes.
    @Test func `The departure filter does not check a route choice`() {
        #expect(!state(hasHiddenRoutes: false, isListFiltered: true, departureFilter: .scheduledOnly).isRouteFilterOn)
    }

    @Test func `Service alerts are reachable only when the stop has some`() {
        #expect(state(hasServiceAlerts: true).canShowServiceAlerts)
        #expect(!state(hasServiceAlerts: false).canShowServiceAlerts)
    }

    // MARK: - Unloaded stop

    /// The regression: when the first fetch fails, `viewModel.stop` is nil but
    /// the action row still renders. Bookmark, Nearby Stops, Walking Directions
    /// and Report a Problem all bottom out in a `guard let stop` that does
    /// nothing, so they have to look unavailable rather than merely act it.
    @Test func `Stop actions are unavailable until the stop loads`() {
        #expect(!state(hasStop: false).canActOnStop)
        #expect(state(hasStop: true).canActOnStop)
    }

    /// A failed first fetch reports no routes and no alerts, so the two gates
    /// that already existed close on their own — `canActOnStop` is what the rest
    /// of the row needed.
    @Test func `A failed first fetch leaves the whole row inert`() {
        let unloaded = state(hasStop: false, routeCount: 0, hasServiceAlerts: false)
        #expect(!unloaded.canActOnStop)
        #expect(!unloaded.canFilter)
        #expect(!unloaded.canShowServiceAlerts)
    }
}
