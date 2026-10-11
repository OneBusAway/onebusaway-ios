//
//  StopArrivalsPollerTests.swift
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
final class StopArrivalsPollerTests: OBATestCase {

    private let stopID = "1_75414"
    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"

    /// Thread-safe request counter and failure switch; matchers run off-main.
    private nonisolated final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests = 0
        private var _failing = false

        var requests: Int { lock.withLock { _requests } }
        var failing: Bool {
            get { lock.withLock { _failing } }
            set { lock.withLock { _failing = newValue } }
        }
        func record() { lock.withLock { _requests += 1 } }
    }

    private func mockArrivals(_ dataLoader: MockDataLoader, gate: Gate) {
        // Order matters: MockDataLoader returns the first matcher that accepts.
        dataLoader.mock(data: Data("{}".utf8), statusCode: 500) { [arrivalsPath] request in
            guard request.url?.path.contains(arrivalsPath) == true, gate.failing else { return false }
            gate.record()
            return true
        }
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { [arrivalsPath] request in
            guard request.url?.path.contains(arrivalsPath) == true else { return false }
            gate.record()
            return true
        }
    }

    @Test func `Emits once immediately`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        let stream = StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock)
        var iterator = stream.makeAsyncIterator()

        let first = try #require(await iterator.next())
        let arrivals = try first.get()
        // The fixture's departures are from 2018, so `matching` (which drops
        // `.past`) leaves nothing — proving the filter runs. That the fetch
        // happened is the request count; non-empty delivery is covered by
        // BookmarkArrivalsLoaderTests and the widget tests.
        #expect(arrivals.isEmpty)
        #expect(gate.requests == 1)
    }

    @Test func `Emits again on each tick`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        let stream = StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock)
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        await poll(until: { clock.sleeperCount == 1 }, "the poller should be sleeping until the next tick")
        clock.advance(by: .seconds(30))

        let second = try #require(await iterator.next())
        #expect((try? second.get()) != nil)
        #expect(gate.requests == 2)
    }

    @Test func `A failed tick delivers a failure and the next tick recovers`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        gate.failing = true
        let stream = StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock)
        var iterator = stream.makeAsyncIterator()

        let first = try #require(await iterator.next())
        guard case .failure = first else {
            Issue.record("expected the first tick to fail")
            return
        }

        gate.failing = false
        await poll(until: { clock.sleeperCount == 1 }, "the poller should survive a failure and sleep")
        clock.advance(by: .seconds(30))

        let second = try #require(await iterator.next())
        guard case .success = second else {
            Issue.record("expected the second tick to succeed")
            return
        }
        #expect(gate.requests == 2)
    }

    @Test func `Cancelling the consumer stops the fetches`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        let consumer = Task {
            for await _ in StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock) {
                // consume forever
            }
        }
        await poll(until: { gate.requests == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        consumer.cancel()
        _ = await consumer.value

        await poll(until: { clock.sleeperCount == 0 }, "cancellation should unpark the sleeper")
        clock.advance(by: .seconds(60))
        try await Task.sleep(for: .milliseconds(50))
        #expect(gate.requests == 1)
    }
}
