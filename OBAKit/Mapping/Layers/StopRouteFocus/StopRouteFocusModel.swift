//
//  StopRouteFocusModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore
import UIKit

/// What the map needs from a departure, beyond what the list needs.
///
/// Mirrors `DepartureListEntry`'s reason for existing: `ArrivalDeparture` only
/// decodes from JSON, so tests pass stubs.
protocol MapDepartureEntry: DepartureListEntry {
    var routeShortName: String { get }
    var routeColor: UIColor { get }
    var shapeID: String? { get }
    var tripID: String { get }
    var vehicleID: String? { get }
    /// `position` preferred, `lastKnownLocation` as fallback, nil when neither is
    /// usable. Never a null-island placeholder.
    var vehicleCoordinate: CLLocationCoordinate2D? { get }
    var orientation: CLLocationDirection { get }
}

/// The map's view of one selected stop: which routes to draw and where their
/// vehicles are. Pure — no network, no side effects.
///
/// Deliberately NOT `Equatable`: `CLLocationCoordinate2D` has no `Equatable`
/// conformance (verified — synthesis fails with "stored property type
/// 'CLLocationCoordinate2D' does not conform to protocol 'Equatable'"), and
/// nothing compares whole models, so adding one would be busywork.
struct StopRouteFocusModel {

    struct DrawnRoute: Equatable, Identifiable {
        let routeID: RouteID
        var id: RouteID { routeID }
        let shortName: String
        let color: UIColor
        /// Pinned from the route's soonest departure at derivation time.
        let shapeID: String?
        let hasLiveVehicle: Bool
    }

    struct DrawnVehicle: Identifiable {
        /// `vehicleID` when the agency reports one, `tripID` otherwise.
        let id: String
        let routeID: RouteID
        let coordinate: CLLocationCoordinate2D
        let orientation: CLLocationDirection
        /// The departure this vehicle is serving. The layer resolves it back to
        /// the live `ArrivalDeparture` (and thus its `TripStatus`) rather than
        /// snapshotting one here — the annotation REQUIRES a non-nil
        /// `TripStatus`, see Task 7.
        let departureID: String
    }

    let routes: [DrawnRoute]
    let vehicles: [DrawnVehicle]

    static let empty = StopRouteFocusModel(routes: [], vehicles: [])

    /// The list's filter chain, reproduced exactly. The map must show lines for
    /// precisely the departures the list is showing — `isListFiltered` is
    /// rider-toggleable, so filtering unconditionally would hide lines for routes
    /// the list is currently displaying.
    ///
    /// Mirrors `StopPageView.filteredDepartures`.
    static func visibleDepartures(
        _ departures: [ArrivalDeparture],
        isListFiltered: Bool,
        preferences: StopPreferences
    ) -> [ArrivalDeparture] {
        let visible = isListFiltered ? departures.filter(preferences: preferences) : departures
        return visible.filteringTerminalDuplicates()
    }

    /// - Parameter routeCap: Maximum routes to draw. A downtown stop can serve
    ///   20+ routes over the arrival window; drawing all of them is both a
    ///   performance problem and an unreadable map.
    static func make<D: MapDepartureEntry>(departures: [D], routeCap: Int) -> StopRouteFocusModel {
        // The caller's list is NOT sorted — `filteredDepartures` sorts nowhere,
        // and sorting happens downstream in StopPageListBuilder. Sort here.
        let upcoming = departures
            .filter { $0.temporalState != .past }
            .sorted { $0.arrivalDepartureMinutes < $1.arrivalDepartureMinutes }

        // First appearance in the sorted list == soonest arrival per route.
        var routeOrder: [RouteID] = []
        var soonestByRoute: [RouteID: D] = [:]
        for departure in upcoming where soonestByRoute[departure.routeID] == nil {
            soonestByRoute[departure.routeID] = departure
            routeOrder.append(departure.routeID)
        }
        let drawnRouteIDs = Array(routeOrder.prefix(routeCap))
        let drawnRouteIDSet = Set(drawnRouteIDs)

        var vehicles: [DrawnVehicle] = []
        var seenVehicleIDs = Set<String>()
        var routesWithVehicles = Set<RouteID>()
        for departure in upcoming where drawnRouteIDSet.contains(departure.routeID) {
            guard let coordinate = departure.vehicleCoordinate else { continue }
            let identity = departure.vehicleID ?? departure.tripID
            guard seenVehicleIDs.insert(identity).inserted else { continue }
            vehicles.append(DrawnVehicle(
                id: identity,
                routeID: departure.routeID,
                coordinate: coordinate,
                orientation: departure.orientation,
                departureID: departure.id
            ))
            routesWithVehicles.insert(departure.routeID)
        }

        let routes = drawnRouteIDs.compactMap { routeID -> DrawnRoute? in
            guard let soonest = soonestByRoute[routeID] else { return nil }
            return DrawnRoute(
                routeID: routeID,
                shortName: soonest.routeShortName,
                color: soonest.routeColor,
                shapeID: soonest.shapeID,
                hasLiveVehicle: routesWithVehicles.contains(routeID)
            )
        }

        return StopRouteFocusModel(routes: routes, vehicles: vehicles)
    }
}

extension ArrivalDeparture: MapDepartureEntry {

    var routeColor: UIColor { route.color ?? ThemeColors.shared.brand }

    var shapeID: String? { trip.shapeID }

    /// `position` is the extrapolated current location and is what the map should
    /// draw; `lastKnownLocation` is the raw last report. Prefer the former.
    ///
    /// Deliberately does NOT reuse `VehicleAnnotation.updateAnnotation()`, which
    /// reads only `lastKnownLocation` and falls back to a literal (0, 0) — it
    /// manufactures exactly the null-island coordinate this must reject.
    var vehicleCoordinate: CLLocationCoordinate2D? {
        guard let location = tripStatus?.position ?? tripStatus?.lastKnownLocation else { return nil }
        let coordinate = location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate), !coordinate.isNullIsland else { return nil }
        return coordinate
    }

    var orientation: CLLocationDirection { tripStatus?.orientation ?? 0 }
}
