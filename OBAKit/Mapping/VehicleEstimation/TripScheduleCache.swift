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
/// the map session. Same shape as `ShapeCache`: bounded, de-duplicates in-flight
/// fetches, and drops a fetch that resolves after `removeAll()`.
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

    private final class InFlightBox {
        let task: Task<Schedule, Error>
        init(task: Task<Schedule, Error>) { self.task = task }
    }

    private let fetch: Fetch
    private var storage: [String: Schedule] = [:]
    private var inFlight: [String: InFlightBox] = [:]
    private var insertionOrder: [String] = []
    private let capacity = 64
    private var generation: UInt64 = 0

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// Keyed by trip and service day: the vehicle doesn't change the schedule.
    private static func key(_ request: Request) -> String {
        "\(request.tripID)|\(Int64(request.serviceDate.timeIntervalSince1970))"
    }

    func schedule(for request: Request) async throws -> Schedule {
        let key = Self.key(request)
        if let cached = storage[key] { return cached }
        if let existing = inFlight[key] { return try await existing.task.value }

        let generation = self.generation
        let box = InFlightBox(task: Task { [fetch] in try await fetch(request) })
        inFlight[key] = box

        // Identity, not `defer`, for the reason `ShapeCache.coordinates(forShapeID:)` gives.
        let schedule: Schedule
        do {
            schedule = try await box.task.value
        } catch {
            if inFlight[key] === box { inFlight[key] = nil }
            throw error
        }
        if inFlight[key] === box { inFlight[key] = nil }

        guard generation == self.generation else { return schedule }
        storage[key] = schedule
        insertionOrder.append(key)
        while insertionOrder.count > capacity {
            storage[insertionOrder.removeFirst()] = nil
        }
        return schedule
    }

    func removeAll() {
        generation &+= 1
        storage.removeAll()
        insertionOrder.removeAll()
        for box in inFlight.values { box.task.cancel() }
        inFlight.removeAll()
    }
}
