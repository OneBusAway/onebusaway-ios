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

    private func makeLayer(mapView: MKMapView = MKMapView()) -> StopRouteFocusMapLayer {
        StopRouteFocusMapLayer(
            mapView: mapView,
            shapeCache: ShapeCache { _ in "" },
            formatters: Self.formatters
        )
    }

    private func vehicles(on mapView: MKMapView) -> [StopVehicleAnnotation] {
        mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }
    }

    // MARK: - The symptom

    /// The bug as the rider saw it: route lines, no buses. One emission — the
    /// layer's very first, with no prior state anywhere — has to be enough to put
    /// markers on the map.
    @Test func `The first emission alone puts vehicle markers on the map`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.apply(arrivals: try StopArrivalsFixture.upcoming(), isListFiltered: false, preferences: StopPreferences())

        // The fixture carries four departures, each with a distinct vehicle ID and
        // a `tripStatus.position`.
        #expect(vehicles(on: mapView).count == 4)
    }

    /// Pins the actual failure mechanism, in isolation from how the resolver gets
    /// installed: a resolver that cannot answer silently costs every vehicle, with
    /// no error and no empty state. This is what the shipped code did on first
    /// load, and it is why the map drew lines with nothing on them.
    @Test func `A resolver that answers nothing costs every vehicle, silently`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.apply(arrivals: try StopArrivalsFixture.upcoming(), isListFiltered: false, preferences: StopPreferences())
        #expect(vehicles(on: mapView).count == 4)

        // Re-apply the same arrivals, but with the resolver knocked out the way a
        // stale read knocked it out.
        layer.departureProvider = { _ in nil }
        layer.update(model: StopRouteFocusModel.make(
            departures: try StopArrivalsFixture.upcoming().arrivalsAndDepartures,
            routeCap: StopRouteFocusMapLayer.routeCap
        ))

        #expect(vehicles(on: mapView).isEmpty)
    }

    // MARK: - The resolver

    /// The regression: the resolver has to answer from the emission it was handed,
    /// with no help from any other state. Nothing in this test writes the arrivals
    /// anywhere the layer could read them from.
    @Test func `Applying an emission installs a resolver for that emission's departures`() throws {
        let layer = makeLayer()
        let arrivals = try StopArrivalsFixture.load()
        let departure = try #require(arrivals.arrivalsAndDepartures.first)

        layer.apply(arrivals: arrivals, isListFiltered: false, preferences: StopPreferences())

        #expect(layer.departureProvider?(departure.id) === departure)
    }

    /// Every departure, not just the first — the resolver is keyed by ID and the
    /// layer asks it once per vehicle.
    @Test func `The resolver answers for every departure in the emission`() throws {
        let layer = makeLayer()
        let arrivals = try StopArrivalsFixture.load()

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

        layer.apply(arrivals: try StopArrivalsFixture.load(), isListFiltered: false, preferences: StopPreferences())

        #expect(layer.departureProvider?("stop=nope,trip=nope,route=nope") == nil)
    }

    /// The pre-load emission. `combineLatest` fires synchronously on subscribe,
    /// while arrivals are still nil, so this is the layer's very first call every
    /// time a sheet opens.
    @Test func `A nil emission installs a resolver that answers nothing`() throws {
        let layer = makeLayer()
        let departure = try #require(try StopArrivalsFixture.load().arrivalsAndDepartures.first)

        layer.apply(arrivals: nil, isListFiltered: false, preferences: StopPreferences())

        #expect(layer.departureProvider != nil)
        #expect(layer.departureProvider?(departure.id) == nil)
    }
}
