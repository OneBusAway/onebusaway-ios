//
//  NearbyStopsLoader.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// Stops near a coordinate, nearest first, capped. Stateless; the watch's
/// Nearby screen calls it once per location fix.
///
/// `getStops(coordinate:)` has no radius parameter — the server applies its
/// default — so the cap is client-side over whatever the server returned.
public struct NearbyStopsLoader: Sendable {
    public let limit: Int

    public init(limit: Int = 20) {
        self.limit = limit
    }

    public func stops(near coordinate: CLLocationCoordinate2D, using apiService: RESTAPIService) async throws -> [Stop] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let stops = try await apiService.getStops(coordinate: coordinate).list

        return Array(
            stops
                .sorted { $0.location.distance(from: origin) < $1.location.distance(from: origin) }
                .prefix(limit)
        )
    }
}
