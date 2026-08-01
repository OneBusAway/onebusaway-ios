//
//  StopRouteFocusMapLayer.swift
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

/// Draws the routes serving the selected stop and the vehicles arriving on them.
///
/// Selection-driven, not viewport-driven: it is activated when a stop sheet opens
/// and torn down when it closes, so `viewportDidChange` is a no-op and there is
/// no zoom gate — a trip shape spans far more than a stop-density viewport, and
/// culling it by visible-rect height would hide the line exactly when it is most
/// useful.
@MainActor
final class StopRouteFocusMapLayer: NSObject, MapLayer {

    // MARK: - Styling

    private enum Style {
        static let coreWidth: CGFloat = 5
        static let focusedCoreWidth: CGFloat = 7
        static let casingExtraWidth: CGFloat = 4
        static let dimmedAlpha: CGFloat = 0.32
        static let normalAlpha: CGFloat = 1.0
    }

    // MARK: - MapLayer

    let id = "stopRoutes"
    var title: String {
        OBALoc("map_layer.stop_routes.title", value: "Route lines & vehicles",
               comment: "Map sheet row for the layer drawing a selected stop's routes and live vehicles.")
    }
    let iconName = "arrow.triangle.branch"
    var tintColor: UIColor { ThemeColors.shared.brand }
    let group = MapLayerGroup.transit
    let isEnabledByDefault = true
    let availability = MapLayerAvailability.available
    /// No zoom gate — see the type doc.
    let zoomWindow = MapLayerZoomWindow(maxVisibleHeight: .greatestFiniteMagnitude)
    let densityBudget = 32
    let isClusterable = false
    let refreshPolicy = MapLayerRefreshPolicy.static
    let staleAfter: Duration? = .seconds(120)

    // MARK: - State

    private let mapView: MKMapView
    private let shapeCache: ShapeCache

    private var focus: StopMapFocus?
    private var cancellables = Set<AnyCancellable>()

    private var overlays: [RouteShapeOverlay] = []
    private var annotations: [StopVehicleAnnotation] = []
    private var model: StopRouteFocusModel = .empty

    /// Shapes already drawn, so a refresh doesn't redraw an unchanged line.
    private var drawnShapeIDsByRoute: [RouteID: String] = [:]

    /// Resolves a departure ID back to the live model object. Set by
    /// `MapViewController` (Task 11) BEFORE the first `update(model:)`, because
    /// vehicle annotations cannot be built without the `TripStatus` it yields.
    var departureProvider: ((String) -> ArrivalDeparture?)?

    /// Pushes the trip screen from the callout. Set by `MapViewController`.
    var onFollowTrip: ((ArrivalDeparture) -> Void)?
    /// Invalidates late shape responses for a presentation that has since ended.
    private var presentationToken = UUID()
    private var shapeTasks: [Task<Void, Never>] = []

    init(mapView: MKMapView, shapeCache: ShapeCache) {
        self.mapView = mapView
        self.shapeCache = shapeCache
        super.init()
    }

    // MARK: - Presentation lifecycle

    /// Called when a stop sheet opens. Subscribes to focus changes so chip and
    /// marker taps restyle the lines.
    func begin(focus: StopMapFocus) {
        end()
        self.focus = focus
        presentationToken = UUID()

        focus.$focusedRouteID
            .removeDuplicates()
            .sink { [weak self] _ in self?.restyleOverlays() }
            .store(in: &cancellables)
    }

    /// Called when the sheet closes. Cancels in-flight shape work so a late
    /// response can't draw onto a map that has moved on.
    func end() {
        presentationToken = UUID()
        for task in shapeTasks { task.cancel() }
        shapeTasks.removeAll()
        cancellables.removeAll()
        focus = nil
        model = .empty
        drawnShapeIDsByRoute.removeAll()
        removeAllContent()
    }

    /// Called on every arrivals refresh.
    func update(model: StopRouteFocusModel) {
        self.model = model
        focus?.apply(routes: model.routes)
        syncVehicleAnnotations()
        syncRouteOverlays()
    }

    // MARK: - Vehicles

    private func syncVehicleAnnotations() {
        mapView.removeAnnotations(annotations)
        annotations = model.vehicles.compactMap { vehicle in
            // A non-nil TripStatus is mandatory — without it the marker renders as
            // a bare dot with no icon and no heading arrow. See StopVehicleAnnotation.
            // Every modelled vehicle derived its coordinate from a TripStatus, so
            // this lookup only fails if the departure vanished between refreshes.
            guard let tripStatus = departureProvider?(vehicle.departureID)?.tripStatus else { return nil }
            return StopVehicleAnnotation(
                id: vehicle.id,
                routeID: vehicle.routeID,
                routeColor: model.routes.first { $0.routeID == vehicle.routeID }?.color ?? tintColor,
                departureID: vehicle.departureID,
                tripStatus: tripStatus,
                coordinate: vehicle.coordinate
            )
        }
        mapView.addAnnotations(annotations)
    }

    // MARK: - Shapes

