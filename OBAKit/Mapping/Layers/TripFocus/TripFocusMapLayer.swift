//
//  TripFocusMapLayer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import OBAKitCore
import UIKit

/// Draws one trip and nothing else: its shape split into the part already
/// travelled and the part still ahead, a dot for every stop, a marker at the
/// terminal, and the vehicle.
///
/// Presentation-driven like `StopRouteFocusMapLayer` — begun when the trip page
/// is pushed and ended when it goes away — so `viewportDidChange` is a no-op and
/// there is no zoom gate. A trip spans far more than a stop-density viewport, and
/// culling it by visible-rect height would hide the line exactly when it is most
/// useful.
@MainActor
final class TripFocusMapLayer: NSObject, MapLayer {

    private enum Style {
        static let coreWidth: CGFloat = 6
        static let casingExtraWidth: CGFloat = 4
        /// The travelled half is thinner as well as gray: it is context, not the
        /// thing the rider is tracking.
        static let spentCoreWidth: CGFloat = 4
        static let spentAlpha: CGFloat = 0.85
    }

    // MARK: - MapLayer

    static let layerID = "tripFocus"

    var id: String { Self.layerID }
    var title: String {
        OBALoc("map_layers.trip_focus", value: "Followed trip",
               comment: "Map sheet row for the layer drawing the trip the rider is following.")
    }
    let iconName = "point.topleft.down.to.point.bottomright.curvepath"
    var tintColor: UIColor { ThemeColors.shared.brand }
    let group = MapLayerGroup.transit
    let isEnabledByDefault = true
    let availability = MapLayerAvailability.available
    /// No zoom gate — see the type doc.
    let zoomWindow = MapLayerZoomWindow(maxVisibleHeight: .greatestFiniteMagnitude)
    let densityBudget = 128
    let isClusterable = false
    let refreshPolicy = MapLayerRefreshPolicy.static
    let staleAfter: Duration? = nil

    // MARK: - State

    private let mapView: MKMapView

    private var focus: TripMapFocus?
    private var cancellables = Set<AnyCancellable>()

    private var shapeOverlays: [TripShapeOverlay] = []
    private var stopAnnotations: [TripStopAnnotation] = []
    private var vehicleAnnotation: VehicleAnnotation?

    /// The trip the camera has already been framed for. Framing happens once per
    /// trip, not once per refresh: the position updates every 30s, and re-framing
    /// on each one would snatch the map back from a rider who had panned away.
    private var framedTripID: String?

    init(mapView: MKMapView) {
        self.mapView = mapView
        super.init()

        // Self-registered rather than added to `MapRegionManager.registerAnnotationViews`:
        // this view is meaningless outside this layer, and registering it here
        // keeps the dequeue and the registration in one file.
        mapView.register(
            TripStopAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: TripStopAnnotationView.reuseIdentifier
        )
    }

    // MARK: - Presentation lifecycle

    /// Called when the trip page is pushed.
    func begin(focus: TripMapFocus) {
        reset()
        self.focus = focus

        focus.$content
            .sink { [weak self] content in self?.render(content) }
            .store(in: &cancellables)
    }

    /// Called when the trip page goes away.
    func end() {
        reset()
    }

    private func reset() {
        cancellables.removeAll()
        focus = nil
        framedTripID = nil
        removeAllContent()
    }

    // MARK: - Rendering

    private func render(_ content: TripMapFocus.Content?) {
        removeAllContent()

        guard let content else { return }

        // Split once: the drawing and the camera have to agree about which half
        // of the shape is still ahead of the bus.
        let split = Self.split(content)

        drawShape(split)
        drawStops(content)
        drawVehicle(content)
        frameCameraIfNeeded(content, split: split)
    }

    /// No reported progress means nothing is known to have been travelled, so the
    /// whole shape counts as ahead rather than guessing at a split.
    private static func split(_ content: TripMapFocus.Content) -> TripShapeSplit.Result {
        content.progress.map {
            TripShapeSplit.split(coordinates: content.shape, atFraction: $0)
        } ?? TripShapeSplit.Result(spent: [], ahead: content.shape)
    }

    private func drawShape(_ split: TripShapeSplit.Result) {
        // Spent first, then ahead, so where the two meet the live half wins the
        // z-order. Casing before core within each, for the same reason.
        add(coordinates: split.spent, isSpent: true)
        add(coordinates: split.ahead, isSpent: false)
    }

    private func add(coordinates: [CLLocationCoordinate2D], isSpent: Bool) {
        guard coordinates.count >= 2 else { return }

        let casing = TripShapeOverlay.make(coordinates: coordinates, isSpent: isSpent, isCasing: true)
        let core = TripShapeOverlay.make(coordinates: coordinates, isSpent: isSpent, isCasing: false)
        shapeOverlays.append(contentsOf: [casing, core])
        mapView.addOverlays([casing, core], level: .aboveRoads)
    }

    private func drawStops(_ content: TripMapFocus.Content) {
        // A stop whose location the feed omits costs one dot, not the trip.
        stopAnnotations = content.stops.compactMap { row in
            row.coordinate.map {
                TripStopAnnotation(row: row, coordinate: $0, routeColor: content.routeColor)
            }
        }
        mapView.addAnnotations(stopAnnotations)
    }

