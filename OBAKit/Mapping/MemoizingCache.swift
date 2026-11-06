//
//  MemoizingCache.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Memoizes values that are expensive to fetch and don't change for the life of
/// a map session: `ShapeCache`'s shapes, `TripScheduleCache`'s stop times.
///
/// Bounded, so a long session can't grow it without limit; de-duplicates
/// in-flight fetches, so two callers wanting one key share one request; and drops
/// a fetch that resolves after `removeAll()`, so a torn-down presentation can't
/// repopulate it. A failed fetch is not cached.
actor MemoizingCache<Key: Hashable & Sendable, Value: Sendable> {

    /// `Task` is a struct with no identity of its own, so `===` can't compare
    /// two `Task` values directly. This box gives each in-flight fetch a
    /// reference identity to compare against, which is what lets us tell "my
    /// task is still the installed one" apart from "someone else's newer task
    /// replaced mine" without using `defer` (see the comment in `value(for:fetch:)`).
    private final class InFlightBox {
        let task: Task<Value, Error>
        init(task: Task<Value, Error>) {
            self.task = task
        }
    }

    private var storage: [Key: Value] = [:]
    private var inFlight: [Key: InFlightBox] = [:]

    /// Beyond this, the least-recently-inserted entries are dropped.
    private let capacity: Int
    private var insertionOrder: [Key] = []

    /// Bumped by `removeAll()` so an in-flight fetch that resolves afterwards can
    /// tell it belongs to a torn-down presentation and decline to cache itself.
    private var generation: UInt64 = 0

    init(capacity: Int = 64) {
        self.capacity = capacity
    }

    func value(for key: Key, fetch: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let cached = storage[key] { return cached }
        if let existing = inFlight[key] { return try await existing.task.value }

        let generation = self.generation
        let box = InFlightBox(task: Task { try await fetch() })
        inFlight[key] = box

        // No `defer` here. The actor suspends at the `await` below, so a `defer`
        // would run after other callers have had a turn — and would clear whatever
        // NEW task another caller installed for this key, not necessarily ours.
        // Compare identity instead.
        let value: Value
        do {
            value = try await box.task.value
        } catch {
            if inFlight[key] === box { inFlight[key] = nil }
            throw error
        }
        if inFlight[key] === box { inFlight[key] = nil }

        // Drop a response that resolved after `removeAll()` — otherwise a fetch
        // started for a dismissed sheet repopulates the cache for a presentation
        // that no longer exists.
        guard generation == self.generation else { return value }
        storage[key] = value
        insertionOrder.append(key)
        while insertionOrder.count > capacity {
            storage[insertionOrder.removeFirst()] = nil
        }
        return value
    }

    func removeAll() {
        generation &+= 1
        storage.removeAll()
        insertionOrder.removeAll()
        for box in inFlight.values { box.task.cancel() }
        inFlight.removeAll()
    }
}
