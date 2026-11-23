//
//  StopArrivalsModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct StopArrivalsModelTests {

    private func makeStop() -> Stop {
        Stop(
            id: "1_100",
            name: "3rd & Pike",
            direction: "S",
            location: CLLocation(latitude: 47.6097, longitude: -122.3378)
        )
    }

    private func makeArrival() throws -> ArrivalDeparture {
        try Fixtures.loadRESTAPIPayload(
            type: ArrivalDeparture.self,
            fileName: "arrival-and-departure-for-stop-1_11420.json"
        )
    }

    @Test @MainActor func `Initial phase is loading`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        #expect(model.phase == .loading)
    }

    @Test @MainActor func `Missing API service transitions to failed immediately`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.startPolling()

        if case .failed(let message) = model.phase {
            #expect(message == Strings.noTransitRegion)
        } else {
            Issue.record("Expected failed phase when API service is nil, got \(model.phase)")
        }
    }

    @Test @MainActor func `Successful fetch with arrivals transitions to loaded`() throws {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))

        if case .loaded(let arrivals, _, let stale) = model.phase {
            #expect(arrivals.count == 1)
            #expect(stale == false)
        } else {
            Issue.record("Expected loaded phase, got \(model.phase)")
        }
    }

    @Test @MainActor func `Successful fetch with empty arrivals transitions to empty`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.apply(.success([]))

        if case .empty = model.phase {
            // Success
        } else {
            Issue.record("Expected empty phase, got \(model.phase)")
        }
    }

    @Test @MainActor func `Offline network error transitions to offline phase`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let offlineError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        model.apply(.failure(offlineError))

        #expect(model.phase == .offline)
    }

    @Test @MainActor func `Other error transitions to failed phase with message`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let serverError = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server 500"])

        model.apply(.failure(serverError))

        if case .failed(let message) = model.phase {
            #expect(message == "Server 500")
        } else {
            Issue.record("Expected failed phase, got \(model.phase)")
        }
    }

    @Test @MainActor func `Failure when loaded preserves arrivals and marks stale`() throws {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        model.apply(.failure(error))

        if case .loaded(let arrivals, _, let stale) = model.phase {
            #expect(arrivals.count == 1)
            #expect(stale == true)
        } else {
            Issue.record("Expected loaded(stale: true), got \(model.phase)")
        }
    }

    @Test @MainActor func `Recovery after stale loaded phase restores fresh loaded state`() throws {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))
        model.apply(.failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))

        if case .loaded(_, _, let stale) = model.phase {
            #expect(stale == true)
        } else {
            Issue.record("Expected stale loaded phase")
        }

        // Subsequent poll succeeds
        model.apply(.success([arrival]))

        if case .loaded(let arrivals, _, let stale) = model.phase {
            #expect(arrivals.count == 1)
            #expect(stale == false)
        } else {
            Issue.record("Expected fresh loaded(stale: false) after recovery, got \(model.phase)")
        }
    }

    @Test @MainActor func `Recovery from offline to empty when poll returns no arrivals`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.apply(.failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
        #expect(model.phase == .offline)

        model.apply(.success([]))

        if case .empty = model.phase {
            // Success
        } else {
            Issue.record("Expected empty phase after recovering from offline, got \(model.phase)")
        }
    }

    @Test @MainActor func `Non-offline error while in empty phase leaves phase unchanged`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.apply(.success([]))
        if case .empty = model.phase {
            // expected
        } else {
            Issue.record("Expected empty phase")
        }

        // Server 500 error while in empty phase does not transition to offline or wipe empty state
        let serverError = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)
        model.apply(.failure(serverError))

        if case .empty = model.phase {
            // expected to remain in empty
        } else {
            Issue.record("Expected empty phase to be preserved on non-offline failure, got \(model.phase)")
        }
    }

    @Test @MainActor func `Offline failure when empty transitions to offline`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.apply(.success([]))
        if case .empty = model.phase {
            // expected
        } else {
            Issue.record("Expected empty phase")
        }

        let offlineError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        model.apply(.failure(offlineError))

        #expect(model.phase == .offline)
    }

    @Test @MainActor func `Retry transitions to loading and restarts polling`() throws {
        let stop = makeStop()
        let service = RESTAPIService.standalone(
            region: Fixtures.pugetSoundRegion,
            apiKey: "key",
            appVersion: "1.0",
            uuid: "uuid"
        )
        let model = StopArrivalsModel(stop: stop, apiService: service)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))
        #expect(model.phase != .loading)

        model.retry()
        defer { model.stopPolling() }

        #expect(model.phase == .loading)
    }

    @Test @MainActor func `Retry without API service ends in failed`() throws {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))
        #expect(model.phase != .loading)

        model.retry()

        if case .failed(let message) = model.phase {
            #expect(message == Strings.noTransitRegion)
        } else {
            Issue.record("Expected failed after retry with nil apiService")
        }
    }
}

