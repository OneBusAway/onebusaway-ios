//
//  StopRouteFocusApplyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// `StopRouteFocusMapLayer.apply(arrivals:isListFiltered:preferences:)` — the seam
/// that takes one arrivals emission and derives everything the layer needs from it.
///
/// It exists because the two halves used to come from different places:
/// `MapViewController` built the model from the value its `@Published` sink emitted,
/// but resolved departures by reading `viewModel.stopArrivals` back out. `@Published`
/// publishes in `willSet`, so that read returned the PREVIOUS value — nil on the
/// first load. No departure resolved, `syncVehicleAnnotations` skipped every vehicle,
/// and the map drew route lines with nothing running on them until the next 15s
/// refresh, which then resolved a generation stale forever after.
@MainActor
@Suite(.serialized)
final class StopRouteFocusApplyTests {

    private static let formatters = Formatters(
        locale: Locale(identifier: "en_US"),
        calendar: Calendar(identifier: .gregorian),
        themeColors: ThemeColors.shared
    )

    private func makeLayer() -> StopRouteFocusMapLayer {
        StopRouteFocusMapLayer(
            mapView: MKMapView(),
            shapeCache: ShapeCache { _ in "" },
            formatters: Self.formatters
        )
    }

    private func loadArrivals() throws -> StopArrivals {
        try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals_and_departures_for_stop_1_10020.json"
        )
    }

    /// The regression: the resolver has to answer from the emission it was handed,
    /// with no help from any other state. Nothing in this test writes the arrivals
    /// anywhere the layer could read them from.
    @Test func `Applying an emission installs a resolver for that emission's departures`() throws {
        let layer = makeLayer()
        let arrivals = try loadArrivals()
        let departure = try #require(arrivals.arrivalsAndDepartures.first)

        layer.apply(arrivals: arrivals, isListFiltered: false, preferences: StopPreferences())

        #expect(layer.departureProvider?(departure.id) === departure)
    }

    /// Every departure, not just the first — the resolver is keyed by ID and the
    /// layer asks it once per vehicle.
    @Test func `The resolver answers for every departure in the emission`() throws {
        let layer = makeLayer()
        let arrivals = try loadArrivals()

        layer.apply(arrivals: arrivals, isListFiltered: false, preferences: StopPreferences())

        for departure in arrivals.arrivalsAndDepartures {
            #expect(layer.departureProvider?(departure.id) === departure)
        }
    }

    /// A departure from a *different* load must not resolve. Without this, the
    /// stale-generation half of the bug reads as passing: the old resolver did
    /// answer, just from the wrong emission.
    @Test func `The resolver refuses an ID that is not in the emission`() throws {
        let layer = makeLayer()

        layer.apply(arrivals: try loadArrivals(), isListFiltered: false, preferences: StopPreferences())

        #expect(layer.departureProvider?("stop=nope,trip=nope,route=nope") == nil)
    }

    /// The pre-load emission. `combineLatest` fires synchronously on subscribe,
    /// while arrivals are still nil, so this is the layer's very first call every
    /// time a sheet opens.
    @Test func `A nil emission installs a resolver that answers nothing`() throws {
        let layer = makeLayer()
        let departure = try #require(try loadArrivals().arrivalsAndDepartures.first)

        layer.apply(arrivals: nil, isListFiltered: false, preferences: StopPreferences())

        #expect(layer.departureProvider != nil)
        #expect(layer.departureProvider?(departure.id) == nil)
    }
}
