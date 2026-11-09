//
//  CachedRoute.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import GRDB

/// One route of a region, stored once and shared by every cached stop that lists
/// it in `routeIDs` (#1555).
///
/// Before schema v3 each stop embedded full copies of its routes, each carrying
/// its agency, so a route serving fifty stops was stored fifty times. A synced
/// 7,077-stop region measured 22 MB on disk that way.
struct CachedRoute: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cachedRoute"

    let id: String
    let regionId: Int
    let lastUpdated: Double
    let routeData: Data

    /// Returns `nil` if the route cannot be encoded, so a corrupted route is never stored.
    init?(route: Route, regionId: Int, lastUpdated: Date) {
        do {
            self.routeData = try JSONEncoder().encode(route)
        } catch {
            Logger.error("Failed to encode route \(route.id) for caching: \(error)")
            return nil
        }

        self.id = route.id
        self.regionId = regionId
        self.lastUpdated = lastUpdated.timeIntervalSince1970
    }

    func toRoute() -> Route? {
        do {
            return try JSONDecoder().decode(Route.self, from: routeData)
        } catch {
            Logger.error("Failed to decode cached route \(id): \(error)")
            return nil
        }
    }
}
