//
//  StopRouteFocusMapLayerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

/// Records calls to the two overlay mutation entry points `restyleOverlays()`'s
/// remove/re-add fallback relies on, so a test can prove that fallback actually
/// fired against real map content — not just that its styling math is correct
/// when called directly on freshly-constructed overlays.
private final class OverlayTrackingMapView: MKMapView {
    private(set) var removeOverlaysCallCount = 0
    private(set) var addOverlaysCallCount = 0

    override func removeOverlays(_ overlays: [MKOverlay]) {
        removeOverlaysCallCount += 1
        super.removeOverlays(overlays)
    }

    override func addOverlays(_ overlays: [MKOverlay], level: MKOverlayLevel) {
        addOverlaysCallCount += 1
        super.addOverlays(overlays, level: level)
    }
}

@MainActor
@Suite(.serialized)
final class StopRouteFocusMapLayerTests {

    /// Counts fetches so shape-pinning tests can prove a refetch did NOT happen.
    private actor FetchCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    /// A real Google-encoded polyline (two points near downtown Seattle) —
    /// same idiom `ShapeCacheTests.encodedSeattleLine()` (Task 4) established.
    /// A cache backed by `{ _ in "" }`, which every test used before this fix,
    /// makes `fetchAndDrawShape`'s `coordinates.count > 1` guard fail every
    /// time, so `overlays` is never populated and the restyle fallback is never
    /// exercised against real content. Using a real encoded string is what
    /// makes overlays actually land on the map.
    private func encodedSeattleLine() -> String {
        Polyline(coordinates: [
            CLLocationCoordinate2D(latitude: 47.60, longitude: -122.33),
            CLLocationCoordinate2D(latitude: 47.61, longitude: -122.34)
        ]).encodedPolyline
    }

    private func makeLayer(
        mapView: MKMapView,
        shapeCache: ShapeCache? = nil
    ) -> StopRouteFocusMapLayer {
        let cache = shapeCache ?? ShapeCache { [encoded = encodedSeattleLine()] _ in encoded }
        let layer = StopRouteFocusMapLayer(mapView: mapView, shapeCache: cache)
        // REQUIRED: `syncVehicleAnnotations` builds nothing without a resolvable
        // departure, because `StopVehicleAnnotation` needs a non-nil `TripStatus`
        // (see Task 7). Backed by a fixture-loaded `ArrivalDeparture`.
        layer.departureProvider = { _ in Self.fixtureDeparture }
        return layer
    }

    /// A fixture-loaded `ArrivalDeparture` with a non-nil `tripStatus`. Reuses the
    /// exact fixture Task 5 already validated for this purpose:
    /// `arrivals_and_departures_for_stop_1_10020.json`, decoded via
    /// `Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName:)`. Every
    /// arrival in that fixture carries an embedded `tripStatus` object (confirmed
    /// by inspecting the JSON directly), so the first entry is a usable stand-in
    /// for whatever departure ID `departureProvider` is asked to resolve — the
    /// tests only care that a `TripStatus` is available, not which one.
    ///
    /// Note: `Fixtures.loadRESTAPIPayload` does NOT resolve references as part of
    /// decoding (`Fixtures.swift:53-57` just decodes and returns `.list`) — that
    /// doesn't matter here because this fixture's `tripStatus` is embedded inline
    /// per arrival rather than reference-resolved.
    private static let fixtureDeparture: ArrivalDeparture? = try? Fixtures.loadRESTAPIPayload(
        type: StopArrivals.self,
        fileName: "arrivals_and_departures_for_stop_1_10020.json"
    ).arrivalsAndDepartures.first

    private func model(
        routeIDs: [RouteID],
        vehicleRouteIDs: [RouteID],
        shapeIDForRoute: (RouteID) -> String? = { "s_\($0)" }
    ) -> StopRouteFocusModel {
        StopRouteFocusModel(
            routes: routeIDs.map {
                StopRouteFocusModel.DrawnRoute(
                    routeID: $0, shortName: $0, color: .systemBlue,
                    shapeID: shapeIDForRoute($0), hasLiveVehicle: vehicleRouteIDs.contains($0)
                )
            },
            vehicles: vehicleRouteIDs.map {
                StopRouteFocusModel.DrawnVehicle(
                    id: "v_\($0)", routeID: $0,
                    coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
                    orientation: 90, departureID: "d_\($0)"
                )
            }
        )
    }

    @Test func `Update adds one vehicle annotation per drawn vehicle`() {
        #expect(Self.fixtureDeparture != nil)
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H"]))

        #expect(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.count == 1)
    }

