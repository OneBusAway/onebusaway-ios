//
//  StopRouteFocusLaneTests.swift
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

/// The stop's routes draw side by side where they share a street (#1569), measured
/// on screen; `RouteLaneLayoutTests` covers the layout itself.
@MainActor
@Suite(.serialized)
final class StopRouteFocusLaneTests {

    /// A two-point line near downtown Seattle; the default cache gives it to every route.
    private func encodedSeattleLine() -> String {
        Polyline(coordinates: [
            CLLocationCoordinate2D(latitude: 47.60, longitude: -122.33),
            CLLocationCoordinate2D(latitude: 47.61, longitude: -122.34)
        ]).encodedPolyline
    }

    private func makeLayer(mapView: MKMapView, shapeCache: ShapeCache? = nil) -> StopRouteFocusMapLayer {
        let formatters = Formatters(
            locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared
        )
        let cache = shapeCache ?? ShapeCache { [encoded = encodedSeattleLine()] _ in encoded }
        return StopRouteFocusMapLayer(mapView: mapView, shapeCache: cache, formatters: formatters)
    }

    /// Routes with a shape each and no vehicles.
    private func model(routeIDs: [RouteID]) -> StopRouteFocusModel {
        StopRouteFocusModel(
            routes: routeIDs.map {
                StopRouteFocusModel.DrawnRoute(routeID: $0, shortName: $0, color: .systemBlue, shapeID: "s_\($0)", hasLiveVehicle: false)
            },
            vehicles: []
        )
    }

    /// A map with a size, framed on `encodedSeattleLine`, so screen distances mean something.
    private func makeSizedMapView() -> MKMapView {
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        frame(mapView, span: 0.02)
        return mapView
    }

    private func frame(_ mapView: MKMapView, span: CLLocationDegrees) {
        mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.605, longitude: -122.335),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        ), animated: false)
    }

    /// How far apart, in screen points, the middles of two routes' lines are drawn.
    private func gap(between first: RouteID, and second: RouteID, on mapView: MKMapView) throws -> CGFloat {
        let a = screenMiddle(of: try coreOverlay(for: first, on: mapView), on: mapView)
        let b = screenMiddle(of: try coreOverlay(for: second, on: mapView), on: mapView)
        return hypot(a.x - b.x, a.y - b.y)
    }

    private func coreOverlay(for routeID: RouteID, on mapView: MKMapView) throws -> RouteShapeOverlay {
        try #require(mapView.overlays.compactMap { $0 as? RouteShapeOverlay }.first { $0.routeID == routeID && $0.part == .core })
    }

    /// The overlay's middle point, in the map view's points.
    private func screenMiddle(of overlay: RouteShapeOverlay, on mapView: MKMapView) -> CGPoint {
        mapView.convert(overlay.points()[overlay.pointCount / 2].coordinate, toPointTo: mapView)
    }

    /// Every route in `model` gets the same shape from the default cache.
    @Test func `Two routes on the same street draw side by side`() async throws {
        let mapView = makeSizedMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H", "62"]))
        await layer.awaitPendingShapeWork()

        #expect(abs(try gap(between: "H", and: "62", on: mapView) - StopRouteFocusMapLayer.laneWidth) < 1.5)
    }

    @Test func `A route on its own street draws exactly its shape`() async throws {
        let mapView = makeSizedMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())

        layer.update(model: model(routeIDs: ["H"]))
        await layer.awaitPendingShapeWork()

        let core = try coreOverlay(for: "H", on: mapView)
        let shape = try #require(Polyline(encodedPolyline: encodedSeattleLine()).coordinates)
        let first = core.points()[0].coordinate, last = core.points()[core.pointCount - 1].coordinate
        #expect(abs(first.latitude - shape[0].latitude) < 1e-9 && abs(first.longitude - shape[0].longitude) < 1e-9)
        #expect(abs(last.latitude - shape[1].latitude) < 1e-9 && abs(last.longitude - shape[1].longitude) < 1e-9)
    }

    /// The lanes are a line's width apart on screen, so a new zoom has to move them.
    @Test func `Zooming in keeps shared routes a lane apart`() async throws {
        let mapView = makeSizedMapView()
        let layer = makeLayer(mapView: mapView)
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H", "62"]))
        await layer.awaitPendingShapeWork()

        frame(mapView, span: 0.005)
        layer.viewportDidChange(mapView.visibleMapRect)

        #expect(abs(try gap(between: "H", and: "62", on: mapView) - StopRouteFocusMapLayer.laneWidth) < 1.5)
        // Redrawn, not stacked on top of the old lines.
        #expect(mapView.overlays.compactMap { $0 as? RouteShapeOverlay }.count == 6)
    }

    /// Only shared lines depend on the zoom; one alone on its street isn't redrawn.
    @Test func `Zooming leaves a line on its own street as it was`() async throws {
        let mapView = makeSizedMapView()
        let elsewhere = Polyline(coordinates: [
            CLLocationCoordinate2D(latitude: 47.62, longitude: -122.30),
            CLLocationCoordinate2D(latitude: 47.63, longitude: -122.31)
        ]).encodedPolyline
        let cache = ShapeCache { [shared = encodedSeattleLine()] shapeID in ["s_8": elsewhere][shapeID] ?? shared }
        let layer = makeLayer(mapView: mapView, shapeCache: cache)
        layer.begin(focus: StopMapFocus())
        layer.update(model: model(routeIDs: ["H", "62", "8"]))
        await layer.awaitPendingShapeWork()
        let alone = try coreOverlay(for: "8", on: mapView)

        frame(mapView, span: 0.005)
        layer.viewportDidChange(mapView.visibleMapRect)

        #expect(try coreOverlay(for: "8", on: mapView) === alone)
        #expect(abs(try gap(between: "H", and: "62", on: mapView) - StopRouteFocusMapLayer.laneWidth) < 1.5)
    }
}