    private func drawVehicle(_ content: TripMapFocus.Content) {
        guard let status = content.vehicle, Self.vehicleCoordinate(content) != nil else { return }

        let annotation = VehicleAnnotation(tripStatus: status)
        vehicleAnnotation = annotation
        mapView.addAnnotation(annotation)
    }

    /// The part of the map this layer may frame into — everything the host isn't
    /// covering with a sheet or a toolbar. Supplied by the host because only the
    /// host knows its own chrome; see `MapViewController.tripCameraInsets()`.
    /// Unset, the framing respects the safe area and nothing else.
    var cameraInsets: (() -> UIEdgeInsets)?

    /// Frames the bus and the rider together, which is the comparison the page
    /// exists to support, plus the path between them where that fits. Falls back
    /// to the part of the trip still ahead when no vehicle position has been
    /// reported, and to the stops when there is no shape at all.
    private func frameCameraIfNeeded(_ content: TripMapFocus.Content, split: TripShapeSplit.Result) {
        guard framedTripID != content.tripID, let rect = framingRect(content, split: split) else { return }

        framedTripID = content.tripID
        mapView.setVisibleMapRect(rect, edgePadding: framingInsets(), animated: true)
    }

    private func framingRect(_ content: TripMapFocus.Content, split: TripShapeSplit.Result) -> MKMapRect? {
        let rider = userCoordinate

        if let rect = TripCameraFraming.rect(
            vehicle: Self.vehicleCoordinate(content),
            userLocation: rider,
            corridor: TripCameraFraming.corridor(ahead: split.ahead, userLocation: rider)
        ) {
            return rect
        }

        // A one-point shape frames to nothing useful, so it falls through to the
        // stops the same way an empty one does.
        if split.ahead.count >= 2 {
            return TripCameraFraming.rect(of: split.ahead)
        }

        return TripCameraFraming.rect(of: stopAnnotations.map(\.coordinate))
    }

    private func framingInsets() -> UIEdgeInsets {
        cameraInsets?() ?? MapCameraInsets.insets(mapSize: mapView.bounds.size, safeArea: mapView.safeAreaInsets)
    }

    /// The blue dot, when there is one. Gated on `showsUserLocation` so a rider
    /// who has location off doesn't get the camera framed around a stale fix.
    private var userCoordinate: CLLocationCoordinate2D? {
        guard mapView.showsUserLocation else { return nil }
        return mapView.userLocation.location?.coordinate
    }

    private static func vehicleCoordinate(_ content: TripMapFocus.Content) -> CLLocationCoordinate2D? {
        guard let status = content.vehicle, !status.coordinate.isNullIsland else { return nil }
        return status.coordinate
    }

    private func removeAllContent() {
        mapView.removeOverlays(shapeOverlays)
        mapView.removeAnnotations(stopAnnotations)
        if let vehicleAnnotation {
            mapView.removeAnnotation(vehicleAnnotation)
        }
        shapeOverlays.removeAll()
        stopAnnotations.removeAll()
        vehicleAnnotation = nil
    }

    // MARK: - MapLayer conformance

    func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? {
        guard let overlay = overlay as? TripShapeOverlay else { return nil }

        let renderer = MKPolylineRenderer(polyline: overlay)
        let coreWidth = overlay.isSpent ? Style.spentCoreWidth : Style.coreWidth
        let color = focus?.content?.routeColor ?? tintColor

        renderer.lineWidth = overlay.isCasing ? coreWidth + Style.casingExtraWidth : coreWidth
        renderer.strokeColor = overlay.isCasing ? .white : (overlay.isSpent ? .systemGray3 : color)
        renderer.lineCap = .round
        renderer.lineJoin = .round
        renderer.alpha = overlay.isSpent ? Style.spentAlpha : 1

        return renderer
    }

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        if annotation is TripStopAnnotation {
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: TripStopAnnotationView.reuseIdentifier,
                for: annotation
            )
        }

        // Claimed here rather than left to the map's own handling so the marker
        // picks up this trip's route color; layers get first claim.
        guard annotation === vehicleAnnotation else { return nil }

        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: MKMapView.reuseIdentifier(for: PulsingVehicleAnnotationView.self),
            for: annotation
        ) as? PulsingVehicleAnnotationView
        view?.realTimeAnnotationColor = focus?.content?.routeColor ?? tintColor
        return view
    }

    func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }

    func activate() { }

    func deactivate() { end() }

    /// Selection-driven, not viewport-driven — see the type doc.
    func viewportDidChange(_ mapRect: MKMapRect?) { }

    /// The map can be cleared out from under a layer (a region change, a search
    /// reset). Drop the bookkeeping rather than leave it pointing at annotations
    /// the map no longer has, which would make the next `removeAllContent` a
    /// no-op and leak the following trip's markers on top.
    func mapAnnotationsWereCleared() {
        stopAnnotations.removeAll()
        vehicleAnnotation = nil
    }

    func mapOverlaysWereCleared() {
        shapeOverlays.removeAll()
    }
}