    @Test func `Update replaces rather than accumulates markers`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))

        #expect(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.count == 1)
    }

    @Test func `Update draws a casing and a core overlay per route with a shape`() async {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H", "62"]))
        await layer.awaitPendingShapeWork()

        let overlays = mapView.overlays.compactMap { $0 as? RouteShapeOverlay }
        #expect(overlays.count == 4)
        for routeID in ["H", "62"] {
            let forRoute = overlays.filter { $0.routeID == routeID }
            #expect(forRoute.count == 2)
            #expect(forRoute.filter(\.isCasing).count == 1)
            #expect(forRoute.filter { !$0.isCasing }.count == 1)
        }
    }

    @Test func `end removes everything the layer added`() async {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))
        await layer.awaitPendingShapeWork()
        // Confirm there is real content to remove — otherwise this test would
        // trivially pass against an already-empty map.
        #expect(!mapView.overlays.compactMap { $0 as? RouteShapeOverlay }.isEmpty)
        #expect(!mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.isEmpty)

        layer.end()

        #expect(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.isEmpty)
        #expect(mapView.overlays.compactMap { $0 as? RouteShapeOverlay }.isEmpty)
    }

    @Test func `Renderer styles the casing wider than the core`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        var coords = [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
                      CLLocationCoordinate2D(latitude: 47.7, longitude: -122.4)]
        let casing = RouteShapeOverlay.make(coordinates: coords, routeID: "H", isCasing: true)
        let core = RouteShapeOverlay.make(coordinates: coords, routeID: "H", isCasing: false)
        _ = coords

        let casingWidth = (layer.renderer(for: casing, in: mapView) as? MKPolylineRenderer)?.lineWidth
        let coreWidth = (layer.renderer(for: core, in: mapView) as? MKPolylineRenderer)?.lineWidth

        #expect(casingWidth != nil && coreWidth != nil)
        #expect(casingWidth! > coreWidth!)
    }

    @Test func `Renderer ignores overlays that are not ours`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        var coords = [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
                      CLLocationCoordinate2D(latitude: 47.7, longitude: -122.4)]
        let plain = MKPolyline(coordinates: &coords, count: coords.count)

        #expect(layer.renderer(for: plain, in: mapView) == nil)
    }

    @Test func `An unfocused route dims when another route is focused`() async {
        let mapView = OverlayTrackingMapView()
        let layer = makeLayer(mapView: mapView)
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H", "62"]))
        await layer.awaitPendingShapeWork()

        let overlaysBeforeToggle = mapView.overlays.compactMap { $0 as? RouteShapeOverlay }
        #expect(overlaysBeforeToggle.count == 4)
        let addOverlaysCallCountBeforeToggle = mapView.addOverlaysCallCount

        focus.toggleFocus(routeID: "H")

        // `mapView` has no window, so `mapView.renderer(for:)` returns nil for
        // every overlay MapKit hasn't rendered — which, headlessly, is all of
        // them. That is exactly the case `restyleOverlays()`'s remove/re-add
        // fallback exists for. Prove it actually ran, rather than trusting that
        // the styling math alone means the fallback fired.
        #expect(mapView.addOverlaysCallCount > addOverlaysCallCountBeforeToggle)
        #expect(mapView.removeOverlaysCallCount > 0)

        // The overlays are still the ones on the map post-toggle (same content,
        // re-added) — pull them from the map itself, not fresh instances, so the
        // alpha assertion is about what `restyleOverlays()` actually left behind.
        let overlaysAfterToggle = mapView.overlays.compactMap { $0 as? RouteShapeOverlay }
        #expect(overlaysAfterToggle.count == 4)

        let dimmedCore = overlaysAfterToggle.first { $0.routeID == "62" && !$0.isCasing }
        let focusedCore = overlaysAfterToggle.first { $0.routeID == "H" && !$0.isCasing }
        #expect(dimmedCore != nil && focusedCore != nil)

        let dimmedAlpha = (layer.renderer(for: dimmedCore!, in: mapView) as? MKPolylineRenderer)?.alpha
        let focusedAlpha = (layer.renderer(for: focusedCore!, in: mapView) as? MKPolylineRenderer)?.alpha

        #expect(dimmedAlpha! < focusedAlpha!)
    }

    @Test func `Shape pinning holds when the soonest departure rolls over to a different shapeID`() async {
        let counter = FetchCounter()
        let encoded = encodedSeattleLine()
        let cache = ShapeCache { _ in
            await counter.increment()
            return encoded
        }
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView, shapeCache: cache)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: [], shapeIDForRoute: { _ in "shape_A" }))
        await layer.awaitPendingShapeWork()
        #expect(await counter.count == 1)
        let overlaysAfterFirst = mapView.overlays.compactMap { $0 as? RouteShapeOverlay }
        #expect(overlaysAfterFirst.count == 2)

        // The soonest arrival for "H" rolled over to a different trip, with a
        // different shapeID. `drawnShapeIDsByRoute` should keep the line pinned
        // to what's already drawn rather than refetching and redrawing.
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: [], shapeIDForRoute: { _ in "shape_B" }))
        await layer.awaitPendingShapeWork()

        #expect(await counter.count == 1)
        let overlaysAfterSecond = mapView.overlays.compactMap { $0 as? RouteShapeOverlay }
        #expect(overlaysAfterSecond.count == 2)
        // Same overlay instances, not rebuilt — the line is literally unchanged,
        // not just numerically equal.
        #expect(Set(overlaysAfterSecond.map(ObjectIdentifier.init)) == Set(overlaysAfterFirst.map(ObjectIdentifier.init)))
    }
}
