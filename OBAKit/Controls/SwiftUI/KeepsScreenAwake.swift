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
///
/// There is one way in, `acquire(owner:)`/`release(owner:)`. The bare counter
/// underneath is private so `leaseCount` and `owners` cannot drift apart.
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
    /// Everything currently holding a lease, keyed by identity. This is what
    /// makes `acquire`/`release` idempotent, which a bare count cannot be: a
    /// screen that sees `viewWillAppear` twice without an intervening
    /// `viewWillDisappear` would otherwise leak a lease and strand the timer
    /// disabled for the rest of the session.
    private var owners: Set<ObjectIdentifier> = []

    private init() {}

    /// Test seam: the lease count, so the pairing can be asserted without
    /// driving a real view hierarchy.
    var activeLeases: Int { leaseCount }

    /// Test seam: drops every lease and forgets every owner.
    ///
    /// Both halves matter. Releasing until `leaseCount` reaches zero leaves
    /// `owners` populated, and `ObjectIdentifier` is only an address — the next
    /// test's owner object can land on a freed one and have its `acquire` seen
    /// as a repeat and silently dropped. The singleton outlives each test, so a
    /// test that fails partway through has to leave nothing behind.
    func resetForTesting() {
        owners.removeAll()
        leaseCount = 0
        cancelFailsafe()
        stateBeforeFirstLease = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Takes a lease on behalf of `owner`, at most one at a time.
    ///
    /// Every caller supplies an owner: `Idleable`'s appear/disappear callbacks
    /// are not guaranteed by UIKit to alternate strictly, and SwiftUI can run
    /// `onAppear` more than once for one logical appearance. Keying the lease
    /// makes both idempotent, which a bare counter cannot be — a repeat acquire
    /// would leak a lease and strand the timer disabled for the session.
    func acquire(owner: ObjectIdentifier) {
        guard owners.insert(owner).inserted else { return }
        acquireLease()
    }

    /// Returns `owner`'s lease, if it holds one. A release without a matching
    /// acquire is a no-op rather than an unbalanced decrement.
    func release(owner: ObjectIdentifier) {
        guard owners.remove(owner) != nil else { return }
        releaseLease()
    }

    /// Private so `owners` cannot fall out of step with `leaseCount`: the keyed
    /// pair above is the only way in.
    private func acquireLease() {
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

    private func releaseLease() {
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
        // Error, not info: reaching here means a lease was never returned, which
        // is a bug by definition — and one whose only symptom, the display
        // sleeping mid-trip, is otherwise invisible in production diagnostics.
        Logger.error("ScreenAwakeCoordinator: failsafe expired after \(Int(Self.failsafeInterval))s with \(leaseCount) lease(s) outstanding; letting the screen sleep.")
        UIApplication.shared.isIdleTimerDisabled = stateBeforeFirstLease
    }
}

/// Identifies one mounted `keepsScreenAwake()` to the coordinator.
///
/// A class purely so it has an address: `ScreenAwakeCoordinator` keys leases by
/// `ObjectIdentifier`, and `@State` gives this instance the lifetime of the
/// view, which is exactly the lifetime of the lease.
private final class ScreenAwakeLeaseToken {}

/// Holds the idle timer off while a live, self-refreshing screen is visible.
///
/// The lease is taken on appear and returned on disappear. The pairing does not
/// need a local latch: the lease is keyed on `token`, so the coordinator makes
/// a repeat acquire a no-op — which matters because SwiftUI can run `onAppear`
/// more than once for one logical appearance.
///
/// The hold is also dropped for the duration of a backgrounding and re-taken on
/// the `.background → .active` edge. Neither `onAppear` nor `onDisappear` fires
/// when the app backgrounds with the screen still mounted, so without this a
/// rider who pockets the phone for longer than `failsafeInterval` comes back to
/// a screen whose failsafe has already expired and which nothing will ever
/// re-arm — the display sleeps mid-trip for the rest of that screen's life.
private struct KeepsScreenAwakeModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var token = ScreenAwakeLeaseToken()

    private var owner: ObjectIdentifier { ObjectIdentifier(token) }

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
        ScreenAwakeCoordinator.shared.acquire(owner: owner)
    }

    private func release() {
        ScreenAwakeCoordinator.shared.release(owner: owner)
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