    private func syncRouteOverlays() {
        let wantedRouteIDs = Set(model.routes.map(\.routeID))

        // Drop lines for routes that have left the arrival set.
        let stale = overlays.filter { !wantedRouteIDs.contains($0.routeID) }
        if !stale.isEmpty {
            mapView.removeOverlays(stale)
            overlays.removeAll { !wantedRouteIDs.contains($0.routeID) }
        }
        drawnShapeIDsByRoute = drawnShapeIDsByRoute.filter { wantedRouteIDs.contains($0.key) }

        for route in model.routes {
            guard let shapeID = route.shapeID, !shapeID.isEmpty else { continue }
            // Pin the shape: the soonest arrival rolls over as buses depart, so
            // re-resolving it every refresh would refetch and visibly redraw an
            // otherwise-unchanged line.
            guard drawnShapeIDsByRoute[route.routeID] == nil else { continue }
            drawnShapeIDsByRoute[route.routeID] = shapeID
            fetchAndDrawShape(shapeID: shapeID, route: route)
        }
    }

    private func fetchAndDrawShape(shapeID: String, route: StopRouteFocusModel.DrawnRoute) {
        let token = presentationToken
        let task = Task { [weak self, shapeCache] in
            guard let coordinates = try? await shapeCache.coordinates(forShapeID: shapeID),
                  coordinates.count > 1 else { return }
            guard let self, self.presentationToken == token else { return }
            self.addShape(coordinates: coordinates, routeID: route.routeID)
        }
        shapeTasks.append(task)
    }

    private func addShape(coordinates: [CLLocationCoordinate2D], routeID: RouteID) {
        // Casing first so the colored core draws above it.
        let casing = RouteShapeOverlay.make(coordinates: coordinates, routeID: routeID, isCasing: true)
        let core = RouteShapeOverlay.make(coordinates: coordinates, routeID: routeID, isCasing: false)
        overlays.append(contentsOf: [casing, core])
        mapView.addOverlays([casing, core], level: .aboveRoads)
    }

    // MARK: - Focus restyling

    private func restyleOverlays() {
        // `mapView.renderer(for:)` returns nil for any overlay MapKit has not asked
        // the delegate to render yet — offscreen ones, and everything if the map is
        // not in a window. Re-adding forces a fresh `rendererFor` round trip, which
        // picks up the new focus state. Without this fallback a chip tap silently
        // does nothing for the lines that happen to be off-screen.
        var needsReadd: [RouteShapeOverlay] = []
        for overlay in overlays {
            if let renderer = mapView.renderer(for: overlay) as? MKPolylineRenderer {
                apply(style: overlay, to: renderer)
                renderer.setNeedsDisplay()
            } else {
                needsReadd.append(overlay)
            }
        }
        if !needsReadd.isEmpty {
            mapView.removeOverlays(needsReadd)
            mapView.addOverlays(needsReadd, level: .aboveRoads)
        }
        for annotation in annotations {
            guard let view = mapView.view(for: annotation) as? PulsingVehicleAnnotationView else { continue }
            view.zPriority = (annotation.routeID == focus?.focusedRouteID) ? .max : .defaultUnselected
        }
    }

    private func apply(style overlay: RouteShapeOverlay, to renderer: MKPolylineRenderer) {
        let focusedRouteID = focus?.focusedRouteID
        let isFocused = overlay.routeID == focusedRouteID
        let color = model.routes.first { $0.routeID == overlay.routeID }?.color ?? tintColor

        let coreWidth = isFocused ? Style.focusedCoreWidth : Style.coreWidth
        renderer.lineWidth = overlay.isCasing ? coreWidth + Style.casingExtraWidth : coreWidth
        // The casing is what keeps a route-colored line legible over the basemap.
        renderer.strokeColor = overlay.isCasing ? .white : color
        renderer.lineCap = .round
        renderer.lineJoin = .round
        renderer.alpha = (focusedRouteID == nil || isFocused) ? Style.normalAlpha : Style.dimmedAlpha
    }

    private func removeAllContent() {
        mapView.removeOverlays(overlays)
        mapView.removeAnnotations(annotations)
        overlays.removeAll()
        annotations.removeAll()
    }

    // MARK: - MapLayer conformance

    func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? {
        guard let overlay = overlay as? RouteShapeOverlay else { return nil }
        let renderer = MKPolylineRenderer(polyline: overlay)
        apply(style: overlay, to: renderer)
        return renderer
    }

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        guard let annotation = annotation as? StopVehicleAnnotation else { return nil }
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: MKMapView.reuseIdentifier(for: PulsingVehicleAnnotationView.self),
            for: annotation
        ) as? PulsingVehicleAnnotationView
        // Set the color BEFORE the annotation, or the didSet chain applies the
        // previous route's color — see PulsingVehicleAnnotationView.
        view?.realTimeAnnotationColor = annotation.routeColor
        view?.isSelectable = true
        view?.canShowCallout = true
        view?.annotation = annotation
        return view
    }

    func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }

    func activate() { }

    func deactivate() { end() }

    /// Selection-driven, not viewport-driven.
    func viewportDidChange(_ mapRect: MKMapRect?) { }

    func mapAnnotationsWereCleared() {
        guard focus != nil else { return }
        mapView.addAnnotations(annotations)
    }

    func mapOverlaysWereCleared() {
        guard focus != nil else { return }
        mapView.addOverlays(overlays, level: .aboveRoads)
    }
}
