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

    private let fetch: Fetch
    /// Shapes are a few KB each; 64 bounds a long session at a few hundred KB.
    private let cache = MemoizingCache<String, [CLLocationCoordinate2D]>(capacity: 64)

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func coordinates(forShapeID shapeID: String) async throws -> [CLLocationCoordinate2D] {
        try await cache.value(for: shapeID) { [fetch] in
            Polyline(encodedPolyline: try await fetch(shapeID)).coordinates ?? []
        }
    }

    func removeAll() async {
        await cache.removeAll()
    }
}
