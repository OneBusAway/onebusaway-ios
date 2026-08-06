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

/// Arbitrates the idle timer between every screen that wants it held off.
///
/// A shared lease count rather than a per-view latch. A per-view latch cannot
/// survive two live screens overlapping: SwiftUI routinely runs the incoming
/// view's `onAppear` before the outgoing view's `onDisappear`, so the incoming
/// screen sees the timer already disabled, declines to latch, and the outgoing
/// screen then re-enables the timer out from under it. Counting leases instead
/// means the timer is restored exactly once, when the last screen goes away.
///
/// `Idleable` routes through here too, rather than writing
/// `isIdleTimerDisabled` itself. Two arbiters over one global cannot stay
/// consistent across the UIKit/SwiftUI boundary: a pushed `Idleable` screen
/// dismissed over a SwiftUI screen holding a lease used to switch the timer
/// straight back on, and the reverse ordering left it disabled with nothing
/// holding it and no failsafe armed.
@MainActor
final class ScreenAwakeCoordinator {
    static let shared = ScreenAwakeCoordinator()

    /// The idle timer is a global the app can only leave switched off by
    /// mistake, so cap how long a mistake can last.
    static let failsafeInterval: TimeInterval = 600

    private var leaseCount = 0
    /// What the idle timer was before we first touched it, so releasing the
    /// last lease cannot switch off a hold some other subsystem placed.
    private var stateBeforeFirstLease = false
    private var failsafe: Timer?
    /// Owners currently holding an owner-keyed lease. Lets
    /// `acquire(owner:)`/`release(owner:)` be idempotent, which the raw
    /// counting API cannot be: a view controller that sees `viewWillAppear`
    /// twice without an intervening `viewWillDisappear` would otherwise leak a
    /// lease and strand the timer disabled for the rest of the session.
    private var owners: Set<ObjectIdentifier> = []

    private init() {}

    /// Test seam: the lease count, so the pairing can be asserted without
    /// driving a real view hierarchy.
    var activeLeases: Int { leaseCount }

    /// Takes a lease on behalf of `owner`, at most one at a time. Used by
    /// `Idleable`, whose appear/disappear callbacks UIKit does not guarantee to
    /// deliver in strict alternation.
    func acquire(owner: ObjectIdentifier) {
        guard owners.insert(owner).inserted else { return }
        acquire()
    }

    /// Returns `owner`'s lease, if it holds one. A release without a matching
    /// acquire is a no-op rather than an unbalanced decrement.
    func release(owner: ObjectIdentifier) {
        guard owners.remove(owner) != nil else { return }
        release()
    }

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
///
/// The hold is also dropped for the duration of a backgrounding and re-taken on
/// the `.background → .active` edge. Neither `onAppear` nor `onDisappear` fires
/// when the app backgrounds with the screen still mounted, so without this a
/// rider who pockets the phone for longer than `failsafeInterval` comes back to
/// a screen whose failsafe has already expired and which nothing will ever
/// re-arm — the display sleeps mid-trip for the rest of that screen's life.
private struct KeepsScreenAwakeModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var holdsLease = false

    func body(content: Content) -> some View {
        content
            .onAppear(perform: acquire)
            .onDisappear(perform: release)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    acquire()
                case .background:
                    release()
                case .inactive:
                    // Control Center, a banner, the app switcher: the screen is
                    // still the rider's, so the hold stays.
                    break
                @unknown default:
                    break
                }
            }
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
