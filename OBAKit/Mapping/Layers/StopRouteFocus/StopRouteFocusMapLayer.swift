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
/// and torn down when it closes, so `viewportDidChange` only lays the direction
/// chevrons out again for the new zoom, and there is no zoom gate — a trip shape
/// spans far more than a stop-density viewport, and culling it by visible-rect
/// height would hide the line exactly when it is most useful.
@MainActor
final class StopRouteFocusMapLayer: NSObject, MapLayer {

    // MARK: - Styling

    private enum Style {
        /// At least `RouteArrowStyle.minimumLineWidth`, so every route's line keeps
        /// its direction chevrons, not just the focused one's.
        static let coreWidth: CGFloat = 6
        static let focusedCoreWidth: CGFloat = 9
        static let dimmedAlpha: CGFloat = 0.32
        static let normalAlpha: CGFloat = 1.0
    }

    /// How far apart, in screen points, routes sharing a street draw: an unfocused
    /// line and its casing, so neighbors touch without covering each other.
    static let laneWidth: CGFloat = Style.coreWidth + RouteArrowStyle.casingExtraWidth

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
    /// What the direction chevrons keep clear of.
    private let arrowContext = RouteArrowContext()
    private var model: StopRouteFocusModel = .empty

    /// Which vehicle the focused route is currently standing on — the one whose
    /// callout is open. Focus itself is per-route; this is what lets a second tap
    /// on *that* marker clear focus without a tap on a sibling marker doing the
    /// same. See `didSelectVehicle(_:)`.
    private var focusedVehicleID: String?

    /// Shapes already drawn, so a refresh doesn't redraw an unchanged line.
    private var drawnShapeIDsByRoute: [RouteID: String] = [:]

    /// Each drawn route's shape as fetched, before it moves over for a shared street.
    private var shapes: [RouteID: [CLLocationCoordinate2D]] = [:]
    /// Where each drawn route sits across the streets it shares.
    private var lanes: [RouteID: RouteLaneLayout.Line] = [:]
    /// The screen points per map point the lines were last moved over for.
    private var laneScale: CGFloat?
    /// The routes drawn moved over for a shared street.
    private var offsetRouteIDs = Set<RouteID>()

    /// Resolves a departure ID back to the live model object. Set by
    /// `MapViewController` (Task 11) BEFORE the first `update(model:)`, because
    /// vehicle annotations cannot be built without the `TripStatus` it yields.
    var departureProvider: ((String) -> ArrivalDeparture?)?

    /// Pushes the trip screen from the callout. Set by `MapViewController`.
    var onFollowTrip: ((ArrivalDeparture) -> Void)?
    /// Invalidates late shape responses for a presentation that has since ended.
    private var presentationToken = UUID()
    private var shapeTasks: [Task<Void, Never>] = []

    // MARK: - Estimated positions

    /// `nil` leaves every vehicle where the feed says.
    private let vehicleEstimation: VehicleEstimationDriver?
    private let tripSchedules: TripScheduleCache?
    /// Vehicles whose marker follows an estimate, by `DrawnVehicle.id`.
    private var estimates: [String: VehicleEstimate] = [:]
    private var estimationTask: Task<Void, Never>?
    private var latestServerClock: ServerClockSample?

    init(
        mapView: MKMapView,
        shapeCache: ShapeCache,
        formatters: Formatters,
        vehicleEstimation: VehicleEstimationDriver? = nil,
        tripSchedules: TripScheduleCache? = nil
    ) {
        self.mapView = mapView
        self.shapeCache = shapeCache
        self.formatters = formatters
        self.vehicleEstimation = vehicleEstimation
        self.tripSchedules = tripSchedules
        super.init()
        vehicleEstimation?.onEstimates = { [weak self] in self?.apply(estimates: $0) }
    }

