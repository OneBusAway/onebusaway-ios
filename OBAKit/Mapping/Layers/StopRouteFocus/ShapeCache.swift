//
//  ShapeCache.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// Memoizes decoded route shapes for the life of a map session.
///
/// Shapes are static per region, and the same shape is commonly shared by
/// several routes, so refetching per stop-open would be pure waste. Bounded
/// because a long session visiting many stops would otherwise grow without
/// limit, and invalidated on region change because shape IDs are region-scoped.
///
/// An `actor` rather than a `@MainActor` type: the fetch is `nonisolated async`
/// and the decode is pure CPU work with no reason to occupy the main actor.
actor ShapeCache {

    /// Injected so tests can count fetches without a network stub. Production
    /// passes a closure over `RESTAPIService.getShape(id:)`.
    typealias Fetch = @Sendable (String) async throws -> String

    /// `Task` is a struct with no identity of its own, so `===` can't compare
    /// two `Task` values directly. This box gives each in-flight fetch a
    /// reference identity to compare against, which is what lets us tell "my
    /// task is still the installed one" apart from "someone else's newer task
    /// replaced mine" without using `defer` (see the comment in
    /// `coordinates(forShapeID:)`).
    private final class InFlightBox {
        let task: Task<[CLLocationCoordinate2D], Error>
        init(task: Task<[CLLocationCoordinate2D], Error>) {
            self.task = task
        }
    }

    private let fetch: Fetch
    private var storage: [String: [CLLocationCoordinate2D]] = [:]
    /// In-flight requests, so two routes sharing a shape don't both fetch.
    private var inFlight: [String: InFlightBox] = [:]

    /// Beyond this, the least-recently-inserted entries are dropped. Shapes are
    /// a few KB each; this bounds a long session at a few hundred KB.
    private let capacity = 64
    private var insertionOrder: [String] = []

    /// Bumped by `removeAll()` so an in-flight fetch that resolves afterwards can
    /// tell it belongs to a torn-down presentation and decline to cache itself.
    private var generation: UInt64 = 0

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func coordinates(forShapeID shapeID: String) async throws -> [CLLocationCoordinate2D] {
        if let cached = storage[shapeID] { return cached }
        if let existing = inFlight[shapeID] { return try await existing.task.value }

        let generation = self.generation
        let task = Task<[CLLocationCoordinate2D], Error> { [fetch] in
            let encoded = try await fetch(shapeID)
            return Polyline(encodedPolyline: encoded).coordinates ?? []
        }
        let box = InFlightBox(task: task)
        inFlight[shapeID] = box

        // No `defer` here. The actor suspends at the `await` below, so a `defer`
        // would run after other callers have had a turn — and would clear whatever
        // NEW task another caller installed for this shape ID, not necessarily
        // ours. Compare identity instead.
        let coordinates: [CLLocationCoordinate2D]
        do {
            coordinates = try await task.value
        } catch {
            if inFlight[shapeID] === box { inFlight[shapeID] = nil }
            throw error
        }
        if inFlight[shapeID] === box { inFlight[shapeID] = nil }

        // Drop a response that resolved after `removeAll()` — otherwise a fetch
        // started for a dismissed sheet repopulates the cache for a presentation
        // that no longer exists.
        guard generation == self.generation else { return coordinates }
        store(coordinates, for: shapeID)
        return coordinates
    }

    func removeAll() {
        generation &+= 1
        storage.removeAll()
        insertionOrder.removeAll()
        for box in inFlight.values { box.task.cancel() }
        inFlight.removeAll()
    }

    private func store(_ coordinates: [CLLocationCoordinate2D], for shapeID: String) {
        storage[shapeID] = coordinates
        insertionOrder.append(shapeID)
        while insertionOrder.count > capacity {
            let evicted = insertionOrder.removeFirst()
            storage[evicted] = nil
        }
    }
}
