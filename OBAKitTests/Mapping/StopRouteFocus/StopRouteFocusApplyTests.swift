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

    private static let fixtureName = "arrivals_and_departures_for_stop_1_10020.json"

    private func loadArrivals() throws -> StopArrivals {
        try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: Self.fixtureName)
    }

    /// The same fixture with its arrival and departure times moved into the near
    /// future.
    ///
    /// Necessary because `StopRouteFocusModel.make` drops anything whose
    /// `temporalState` is `.past`, and the fixture's timestamps are fixed at 2019.
    /// Loaded as-is it yields zero routes and zero vehicles, so a test built on it
    /// would assert an empty map and pass no matter what the layer did.
    ///
    /// The four time keys are rewritten in place and the payload re-decoded through
    /// the same `RESTAPIResponse` path `Fixtures.loadRESTAPIPayload` uses, so
    /// `references` — and therefore each `TripStatus.activeTrip` — still resolve.
    private func upcomingArrivals() throws -> StopArrivals {
        var payload = try #require(
            try JSONSerialization.jsonObject(with: Fixtures.loadData(file: Self.fixtureName)) as? [String: Any]
        )
        var data = try #require(payload["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        var departures = try #require(entry["arrivalsAndDepartures"] as? [[String: Any]])

        for index in departures.indices {
            // Minutes apart so `make`'s soonest-per-route ordering stays meaningful.
            let millis = Int((Date().timeIntervalSince1970 + Double((index + 2) * 60)) * 1000)
            for key in ["predictedArrivalTime", "scheduledArrivalTime", "predictedDepartureTime", "scheduledDepartureTime"] {
                departures[index][key] = millis
            }
        }

        entry["arrivalsAndDepartures"] = departures
        data["entry"] = entry
        payload["data"] = data

        let rewritten = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<StopArrivals>.self, from: rewritten).list
    }

    // MARK: - The symptom

    /// The bug as the rider saw it: route lines, no buses. One emission — the
    /// layer's very first, with no prior state anywhere — has to be enough to put
    /// markers on the map.
    @Test func `The first emission alone puts vehicle markers on the map`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.apply(arrivals: try upcomingArrivals(), isListFiltered: false, preferences: StopPreferences())

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

        layer.apply(arrivals: try upcomingArrivals(), isListFiltered: false, preferences: StopPreferences())
        #expect(vehicles(on: mapView).count == 4)

        // Re-apply the same arrivals, but with the resolver knocked out the way a
        // stale read knocked it out.
        layer.departureProvider = { _ in nil }
        layer.update(model: StopRouteFocusModel.make(
            departures: try upcomingArrivals().arrivalsAndDepartures,
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
