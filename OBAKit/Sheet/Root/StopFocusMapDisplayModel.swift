//
//  StopFocusMapDisplayModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import SwiftUI
import OBAKitCore

/// What the panel's map draws for an open stop sheet: a line for each route serving
/// the stop and the vehicles arriving on them.
///
/// The panel's counterpart of `StopRouteFocusMapLayer`, which draws on an
/// `MKMapView` the panel doesn't have. Both derive what to draw with
/// `StopRouteFocusModel`, fetch shapes through a `ShapeCache`, and tell the sheet's
/// route chips what is drawn through its `StopMapFocus`.
///
/// It doesn't move the camera. The panel already frames the stop when its sheet
/// opens, and the routes run far past the stop; framing them would pull the rider
/// out to a whole-city view.
@MainActor
final class StopFocusMapDisplayModel: ObservableObject {

    /// How a route and its vehicles are drawn while a chip or marker focuses a route.
    enum Emphasis {
        case normal
        case focused
        case dimmed
    }

    /// The casing and the colored core drawn over it, as two polylines, matching the
    /// separate overlays `StopRouteFocusMapLayer` adds for each.
    struct ShapeLine {
        let casing: MKPolyline
        let core: MKPolyline
    }

    struct RouteLine: Identifiable {
        let id: RouteID
        let line: ShapeLine
        let color: Color
        /// Under the core; see `RouteArrowStyle.casingColor(for:)`.
        let casingColor: Color
        let arrowColor: Color
        /// Spaced in meters. The map tab places its own in screen points with
        /// `RouteArrowLayout`, which this map can't.
        let arrows: [PolylineArrowPlacement]
        let emphasis: Emphasis
    }

    struct Vehicle: Identifiable {
        /// `vehicleID` when the agency reports one, `tripID` otherwise.
        let id: String
        let routeID: RouteID
        let coordinate: CLLocationCoordinate2D
        /// In degrees, as OBA reports it.
        let orientation: CLLocationDirection
        let routeType: Route.RouteType
        let isRealTime: Bool
        let color: Color
        let emphasis: Emphasis
        let accessibilityLabel: String
        let accessibilityValue: String
        /// What a tap on the marker follows.
        let departure: ArrivalDeparture
    }

    /// Resolved once per change rather than in `body`, which re-runs on every
    /// sheet-height change while a sheet is dragged. Same reason as
    /// `TripFocusMapDisplayModel.Display`.
    struct Display {
        /// Only routes whose shape has loaded, in the model's soonest-first order.
        let routes: [RouteLine]
        let vehicles: [Vehicle]
    }

    @Published private(set) var display: Display?

    /// The stop sheet whose routes are drawn.
    var owner: AppSheetRoute? { entries.last?.owner }

    /// One entry per open stop sheet, newest last, and the newest is the one drawn.
    ///
    /// A stack for the reason `TripFocusMapDisplayModel.entries` gives: stop → trip →
    /// stop puts a second stop sheet over the first, and the first must draw again
    /// when the second closes. Every entry keeps its own latest arrivals, because a
    /// covered sheet goes on refreshing and the map has to come back current.
    private var entries: [Entry] = []

    private struct Entry {
        let owner: AppSheetRoute
        /// Weak because the sheet owns it.
        weak var focus: StopMapFocus?
        var arrivals: Arrivals?
    }

    /// One arrivals emission, with everything drawing needs from it.
    private struct Arrivals {
        let model: StopRouteFocusModel
        let departures: [String: ArrivalDeparture]
    }

    private let shapeCache: ShapeCache
    private let formatters: Formatters

    /// Shapes loaded for the drawn stop, by shape ID.
    private var shapes: [String: [CLLocationCoordinate2D]] = [:]

    /// The drawn routes laid out across the streets they share, and which shape each
    /// route was laid out with. Laid out again only when that changes: the layout
    /// is far more work than a redraw, and arrivals refresh every 15 seconds.
    private var lanes = RouteLanes.empty
    private var laneShapeIDs: [RouteID: String] = [:]

    /// Screen points per map point, from the panel's camera. `nil` until the map
    /// first settles.
    private var screenScale: CGFloat?
    /// What the lanes in `display` were drawn at.
    private var drawnScreenScale: CGFloat?
    private var shapeTasks: [String: Task<Void, Never>] = [:]
    private var focusedRouteID: RouteID?
    private var focusCancellable: AnyCancellable?

