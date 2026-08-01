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

    static let layerID = "stopRoutes"

    var id: String { Self.layerID }
    var title: String {
        OBALoc("map_layers.stop_routes", value: "Route lines & vehicles",
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
    /// No freshness surface — unlike the rental layers, this layer has nothing
    /// analogous to a fetch timestamp to compare against.
    let staleAfter: Duration? = nil

    // MARK: - State

    private let mapView: MKMapView
    private let shapeCache: ShapeCache
    private let formatters: Formatters

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

    init(mapView: MKMapView, shapeCache: ShapeCache, formatters: Formatters) {
        self.mapView = mapView
        self.shapeCache = shapeCache
        self.formatters = formatters
        super.init()
    }

    /// Cancels and drops every cached shape. Called by `MapViewController` when
    /// the current region actually changes — shape IDs are region-scoped, so a
    /// cache built for the old region must not answer for the new one.
    ///
    /// Returns the spawned `Task` so tests can await completion; production
    /// callers fire-and-forget.
    @discardableResult
    func invalidateShapeCache() -> Task<Void, Never> {
        let shapeCache = shapeCache
        return Task { await shapeCache.removeAll() }
    }

    // MARK: - Presentation lifecycle

    /// Called when a stop sheet opens. Subscribes to focus changes so chip and
    /// marker taps restyle the lines.
    ///
    /// Does NOT clear `departureProvider`/`onFollowTrip` — `resetPresentationState()`
    /// is shared with `end()`, but releasing those two here would race a caller
    /// that sets them before `begin(focus:)` (as this layer's own tests do); the
    /// production caller sets them after, but nothing requires that ordering.
    func begin(focus: StopMapFocus) {
        resetPresentationState()
        self.focus = focus
        presentationToken = UUID()

        focus.$focusedRouteID
            .removeDuplicates()
            .sink { [weak self] routeID in
                self?.restyleOverlays()
                self?.selectFocusedVehicleAnnotation(routeID: routeID)
            }
            .store(in: &cancellables)
    }

    /// Called when the sheet closes. Cancels in-flight shape work so a late
    /// response can't draw onto a map that has moved on, and releases the
    /// closures the outgoing presentation installed — they're re-supplied by
    /// the next `begin(focus:)`, and leaving them set until then just holds
    /// dead references to a presentation that no longer exists.
    func end() {
        resetPresentationState()
        departureProvider = nil
        onFollowTrip = nil
    }

    private func resetPresentationState() {
        presentationToken = UUID()
        for task in shapeTasks { task.cancel() }
        shapeTasks.removeAll()
        cancellables.removeAll()
        focus = nil
        model = .empty
        drawnShapeIDsByRoute.removeAll()
        removeAllContent()
    }

    /// Max routes drawn for one stop. A downtown stop serves 20+ over the arrival
    /// window; drawing all of them is both slow and unreadable.
    static let routeCap = 6

    /// Applies one arrivals emission — the departure resolver and the model, both
    /// derived from that same value, in the order `update` needs them.
    ///
    /// This exists so a caller cannot source the two separately.
    /// `MapViewController` drives it from a `@Published` sink, and `@Published`
    /// publishes in `willSet`: reading `viewModel.stopArrivals` back from inside
    /// that sink returns the PREVIOUS value. That put zero vehicles on the map on
    /// first load — the previous value was nil, no departure resolved, and
    /// `syncVehicleAnnotations` skipped every one — and left every refresh after
    /// resolving a generation stale.
    func apply(arrivals: StopArrivals?, isListFiltered: Bool, preferences: StopPreferences) {
        let all = arrivals?.arrivalsAndDepartures ?? []
        // Assigned before `update`, which consults it for every vehicle.
        departureProvider = { departureID in all.first { $0.id == departureID } }

        let visible = StopRouteFocusModel.visibleDepartures(
            all,
            isListFiltered: isListFiltered,
            preferences: preferences
        )
        update(model: StopRouteFocusModel.make(departures: visible, routeCap: Self.routeCap))
    }

    /// Called on every arrivals refresh. Guarded on `focus`: a disabled layer's
    /// `deactivate()` (→ `end()`) clears it, but the Combine sink that calls this
    /// keeps running until the sheet itself closes — without this guard, the
    /// next arrivals tick would silently redraw everything the toggle just
    /// turned off.
    func update(model: StopRouteFocusModel) {
        guard focus != nil else { return }
        self.model = model
        focus?.apply(routes: model.routes)
        syncVehicleAnnotations()
        syncRouteOverlays()
    }

    /// Vehicle-marker tap writes focus too — the spec's escape hatch at `.tip`,
    /// where the chip row is hidden. `MapViewController` calls this from
    /// `mapView(_:didSelect:)`.
    func toggleFocus(routeID: RouteID) {
        focus?.toggleFocus(routeID: routeID)
    }

    /// The chip-tap half of the spec's focus behavior: focusing a route also
    /// opens its vehicle's callout. A no-op when the route has no drawn vehicle,
    /// or when focus was cleared.
    ///
    /// Yields to an existing selection on the same route, because this runs for
    /// *marker* taps too: `MapViewController.mapView(_:didSelect:)` routes a tap
    /// into `toggleFocus`, which lands here with the marker already selected. On
    /// a route with two buses running, picking "the route's first annotation"
    /// then dragged selection off the marker the rider actually tapped and onto
    /// the other one — they tapped one vehicle and got a different vehicle's
    /// callout.
    private func selectFocusedVehicleAnnotation(routeID: RouteID?) {
        guard let routeID else { return }
        if let selected = mapView.selectedAnnotations.first as? StopVehicleAnnotation,
           selected.routeID == routeID {
            return
        }
        guard let annotation = annotations.first(where: { $0.routeID == routeID }) else { return }
        mapView.selectAnnotation(annotation, animated: true)
    }

    // MARK: - Vehicles

    /// Diffs against the previous refresh by `DrawnVehicle.id` rather than
    /// removing and re-adding everything. Wholesale replacement dismisses any
    /// open callout on every 15s arrivals tick — and the callout carries the
    /// feature's primary action, "Follow this trip" — pops markers instead of
    /// moving them, and drops the focused route's raised `zPriority` until the
    /// next chip tap. Survivors are mutated in place; only the delta is
    /// added/removed.
    private func syncVehicleAnnotations() {
        var survivors: [String: StopVehicleAnnotation] = [:]
        for annotation in annotations { survivors[annotation.id] = annotation }

        var next: [StopVehicleAnnotation] = []
        var toAdd: [StopVehicleAnnotation] = []
        var seenIDs = Set<String>()

        for vehicle in model.vehicles {
            // A non-nil TripStatus is mandatory — without it the marker renders as
            // a bare dot with no icon and no heading arrow. See StopVehicleAnnotation.
            // Every modelled vehicle derived its coordinate from a TripStatus, so
            // this lookup only fails if the departure vanished between refreshes.
            guard let tripStatus = departureProvider?(vehicle.departureID)?.tripStatus else { continue }
            seenIDs.insert(vehicle.id)

            if let existing = survivors[vehicle.id] {
                let routeColor = model.routes.first { $0.routeID == vehicle.routeID }?.color ?? tintColor
                existing.update(tripStatus: tripStatus, coordinate: vehicle.coordinate, routeColor: routeColor)
                if let view = mapView.view(for: existing) as? PulsingVehicleAnnotationView {
                    view.realTimeAnnotationColor = routeColor
                    view.applyTripStatus(tripStatus)
                }
                next.append(existing)
            } else {
                let annotation = StopVehicleAnnotation(
                    id: vehicle.id,
                    routeID: vehicle.routeID,
                    routeColor: model.routes.first { $0.routeID == vehicle.routeID }?.color ?? tintColor,
                    departureID: vehicle.departureID,
                    tripStatus: tripStatus,
                    coordinate: vehicle.coordinate
                )
                next.append(annotation)
                toAdd.append(annotation)
            }
        }

        let toRemove = annotations.filter { !seenIDs.contains($0.id) }
        if !toRemove.isEmpty { mapView.removeAnnotations(toRemove) }
        if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }
        annotations = next

        applyVehicleZPriority()
    }

    /// Raises the focused route's marker above the rest. Applied both here
    /// (so a vehicle added or updated mid-refresh gets the right priority
    /// immediately) and from `restyleOverlays()` (so a chip/marker tap re-styles
    /// markers already on the map).
    private func applyVehicleZPriority() {
        for annotation in annotations {
            guard let view = mapView.view(for: annotation) as? PulsingVehicleAnnotationView else { continue }
            view.zPriority = (annotation.routeID == focus?.focusedRouteID) ? .max : .defaultUnselected
        }
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

    /// Test seam: awaits any shape fetches `update(model:)` kicked off, so a test
    /// can assert against settled overlay state instead of guessing with a sleep.
    /// `fetchAndDrawShape` spawns detached, unstructured work — nothing else
    /// naturally makes it awaitable from outside the layer.
    func awaitPendingShapeWork() async {
        for task in shapeTasks { await task.value }
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
        var routesNeedingReadd = Set<RouteID>()
        for overlay in overlays {
            if let renderer = mapView.renderer(for: overlay) as? MKPolylineRenderer {
                apply(style: overlay, to: renderer)
                renderer.setNeedsDisplay()
            } else {
                routesNeedingReadd.insert(overlay.routeID)
            }
        }
        if !routesNeedingReadd.isEmpty {
            // Re-add a route's casing AND core together, in their original
            // casing-first order — even when only one half actually needed a
            // fresh `rendererFor` round trip. Re-adding just one half would move
            // only it to the top of the overlay stack and invert the pair's
            // z-order.
            let needsReadd = overlays.filter { routesNeedingReadd.contains($0.routeID) }
            mapView.removeOverlays(needsReadd)
            mapView.addOverlays(needsReadd, level: .aboveRoads)
        }
        applyVehicleZPriority()
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
        view.map { configure($0, for: annotation) }
        return view
    }

    /// Applies one vehicle's identity to a view that may have been recycled from a
    /// different one.
    ///
    /// Split out of `annotationView(for:in:)` so a test can hand it a view still
    /// carrying the previous vehicle's callout — the exact state MapKit's reuse
    /// queue produces, and one a test driving `annotationView` cannot reach,
    /// because the queue hands back a fresh view whenever nothing has been
    /// recycled yet.
    func configure(_ view: PulsingVehicleAnnotationView, for annotation: StopVehicleAnnotation) {
        view.realTimeAnnotationColor = annotation.routeColor
        view.isSelectable = true
        view.canShowCallout = true
        // Assigned unconditionally, including to nil. `MKAnnotationView.prepareForReuse`
        // does not clear accessory views, so an `if let` here left the previous
        // vehicle's callout attached whenever the new annotation's departure failed
        // to resolve — one vehicle's callout on another vehicle's marker.
        view.detailCalloutAccessoryView = departureProvider?(annotation.departureID)
            .map { makeCallout(for: $0, annotation: annotation) }
    }

    /// Relative-time formatter for "position updated 12s ago". Held statically —
    /// constructing one per callout is measurably wasteful and they are stateless.
    private static let updatedFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        // `.abbreviated` ("12s ago"), not `.short` ("12 sec. ago") — the design's
        // freshness line, and short enough not to wrap under the countdown.
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// "Vehicle NNNN" — see the spec's callout content list.
    private static let vehicleLabelFormat = OBALoc(
        "vehicle_callout.vehicle_label_fmt",
        value: "Vehicle %@",
        comment: "Label identifying a vehicle by its ID in the map's vehicle callout, e.g. 'Vehicle 1234'."
    )

    private func makeCallout(for departure: ArrivalDeparture, annotation: StopVehicleAnnotation) -> UIView {
        // `DepartureStatus`'s members are `label` and `color` — NOT statusLabel /
        // statusColor. Verified at DepartureStatus.swift:52 and :35.
        let status = DepartureStatus(arrivalDeparture: departure)
        // `route` is declared `Route!` (ArrivalDeparture.swift:53). `routeShortName`
        // (:220) still force-unwraps through it when `_routeShortName` is nil, so
        // reach for `route?` directly here rather than through that property —
        // optional-chaining an implicitly-unwrapped optional never traps.
        let headsign = departure.tripHeadsign ?? departure.route?.shortName ?? ""
        return VehicleCalloutView(
            // Same optional-chained reach as `headsign` above, and for the same
            // reason: `ArrivalDeparture.routeShortName` force-unwraps `route`.
            routeShortName: departure.route?.shortName ?? "",
            headsign: headsign,
            vehicleLabel: String(format: Self.vehicleLabelFormat, annotation.id),
            countdownText: formatters.shortFormattedTime(until: departure),
            statusText: status.label,
            statusColor: status.color,
            // There is no `Formatters.formattedLastUpdated`. `ArrivalDeparture`
            // carries `lastUpdated: Date` (:35); format it here.
            updatedText: Self.updatedFormatter.localizedString(for: departure.lastUpdated, relativeTo: Date()),
            routeColor: annotation.routeColor,
            onFollow: { [weak self] in self?.onFollowTrip?(departure) }
        )
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
