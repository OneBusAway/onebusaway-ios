//
//  MapViewController+RouteFilter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

// MARK: - Routes on Map

extension MapViewController {

    /// Filters the map to `route` by publishing it exactly as a picked route
    /// search result is published. `MapRegionManager` then loads its stops and
    /// polyline, hides ambient stops, and opens `RouteStopsViewController`, whose
    /// Close button (`dismissModalController(_:)` → `cancelSearch()`) restores them.
    ///
    /// The route sheet is a child panel rather than a presentation, so this can run
    /// while the Map sheet is still animating away.
    ///
    /// See: https://github.com/OneBusAway/onebusaway-ios/issues/1414
    func showRouteOnMap(_ route: Route) {
        // `displaySearchResult(stopsForRoute:)` clears annotations but not
        // overlays, so a route already on screen would leave its polyline behind.
        if mapRegionManager.searchResponse != nil {
            mapRegionManager.cancelSearch()
        }

        let request = SearchRequest(query: route.shortName, type: .route)
        mapRegionManager.searchResponse = SearchResponse(request: request, results: [route], boundingRegion: nil, error: nil)
    }
}
