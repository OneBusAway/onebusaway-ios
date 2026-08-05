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

    private static let formatters = Formatters(
        locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared
    )

    private func makeLayer(
        mapView: MKMapView,
        shapeCache: ShapeCache? = nil
    ) -> StopRouteFocusMapLayer {
        let cache = shapeCache ?? ShapeCache { [encoded = encodedSeattleLine()] _ in encoded }
        let layer = StopRouteFocusMapLayer(mapView: mapView, shapeCache: cache, formatters: Self.formatters)
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

    /// Two vehicles running the same route — the case where "the tapped marker"
    /// and "the route's first marker" are different objects.
    private func twoVehicleModel(routeID: RouteID) -> StopRouteFocusModel {
        StopRouteFocusModel(
            routes: [
                StopRouteFocusModel.DrawnRoute(
                    routeID: routeID, shortName: routeID, color: .systemBlue,
                    shapeID: "s_\(routeID)", hasLiveVehicle: true
                )
            ],
            vehicles: (1...2).map { index in
                StopRouteFocusModel.DrawnVehicle(
                    id: "v\(index)_\(routeID)", routeID: routeID,
                    coordinate: CLLocationCoordinate2D(latitude: 47.6 + Double(index) / 100.0, longitude: -122.3),
                    orientation: 90, departureID: "d\(index)_\(routeID)"
                )
            }
        )
    }

    /// The two vehicles of `twoVehicleModel`, ordered by ID so "first" and
    /// "second" mean the same thing to every test.
    private func vehicles(on mapView: MKMapView) -> [StopVehicleAnnotation] {
        mapView.annotations
            .compactMap { $0 as? StopVehicleAnnotation }
            .sorted { $0.id < $1.id }
    }

    /// What `MapViewController.mapView(_:didSelect:)` does on a marker tap:
    /// MapKit has already selected the tapped marker, then the controller routes
    /// the tap into the layer.
    private func tap(_ annotation: StopVehicleAnnotation, on mapView: MKMapView, in layer: StopRouteFocusMapLayer) {
        mapView.selectAnnotation(annotation, animated: false)
        layer.didSelectVehicle(annotation)
    }

    /// Regression: tapping a vehicle marker routes into the layer, whose
    /// `focusedRouteID` sink opens "the route's" callout. That lookup took the
    /// route's FIRST annotation, so tapping the second bus on a route yanked
    /// selection over to the first one — the rider tapped one vehicle and got a
    /// different vehicle's callout.
    @Test func `Tapping the second vehicle on a route leaves that vehicle selected`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: twoVehicleModel(routeID: "H"))

        let onMap = vehicles(on: mapView)
        #expect(onMap.count == 2)
        let second = try #require(onMap.last)

        tap(second, on: mapView, in: layer)

        #expect(mapView.selectedAnnotations.first === second)
    }

    /// Regression: focus is per-route but the gesture is per-vehicle, and the
    /// marker tap used to call `toggleFocus`. Tapping the second bus on a route
    /// the rider was already following therefore unfocused it — right callout,
    /// but the route line stopped being highlighted.
    @Test func `Tapping a second vehicle on a focused route keeps the route focused`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.update(model: twoVehicleModel(routeID: "H"))

        let onMap = vehicles(on: mapView)
        let first = try #require(onMap.first)
        let second = try #require(onMap.last)

        tap(first, on: mapView, in: layer)
        #expect(focus.focusedRouteID == "H")

        tap(second, on: mapView, in: layer)

        #expect(focus.focusedRouteID == "H")
        #expect(mapView.selectedAnnotations.first === second)
    }

    /// The escape hatch this must not cost us: at `.tip` the chip row is hidden,
    /// so tapping the focused marker again is the only way to clear focus. A tap
    /// lands here only after the marker has been deselected (tapping an already
    /// selected annotation doesn't re-fire selection), which is why the test
    /// deselects between taps.
    @Test func `Tapping the focused vehicle again clears focus`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.update(model: twoVehicleModel(routeID: "H"))
        let first = try #require(vehicles(on: mapView).first)

        tap(first, on: mapView, in: layer)
        #expect(focus.focusedRouteID == "H")

        mapView.deselectAnnotation(first, animated: false)
        tap(first, on: mapView, in: layer)

        #expect(focus.focusedRouteID == nil)
    }

    /// Focus follows the tap across routes, rather than requiring a clear first.
    @Test func `Tapping a vehicle on another route moves focus to it`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H", "62"]))

        let onMap = vehicles(on: mapView)
        let onH = try #require(onMap.first { $0.routeID == "H" })
        let on62 = try #require(onMap.first { $0.routeID == "62" })

        tap(onH, on: mapView, in: layer)
        #expect(focus.focusedRouteID == "H")

        tap(on62, on: mapView, in: layer)

        #expect(focus.focusedRouteID == "62")
    }

    /// The chip-tap half of the same code path still has to open a callout: with
    /// nothing selected, focusing a route reveals one of its vehicles.
    @Test func `Focusing a route with nothing selected opens one of its vehicles`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.update(model: twoVehicleModel(routeID: "H"))

        focus.toggleFocus(routeID: "H")

        let selected = try #require(mapView.selectedAnnotations.first as? StopVehicleAnnotation)
        #expect(selected.routeID == "H")
    }

    /// The other way a rider ends up looking at the wrong vehicle: annotation
    /// views are recycled, `MKAnnotationView.prepareForReuse` does not clear
    /// accessory views, and the layer used to assign the callout only when the
    /// departure resolved. A recycled view whose new annotation resolves to
    /// nothing then still carried the previous vehicle's callout.
    /// A recycled view, modelled directly: MapKit's reuse queue hands back a view
    /// that still carries the previous vehicle's callout, and
    /// `MKAnnotationView.prepareForReuse` does not clear accessory views.
    ///
    /// Driving `annotationView(for:in:)` cannot reach this state — with nothing
    /// yet recycled the queue returns a fresh view, so the assertion passes with
    /// or without the bug. Hence `configure(_:for:)`.
    @Test func `Configuring a recycled view drops the previous vehicle's callout`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: twoVehicleModel(routeID: "H"))
        let annotation = try #require(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first)

        let recycled = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: nil)
        recycled.detailCalloutAccessoryView = UILabel() // the previous vehicle's callout

        // This vehicle's departure has left the arrival set.
        layer.departureProvider = { _ in nil }
        layer.configure(recycled, for: annotation)

        #expect(recycled.detailCalloutAccessoryView == nil)
    }

    @Test func `Configuring a recycled view installs the new vehicle's callout`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: twoVehicleModel(routeID: "H"))
        let annotation = try #require(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first)

        let recycled = PulsingVehicleAnnotationView(annotation: nil, reuseIdentifier: nil)
        recycled.detailCalloutAccessoryView = UILabel()

        layer.configure(recycled, for: annotation)

        #expect(recycled.detailCalloutAccessoryView is VehicleCalloutView)
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

    @Test func `A surviving vehicle keeps the same annotation object across updates`() throws {
        // Regression: `syncVehicleAnnotations()` used to remove and re-add every
        // marker on every refresh, which dismisses any open callout on the
        // survivor. Diffing by `DrawnVehicle.id` and mutating in place preserves
        // MapKit identity for a vehicle that is still in the arrival set.
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H", "62"]))
        let survivor = try #require(
            mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first { $0.routeID == "H" }
        )

        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H", "62"]))
        let afterRefresh = try #require(
            mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first { $0.routeID == "H" }
        )

        #expect(survivor === afterRefresh)
        #expect(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.count == 2)
    }

    @Test func `Update adds and removes only the delta, keeping survivors`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H", "62"]))
        let survivor = try #require(
            mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first { $0.routeID == "62" }
        )

        // "H" leaves the arrival set, "40" joins it; "62" stays.
        layer.update(model: model(routeIDs: ["62", "40"], vehicleRouteIDs: ["62", "40"]))
        let after = mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }

        #expect(after.count == 2)
        #expect(after.contains { $0 === survivor })
        #expect(!after.contains { $0.routeID == "H" })
        #expect(after.contains { $0.routeID == "40" })
    }

    @Test func `update(model:) is a no-op once end() has cleared focus`() {
        // A disabled layer's deactivate() -> end() clears `focus`, but the
        // arrivals sink that calls update(model:) keeps running until the sheet
        // itself closes. Without the `focus != nil` guard, the next refresh
        // would silently redraw everything the toggle just turned off.
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.end()

        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))

        #expect(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.isEmpty)
        #expect(mapView.overlays.compactMap { $0 as? RouteShapeOverlay }.isEmpty)
    }

    @Test func `invalidateShapeCache clears the cache so the next fetch is a real refetch`() async throws {
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

        await layer.invalidateShapeCache().value

        _ = try? await cache.coordinates(forShapeID: "shape_A")
        #expect(await counter.count == 2)
    }

    // MARK: - Focus wiring (marker tap / chip tap)

    @Test func `A marker tap forwards to the attached focus object`() throws {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))
        let annotation = try #require(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first)

        layer.didSelectVehicle(annotation)

        #expect(focus.focusedRouteID == "H")
    }

    @Test func `Focusing a route selects its vehicle's callout`() throws {
        // The chip-tap half of the spec's focus behavior: focusing a route also
        // opens its vehicle's callout. `toggleFocus(routeID:)` is what a vehicle
        // marker tap calls, and a chip tap calls `StopMapFocus.toggleFocus`
        // directly — both converge on `focusedRouteID`, which this sink observes.
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))
        let annotation = try #require(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first)

        focus.toggleFocus(routeID: "H")

        #expect(mapView.selectedAnnotations.contains { ($0 as? StopVehicleAnnotation) === annotation })
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

    /// The pin `syncRouteOverlays` writes before the fetch starts is what makes
    /// every later refresh skip the route. Left behind after a failure — a
    /// dropped request, or a shape that decodes to a single point — one transient
    /// error costs the route its line for the whole presentation.
    @Test func `A failed shape fetch is unpinned so the next refresh retries it`() async {
        let counter = FetchCounter()
        let encoded = encodedSeattleLine()
        // Fails once, then succeeds: the transient-network case.
        let cache = ShapeCache { _ in
            await counter.increment()
            guard await counter.count > 1 else { throw CancellationError() }
            return encoded
        }
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView, shapeCache: cache)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: [], shapeIDForRoute: { _ in "shape_A" }))
        await layer.awaitPendingShapeWork()
        #expect(await counter.count == 1)
        #expect(mapView.overlays.compactMap { $0 as? RouteShapeOverlay }.isEmpty, "a failed fetch draws nothing")

        // The next arrivals tick, same shape ID. Retried, not skipped.
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: [], shapeIDForRoute: { _ in "shape_A" }))
        await layer.awaitPendingShapeWork()

        #expect(await counter.count == 2)
        #expect(mapView.overlays.compactMap { $0 as? RouteShapeOverlay }.count == 2)
    }

    // MARK: - Vehicle callout

    /// The fixture's second arrival on a different trip ("LAKE CITY WEDGWOOD"
    /// versus the first entry's "SEATTLE CENTER UNIVERSITY DISTRICT"), used to
    /// prove the callout tracks whichever departure `departureProvider` currently
    /// resolves rather than one captured at `update(model:)` time.
    private static let secondFixtureDeparture: ArrivalDeparture? = try? Fixtures.loadRESTAPIPayload(
        type: StopArrivals.self,
        fileName: "arrivals_and_departures_for_stop_1_10020.json"
    ).arrivalsAndDepartures[1]

    @Test func `The callout attaches to the annotation view as detailCalloutAccessoryView`() throws {
        let mapView = MKMapView()
        mapView.registerAnnotationView(PulsingVehicleAnnotationView.self)
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))

        let annotation = try #require(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first)
        let view = layer.annotationView(for: annotation, in: mapView)

        #expect(view?.detailCalloutAccessoryView is VehicleCalloutView)
    }

    @Test func `The callout reads the departure live through departureProvider, not a stale snapshot`() throws {
        let first = try #require(Self.fixtureDeparture)
        let second = try #require(Self.secondFixtureDeparture)
        #expect(first.tripHeadsign != second.tripHeadsign)

        let mapView = MKMapView()
        mapView.registerAnnotationView(PulsingVehicleAnnotationView.self)
        let layer = makeLayer(mapView: mapView)
        var current: ArrivalDeparture? = first
        layer.departureProvider = { _ in current }
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))

        let annotation = try #require(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first)

        let firstView = try #require(layer.annotationView(for: annotation, in: mapView)?.detailCalloutAccessoryView as? VehicleCalloutView)
        #expect(firstView.accessibilityLabel?.contains(try #require(first.tripHeadsign)) == true)

        // Same annotation, no `update(model:)` in between — only the provider's
        // answer changed. If `annotationView(for:in:)` ever cached the departure
        // it read the first time (or the model snapshot from `update`), this
        // second call would still show the first trip's headsign.
        current = second
        let secondView = try #require(layer.annotationView(for: annotation, in: mapView)?.detailCalloutAccessoryView as? VehicleCalloutView)
        #expect(secondView.accessibilityLabel?.contains(try #require(second.tripHeadsign)) == true)
        #expect(secondView.accessibilityLabel?.contains(try #require(first.tripHeadsign)) == false)
    }

    @Test func `Following the callout invokes onFollowTrip with the departure it was built from`() throws {
        let departure = try #require(Self.fixtureDeparture)
        let mapView = MKMapView()
        mapView.registerAnnotationView(PulsingVehicleAnnotationView.self)
        let layer = makeLayer(mapView: mapView)
        layer.departureProvider = { _ in departure }
        var followed: ArrivalDeparture?
        layer.onFollowTrip = { followed = $0 }
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))

        let annotation = try #require(mapView.annotations.compactMap { $0 as? StopVehicleAnnotation }.first)
        let callout = try #require(layer.annotationView(for: annotation, in: mapView)?.detailCalloutAccessoryView as? VehicleCalloutView)
        callout.simulateFollowTap()

        #expect(followed === departure)
    }

    // MARK: - Suppression (yielding the map to the trip page)

    /// Suppression is not `end()`. The stop sheet is still presented underneath
    /// the trip page, so the presentation has to survive and come back intact.
    @Test func `Suppressing the layer takes its content off the map`() async {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))
        await layer.awaitPendingShapeWork()
        #expect(!mapView.overlays.isEmpty)
        #expect(!vehicles(on: mapView).isEmpty)

        layer.setSuppressed(true)

        #expect(mapView.overlays.isEmpty)
        #expect(vehicles(on: mapView).isEmpty)
    }

    @Test func `Unsuppressing puts the stop's routes and vehicles back`() async {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))
        await layer.awaitPendingShapeWork()
        layer.setSuppressed(true)

        layer.setSuppressed(false)
        await layer.awaitPendingShapeWork()

        #expect(!mapView.overlays.isEmpty, "the route line should be drawn again")
        #expect(!vehicles(on: mapView).isEmpty, "the vehicles should be back")
    }

    /// The arrivals feed keeps ticking behind the trip page. If a refresh redrew
    /// while suppressed, the stop's routes would reappear on top of the trip the
    /// rider is following.
    @Test func `An arrivals refresh while suppressed draws nothing`() async {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.setSuppressed(true)

        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))
        await layer.awaitPendingShapeWork()

        #expect(mapView.overlays.isEmpty)
        #expect(vehicles(on: mapView).isEmpty)
    }

    /// The chips read their decoration from the model, so it has to stay current
    /// even while nothing is drawn.
    @Test func `A refresh while suppressed still reaches the focus object`() {
        let layer = makeLayer(mapView: MKMapView())
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.setSuppressed(true)

        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))

        #expect(focus.isFocusable(routeID: "H"))
    }

    @Test func `Ending the presentation clears suppression`() async {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.setSuppressed(true)

        layer.end()
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))
        await layer.awaitPendingShapeWork()

        #expect(!mapView.overlays.isEmpty, "a fresh presentation must not inherit suppression")
    }
}