// MARK: - End-to-end wiring tests (issue #1917)

/// Exercises the model→poller→coordinator path through the model's public
/// API, with a mocked service and a TestClock. The poller tests cannot reach
/// this wiring: they drive the poller (and the coordinator) directly.
@Suite(.serialized)
final class StopArrivalsModelWiringTests: OBATestCase {

    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"

    /// Thread-safe request counter; matchers run off-main.
    private nonisolated final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests = 0
        private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        var requests: Int { lock.withLock { _requests } }

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
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { [arrivalsPath] request in
            guard request.url?.path.contains(arrivalsPath) == true else { return false }
            gate.record()
            return true
        }
    }

    private func makeModel(dataLoader: MockDataLoader, clock: TestClock, poller: StopArrivalsPoller = StopArrivalsPoller()) -> StopArrivalsModel {
        let service = buildRESTService(dataLoader: dataLoader)
        return StopArrivalsModel(
            stop: Stop(
                id: "1_75414",
                name: "3rd & Pike",
                direction: "S",
                location: CLLocation(latitude: 47.6097, longitude: -122.3378)
            ),
            apiService: service,
            interval: .seconds(30),
            poller: poller,
            clock: clock
        )
    }

    /// Waits until the model has applied a fetch and reached `.empty`. The
    /// request gate fires when the request is issued, before the response
    /// reaches the model, so asserting the phase right after `waitForRequests`
    /// can read `.loading` and fail a correct wiring. Polls with a bound so a
    /// missing response still fails the test instead of hanging it.
    /// Note: every arrival in the fixture is in the past, so the model is
    /// already `.empty` once the first fetch lands — in these tests this
    /// mainly confirms a fetch was applied, and the request count is the
    /// real assertion.
    private func waitForEmptyPhase(_ model: StopArrivalsModel) async throws {
        for _ in 0..<400 {
            if case .empty = model.phase {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected empty phase, got \(model.phase)")
    }

    @Test(.timeLimit(.minutes(1))) func `setScenePhase background pauses polling and active resumes with an immediate fetch`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let clock = TestClock()
        let model = makeModel(dataLoader: dataLoader, clock: clock)
        defer { model.stopPolling() }

        // 1. First fetch on start.
        model.startPolling()
        await gate.waitForRequests(count: 1)
        try await waitForEmptyPhase(model)
        await clock.waitForSleepers(count: 1)

        // 2. Background: the poller leaves its sleep and parks in
        // waitUntilActive. Advancing the clock while backgrounded must
        // not fetch.
        model.setScenePhase(.background)
        await clock.waitForSleepers(count: 0)
        clock.advance(by: .seconds(90))
        #expect(gate.requests == 1)

        // 3. Foreground: immediate fetch, no timer wait.
        model.setScenePhase(.active)
        await gate.waitForRequests(count: 2)
        try await waitForEmptyPhase(model)
    }

    @Test(.timeLimit(.minutes(1))) func `triggerRefresh triggers an immediate fetch without waiting for the timer`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let clock = TestClock()
        let model = makeModel(dataLoader: dataLoader, clock: clock)
        defer { model.stopPolling() }

        model.startPolling()
        await gate.waitForRequests(count: 1)
        await clock.waitForSleepers(count: 1)

        // No clock advance: the refresh alone must fetch. This exercises
        // the model's refresh stream through the poller to the coordinator —
        // the poller test calls coordinator.triggerRefresh() directly, so
        // this path was untested.
        model.triggerRefresh()
        await gate.waitForRequests(count: 2)
        try await waitForEmptyPhase(model)
    }

    @Test(.timeLimit(.minutes(1))) func `retry while polling refreshes in place without waiting for the timer`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let clock = TestClock()
        let model = makeModel(dataLoader: dataLoader, clock: clock)
        defer { model.stopPolling() }

        model.startPolling()
        await gate.waitForRequests(count: 1)
        await clock.waitForSleepers(count: 1)

        // retry() while polling refreshes in place: a prompt re-fetch with
        // no clock advance and no poll restart.
        model.retry()
        await gate.waitForRequests(count: 2)
        try await waitForEmptyPhase(model)
    }

    @Test(.timeLimit(.minutes(1))) func `startPolling while backgrounded begins paused and fetches on foregrounding`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let clock = TestClock()
        // Observe the coordinator the poller itself creates from the model's
        // remembered phase, so the test can wait for the poller to reach its
        // background wait instead of guessing with a fixed sleep: if the
        // poller had not started yet, "no request, no sleeper" would pass
        // vacuously. The coordinator must come from the poller, not the test:
        // a test-built coordinator would bypass the `initialScenePhase`
        // seeding this test exists to cover.
        let (coordinatorStream, coordinatorContinuation) = AsyncStream<PollerCoordinator>.makeStream(bufferingPolicy: .bufferingNewest(1))
        var poller = StopArrivalsPoller()
        poller.onCoordinatorCreated = { coordinator in coordinatorContinuation.yield(coordinator) }
        let model = makeModel(dataLoader: dataLoader, clock: clock, poller: poller)
        defer { model.stopPolling() }

        // Remember the phase before polling starts: the poll must replay
        // it and begin paused instead of fetching once while backgrounded.
        model.setScenePhase(.background)

        model.startPolling()

        // The coordinator the poller actually created, from the model's
        // remembered phase.
        var coordinatorIterator = coordinatorStream.makeAsyncIterator()
        guard let coordinator = await coordinatorIterator.next() else {
            Issue.record("Expected the poller to create a coordinator")
            return
        }

        // The seeding itself: the coordinator must have been created
        // backgrounded. This is what fails if startPolling() stops passing
        // the remembered phase — the wait below alone cannot prove it,
        // because the replayed phase could park the coordinator first.
        #expect(await coordinator.initialForeground == false)

        // The poller has reached its background wait: it started, and it is
        // parked instead of fetching. If the replay were missing it would
        // have fetched immediately and parked in a clock sleep instead —
        // neither must have happened.
        await coordinator.waitForWaiters(count: 1)
        #expect(gate.requests == 0)
        #expect(await clock.sleeperCount == 0)

        model.setScenePhase(.active)
        await gate.waitForRequests(count: 1)
        try await waitForEmptyPhase(model)
    }

    @Test(.timeLimit(.minutes(1))) func `restarting polling creates fresh streams so triggerRefresh still works`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let clock = TestClock()
        let model = makeModel(dataLoader: dataLoader, clock: clock)
        defer { model.stopPolling() }

        // 1. First poll: initial fetch, then settle into sleep.
        model.startPolling()
        await gate.waitForRequests(count: 1)
        await clock.waitForSleepers(count: 1)

        // 2. Stop, then start again: a fresh poll with fresh streams.
        model.stopPolling()
        await clock.waitForSleepers(count: 0)

        model.startPolling()
        await gate.waitForRequests(count: 2)
        await clock.waitForSleepers(count: 1)

        // 3. A refresh on the restarted poll must be delivered: the
        // streams are fresh, not the cancelled ones from the first poll.
        model.triggerRefresh()
        await gate.waitForRequests(count: 3)
        try await waitForEmptyPhase(model)
    }
}
