//
//  TripFocusMapLayerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import CoreLocation
import MapKit
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class TripFocusMapLayerTests {

    private let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))

    private func shape(points: Int = 5) -> [CLLocationCoordinate2D] {
        TripMapFocusFixture.shape(points: points)
    }

    private func row(
        _ index: Int,
        stopID: StopID,
        coordinate: CLLocationCoordinate2D?,
        isPassed: Bool = false,
        isTerminal: Bool = false
    ) -> TripStopListModel.Row {
        TripMapFocusFixture.row(index, stopID: stopID, coordinate: coordinate, isPassed: isPassed, isTerminal: isTerminal)
    }

    private func content(
        shape: [CLLocationCoordinate2D],
        progress: Double?,
        stops: [TripStopListModel.Row] = [],
        vehicle: TripStatus? = nil
    ) -> TripMapFocus.Content {
        TripMapFocusFixture.content(shape: shape, progress: progress, stops: stops, vehicle: vehicle)
    }

    private func vehicle() throws -> TripStatus {
        try TripMapFocusFixture.vehicle()
    }

    /// Held for the length of the test. The layer's subscription to the focus
    /// lives in its own `cancellables`, so a layer nobody retains deallocates and
    /// silently stops responding — which in production is `MapRegionManager`'s
    /// job. Without this the "refresh replaces" test passed on stale overlays
    /// nothing was updating.
    private var layer: TripFocusMapLayer!

    /// Drives the layer the way the trip page does: hand it a focus, then push a
    /// value through it.
    @discardableResult
    private func focus(_ content: TripMapFocus.Content?) -> TripMapFocus {
        layer = TripFocusMapLayer(mapView: mapView)
        let focus = TripMapFocus()
        layer.begin(focus: focus)
        focus.apply(content)
        return focus
    }

    private var shapeOverlays: [TripShapeOverlay] {
        mapView.overlays.compactMap { $0 as? TripShapeOverlay }
    }

    private var stopAnnotations: [TripStopAnnotation] {
        mapView.annotations.compactMap { $0 as? TripStopAnnotation }
    }

    private func renderer(for overlay: TripShapeOverlay) -> MKOverlayRenderer? {
        layer.renderer(for: overlay, in: mapView)
    }

    // MARK: - The shape

    /// Each half draws as a casing under a core, and the half ahead adds its
    /// chevrons on top, so a split trip is five overlays, not two.
    @Test func `A trip in progress draws both halves of its shape`() {
        focus(content(shape: shape(), progress: 0.5))

        #expect(shapeOverlays.filter { $0.isSpent }.map(\.part) == [.casing, .core])
        #expect(shapeOverlays.filter { !$0.isSpent }.map(\.part) == [.casing, .core, .arrows])
    }

    /// No reported progress is not zero progress. Nothing is known to have been
    /// travelled, so nothing may be drawn as travelled.
    @Test func `A trip with no reported progress draws entirely as ahead`() {
        focus(content(shape: shape(), progress: nil))

        #expect(shapeOverlays.allSatisfy { !$0.isSpent })
        #expect(shapeOverlays.count == 3)
    }

    @Test func `A trip that has not started draws no travelled half`() {
        focus(content(shape: shape(), progress: 0))

        #expect(shapeOverlays.allSatisfy { !$0.isSpent })
    }

    @Test func `Only the line still ahead draws direction arrows`() {
        focus(content(shape: shape(), progress: 0.5))

        let arrowLines = shapeOverlays.filter { renderer(for: $0) is RouteArrowRenderer }
        #expect(arrowLines.count == 1)
        #expect(arrowLines.allSatisfy { !$0.isSpent && $0.part == .arrows })
        // The lines themselves stay MapKit's own, drawn as vectors at the zoom shown.
        #expect(shapeOverlays.filter { $0.part != .arrows }.allSatisfy { type(of: renderer(for: $0)!) == MKPolylineRenderer.self })
    }

    /// The issue that prompted the redesign: chevrons landing on top of stop dots.
    @Test func `Direction arrows keep clear of the trip's stops`() throws {
        let stop = CLLocationCoordinate2D(latitude: 47, longitude: -121.985)
        focus(content(shape: shape(), progress: 0, stops: [row(0, stopID: "A", coordinate: stop)]))

        let line = try #require(shapeOverlays.first { $0.part == .arrows })
        let lineRenderer = try #require(renderer(for: line) as? RouteArrowRenderer)
        // Close enough that the stop sits among several candidates.
        let zoomScale: MKZoomScale = 0.05
        let stopPoint = MKMapPoint(stop)
        func isClear(_ arrow: RouteArrowLayout.Arrow) -> Bool {
            hypot(arrow.point.x - stopPoint.x, arrow.point.y - stopPoint.y) * zoomScale >= RouteArrowLayout.Rules.markerClearance
        }

        // Without the stop, a chevron would land on it — so a clear result below is
        // the layer's doing, not luck.
        let unobstructed = RouteArrowLayout(points: shape().map { CGPoint(x: MKMapPoint($0).x, y: MKMapPoint($0).y) })
        #expect(!unobstructed.arrows(scale: zoomScale).allSatisfy(isClear))

        let arrows = lineRenderer.arrows(scale: zoomScale)
        #expect(!arrows.isEmpty)
        #expect(arrows.allSatisfy(isClear))
    }

    /// An agency that publishes no shape still gets a usable map: the stops carry
    /// the trip's path on their own.
    @Test func `A trip with no shape still draws its stops`() {
        focus(content(
            shape: [],
            progress: 0.5,
            stops: [row(0, stopID: "A", coordinate: CLLocationCoordinate2D(latitude: 47, longitude: -122))]
        ))

        #expect(shapeOverlays.isEmpty)
        #expect(stopAnnotations.count == 1)
    }

    // MARK: - Stops

    @Test func `Every stop with a location gets a dot`() {
        let coordinate = CLLocationCoordinate2D(latitude: 47, longitude: -122)
        focus(content(
            shape: shape(),
            progress: 0.5,
            stops: [
                row(0, stopID: "A", coordinate: coordinate, isPassed: true),
                row(1, stopID: "B", coordinate: coordinate),
                row(2, stopID: "C", coordinate: coordinate, isTerminal: true)
            ]
        ))

        #expect(stopAnnotations.count == 3)
        #expect(stopAnnotations.filter(\.isPassed).count == 1)
        #expect(stopAnnotations.filter(\.isTerminal).count == 1)
    }

    /// A feed that omits one stop's location costs that dot and nothing else —
    /// and specifically must not place it at Null Island.
    @Test func `A stop with no location is skipped rather than faked`() {
        focus(content(
            shape: shape(),
            progress: 0.5,
            stops: [
                row(0, stopID: "A", coordinate: CLLocationCoordinate2D(latitude: 47, longitude: -122)),
                row(1, stopID: "B", coordinate: nil)
            ]
        ))

        #expect(stopAnnotations.count == 1)
        #expect(stopAnnotations.allSatisfy { !$0.coordinate.isNullIsland })
    }

    // MARK: - Camera

    /// The bus is what the rider opened the page for. Framing the whole line
    /// instead — several miles of it — shrinks the bus to a speck, which is the
    /// behaviour this replaced.
    @Test func `A trip with a live vehicle frames the bus, not the whole line`() throws {
        let status = try vehicle()
        let line = shape()

        focus(content(shape: line, progress: 0.5, vehicle: status))

        #expect(mapView.visibleMapRect.contains(MKMapPoint(status.coordinate)))
        #expect(!mapView.visibleMapRect.contains(MKMapPoint(line[0])))
    }

    /// No reported position, so there's nothing better to frame than where the
    /// trip is going.
    @Test func `A trip with no vehicle position frames the part still ahead`() {
        let line = shape()

        focus(content(shape: line, progress: 0.5))

        #expect(mapView.visibleMapRect.contains(MKMapPoint(line[4])))
        #expect(!mapView.visibleMapRect.contains(MKMapPoint(line[0])))
    }

    /// Framing is once per trip. The position refreshes every 30s, and a camera
    /// that re-framed on each tick would snatch the map back from a rider who
    /// had panned away to look at something else.
    @Test func `A refresh leaves the camera where the rider put it`() throws {
        let focus = focus(content(shape: shape(), progress: 0.5, vehicle: try vehicle()))

        let panned = MKMapRect(origin: MKMapPoint(CLLocationCoordinate2D(latitude: 40, longitude: -80)),
                               size: MKMapSize(width: 10000, height: 10000))
        mapView.visibleMapRect = panned
        focus.apply(content(shape: shape(), progress: 0.6, vehicle: try vehicle()))

        #expect(!mapView.visibleMapRect.contains(MKMapPoint(try vehicle().coordinate)))
    }

    // MARK: - Lifecycle

    @Test func `Ending the focus takes everything off the map`() {
        focus(content(
            shape: shape(),
            progress: 0.5,
            stops: [row(0, stopID: "A", coordinate: CLLocationCoordinate2D(latitude: 47, longitude: -122))]
        ))

        layer.end()

        #expect(shapeOverlays.isEmpty)
        #expect(stopAnnotations.isEmpty)
    }

    /// A refresh replaces what's drawn rather than adding to it — otherwise every
    /// 30s tick would stack another copy of the line on the map.
    @Test func `A refresh replaces the drawn trip instead of stacking on it`() {
        let focus = focus(content(shape: shape(), progress: 0.5))
        let firstCount = shapeOverlays.count

        focus.apply(content(shape: shape(), progress: 0.6))

        #expect(shapeOverlays.count == firstCount)
    }

    /// Polling used to `removeAnnotation`/`addAnnotation` the bus on every
    /// tick. MapKit treats that as a new pin, so the marker pops instead of
    /// sliding, and any open callout is dismissed. Keep the same object.
    /// See: https://github.com/OneBusAway/onebusaway-ios/issues/1109
    @Test func `A refresh moves the existing vehicle annotation instead of replacing it`() throws {
        let status = try vehicle()
        let focus = focus(content(shape: shape(), progress: 0.5, vehicle: status))
        let first = try #require(mapView.annotations.compactMap { $0 as? VehicleAnnotation }.first)

        focus.apply(content(shape: shape(), progress: 0.6, vehicle: status))

        let after = mapView.annotations.compactMap { $0 as? VehicleAnnotation }
        #expect(after.count == 1)
        #expect(after.first === first)
    }

    @Test func `Clearing the focus clears the map`() {
        let focus = focus(content(shape: shape(), progress: 0.5))

        focus.clear()

        #expect(shapeOverlays.isEmpty)
    }

    // MARK: - Estimated position

    private var vehicleAnnotations: [VehicleAnnotation] {
        mapView.annotations.compactMap { $0 as? VehicleAnnotation }
    }

    /// The shape fixture runs east along latitude 47.
    private let alongShape = CLLocationCoordinate2D(latitude: 47, longitude: -121.975)

    @Test func `An estimate moves the vehicle marker without replacing it`() throws {
        let focus = focus(content(shape: shape(), progress: 0.2, vehicle: try vehicle()))
        let marker = try #require(vehicleAnnotations.first)

        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape))

        #expect(vehicleAnnotations.count == 1)
        #expect(vehicleAnnotations.first === marker)
        #expect(marker.coordinate.latitude == alongShape.latitude)
        #expect(marker.coordinate.longitude == alongShape.longitude)
    }

    /// Polls still arrive every 30 s with the raw fix. Moving the marker to it
    /// would yank an estimated bus back to where it was a minute ago.
    @Test func `A poll does not drag an estimated marker back to the reported fix`() throws {
        let status = try vehicle()
        let focus = focus(content(shape: shape(), progress: 0.2, vehicle: status))
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape))

        focus.apply(content(shape: shape(), progress: 0.25, vehicle: status))

        let marker = try #require(vehicleAnnotations.first)
        #expect(marker.coordinate.longitude == alongShape.longitude)
    }

    @Test func `A marker drawn while an estimate is running starts at the estimate`() throws {
        let focus = focus(content(shape: shape(), progress: 0.2))
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape))

        focus.apply(content(shape: shape(), progress: 0.2, vehicle: try vehicle()))

        let marker = try #require(vehicleAnnotations.first)
        #expect(marker.coordinate.longitude == alongShape.longitude)
    }

    @Test func `Clearing the estimate puts the marker back on the reported fix`() throws {
        let status = try vehicle()
        let focus = focus(content(shape: shape(), progress: 0.2, vehicle: status))
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape))

        focus.applyVehicleEstimate(nil)

        let marker = try #require(vehicleAnnotations.first)
        #expect(marker.coordinate.latitude == status.coordinate.latitude)
        #expect(marker.coordinate.longitude == status.coordinate.longitude)
    }

    private func unit(_ fraction: Double) -> CGFloat {
        TripShapeSplit.unitDistance(coordinates: shape(), atFraction: fraction)
    }

    private func lineRenderer(isSpent: Bool, part: RouteLinePart = .core) throws -> MKPolylineRenderer {
        let overlay = try #require(shapeOverlays.first { $0.isSpent == isSpent && $0.part == part })
        return try #require(renderer(for: overlay) as? MKPolylineRenderer)
    }

    /// The line's gray-to-colored join is where the bus is, on every tick: the
    /// colored line never trails behind the marker. A tick moves the join by
    /// stroking less of a line drawn once, not by drawing a new one.
    @Test func `Every tick cuts the line at the marker without replacing it`() throws {
        let focus = focus(content(shape: shape(), progress: 0.2, vehicle: try vehicle()))

        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.6))
        let drawn = shapeOverlays.map(ObjectIdentifier.init)
        #expect(shapeOverlays.allSatisfy { $0.pointCount == shape().count })
        expectClose(Double(try lineRenderer(isSpent: false).strokeStart), Double(unit(0.6)), within: 1e-9)
        expectClose(Double(try lineRenderer(isSpent: true).strokeEnd), Double(unit(0.6)), within: 1e-9)

        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.61, shouldSnap: false))
        #expect(shapeOverlays.map(ObjectIdentifier.init) == drawn)
        expectClose(Double(try lineRenderer(isSpent: false).strokeStart), Double(unit(0.61)), within: 1e-9)
        expectClose(Double(try lineRenderer(isSpent: false, part: .casing).strokeStart), Double(unit(0.61)), within: 1e-9)
        expectClose(Double(try lineRenderer(isSpent: true).strokeEnd), Double(unit(0.61)), within: 1e-9)
    }

    @Test func `Direction arrows start at the marker`() throws {
        let focus = focus(content(shape: shape(), progress: 0.2, vehicle: try vehicle()))
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.6))

        let arrows = try #require(try lineRenderer(isSpent: false, part: .arrows) as? RouteArrowRenderer)
        let cut = MKMapPoint(TripShapeSplit.split(coordinates: shape(), atFraction: 0.6).ahead[0]).x
        let placed = arrows.arrows(scale: 0.05)
        #expect(!placed.isEmpty)
        #expect(placed.allSatisfy { $0.point.x >= cut })
    }

    @Test func `A poll keeps the line cut at the estimate`() throws {
        let status = try vehicle()
        let focus = focus(content(shape: shape(), progress: 0.2, vehicle: status))
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.6))

        focus.apply(content(shape: shape(), progress: 0.25, vehicle: status))

        expectClose(Double(try lineRenderer(isSpent: false).strokeStart), Double(unit(0.6)), within: 1e-9)
    }

    @Test func `Without an estimate the line is cut at the reported progress again`() throws {
        let focus = focus(content(shape: shape(), progress: 0.2, vehicle: try vehicle()))
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape, progress: 0.6))

        focus.applyVehicleEstimate(nil)

        let spent = try #require(shapeOverlays.first { $0.isSpent && $0.part == .core })
        expectClose(spent.points()[spent.pointCount - 1].coordinate.longitude, -121.992, within: 0.0005)
        #expect(try lineRenderer(isSpent: false).strokeStart == 0)
    }

    // MARK: - Reported positions (debug)

    private var reportedPositions: [ReportedPositionAnnotation] {
        mapView.annotations.compactMap { $0 as? ReportedPositionAnnotation }
    }

    @Test func `The debug overlay marks the reported fix and the server's position beside an estimate`() throws {
        let status = try vehicle()
        let focus = focus(TripMapFocusFixture.content(shape: shape(), progress: 0.2, vehicle: status, showsReportedPositions: true))
        #expect(reportedPositions.isEmpty)

        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape))

        let gps = try #require(reportedPositions.first { $0.kind == .lastKnownLocation })
        #expect(gps.coordinate.latitude == status.lastKnownLocation?.coordinate.latitude)
        let server = try #require(reportedPositions.first { $0.kind == .serverPosition })
        #expect(server.coordinate.latitude == status.position?.coordinate.latitude)
        #expect(reportedPositions.count == 2)

        focus.apply(TripMapFocusFixture.content(shape: shape(), progress: 0.25, vehicle: status, showsReportedPositions: true))
        #expect(reportedPositions.count == 2)

        focus.applyVehicleEstimate(nil)
        #expect(reportedPositions.isEmpty)
    }

    @Test func `Without the debug toggle no reported positions are drawn`() throws {
        let focus = focus(TripMapFocusFixture.content(shape: shape(), progress: 0.2, vehicle: try vehicle()))
        focus.applyVehicleEstimate(TripMapFocusFixture.estimate(at: alongShape))
        #expect(reportedPositions.isEmpty)
    }
}

