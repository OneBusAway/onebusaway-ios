//
//  TripScheduleCache.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Memoizes each trip's stop times for vehicle position estimation on a stop's map.
///
/// One `trip-details` call per vehicle drawn, about 10–20 KB, rather than one
/// `trips-for-route` per route, which runs to hundreds of kilobytes. A trip's
/// schedule doesn't change through its service day, so each is fetched once for
/// the map session.
actor TripScheduleCache {

    struct Request: Sendable, Hashable {
        let tripID: String
        let vehicleID: String?
        let serviceDate: Date
    }

    struct Schedule: Sendable {
        let stopTimes: [TripGeometry.StopTime]
        let serverTripLength: Double?
    }

    /// Injected so tests can count fetches. Production passes a closure over
    /// `RESTAPIService.getTrip(tripID:vehicleID:serviceDate:)`.
    typealias Fetch = @Sendable (Request) async throws -> Schedule

    /// Keyed by trip and service day: the vehicle doesn't change the schedule.
    private struct Key: Hashable, Sendable {
        let tripID: String
        let serviceDate: Date
    }

    private let fetch: Fetch
    private let cache = MemoizingCache<Key, Schedule>(capacity: 64)

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func schedule(for request: Request) async throws -> Schedule {
        try await cache.value(for: Key(tripID: request.tripID, serviceDate: request.serviceDate)) { [fetch] in
            try await fetch(request)
        }
    }

    func removeAll() async {
        await cache.removeAll()
    }
}
