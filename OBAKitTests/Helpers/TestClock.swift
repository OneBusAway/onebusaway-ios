//
//  TestClock.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A `Clock` that only moves when a test calls `advance(by:)` or `advance(bySeconds:)`.
///
/// `sleep(until:)` parks the caller until the clock reaches the deadline;
/// cancellation throws `CancellationError` and unparks only the cancelled
/// caller. Tests wait for `sleeperCount` to reach the expected value before
/// advancing, so the sleeper is registered before the clock moves.
nonisolated final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol, Sendable {
        var offset: Duration

        init(offset: Duration = .zero) {
            self.offset = offset
        }

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    typealias Duration = Swift.Duration

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct Waiter {
        let id: UUID
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var currentInstant = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var waiters: [Waiter] = []

    init() {}

    var now: Instant {
        lock.withLock { currentInstant }
    }

    var minimumResolution: Duration { .zero }

    /// How many callers are parked in `sleep`.
    var sleeperCount: Int {
        lock.withLock { sleepers.count }
    }

    private func matchingWaiters() -> [CheckedContinuation<Void, Never>] {
        let count = sleepers.count
        var matched: [CheckedContinuation<Void, Never>] = []
        waiters.removeAll { waiter in
            if waiter.count == count {
                matched.append(waiter.continuation)
                return true
            }
            return false
        }
        return matched
    }

    /// Suspends until `sleeperCount` reaches `target`. Completes immediately if already at `target`.
    /// Cancellation-aware: if the waiting test is cancelled (e.g. by a `@Test`
    /// time limit), the wait returns instead of suspending forever in the
    /// checked continuation — otherwise the test body (and its deferred
    /// cleanup) would never run and the test run would hang.
    func waitForSleepers(count target: Int) async {
        if Task.isCancelled { return }
        let matched = lock.withLock { sleepers.count == target }
        if matched { return }

        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let shouldResumeImmediately = lock.withLock { () -> Bool in
                    // Checked under the same lock as registration: a cancel
                    // landing between the entry check and this point must
                    // not leave a waiter nobody resumes.
                    if Task.isCancelled || sleepers.count == target {
                        return true
                    }
                    waiters.append(Waiter(id: waiterID, count: target, continuation: continuation))
                    return false
                }
                if shouldResumeImmediately {
                    continuation.resume()
                }
            }
        } onCancel: {
            // Removal under the lock is the handoff: matchingWaiters()
            // removes due waiters the same way, so the continuation is
            // resumed exactly once, by whichever side claims it first.
            let toResume = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return nil }
                return waiters.remove(at: index).continuation
            }
            toResume?.resume()
        }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()

        // Cancellation is checked under the lock, not before it: a cancel that
        // lands before the sleeper is registered finds nothing for `onCancel` to
        // remove, so registering anyway would park the caller until the next
        // `advance(by:)`. An already-cancelled caller runs `onCancel` first (a
        // no-op) and is turned away here.
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                enum Outcome { case due, cancelled, parked }
                let (outcome, waitersToResume) = lock.withLock { () -> (Outcome, [CheckedContinuation<Void, Never>]) in
                    if Task.isCancelled {
                        return (.cancelled, [])
                    }
                    if deadline <= currentInstant {
                        return (.due, [])
                    }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return (.parked, matchingWaiters())
                }
                switch outcome {
                case .due: continuation.resume()
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .parked:
                    for waiter in waitersToResume {
                        waiter.resume()
                    }
                }
            }
        } onCancel: {
            let (cancelled, waitersToResume) = lock.withLock { () -> (Sleeper?, [CheckedContinuation<Void, Never>]) in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return (nil, []) }
                let removed = sleepers.remove(at: index)
                return (removed, matchingWaiters())
            }
            for waiter in waitersToResume {
                waiter.resume()
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the clock forward and wakes every sleeper whose deadline has passed.
    func advance(by duration: Duration) {
        let (due, waitersToResume) = lock.withLock { () -> ([Sleeper], [CheckedContinuation<Void, Never>]) in
            currentInstant = currentInstant.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= currentInstant }
            sleepers.removeAll { $0.deadline <= currentInstant }
            return (due, matchingWaiters())
        }
        for waiter in waitersToResume {
            waiter.resume()
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    /// Moves the clock forward by seconds.
    func advance(bySeconds seconds: Double) {
        advance(by: .seconds(seconds))
    }
}
