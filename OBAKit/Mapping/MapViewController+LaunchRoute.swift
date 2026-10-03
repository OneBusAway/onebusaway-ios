//
//  MapViewController+LaunchRoute.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

/// Opens the map on the route named by `OBAKitConfig.LaunchRouteID`.
///
/// Reuses the route-search display rather than drawing anything of its own, so the
/// launch route looks and dismisses exactly like a route the rider searched for.
extension MapViewController {

    /// Safe to call repeatedly: `LaunchRouteGate` hands out the route at most once
    /// per launch, and only after a region exists to look it up in.
    func showLaunchRouteIfNeeded() {
        guard let routeID = application.launchRouteGate.claim(
            hasRegion: application.currentRegion != nil && application.apiService != nil,
            hasPendingNavigation: application.pendingStopID != nil
        ) else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.loadLaunchRoute(routeID: routeID)
        }
    }

    private func loadLaunchRoute(routeID: RouteID) async {
        guard let apiService = application.apiService else { return }

        let stopsForRoute: StopsForRoute
        do {
            stopsForRoute = try await apiService.getStopsForRoute(routeID: routeID).entry
        } catch {
            // Misconfiguration or an outage: the rider still gets the ordinary map.
            Logger.error("LaunchRouteID \(routeID) could not be loaded from the current region; showing the normal map. \(error)")
            return
        }

        let isMapShowingOtherContent = mapRegionManager.searchResponse != nil
            || mapRegionManager.stopSheetSelection != nil
            || presentedViewController != nil

        guard application.launchRouteGate.mayDisplay(
            polylineCount: stopsForRoute.polylines.count,
            isMapShowingOtherContent: isMapShowingOtherContent
        ) else {
            Logger.info("LaunchRouteID \(routeID) loaded but was not shown: suppressed, superseded, or has no geometry.")
            return
        }

        let request = SearchRequest(query: routeID, type: .route)
        mapRegionManager.searchResponse = SearchResponse(request: request, results: [stopsForRoute], boundingRegion: nil, error: nil)
    }
}
