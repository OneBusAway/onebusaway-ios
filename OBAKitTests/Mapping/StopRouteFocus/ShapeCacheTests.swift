//
//  ShapeCacheTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
struct ShapeCacheTests {

    /// Counts calls so the test can prove memoization.
    private actor Counter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private func encodedSeattleLine() -> String {
        // Two points near downtown Seattle, Google encoded-polyline format.
        Polyline(coordinates: [
            CLLocationCoordinate2D(latitude: 47.60, longitude: -122.33),
            CLLocationCoordinate2D(latitude: 47.61, longitude: -122.34)
        ]).encodedPolyline
    }

    @Test func `A shape is fetched once and reused`() async throws {
        let counter = Counter()
        let encoded = encodedSeattleLine()
        let cache = ShapeCache { _ in
            await counter.increment()
            return encoded
        }

        let first = try await cache.coordinates(forShapeID: "1_shape")
        let second = try await cache.coordinates(forShapeID: "1_shape")

        #expect(first.count == 2)
        #expect(second.count == 2)
        #expect(await counter.count == 1)
    }

    @Test func `Distinct shapes fetch separately`() async throws {
        let counter = Counter()
        let encoded = encodedSeattleLine()
        let cache = ShapeCache { _ in
            await counter.increment()
            return encoded
        }

        _ = try await cache.coordinates(forShapeID: "1_a")
        _ = try await cache.coordinates(forShapeID: "1_b")

        #expect(await counter.count == 2)
    }

    @Test func `Concurrent callers for the same shape fetch once`() async throws {
        // The three sequential tests above all hit either `storage` or a cold
        // fetch — delete the whole `inFlight` map and they still pass. This is the
        // one that actually proves in-flight deduplication, which is what keeps a
        // six-route stop from firing six requests for one shared shape.
        let counter = Counter()
        let encoded = encodedSeattleLine()
        let cache = ShapeCache { _ in
            try? await Task.sleep(for: .milliseconds(50))
            await counter.increment()
            return encoded
        }

        async let first = cache.coordinates(forShapeID: "1_shape")
        async let second = cache.coordinates(forShapeID: "1_shape")
        _ = try await (first, second)

        #expect(await counter.count == 1)
    }

    @Test func `removeAll forces a refetch`() async throws {
        let counter = Counter()
        let encoded = encodedSeattleLine()
        let cache = ShapeCache { _ in
            await counter.increment()
            return encoded
        }

        _ = try await cache.coordinates(forShapeID: "1_shape")
        await cache.removeAll()
        _ = try await cache.coordinates(forShapeID: "1_shape")

        #expect(await counter.count == 2)
    }
}
