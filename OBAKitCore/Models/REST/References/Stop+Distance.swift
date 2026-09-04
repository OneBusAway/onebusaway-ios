//
//  Stop+Distance.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

public extension Stop {

    /// Squared distance with longitude scaled by `cos(latitude)` so lat/lon
    /// degrees compare on a common metric scale. Ordering only — no sqrt, and
    /// the result is not meaningful as a real-world distance.
    nonisolated static func squaredDistance(_ stop: Stop, to center: CLLocationCoordinate2D) -> Double {
        let coordinate = stop.location.coordinate
        let dLat = coordinate.latitude - center.latitude
        let dLon = (coordinate.longitude - center.longitude) * cos(center.latitude * .pi / 180)
        return dLat * dLat + dLon * dLon
    }

    /// The `limit` stops closest to `center`, nearest first.
    ///
    /// Shared by `MapStopsObserver`'s cap eviction and the home sheet's nearby
    /// section so both order stops by exactly the same metric.
    nonisolated static func nearest(_ stops: [Stop], to center: CLLocationCoordinate2D, limit: Int) -> [Stop] {
        guard limit > 0 else { return [] }
        return stops
            .sorted { squaredDistance($0, to: center) < squaredDistance($1, to: center) }
            .prefix(limit)
            .map { $0 }
    }
}