    init(shapeCache: ShapeCache, formatters: Formatters) {
        self.shapeCache = shapeCache
        self.formatters = formatters
    }

    // MARK: - Sharing the map

    /// Whether the open stop draws rather than the open trip: whichever sheet is
    /// newer on the stack, since that's the one the rider is looking at. A trip
    /// opened from a stop takes the map, and a stop opened from that trip takes it
    /// back. Both at once would bury the trip under the stop's other routes.
    ///
    /// - Parameter routes: Every route on screen, oldest first; see
    ///   `SheetCoordinator.allRoutes`.
    static func stopTakesMap(stopOwner: AppSheetRoute?, tripOwner: AppSheetRoute?, routes: [AppSheetRoute]) -> Bool {
        guard let stopOwner, let stopIndex = routes.lastIndex(of: stopOwner) else { return false }
        guard let tripOwner, let tripIndex = routes.lastIndex(of: tripOwner) else { return true }
        return stopIndex > tripIndex
    }

    // MARK: - Lifetime

    /// Draws the stop `owner` shows for as long as it is on the sheet stack. A stop
    /// sheet opened over it takes the map until that one closes.
    func show(focus: StopMapFocus, owner: AppSheetRoute) {
        // The sheet reports its focus each time it appears, including on the way
        // back from a sheet it opened over itself.
        guard focus !== entries.last?.focus else { return }

        let arrivals = entries.first { $0.owner == owner }?.arrivals
        entries.removeAll { $0.owner == owner }
        entries.append(Entry(owner: owner, focus: focus, arrivals: arrivals))
        beginDrawingTop()
    }

    /// One arrivals emission from `owner`'s sheet.
    ///
    /// Takes the emitted values rather than reading the view model back, for the
    /// reason `StopRouteFocusMapLayer.apply(arrivals:isListFiltered:preferences:)`
    /// gives: `@Published` emits in `willSet`.
    func apply(arrivals: StopArrivals?, isListFiltered: Bool, preferences: StopPreferences, owner: AppSheetRoute) {
        guard let index = entries.firstIndex(where: { $0.owner == owner }) else { return }

        let all = arrivals?.arrivalsAndDepartures ?? []
        let visible = StopRouteFocusModel.visibleDepartures(all, isListFiltered: isListFiltered, preferences: preferences)
        let model = StopRouteFocusModel.make(departures: visible, routeCap: StopRouteFocusMapLayer.routeCap)
        entries[index].arrivals = Arrivals(
            model: model,
            departures: Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        )
        // A covered sheet's chips still decorate from it.
        entries[index].focus?.apply(routes: model.routes)

        guard index == entries.indices.last else { return }
        loadShapes()
        render()
    }

    /// Drops every stop whose sheet is no longer on the stack and goes back to
    /// drawing the newest one left. Called on every change to that stack; see
    /// `TripFocusMapDisplayModel.clearIfOwnerAbsent(from:)`.
    func clearIfOwnerAbsent(from routes: [AppSheetRoute]) {
        let drawnOwner = owner
        entries.removeAll { !routes.contains($0.owner) || $0.focus == nil }
        guard owner != drawnOwner else { return }
        beginDrawingTop()
    }

    /// Forgets every shape, so a shape ID from the old region can't resolve to the
    /// wrong line in a new one.
    func invalidateShapeCache() {
        let shapeCache = shapeCache
        Task { await shapeCache.removeAll() }
    }

    /// The panel's camera settled at a new zoom. Lanes are sized in screen points,
    /// so shared streets are drawn again once the zoom moves far enough; see
    /// `RouteLanes.needsRedraw(drawnAt:now:)`.
    ///
    /// - Parameter scale: Screen points per map point.
    func updateScreenScale(_ scale: CGFloat) {
        guard scale.isFinite, scale > 0 else { return }
        screenScale = scale
        guard !lanes.sharedRouteIDs.isEmpty,
              RouteLanes.needsRedraw(drawnAt: drawnScreenScale, now: scale) else { return }
        render()
    }

    /// Lets tests wait for the shape fetches `apply` started.
    func awaitPendingShapeWork() async {
        for task in shapeTasks.values {
            await task.value
        }
    }

    // MARK: - Drawing

