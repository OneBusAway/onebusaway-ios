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

    /// Routes `response` when it holds exactly one result. Returns `false` when it
    /// doesn't, leaving the decision (disambiguate, or report no results) to the
    /// caller.
    func presentSingleResult(from response: SearchResponse) async -> Bool {
        guard response.results.count == 1, let result = response.results.first else {
            return false
        }
        await present(result: result)
        return true
    }

    func present(result: Any) async {
        lastError = nil

        switch result {
        case let stop as Stop:
            displayModel.show(stop: stop)
            coordinator.push(.stopDetails(stopID: stop.id))

        case let mapItem as MKMapItem:
            // Matches the UIKit rule: only animate the recenter for nearby
            // destinations, so a cross-region jump doesn't fly the camera across
            // the map.
            let animated = isWithinAnimationRange(mapItem.placemark.coordinate)
            displayModel.show(mapItem: mapItem, animated: animated)
            coordinator.push(.mapItem(mapItem))

        case let route as Route:
            await presentRoute(route)

        case let stopsForRoute as StopsForRoute:
            displayModel.show(stopsForRoute: stopsForRoute)
            coordinator.push(.routeStops(stopsForRoute))

        case let vehicle as VehicleStatus:
            onPresentVehicleTrip(vehicle)

        default:
            Logger.error("SearchResultRouter: unhandled result type \(type(of: result))")
        }
    }

    /// A `Route` carries no geometry. Resolve it into `StopsForRoute` — the polyline
    /// and stop list — before anything can be drawn or listed.
    private func presentRoute(_ route: Route) async {
        guard let apiService = application.apiService else {
            // Every other failure here records `lastError` so the presenting screen
            // can say something. Returning silently would leave the caller reading
            // "succeeded, nothing happened" and the tapped row doing nothing.
            Logger.error("SearchResultRouter: no API service; cannot resolve route \(route.id).")
            lastError = APIError.noRegionSelected
            return
        }

        do {
            let stopsForRoute = try await apiService.getStopsForRoute(routeID: route.id).entry
            displayModel.show(stopsForRoute: stopsForRoute)
            coordinator.push(.routeStops(stopsForRoute))
        } catch {
            Logger.error("SearchResultRouter: failed to load stops for route \(route.id): \(error)")
            lastError = error
        }
    }

    private static let animationDistanceThreshold: CLLocationDistance = 1609 // roughly a mile

    private func isWithinAnimationRange(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let currentLocation = application.locationService.currentLocation else { return false }
        return coordinate.distance(from: currentLocation.coordinate) <= Self.animationDistanceThreshold
    }
}
