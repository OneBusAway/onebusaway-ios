//
//  SearchResultRouter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import OBAKitCore

/// Turns a single search result into a map display plus a sheet route.
///
/// Shared by `SearchSheetViewModel` (single-result searches) and
/// `SearchResultsSheetView` (a row picked out of a disambiguation list), so the two
/// can't drift on what "opening a result" means.
///
/// The UIKit equivalent is split across `MapRegionManager.searchResponse.didSet` and
/// `MapViewController.mapRegionManager(_:showSearchResult:)`.
@MainActor
final class SearchResultRouter {

    private let application: Application
    private let coordinator: SheetCoordinator<AppSheetRoute>
    private let displayModel: MapSearchDisplayModel
    private let onPresentVehicleTrip: (VehicleStatus) -> Void

    /// Set when resolving a result fails, so the presenting screen can render the
    /// failure inline instead of popping a modal over the sheet.
    private(set) var lastError: Error?

    init(
        application: Application,
        coordinator: SheetCoordinator<AppSheetRoute>,
        displayModel: MapSearchDisplayModel,
        onPresentVehicleTrip: @escaping (VehicleStatus) -> Void
    ) {
        self.application = application
        self.coordinator = coordinator
        self.displayModel = displayModel
        self.onPresentVehicleTrip = onPresentVehicleTrip
    }

    /// A search result that has been resolved into everything needed to show it, with
    /// any network work already done.
    ///
    /// Separating this from `present(_:)` lets a caller finish the slow part while its
    /// own screen is still up — so a failure can be reported where the user is looking,
    /// and the sheet stack isn't torn down around an in-flight request.
    enum Resolved {
        case stop(Stop)
        case mapItem(MKMapItem, animated: Bool)
        case route(StopsForRoute)
        /// Handed to the trip bridge rather than a sheet, so it has no sheet route.
        case vehicle(VehicleStatus)
    }

    /// Resolves the single result in `response`. Returns `nil` when the response holds
    /// anything other than exactly one result, leaving that decision (disambiguate, or
    /// report no results) to the caller.
    func resolveSingleResult(from response: SearchResponse) async -> Resolved? {
        guard response.results.count == 1, let result = response.results.first else {
            return nil
        }
        return await resolve(result: result)
    }

    /// Turns a raw search result into a `Resolved`, performing whatever network work
    /// the result needs. Records `lastError` and returns `nil` when it can't be
    /// resolved. Touches neither the map nor the sheet stack.
    func resolve(result: Any) async -> Resolved? {
        lastError = nil

        switch result {
        case let stop as Stop:
            return .stop(stop)

        case let mapItem as MKMapItem:
            // Matches the UIKit rule: only animate the recenter for nearby
            // destinations, so a cross-region jump doesn't fly the camera across
            // the map.
            return .mapItem(mapItem, animated: isWithinAnimationRange(mapItem.placemark.coordinate))

        case let route as Route:
            return await resolveRoute(route)

        case let stopsForRoute as StopsForRoute:
            return .route(stopsForRoute)

        case let vehicle as VehicleStatus:
            return .vehicle(vehicle)

        default:
            Logger.error("SearchResultRouter: unhandled result type \(type(of: result))")
            return nil
        }
    }

    /// Draws the result and opens its sheet in one synchronous step, so the stacked
    /// layer never sits empty between the two.
    ///
    /// Each display is handed the same route value that gets pushed: the display lives
    /// exactly as long as its sheet route is on the stack, so the two must not drift.
    func present(_ resolved: Resolved) {
        switch resolved {
        case .stop(let stop):
            let route = AppSheetRoute.stopDetails(stopID: stop.id)
            displayModel.show(stop: stop, owner: route)
            coordinator.push(route)

        case .mapItem(let mapItem, let animated):
            let route = AppSheetRoute.mapItem(mapItem)
            displayModel.show(mapItem: mapItem, animated: animated, owner: route)
            coordinator.push(route)

        case .route(let stopsForRoute):
            let route = AppSheetRoute.routeStops(stopsForRoute)
            displayModel.show(stopsForRoute: stopsForRoute, owner: route)
            coordinator.push(route)

        case .vehicle(let vehicle):
            onPresentVehicleTrip(vehicle)
        }
    }

    /// Resolve-and-present for callers with nothing to unwind first.
    func present(result: Any) async {
        guard let resolved = await resolve(result: result) else { return }
        present(resolved)
    }

    /// A `Route` carries no geometry. Resolve it into `StopsForRoute` — the polyline
    /// and stop list — before anything can be drawn or listed.
    private func resolveRoute(_ route: Route) async -> Resolved? {
        guard let apiService = application.apiService else {
            // Every other failure here records `lastError` so the presenting screen
            // can say something. Returning silently would leave the caller reading
            // "succeeded, nothing happened" and the tapped row doing nothing.
            Logger.error("SearchResultRouter: no API service; cannot resolve route \(route.id).")
            lastError = APIError.noRegionSelected
            return nil
        }

        do {
            return .route(try await apiService.getStopsForRoute(routeID: route.id).entry)
        } catch {
            Logger.error("SearchResultRouter: failed to load stops for route \(route.id): \(error)")
            lastError = error
            return nil
        }
    }

    private static let animationDistanceThreshold: CLLocationDistance = 1609 // roughly a mile

    private func isWithinAnimationRange(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let currentLocation = application.locationService.currentLocation else { return false }
        return coordinate.distance(from: currentLocation.coordinate) <= Self.animationDistanceThreshold
    }
}
