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
        private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        var requests: Int { lock.withLock { _requests } }
        var failing: Bool {
            get { lock.withLock { _failing } }
            set { lock.withLock { _failing = newValue } }
        }
        func record() {
            let toResume = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                _requests += 1
                let count = _requests
                var due: [CheckedContinuation<Void, Never>] = []
                waiters.removeAll { waiter in
                    if count >= waiter.count {
                        due.append(waiter.continuation)
                        return true
                    }
                    return false
                }
                return due
            }
            for waiter in toResume {
                waiter.resume()
            }
        }

        func waitForRequests(count target: Int) async {
            let alreadyMet = lock.withLock { _requests >= target }
            if alreadyMet { return }

            await withCheckedContinuation { continuation in
                let shouldResume = lock.withLock { () -> Bool in
                    if _requests >= target {
                        return true
                    }
                    waiters.append((count: target, continuation: continuation))
                    return false
                }
                if shouldResume {
                    continuation.resume()
                }
            }
        }
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

        await clock.waitForSleepers(count: 1)
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
        await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(30))

        let second = try #require(await iterator.next())
        guard case .success = second else {
            Issue.record("expected the second tick to succeed")
            return
        }
        #expect(gate.requests == 2)
    }

    @Test func `A cancellation failure during fetch delivers failure without ending the stream and next tick recovers`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        // First request fails with URLError(.cancelled)
        dataLoader.mock(response: MockDataResponse(
            data: nil,
            urlResponse: nil,
            error: URLError(.cancelled),
            matcher: { [arrivalsPath] request in
                guard request.url?.path.contains(arrivalsPath) == true, gate.failing else { return false }
                gate.record()
                return true
            }
        ))
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { [arrivalsPath] request in
            guard request.url?.path.contains(arrivalsPath) == true else { return false }
            gate.record()
            return true
        }

        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        gate.failing = true
        let stream = StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock)
        var iterator = stream.makeAsyncIterator()

        // 1. First tick delivers failure (cancellation-flavored failure is delivered as .failure without terminating the stream)
        let first = try #require(await iterator.next())
        guard case .failure(let error) = first else {
            Issue.record("expected first tick to deliver failure")
            return
        }
        #expect((error as? URLError)?.code == .cancelled)

        // 2. Next tick recovers cleanly
        gate.failing = false
        await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(30))

        let second = try #require(await iterator.next())
        guard case .success = second else {
            Issue.record("expected second tick to recover")
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
        await gate.waitForRequests(count: 1)
        await clock.waitForSleepers(count: 1)

        consumer.cancel()
        _ = await consumer.value

        await clock.waitForSleepers(count: 0)
        clock.advance(by: .seconds(60))
        #expect(gate.requests == 1)
    }

    // MARK: - Adaptive Cadence & Lifecycle Tests

    @Test func `Low Power Mode multiplies cadence interval`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        let stream = StopArrivalsPoller().arrivals(
            for: stopID,
            every: .seconds(30),
            using: service,
            clock: clock,
            powerStateProvider: { true },
            lowPowerMultiplier: 2.0
        )
        var iterator = stream.makeAsyncIterator()

        // 1. Initial emission
        _ = await iterator.next()
        #expect(gate.requests == 1)

        await clock.waitForSleepers(count: 1)
        // 2. Advance 30s — under LPM (60s interval), it should still be sleeping
        clock.advance(by: .seconds(30))
        #expect(await clock.sleeperCount == 1)
        #expect(gate.requests == 1)

        // 3. Advance remaining 30s (total 60s) — now it emits
        clock.advance(by: .seconds(30))
        let second = try #require(await iterator.next())
        #expect((try? second.get()) != nil)
        #expect(gate.requests == 2)
    }

    @Test func `Background scene phase pauses polling and foreground resumes with immediate fetch`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()
        let coordinator = PollerCoordinator()

        let (sceneStream, sceneContinuation) = AsyncStream<PollerScenePhase>.makeStream(bufferingPolicy: .bufferingNewest(1))

        let stream = StopArrivalsPoller().arrivals(
            for: stopID,
            every: .seconds(30),
            using: service,
            clock: clock,
            powerStateProvider: { false },
            scenePhaseStream: sceneStream,
            coordinator: coordinator
        )
        var iterator = stream.makeAsyncIterator()

        // 1. First fetch on start
        _ = await iterator.next()
        #expect(gate.requests == 1)
        await clock.waitForSleepers(count: 1)
        await coordinator.waitForWaiters(count: 1)

        // 2. Transition to background
        sceneContinuation.yield(.background)

        // Poller exits sleep, cancels clock sleeper, and waits in waitUntilActive
        await clock.waitForSleepers(count: 0)
        await coordinator.waitForWaiters(count: 1)

        // Advance clock while in background — no new requests should fire
        clock.advance(by: .seconds(60))
        #expect(gate.requests == 1)

        // 3. Transition back to active foreground
        sceneContinuation.yield(.active)

        // It should immediately perform a fetch upon returning to foreground
        let resumed = try #require(await iterator.next())
        #expect((try? resumed.get()) != nil)
        #expect(gate.requests == 2)
    }

    @Test func `Pull to refresh signal triggers immediate fetch without waiting for timer`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()
        let coordinator = PollerCoordinator()

        let (refreshStream, refreshContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

        let stream = StopArrivalsPoller().arrivals(
            for: stopID,
            every: .seconds(30),
            using: service,
            clock: clock,
            powerStateProvider: { false },
            refreshSignal: refreshStream,
            coordinator: coordinator
        )
        var iterator = stream.makeAsyncIterator()

        // 1. Initial emission
        _ = await iterator.next()
        #expect(gate.requests == 1)

        await clock.waitForSleepers(count: 1)
        await coordinator.waitForWaiters(count: 1)

        // 2. Trigger pull-to-refresh signal without advancing clock
        refreshContinuation.yield()

        let refreshed = try #require(await iterator.next())
        #expect((try? refreshed.get()) != nil)
        #expect(gate.requests == 2)
    }

    @Test func `Advances through multiple ticks with exactly one request per interval`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        let stream = StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock)
        var iterator = stream.makeAsyncIterator()

        // 1. Initial emission
        _ = await iterator.next()
        #expect(gate.requests == 1)

        // 2. Advance through 3 separate ticks
        for expectedRequests in 2...4 {
            await clock.waitForSleepers(count: 1)
            clock.advance(by: .seconds(30))
            let nextEmission = try #require(await iterator.next())
            #expect((try? nextEmission.get()) != nil)
            #expect(gate.requests == expectedRequests)
        }
    }

    @Test func `Sleeps through one normal tick before backgrounding and pausing`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()
        let coordinator = PollerCoordinator()

        let (sceneStream, sceneContinuation) = AsyncStream<PollerScenePhase>.makeStream(bufferingPolicy: .bufferingNewest(1))

        let stream = StopArrivalsPoller().arrivals(
            for: stopID,
            every: .seconds(30),
            using: service,
            clock: clock,
            powerStateProvider: { false },
            scenePhaseStream: sceneStream,
            coordinator: coordinator
        )
        var iterator = stream.makeAsyncIterator()

        // 1. First fetch on start
        _ = await iterator.next()
        #expect(gate.requests == 1)

        // 2. Complete one normal tick in foreground
        await clock.waitForSleepers(count: 1)
        await coordinator.waitForWaiters(count: 1)
        clock.advance(by: .seconds(30))
        let second = try #require(await iterator.next())
        #expect((try? second.get()) != nil)
        #expect(gate.requests == 2)

        await clock.waitForSleepers(count: 1)
        await coordinator.waitForWaiters(count: 1)

        // 3. Transition to background
        sceneContinuation.yield(.background)

        await clock.waitForSleepers(count: 0)
        await coordinator.waitForWaiters(count: 1)

        // Advance 90s (3 full intervals) while in background — no new requests
        clock.advance(by: .seconds(90))
        #expect(gate.requests == 2)

        // 4. Return to foreground — immediate fetch
        sceneContinuation.yield(.active)
        let resumed = try #require(await iterator.next())
        #expect((try? resumed.get()) != nil)
        #expect(gate.requests == 3)
    }

    @Test func `Toggling Low Power Mode does not trigger immediate fetch but applies multiplier on next sleep`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()
        let coordinator = PollerCoordinator()

        let stream = StopArrivalsPoller().arrivals(
            for: stopID,
            every: .seconds(30),
            using: service,
            clock: clock,
            powerStateProvider: { false },
            lowPowerMultiplier: 2.0,
            coordinator: coordinator
        )
        var iterator = stream.makeAsyncIterator()

        // 1. Initial emission
        _ = await iterator.next()
        #expect(gate.requests == 1)

        await clock.waitForSleepers(count: 1)
        await coordinator.waitForWaiters(count: 1)

        // 2. Toggle Low Power Mode to true while mid-sleep
        await coordinator.setLowPower(true)

        // Advance 15s — no premature fetch. Wait for the sleeper/waiter to
        // re-register first: without that, the assertion runs before any
        // async fetch could finish, so it would still pass if toggling woke
        // the sleep.
        clock.advance(by: .seconds(15))
        await clock.waitForSleepers(count: 1)
        await coordinator.waitForWaiters(count: 1)
        #expect(gate.requests == 1)

        // Complete the remaining 15s of the current 30s interval
        clock.advance(by: .seconds(15))
        let second = try #require(await iterator.next())
        #expect((try? second.get()) != nil)
        #expect(gate.requests == 2)

        // 3. Next sleep now uses multiplied 60s interval
        await clock.waitForSleepers(count: 1)
        await coordinator.waitForWaiters(count: 1)

        clock.advance(by: .seconds(30))
        #expect(await clock.sleeperCount == 1)
        #expect(gate.requests == 2)

        clock.advance(by: .seconds(30))
        let third = try #require(await iterator.next())
        #expect((try? third.get()) != nil)
        #expect(gate.requests == 3)
    }

    @Test func `A refresh that arrives while backgrounded does not fetch twice on foregrounding`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()
        let coordinator = PollerCoordinator()

        let (sceneStream, sceneContinuation) = AsyncStream<PollerScenePhase>.makeStream(bufferingPolicy: .bufferingNewest(1))

        let stream = StopArrivalsPoller().arrivals(
            for: stopID,
            every: .seconds(30),
            using: service,
            clock: clock,
            powerStateProvider: { false },
            scenePhaseStream: sceneStream,
            coordinator: coordinator
        )
        var iterator = stream.makeAsyncIterator()

        // 1. Initial emission
        _ = await iterator.next()
        #expect(gate.requests == 1)
        await clock.waitForSleepers(count: 1)
        await coordinator.waitForWaiters(count: 1)

        // 2. Go to background, then trigger a refresh while backgrounded
        sceneContinuation.yield(.background)
        await clock.waitForSleepers(count: 0)
        await coordinator.waitForWaiters(count: 1)

        // Trigger the refresh directly on the coordinator: Task.yield() does
        // not guarantee the refresh consumer runs, so yielding via the
        // stream here is racy. triggerRefresh() records the refresh
        // deterministically, and the foreground fetch below is the one that
        // consumes it.
        await coordinator.triggerRefresh()

        // 3. Return to foreground — one fetch for the refresh, not two
        sceneContinuation.yield(.active)
        let resumed = try #require(await iterator.next())
        #expect((try? resumed.get()) != nil)
        #expect(gate.requests == 2)

        // Settle into the next sleep, then confirm no second fetch followed
        await clock.waitForSleepers(count: 1)
        await coordinator.waitForWaiters(count: 1)
        clock.advance(by: .seconds(5))
        #expect(gate.requests == 2)
    }

    @Test func `A fresh refresh stream per poll works across sequential pollers`() async throws {
        // Documents the contract: callers pass a fresh stream per arrivals()
        // call. An AsyncStream whose iteration was cancelled cannot be
        // iterated again, so a stream must never be reused across a retry() —
        // each poller gets its own stream, as StopArrivalsModel does.
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        // 1. First poller with its own stream: initial fetch, then cancel it.
        let (refreshStream1, _) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let coordinator1 = PollerCoordinator()
        let firstConsumer = Task {
            for await _ in StopArrivalsPoller().arrivals(
                for: stopID,
                every: .seconds(30),
                using: service,
                clock: clock,
                powerStateProvider: { false },
                refreshSignal: refreshStream1,
                coordinator: coordinator1
            ) {}
        }
        await gate.waitForRequests(count: 1)
        await clock.waitForSleepers(count: 1)
        await coordinator1.waitForWaiters(count: 1)

        firstConsumer.cancel()
        _ = await firstConsumer.value
        await clock.waitForSleepers(count: 0)

        // 2. Second poller with a fresh stream: initial fetch, then a refresh
        // on the fresh stream is delivered.
        let (refreshStream2, refreshContinuation2) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let coordinator2 = PollerCoordinator()
        let stream2 = StopArrivalsPoller().arrivals(
            for: stopID,
            every: .seconds(30),
            using: service,
            clock: clock,
            powerStateProvider: { false },
            refreshSignal: refreshStream2,
            coordinator: coordinator2
        )
        var iterator2 = stream2.makeAsyncIterator()
        _ = await iterator2.next()
        #expect(gate.requests == 2)
        await clock.waitForSleepers(count: 1)
        await coordinator2.waitForWaiters(count: 1)

        refreshContinuation2.yield()
        let refreshed = try #require(await iterator2.next())
        #expect((try? refreshed.get()) != nil)
        #expect(gate.requests == 3)
    }
}
