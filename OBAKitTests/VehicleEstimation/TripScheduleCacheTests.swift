//
//  TripScheduleCacheTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
struct TripScheduleCacheTests {

    private actor Counter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    nonisolated private static let request = TripScheduleCache.Request(tripID: "trip", vehicleID: "v1", serviceDate: Date(timeIntervalSince1970: 1_800_000_000))

    nonisolated private static func schedule(_ length: Double = 1000) -> TripScheduleCache.Schedule {
        TripScheduleCache.Schedule(stopTimes: [EstimationFixtures.stop(0, at: 0), EstimationFixtures.stop(length, at: 100)], serverTripLength: length)
    }

    @Test func `A trip's schedule is fetched once and then served from the cache`() async throws {
        let counter = Counter()
        let cache = TripScheduleCache { _ in
            await counter.increment()
            return Self.schedule()
        }

        _ = try await cache.schedule(for: Self.request)
        let second = try await cache.schedule(for: Self.request)

        #expect(await counter.count == 1)
        #expect(second.serverTripLength == 1000)
    }

    @Test func `Concurrent requests for one trip share a fetch`() async throws {
        let counter = Counter()
        let cache = TripScheduleCache { _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return Self.schedule()
        }

        async let first = cache.schedule(for: Self.request)
        async let second = cache.schedule(for: Self.request)
        _ = try await (first, second)

        #expect(await counter.count == 1)
    }

    @Test func `A failed fetch is not cached`() async throws {
        let counter = Counter()
        let cache = TripScheduleCache { _ in
            await counter.increment()
            if await counter.count == 1 { throw URLError(.timedOut) }
            return Self.schedule()
        }

        await #expect(throws: URLError.self) { try await cache.schedule(for: Self.request) }
        _ = try await cache.schedule(for: Self.request)

        #expect(await counter.count == 2)
    }

    @Test func `A fetch that finishes after removeAll is not cached`() async throws {
        let counter = Counter()
        let (started, didStart) = AsyncStream.makeStream(of: Void.self)
        let cache = TripScheduleCache { _ in
            await counter.increment()
            didStart.yield()
            try await Task.sleep(for: .milliseconds(50))
            return Self.schedule()
        }

        async let late = cache.schedule(for: Self.request)
        var starts = started.makeAsyncIterator()
        _ = await starts.next()
        await cache.removeAll()
        _ = try? await late
        _ = try await cache.schedule(for: Self.request)

        #expect(await counter.count == 2)
    }
}