    private func beginDrawingTop() {
        for task in shapeTasks.values { task.cancel() }
        shapeTasks.removeAll()
        shapes.removeAll()
        lanes = .empty
        laneShapeIDs.removeAll()
        focusedRouteID = nil
        focusCancellable = nil

        guard let focus = entries.last?.focus else {
            display = nil
            return
        }

        // `@Published` emits in `willSet`, so the emitted value is passed through
        // rather than read back from `focus`.
        focusCancellable = focus.$focusedRouteID
            .removeDuplicates()
            .sink { [weak self] routeID in
                self?.focusedRouteID = routeID
                self?.render()
            }
        loadShapes()
        render()
    }

    private func loadShapes() {
        guard let model = entries.last?.arrivals?.model else { return }

        for route in model.routes {
            guard let shapeID = route.shapeID, !shapeID.isEmpty,
                  shapes[shapeID] == nil, shapeTasks[shapeID] == nil else { continue }

            let drawnOwner = owner
            shapeTasks[shapeID] = Task { [weak self, shapeCache] in
                let coordinates = try? await shapeCache.coordinates(forShapeID: shapeID)
                // Another stop may have taken the map while the shape loaded.
                guard let self, !Task.isCancelled, self.owner == drawnOwner else { return }
                self.shapeTasks[shapeID] = nil
                // One point is not a line.
                guard let coordinates, coordinates.count > 1 else { return }
                self.shapes[shapeID] = coordinates
                self.render()
            }
        }
    }

    private func render() {
        guard let arrivals = entries.last?.arrivals else {
            display = nil
            return
        }

        let model = arrivals.model
        let colors = Dictionary(model.routes.map { ($0.routeID, $0.color) }, uniquingKeysWith: { first, _ in first })
        layOutLanes(for: model)
        drawnScreenScale = screenScale

        let routes = model.routes.compactMap { route -> RouteLine? in
            guard let coordinates = lanes.coordinates(for: route.routeID, screenScale: screenScale) else { return nil }
            return RouteLine(
                id: route.routeID,
                line: ShapeLine(
                    casing: MKPolyline(coordinates: coordinates, count: coordinates.count),
                    core: MKPolyline(coordinates: coordinates, count: coordinates.count)
                ),
                color: Color(uiColor: route.color),
                casingColor: Color(uiColor: RouteArrowStyle.casingColor(for: route.color)),
                arrowColor: Color(uiColor: RouteArrowStyle.chevronColor(on: route.color)),
                arrows: PolylineDirectionArrows.placements(along: coordinates),
                emphasis: emphasis(for: route.routeID)
            )
        }

        let vehicles = model.vehicles.compactMap { vehicle -> Vehicle? in
            // As on the map tab, a marker needs the departure behind it: the tap
            // follows it, and VoiceOver reads from it.
            guard let departure = arrivals.departures[vehicle.departureID] else { return nil }
            let color = colors[vehicle.routeID] ?? ThemeColors.shared.brand
            return Vehicle(
                id: vehicle.id,
                routeID: vehicle.routeID,
                coordinate: vehicle.coordinate,
                orientation: vehicle.orientation,
                routeType: departure.route?.routeType ?? .bus,
                isRealTime: departure.tripStatus?.isRealTime ?? false,
                color: Color(uiColor: color),
                emphasis: emphasis(for: vehicle.routeID),
                accessibilityLabel: StopRouteFocusMapLayer.accessibilityLabel(
                    routeShortName: departure.route?.shortName,
                    headsign: departure.tripHeadsign,
                    vehicleID: vehicle.id,
                    formatters: formatters
                ),
                accessibilityValue: formatters.accessibilityValue(for: departure),
                departure: departure
            )
        }

        // Nothing to draw yet, or nothing running: no point counting it as drawn.
        display = routes.isEmpty && vehicles.isEmpty ? nil : Display(routes: routes, vehicles: vehicles)
    }

    private func layOutLanes(for model: StopRouteFocusModel) {
        var shapeIDs: [RouteID: String] = [:]
        for route in model.routes {
            if let shapeID = route.shapeID, shapes[shapeID] != nil {
                shapeIDs[route.routeID] = shapeID
            }
        }
        guard shapeIDs != laneShapeIDs else { return }
        laneShapeIDs = shapeIDs
        lanes = RouteLanes(shapes: shapeIDs.compactMapValues { shapes[$0] })
    }

    private func emphasis(for routeID: RouteID) -> Emphasis {
        guard let focusedRouteID else { return .normal }
        return routeID == focusedRouteID ? .focused : .dimmed
    }
}
