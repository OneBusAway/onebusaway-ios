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
        (0..<points).map { CLLocationCoordinate2D(latitude: 47, longitude: -122 + Double($0) * 0.01) }
    }

    private func row(
        _ index: Int,
        stopID: StopID,
        coordinate: CLLocationCoordinate2D?,
        isPassed: Bool = false,
        isTerminal: Bool = false
    ) -> TripStopListModel.Row {
        TripStopListModel.Row(
            id: "\(index)-\(stopID)",
            stopID: stopID,
            name: "Stop \(stopID)",
            coordinate: coordinate,
            date: nil,
            isPassed: isPassed,
            isVehicleHere: false,
            isUserStop: false,
            isTerminal: isTerminal
        )
    }

    private func content(
        shape: [CLLocationCoordinate2D],
        progress: Double?,
        stops: [TripStopListModel.Row] = [],
        vehicle: TripStatus? = nil
    ) -> TripMapFocus.Content {
        TripMapFocus.Content(
            tripID: "trip_1",
            routeColor: .systemRed,
            routeType: .bus,
            shape: shape,
            progress: progress,
            stops: stops,
            vehicle: vehicle
        )
    }

    /// A real `TripStatus`, which only decodes from JSON — see
    /// `StopVehicleAnnotationTests.makeTripStatus` for why this fixture and why
    /// the reference-loading step matters.
    private func vehicle() throws -> TripStatus {
        try Fixtures.loadRESTAPIPayload(
            type: VehicleStatus.self,
            fileName: "api_where_vehicle_1_4351.json"
        ).tripStatus
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

    // MARK: - The shape

    /// Each half draws twice — a white casing under a colored core — so a split
    /// trip is four overlays, not two.
    @Test func `A trip in progress draws both halves of its shape`() {
        focus(content(shape: shape(), progress: 0.5))

        #expect(shapeOverlays.filter { $0.isSpent }.count == 2)
        #expect(shapeOverlays.filter { !$0.isSpent }.count == 2)
    }

    /// No reported progress is not zero progress. Nothing is known to have been
    /// travelled, so nothing may be drawn as travelled.
    @Test func `A trip with no reported progress draws entirely as ahead`() {
        focus(content(shape: shape(), progress: nil))

        #expect(shapeOverlays.allSatisfy { !$0.isSpent })
        #expect(shapeOverlays.count == 2)
    }

    @Test func `A trip that has not started draws no travelled half`() {
        focus(content(shape: shape(), progress: 0))

        #expect(shapeOverlays.allSatisfy { !$0.isSpent })
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

    @Test func `Clearing the focus clears the map`() {
        let focus = focus(content(shape: shape(), progress: 0.5))

        focus.clear()

        #expect(shapeOverlays.isEmpty)
    }
}
