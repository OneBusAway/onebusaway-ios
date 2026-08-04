//
//  KeepsScreenAwake.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// Arbitrates the idle timer between every SwiftUI screen that wants it held
/// off — the SwiftUI counterpart of `Idleable`, including its failsafe.
///
/// A shared lease count rather than a per-view latch. A per-view latch cannot
/// survive two live screens overlapping: SwiftUI routinely runs the incoming
/// view's `onAppear` before the outgoing view's `onDisappear`, so the incoming
/// screen sees the timer already disabled, declines to latch, and the outgoing
/// screen then re-enables the timer out from under it. Counting leases instead
/// means the timer is restored exactly once, when the last screen goes away.
@MainActor
final class ScreenAwakeCoordinator {
    static let shared = ScreenAwakeCoordinator()

    /// Matches `Idleable`'s interval. The idle timer is a global the app can
    /// only leave switched off by mistake, so both implementations cap how long
    /// a mistake can last.
    static let failsafeInterval: TimeInterval = 600

    private var leaseCount = 0
    /// What the idle timer was before we first touched it, so releasing the
    /// last lease cannot switch off a hold some other subsystem placed.
    private var stateBeforeFirstLease = false
    private var failsafe: Timer?

    private init() {}

    /// Test seam: the lease count, so the pairing can be asserted without
    /// driving a real view hierarchy.
    var activeLeases: Int { leaseCount }

    func acquire() {
        if leaseCount == 0 {
            stateBeforeFirstLease = UIApplication.shared.isIdleTimerDisabled
        }
        leaseCount += 1
        UIApplication.shared.isIdleTimerDisabled = true
        // Re-armed on every acquire, as `Idleable.disableIdleTimer()` does: the
        // failsafe guards against a lease that is never released, not against a
        // screen legitimately staying up.
        armFailsafe()
    }

    func release() {
        // A release without a matching acquire would drive the count negative
        // and strand the timer disabled for the rest of the session.
        guard leaseCount > 0 else {
            Logger.warn("ScreenAwakeCoordinator: unbalanced release ignored.")
            return
        }

        leaseCount -= 1
        guard leaseCount == 0 else { return }

        UIApplication.shared.isIdleTimerDisabled = stateBeforeFirstLease
        cancelFailsafe()
    }

    private func armFailsafe() {
        cancelFailsafe()
        failsafe = Timer.scheduledTimer(withTimeInterval: Self.failsafeInterval, repeats: false) { _ in
            Task { @MainActor in
                Self.shared.expireFailsafe()
            }
        }
    }

    private func cancelFailsafe() {
        failsafe?.invalidate()
        failsafe = nil
    }

    /// Lets the screen sleep again while leases are still outstanding. The
    /// count is deliberately left alone: the leases are still real, so the
    /// eventual releases stay balanced and the last one restores the original
    /// state (which this has already reached).
    private func expireFailsafe() {
        cancelFailsafe()
        guard leaseCount > 0 else { return }
        Logger.info("ScreenAwakeCoordinator: failsafe expired after \(Int(Self.failsafeInterval))s; letting the screen sleep.")
        UIApplication.shared.isIdleTimerDisabled = stateBeforeFirstLease
    }
}

/// Holds the idle timer off while a live, self-refreshing screen is visible.
///
/// The lease is taken on appear and returned on disappear, and `holdsLease`
/// keeps that pairing exact — SwiftUI can run `onAppear` more than once for one
/// logical appearance, and a double acquire would never be released.
private struct KeepsScreenAwakeModifier: ViewModifier {
    @State private var holdsLease = false

    func body(content: Content) -> some View {
        content
            .onAppear(perform: acquire)
            .onDisappear(perform: release)
    }

    private func acquire() {
        guard !holdsLease else { return }
        holdsLease = true
        ScreenAwakeCoordinator.shared.acquire()
    }

    private func release() {
        guard holdsLease else { return }
        holdsLease = false
        ScreenAwakeCoordinator.shared.release()
    }
}

extension View {
    /// Keeps the display awake while this view is on screen, yielding to any
    /// other screen that wants the same thing and capping the hold at
    /// `ScreenAwakeCoordinator.failsafeInterval`.
    func keepsScreenAwake() -> some View {
        modifier(KeepsScreenAwakeModifier())
    }
}
