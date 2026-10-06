//
//  RouteFilterOptions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The routes a rider can filter the map down to: every route serving a stop
/// the map has already loaded, so building the list costs no network request.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1414
enum RouteFilterOptions {

    enum Content: Equatable {
        /// Zoomed out past `MapRegionManager.requiredHeightToShowStops`, where no
        /// stops are loaded — any routes still in memory belong to a viewport the
        /// rider has already left.
        case zoomedOut
        case noRoutes
        case routes([Route])
    }

    static func content(stops: [Stop], isZoomedOut: Bool) -> Content {
        guard !isZoomedOut else { return .zoomedOut }
        let routes = routes(from: stops)
        return routes.isEmpty ? .noRoutes : .routes(routes)
    }

    /// Deduplicated by route ID and grouped by agency, so a campus shuttle network
    /// sharing curbs with a city system reads as two blocks rather than one
    /// interleaved list. Within an agency, short names sort the way riders count
    /// them ("2" before "10").
    static func routes(from stops: [Stop]) -> [Route] {
        var seen = Set<RouteID>()
        var routes = [Route]()
        for stop in stops {
            // `routes` is `[Route]!`, nil until references are reconnected.
            for route in stop.routes ?? [] where seen.insert(route.id).inserted {
                routes.append(route)
            }
        }
        return routes.sorted(by: areInIncreasingOrder)
    }

    private static func areInIncreasingOrder(_ lhs: Route, _ rhs: Route) -> Bool {
        let keys: [(String, String)] = [
            (lhs.agency?.name ?? "", rhs.agency?.name ?? ""),
            (lhs.shortName, rhs.shortName),
            (lhs.longName ?? "", rhs.longName ?? ""),
            (lhs.id, rhs.id)
        ]
        for (left, right) in keys {
            switch left.localizedStandardCompare(right) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: continue
            }
        }
        return false
    }
}