    /// Cancels and drops every cached shape. Called by `MapViewController` when
    /// the current region actually changes — shape IDs are region-scoped, so a
    /// cache built for the old region must not answer for the new one.
    ///
    /// Returns the spawned `Task` so tests can await completion; production
    /// callers fire-and-forget.
    @discardableResult
    func invalidateShapeCache() -> Task<Void, Never> {
        let shapeCache = shapeCache, tripSchedules = tripSchedules
        return Task {
            await shapeCache.removeAll()
            // Trip IDs are region-scoped too.
            await tripSchedules?.removeAll()
        }
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

        // `@Published` emits in `willSet`, so a sink that reads
        // `focus.focusedRouteID` still sees the previous value. The emission
        // itself is the new focus — pass it through rather than reading back.
        focus.$focusedRouteID
            .removeDuplicates()
            .sink { [weak self] routeID in
                self?.restyleOverlays(focusedRouteID: routeID)
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
        stopEstimating()
        cancellables.removeAll()
        focus = nil
        focusedVehicleID = nil
        isSuppressed = false
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
    func apply(arrivals: StopArrivals?, isListFiltered: Bool, preferences: StopPreferences, serverClock: ServerClockSample? = nil) {
        latestServerClock = serverClock
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

        // The model is kept current while suppressed — the chips still read their
        // decoration from it — but nothing is drawn, or the next arrivals tick
        // would put the stop's routes back on top of the trip the rider is
        // following.
        guard !isSuppressed else { return }

        syncVehicleAnnotations()
        syncRouteOverlays()
        refreshEstimationInputs()
    }

    /// Whether this layer is standing down so another can have the map.
    private(set) var isSuppressed = false

    /// Hides this layer's content without ending the presentation.
    ///
    /// The trip page needs the map to itself, but the stop sheet underneath it is
    /// still presented and must come back intact on the way out — so this is not
    /// `end()`. State is kept; only what's drawn goes away.
    func setSuppressed(_ suppressed: Bool) {
        guard focus != nil, isSuppressed != suppressed else { return }
        isSuppressed = suppressed

        guard !suppressed else {
            stopEstimating()
            removeAllContent()
            // Shapes are pinned by route so a refresh doesn't redraw an unchanged
            // line. Clearing the pins is what lets them be drawn again on the way
            // back; the coordinates come from `ShapeCache`, so this costs no
            // network.
            drawnShapeIDsByRoute.removeAll()
            return
        }

        syncVehicleAnnotations()
        syncRouteOverlays()
        refreshEstimationInputs()
    }

    /// A vehicle marker tap. `MapViewController` calls this from
    /// `mapView(_:didSelect:)`, with MapKit having already selected the marker.
    ///
    /// Focus is per-route, but the gesture is per-vehicle, and a route can have
    /// two buses running it. Tapping the marker that already represents the
    /// focused route clears focus — the spec's escape hatch at `.tip`, where the
    /// chip row is hidden and the marker is the only way out. Tapping any other
    /// marker focuses its route; on a route already focused that keeps the line
    /// highlighted and just moves the callout to the bus the rider asked about,
    /// where a plain toggle would have unfocused the route out from under them.
    func didSelectVehicle(_ annotation: StopVehicleAnnotation) {
        guard let focus else { return }

        if focus.focusedRouteID == annotation.routeID, focusedVehicleID == annotation.id {
            focus.clearFocus()
        } else {
            focusedVehicleID = annotation.id
            focus.focus(routeID: annotation.routeID)
        }
    }

    /// The chip-tap half of the spec's focus behavior: focusing a route also
    /// opens its vehicle's callout. A no-op when the route has no drawn vehicle,
    /// or when focus was cleared.
    ///
    /// Yields to an existing selection on the same route, because this runs for
    /// *marker* taps too: `MapViewController.mapView(_:didSelect:)` routes a tap
    /// into `didSelectVehicle(_:)`, which lands here with the marker already
    /// selected. On a route with two buses running, picking "the route's first
    /// annotation" then dragged selection off the marker the rider actually
    /// tapped and onto the other one — they tapped one vehicle and got a
    /// different vehicle's callout.
    ///
    /// Also the one place `focusedVehicleID` is settled, whichever surface wrote
    /// focus: a chip tap picks a vehicle here, and a marker tap confirms the one
    /// MapKit already selected.
    private func selectFocusedVehicleAnnotation(routeID: RouteID?) {
        guard let routeID else {
            focusedVehicleID = nil
            return
        }
        if let selected = mapView.selectedAnnotations.first as? StopVehicleAnnotation,
           selected.routeID == routeID {
            focusedVehicleID = selected.id
            return
        }
        guard let annotation = annotations.first(where: { $0.routeID == routeID }) else { return }
        focusedVehicleID = annotation.id
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
                let estimate = estimates[vehicle.id]
                existing.update(tripStatus: tripStatus, coordinate: vehicle.coordinate, routeColor: routeColor, movesMarker: estimate == nil)
                if let view = mapView.view(for: existing) as? PulsingVehicleAnnotationView {
                    view.realTimeAnnotationColor = routeColor
                    view.applyTripStatus(tripStatus)
                    view.applyEstimate(estimate)
                }
                next.append(existing)
            } else {
                let annotation = StopVehicleAnnotation(
                    id: vehicle.id,
                    routeID: vehicle.routeID,
                    routeColor: model.routes.first { $0.routeID == vehicle.routeID }?.color ?? tintColor,
                    departureID: vehicle.departureID,
                    tripStatus: tripStatus,
                    coordinate: estimates[vehicle.id]?.coordinate ?? vehicle.coordinate
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

    // MARK: - Estimation

    /// Gathers each drawn vehicle's shape and schedule, from their caches or the
    /// network, then hands the lot to the driver. Asynchronous, so a vehicle whose
    /// shape or schedule hasn't arrived stays where the feed says until it has.
    private func refreshEstimationInputs() {
        guard let vehicleEstimation, let tripSchedules else { return }
        guard vehicleEstimation.isEnabledNow else {
            if !estimates.isEmpty { vehicleEstimation.update([]) }
            return
        }

        struct Pending {
            let vehicleKey: String
            let tripID: String
            let shapeID: String
            let request: TripScheduleCache.Request
            let serverTripLength: Double
            let fix: VehicleFix?
        }
        let pending: [Pending] = model.vehicles.compactMap { vehicle in
            guard let tripID = vehicle.tripID, let shapeID = vehicle.shapeID, !shapeID.isEmpty,
                  let departure = departureProvider?(vehicle.departureID),
                  let status = departure.tripStatus else { return nil }
            return Pending(
                vehicleKey: vehicle.id,
                tripID: tripID,
                shapeID: shapeID,
                request: .init(tripID: tripID, vehicleID: departure.vehicleID, serviceDate: departure.serviceDate),
                serverTripLength: status.totalDistanceAlongTrip,
                fix: VehicleFix(tripStatus: status, tripID: tripID)
            )
        }
        let serverClocks = [latestServerClock].compactMap { $0 }
        let token = presentationToken

        estimationTask?.cancel()
        estimationTask = Task { [weak self, shapeCache] in
            var inputs: [VehicleEstimationDriver.Input] = []
            for vehicle in pending {
                guard let shape = try? await shapeCache.coordinates(forShapeID: vehicle.shapeID), shape.count > 1 else { continue }
                // Without its schedule a vehicle can still move at its observed speed.
                let schedule = try? await tripSchedules.schedule(for: vehicle.request)
                inputs.append(.init(
                    vehicleKey: vehicle.vehicleKey,
                    tripID: vehicle.tripID,
                    shape: shape,
                    stopTimes: schedule?.stopTimes ?? [],
                    serverTripLength: vehicle.serverTripLength > 0 ? vehicle.serverTripLength : schedule?.serverTripLength,
                    fixes: [vehicle.fix].compactMap { $0 },
                    serverClocks: serverClocks
                ))
            }
            guard !Task.isCancelled, let self, self.presentationToken == token, !self.isSuppressed else { return }
            vehicleEstimation.update(inputs)
            vehicleEstimation.resume()
        }
    }

    /// Test seam: waits for the gathering `refreshEstimationInputs` started.
    func estimationInputsSettled() async {
        await estimationTask?.value
    }

    private func stopEstimating() {
        estimationTask?.cancel()
        estimationTask = nil
        vehicleEstimation?.pause()
        vehicleEstimation?.update([])
        estimates.removeAll()
    }

    private func apply(estimates: [String: VehicleEstimate]) {
        let previous = self.estimates
        self.estimates = estimates
        for annotation in annotations {
            let view = mapView.view(for: annotation) as? PulsingVehicleAnnotationView
            if let estimate = estimates[annotation.id] {
                VehicleCoordinateUpdate.follow(annotation, to: estimate.coordinate, snap: estimate.shouldSnap, in: mapView)
                view?.applyEstimate(estimate)
            } else if previous[annotation.id] != nil {
                // Back to the feed; the next arrivals poll moves it there.
                if let status = annotation.tripStatus { view?.applyTripStatus(status) }
                view?.applyEstimate(nil)
            }
        }
    }

    // MARK: - Shapes

    private func syncRouteOverlays() {
        let wantedRouteIDs = Set(model.routes.map(\.routeID))

        // Drop lines for routes that have left the arrival set. The rest are
        // drawn again, since a route leaving a shared street gives it back.
        if shapes.keys.contains(where: { !wantedRouteIDs.contains($0) }) {
            shapes = shapes.filter { wantedRouteIDs.contains($0.key) }
            drawShapes()
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
            let fetched = try? await shapeCache.coordinates(forShapeID: shapeID)
            guard let self, self.presentationToken == token else { return }

            // `syncRouteOverlays` pinned this shape before the fetch started, and
            // that pin is what makes it skip the route on every later refresh.
            // Leaving it in place after a failure — a dropped request, a shape
            // the server decodes to a single point — costs the route its line for
            // the rest of the presentation. Unpin so the next arrivals tick
            // retries.
            guard let coordinates = fetched, coordinates.count > 1 else {
                if self.drawnShapeIDsByRoute[route.routeID] == shapeID {
                    self.drawnShapeIDsByRoute[route.routeID] = nil
                }
                return
            }
            // Suppressed since the fetch began: drawing now would put the line over
            // the trip that has the map. Unsuppressing clears the pins and refetches.
            guard !self.isSuppressed else { return }
            self.shapes[route.routeID] = coordinates
            self.drawShapes()
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

    /// Lays the routes out across the streets they share, then draws them.
    ///
    /// Every route, not just one that changed: a route arriving on a street moves
    /// the ones already on it over, and one leaving lets them back.
    private func drawShapes() {
        // In a fixed order, not the model's: that follows the soonest arrival, which
        // rolls over as buses depart, and would swap the lines' sides on a redraw.
        let routeIDs = model.routes.map(\.routeID).sorted()
        lanes = RouteLaneLayout.lines(for: routeIDs.compactMap { routeID in
            shapes[routeID].map { (routeID, $0) }
        })
        redrawLanes()
    }

    /// Draws the routes that share a street a lane apart at the map's zoom; see
    /// `RouteLaneLayout`. A line already drawn down the middle of its street, and
    /// staying there, is left as it is: it doesn't depend on the zoom.
    ///
    /// The offset goes into the overlay's coordinates rather than into a renderer
    /// that draws for itself, so the line stays a plain `MKPolylineRenderer`; see
    /// `RouteLinePart`. That ties it to a zoom, so `viewportDidChange` comes back
    /// here when the zoom moves far enough.
    private func redrawLanes() {
        let scale = screenScale
        laneScale = scale
        let laneWidth = scale.map { Double(Self.laneWidth / $0) } ?? 0

        let drawn = Dictionary(grouping: overlays, by: \.routeID)
        var added: [RouteShapeOverlay] = []
        overlays = model.routes.flatMap { route -> [RouteShapeOverlay] in
            guard let line = lanes[route.routeID], let shape = shapes[route.routeID] else { return [] }
            if !line.isShared, !offsetRouteIDs.contains(route.routeID), let lines = drawn[route.routeID] {
                return lines
            }
            let coordinates = line.isShared ? line.offsetCoordinates(laneWidth: laneWidth) : shape
            // Bottom to top: casing, the colored core above it, then its chevrons.
            let parts = [RouteLinePart.casing, .core, .arrows].map {
                RouteShapeOverlay.make(coordinates: coordinates, routeID: route.routeID, part: $0)
            }
            added += parts
            return parts
        }
        offsetRouteIDs = Set(lanes.filter { $0.value.isShared }.keys)

        let kept = Set(overlays.map(ObjectIdentifier.init))
        let replaced = drawn.values.joined().filter { !kept.contains(ObjectIdentifier($0)) }
        // Before the overlays, so the arrows' first draw already knows where the stops are.
        refreshArrowMarkers()
        // Added before the old lines go, so there's no frame without either.
        mapView.addOverlays(added, level: .aboveRoads)
        mapView.removeOverlays(Array(replaced))
    }

    /// Lanes stay put within a quarter of a zoom level, where they are still about
    /// a line's width apart; past that they are drawn again for the new zoom.
    ///
    /// - Returns: Whether they were drawn again.
    private func redrawLanesIfZoomMoved() -> Bool {
        guard !offsetRouteIDs.isEmpty, let scale = screenScale else { return false }
        if let laneScale, abs(log2(scale / laneScale)) < 0.25 { return false }
        redrawLanes()
        return true
    }

    /// Screen points per map point, or nil while the map has no size.
    private var screenScale: CGFloat? {
        let scale = RouteArrowContext.screenScale(of: mapView)
        return scale.isFinite && scale > 0 ? scale : nil
    }

    private func refreshArrowMarkers() {
        arrowContext.refresh(from: mapView, redrawing: overlays)
    }

    // MARK: - Focus restyling

    private func restyleOverlays(focusedRouteID: RouteID?) {
        // `mapView.renderer(for:)` returns nil for any overlay MapKit has not asked
        // the delegate to render yet — offscreen ones, and everything if the map is
        // not in a window. Re-adding forces a fresh `rendererFor` round trip, which
        // picks up the new focus state. Without this fallback a chip tap silently
        // does nothing for the lines that happen to be off-screen.
        var routesNeedingReadd = Set<RouteID>()
        for overlay in overlays {
            if let renderer = mapView.renderer(for: overlay) as? MKPolylineRenderer {
                apply(style: overlay, to: renderer, focusedRouteID: focusedRouteID)
                renderer.setNeedsDisplay()
            } else {
                routesNeedingReadd.insert(overlay.routeID)
            }
        }
        if !routesNeedingReadd.isEmpty {
            // Re-add all of a route's parts together, in their original
            // casing-first order — even when only one actually needed a fresh
            // `rendererFor` round trip. Re-adding just one would move only it
            // to the top of the overlay stack and invert the route's z-order.
            let needsReadd = overlays.filter { routesNeedingReadd.contains($0.routeID) }
            mapView.removeOverlays(needsReadd)
            mapView.addOverlays(needsReadd, level: .aboveRoads)
        }
        applyVehicleZPriority()
    }

    private func apply(style overlay: RouteShapeOverlay, to renderer: MKPolylineRenderer, focusedRouteID: RouteID? = nil) {
        let focusedRouteID = focusedRouteID ?? focus?.focusedRouteID
        let isFocused = overlay.routeID == focusedRouteID
        let color = routeColor(for: overlay.routeID)

        let coreWidth = isFocused ? Style.focusedCoreWidth : Style.coreWidth
        renderer.lineWidth = overlay.isCasing ? coreWidth + RouteArrowStyle.casingExtraWidth : coreWidth
        // The casing is what keeps a route-colored line legible over the basemap.
        renderer.strokeColor = overlay.isCasing ? RouteArrowStyle.casingColor(for: color) : color
        renderer.lineCap = .round
        renderer.lineJoin = .round
        renderer.alpha = (focusedRouteID == nil || isFocused) ? Style.normalAlpha : Style.dimmedAlpha
    }

    private func routeColor(for routeID: RouteID) -> UIColor {
        model.routes.first { $0.routeID == routeID }?.color ?? tintColor
    }

    private func removeAllContent() {
        mapView.removeOverlays(overlays)
        mapView.removeAnnotations(annotations)
        overlays.removeAll()
        annotations.removeAll()
        shapes.removeAll()
        lanes.removeAll()
        laneScale = nil
        offsetRouteIDs.removeAll()
    }

    // MARK: - MapLayer conformance

    func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? {
        guard let overlay = overlay as? RouteShapeOverlay else { return nil }
        let renderer = overlay.part == .arrows
            ? RouteArrowRenderer(polyline: overlay, routeColor: routeColor(for: overlay.routeID), context: arrowContext)
            : MKPolylineRenderer(polyline: overlay)
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
        let departure = departureProvider?(annotation.departureID)
        view.detailCalloutAccessoryView = departure.map { makeCallout(for: $0, annotation: annotation) }

        // MapKit labels an annotation view from its annotation's `title`, which
        // `StopVehicleAnnotation` suppresses to keep the callout clean — leaving
        // the marker silent. Set here, unconditionally, for the same reuse reason
        // as the callout above.
        view.accessibilityLabel = Self.accessibilityLabel(
            routeShortName: departure?.route?.shortName,
            headsign: departure?.tripHeadsign,
            vehicleID: annotation.id,
            formatters: formatters
        )
        view.accessibilityValue = departure.map { formatters.accessibilityValue(for: $0) }
    }

    /// "Route 8 - Seattle Center, Vehicle 1234", falling back to the vehicle
    /// alone when the departure it serves didn't resolve.
    ///
    /// Built from `route?.shortName` rather than `ArrivalDeparture.routeAndHeadsign`,
    /// which force-unwraps `route` through `routeShortName`.
    static func accessibilityLabel(routeShortName: String?, headsign: String?, vehicleID: String, formatters: Formatters) -> String {
        let vehicle = String(format: vehicleLabelFormat, vehicleID)
        let routeAndHeadsign = [routeShortName, headsign]
            .compactMap { String.nilifyBlankValue($0) }
            .joined(separator: " - ")
        guard !routeAndHeadsign.isEmpty else { return vehicle }
        return [formatters.accessibilityLabelForArrivalDeparture(routeAndHeadsign: routeAndHeadsign), vehicle].joined(separator: ", ")
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

    /// Selection-driven, not viewport-driven. A new zoom only lays the arrows and
    /// the lanes of shared streets out again: they are sized and spaced in screen points.
    func viewportDidChange(_ mapRect: MKMapRect?) {
        guard focus != nil else { return }
        // Lines drawn again come with fresh arrows.
        if !redrawLanesIfZoomMoved() {
            arrowContext.refreshScale(from: mapView, redrawing: overlays)
        }
    }

    func stopMarkersDidChange() {
        guard focus != nil else { return }
        refreshArrowMarkers()
    }

    func mapAnnotationsWereCleared() {
        guard focus != nil else { return }
        mapView.addAnnotations(annotations)
    }

    func mapOverlaysWereCleared() {
        guard focus != nil else { return }
        mapView.addOverlays(overlays, level: .aboveRoads)
    }
}
