//
//  TestClock.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A `Clock` that only moves when a test calls `advance(by:)`.
///
/// `sleep(until:)` parks the caller until the clock reaches the deadline;
/// cancellation throws `CancellationError` and unparks only the cancelled
/// caller. Tests wait for `sleeperCount` to reach the expected value before
/// advancing, so the sleeper is registered before the clock moves.
final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

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

    private let lock = NSLock()
    private var currentInstant = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []

    var now: Instant {
        lock.withLock { currentInstant }
    }

    var minimumResolution: Duration { .zero }

    /// How many callers are parked in `sleep`.
    var sleeperCount: Int {
        lock.withLock { sleepers.count }
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
                let outcome = lock.withLock { () -> Outcome in
                    if Task.isCancelled {
                        return .cancelled
                    }
                    if deadline <= currentInstant {
                        return .due
                    }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .parked
                }
                switch outcome {
                case .due: continuation.resume()
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .parked: break
                }
            }
        } onCancel: {
            let cancelled = lock.withLock { () -> Sleeper? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the clock forward and wakes every sleeper whose deadline has passed.
    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [Sleeper] in
            currentInstant = currentInstant.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= currentInstant }
            sleepers.removeAll { $0.deadline <= currentInstant }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }
}
