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

@MainActor
@Suite(.serialized)
final class StopRouteFocusMapLayerTests {

    private func makeLayer(mapView: MKMapView) -> StopRouteFocusMapLayer {
        let layer = StopRouteFocusMapLayer(mapView: mapView, shapeCache: ShapeCache { _ in "" })
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
    private static let fixtureDeparture: ArrivalDeparture? = try? Fixtures.loadRESTAPIPayload(
        type: StopArrivals.self,
        fileName: "arrivals_and_departures_for_stop_1_10020.json"
    ).arrivalsAndDepartures.first

    private func model(routeIDs: [RouteID], vehicleRouteIDs: [RouteID]) -> StopRouteFocusModel {
        StopRouteFocusModel(
            routes: routeIDs.map {
                StopRouteFocusModel.DrawnRoute(
                    routeID: $0, shortName: $0, color: .systemBlue,
                    shapeID: "s_\($0)", hasLiveVehicle: vehicleRouteIDs.contains($0)
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

    @Test func `end removes everything the layer added`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H"], vehicleRouteIDs: ["H"]))

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

    @Test func `An unfocused route dims when another route is focused`() {
        let mapView = MKMapView()
        let layer = makeLayer(mapView: mapView)
        let focus = StopMapFocus()
        layer.begin(focus: focus)
        layer.update(model: model(routeIDs: ["H", "62"], vehicleRouteIDs: ["H", "62"]))

        focus.toggleFocus(routeID: "H")

        var coords = [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
                      CLLocationCoordinate2D(latitude: 47.7, longitude: -122.4)]
        _ = coords
        let dimmed = RouteShapeOverlay.make(coordinates: coords, routeID: "62", isCasing: false)
        let focused = RouteShapeOverlay.make(coordinates: coords, routeID: "H", isCasing: false)

        let dimmedAlpha = (layer.renderer(for: dimmed, in: mapView) as? MKPolylineRenderer)?.alpha
        let focusedAlpha = (layer.renderer(for: focused, in: mapView) as? MKPolylineRenderer)?.alpha

        #expect(dimmedAlpha! < focusedAlpha!)
    }
}
