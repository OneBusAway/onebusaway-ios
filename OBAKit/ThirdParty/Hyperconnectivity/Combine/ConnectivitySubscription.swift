//
//  Subscription.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Combine
import Foundation
import os

/// Demand is not metered: once any is requested, every result is delivered.
///
/// OBA: `cancel()` arrives on the subscriber's thread and results on
/// `Hyperconnectivity`'s queue, so the subscriber sits behind a lock. Upstream
/// read and cleared it unguarded.
nonisolated final class ConnectivitySubscription<S: Subscriber>: Subscription, @unchecked Sendable
where S.Input == ConnectivityResult, S.Failure == Never {

    private struct State {
        var subscriber: S?
        var isStarted = false
    }

    private let connectivity: Hyperconnectivity
    private let state: OSAllocatedUnfairLock<State>

    init(configuration: Hyperconnectivity.Configuration, subscriber: S) {
        self.connectivity = Hyperconnectivity(configuration: configuration)
        self.state = OSAllocatedUnfairLock(uncheckedState: State(subscriber: subscriber))
    }

    // OBA: monitoring starts on the first demand rather than in `init`, so no value
    // can reach the subscriber before it has received the subscription.
    func request(_ demand: Subscribers.Demand) {
        guard demand > .none else { return }

        let shouldStart = state.withLockUnchecked { state in
            guard state.subscriber != nil, !state.isStarted else { return false }
            state.isStarted = true
            return true
        }
        guard shouldStart else { return }

        connectivity.startNotifier { [weak self] result in
            self?.deliver(result)
        }
    }

    // OBA: upstream sent `.finished` to the subscriber here; a cancelled
    // subscription must not send anything further.
    func cancel() {
        state.withLockUnchecked { $0.subscriber = nil }
        connectivity.stopNotifier()
    }

    private func deliver(_ result: ConnectivityResult) {
        // Called outside the lock so a subscriber that cancels from `receive` can't deadlock.
        guard let subscriber = state.withLockUnchecked({ $0.subscriber }) else { return }
        _ = subscriber.receive(result)
    }
}
