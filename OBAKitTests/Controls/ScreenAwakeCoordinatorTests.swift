//
//  ScreenAwakeCoordinatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
@testable import OBAKit

/// The lease arithmetic behind `keepsScreenAwake()` and `Idleable`.
///
/// The per-view latch this replaced could not survive two live screens: the
/// second screen to appear saw the timer already disabled, declined to latch,
/// and the first screen to disappear then re-enabled the timer underneath it.
///
/// `ScreenAwakeCoordinator` is a singleton over a process-global
/// (`UIApplication.isIdleTimerDisabled`), so every test starts by resetting it.
/// Owners are held in local `NSObject`s for the duration of each test:
/// `ObjectIdentifier` is only an address, and a temporary's address is free for
/// the next allocation to reuse, which would make one screen's lease look like
/// another's.
@MainActor
@Suite(.serialized)
struct ScreenAwakeCoordinatorTests {

    private func reset(failsafeInterval: TimeInterval = ScreenAwakeCoordinator.defaultFailsafeInterval) {
        ScreenAwakeCoordinator.shared.resetForTesting(failsafeInterval: failsafeInterval)
    }

    /// How long the failsafe tests let a millisecond-scale timer run before
    /// giving up. Generous relative to the intervals they set, so a loaded CI
    /// machine cannot fail them, and still far short of a hang.
    private static let expiryTimeout: Duration = .seconds(2)

    /// Polls `condition` until it holds or the deadline passes, reporting which.
    ///
    /// The failsafe fires from a real `Timer` on the main run loop, so a test
    /// waiting on it has to suspend rather than block — blocking the main actor
    /// would stop the very run loop the timer needs.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + Self.expiryTimeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func `One lease disables the timer and returning it restores`() {
        reset()
        let screen = NSObject()

        ScreenAwakeCoordinator.shared.acquire(owner: ObjectIdentifier(screen))
        #expect(UIApplication.shared.isIdleTimerDisabled)

        ScreenAwakeCoordinator.shared.release(owner: ObjectIdentifier(screen))
        #expect(!UIApplication.shared.isIdleTimerDisabled)

        reset()
    }

    /// The regression the lease count exists for: a second screen appears before
    /// the first goes away, and the first's departure must not put the display
    /// back to sleep under the second.
    @Test func `An overlapping screen keeps the timer off when the first leaves`() {
        reset()
        let tripScreen = NSObject()
        let sheetScreen = NSObject()

        // CurrentTripView appears.
        ScreenAwakeCoordinator.shared.acquire(owner: ObjectIdentifier(tripScreen))
        // The stop sheet appears on top of it — SwiftUI runs the incoming
        // onAppear before the outgoing onDisappear.
        ScreenAwakeCoordinator.shared.acquire(owner: ObjectIdentifier(sheetScreen))
        // CurrentTripView goes away.
        ScreenAwakeCoordinator.shared.release(owner: ObjectIdentifier(tripScreen))

        #expect(UIApplication.shared.isIdleTimerDisabled)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)

        // Only when the last screen leaves does the timer come back.
        ScreenAwakeCoordinator.shared.release(owner: ObjectIdentifier(sheetScreen))
        #expect(!UIApplication.shared.isIdleTimerDisabled)

        reset()
    }

    /// A hold placed by something outside the coordinator entirely must survive
    /// our leases coming and going.
    @Test func `Releasing the last lease restores a pre-existing hold`() {
        reset()
        UIApplication.shared.isIdleTimerDisabled = true
        let screen = NSObject()

        ScreenAwakeCoordinator.shared.acquire(owner: ObjectIdentifier(screen))
        ScreenAwakeCoordinator.shared.release(owner: ObjectIdentifier(screen))

        #expect(UIApplication.shared.isIdleTimerDisabled)

        reset()
    }

    // MARK: - Failsafe
    //
    // Without it an abandoned screen holds the display awake until the battery
    // runs down. The interval is an instance property so these can drive a real
    // expiry in milliseconds; asserting the 600 alone restates the declaration
    // and would keep passing with `armFailsafe()` deleted outright.

    @Test func `The shipped coordinator caps a hold at ten minutes`() {
        reset()
        #expect(ScreenAwakeCoordinator.defaultFailsafeInterval == 600)
        // Also that a test's short interval is not left behind on the singleton.
        #expect(ScreenAwakeCoordinator.shared.failsafeInterval == 600)
    }

    @Test func `Taking a lease arms the failsafe and returning the last one cancels it`() {
        reset()
        let screen = NSObject()
        let owner = ObjectIdentifier(screen)

        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.armedFailsafe?.isValid == true)

        ScreenAwakeCoordinator.shared.release(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.armedFailsafe == nil)

        reset()
    }

    /// The failsafe is re-armed on every acquire. Two live screens must leave
    /// one timer running, not two racing to expire.
    @Test func `Arming replaces the previous failsafe rather than stacking`() {
        reset()
        let first = NSObject()
        let second = NSObject()

        ScreenAwakeCoordinator.shared.acquire(owner: ObjectIdentifier(first))
        let firstTimer = ScreenAwakeCoordinator.shared.armedFailsafe

        ScreenAwakeCoordinator.shared.acquire(owner: ObjectIdentifier(second))
        let secondTimer = ScreenAwakeCoordinator.shared.armedFailsafe

        #expect(secondTimer !== firstTimer)
        #expect(firstTimer?.isValid == false)
        #expect(secondTimer?.isValid == true)

        reset()
    }

    /// The behaviour the cap exists for: a lease nobody returns must not hold
    /// the display awake forever.
    @Test func `An expired failsafe lets the display sleep under an outstanding lease`() async {
        reset(failsafeInterval: 0.1)
        let screen = NSObject()
        let owner = ObjectIdentifier(screen)

        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        #expect(UIApplication.shared.isIdleTimerDisabled)

        let slept = await waitUntil { !UIApplication.shared.isIdleTimerDisabled }
        #expect(slept)
        // The lease is deliberately left counted: it is still real, so the
        // eventual release has to stay balanced rather than read as unbalanced.
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)
        #expect(ScreenAwakeCoordinator.shared.armedFailsafe == nil)

        ScreenAwakeCoordinator.shared.release(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 0)

        reset()
    }

    /// Expiry caps the hold; it does not put the coordinator out of service.
    @Test func `A lease taken after expiry disables the timer and re-arms`() async {
        reset(failsafeInterval: 0.1)
        let abandoned = NSObject()
        let arriving = NSObject()

        ScreenAwakeCoordinator.shared.acquire(owner: ObjectIdentifier(abandoned))
        let slept = await waitUntil { !UIApplication.shared.isIdleTimerDisabled }
        #expect(slept)

        // A new screen appears while the leaked lease is still counted.
        ScreenAwakeCoordinator.shared.acquire(owner: ObjectIdentifier(arriving))
        #expect(UIApplication.shared.isIdleTimerDisabled)
        #expect(ScreenAwakeCoordinator.shared.armedFailsafe?.isValid == true)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 2)

        reset()
    }

    /// `expireFailsafe`'s `leaseCount > 0` guard. Releasing the last lease
    /// already cancels the timer, so this is only reachable directly — but
    /// without the guard it would write `stateBeforeFirstLease` over a hold the
    /// coordinator does not own.
    @Test func `Firing the failsafe with no leases leaves an outside hold alone`() {
        reset()
        // Something outside the coordinator is holding the timer off.
        UIApplication.shared.isIdleTimerDisabled = true

        ScreenAwakeCoordinator.shared.expireFailsafeForTesting()

        #expect(UIApplication.shared.isIdleTimerDisabled)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 0)

        reset()
    }

    // MARK: - Idempotence

    /// UIKit does not guarantee `viewWillAppear`/`viewWillDisappear` alternate
    /// strictly, and `Idleable` calls straight through from both. A second
    /// appear without an intervening disappear must not leak a lease.
    @Test func `A repeated acquire for one owner takes a single lease`() {
        reset()
        let screen = NSObject()
        let owner = ObjectIdentifier(screen)

        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)

        ScreenAwakeCoordinator.shared.release(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 0)
        #expect(!UIApplication.shared.isIdleTimerDisabled)

        reset()
    }

    @Test func `Releasing an owner that holds no lease is a no-op`() {
        reset()
        let holderScreen = NSObject()
        let strangerScreen = NSObject()
        let holder = ObjectIdentifier(holderScreen)
        let stranger = ObjectIdentifier(strangerScreen)

        ScreenAwakeCoordinator.shared.acquire(owner: holder)
        ScreenAwakeCoordinator.shared.release(owner: stranger)

        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)
        #expect(UIApplication.shared.isIdleTimerDisabled)

        ScreenAwakeCoordinator.shared.release(owner: holder)
        reset()
    }

    /// A repeated release must not drive the count negative and strand the timer
    /// disabled for the rest of the session.
    @Test func `A repeated release is ignored`() {
        reset()
        let screen = NSObject()
        let owner = ObjectIdentifier(screen)

        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        ScreenAwakeCoordinator.shared.release(owner: owner)
        ScreenAwakeCoordinator.shared.release(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 0)

        // The next screen still gets a working hold.
        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)
        #expect(UIApplication.shared.isIdleTimerDisabled)

        reset()
    }

    // MARK: - Across the UIKit/SwiftUI boundary

    /// The cross-boundary regression: a pushed `Idleable` screen opened over a
    /// SwiftUI screen that holds a lease used to write `isIdleTimerDisabled =
    /// false` on its way out, letting the display sleep while the SwiftUI screen
    /// was still showing live departures.
    @Test func `An Idleable screen leaving keeps a SwiftUI screen's hold`() {
        reset()
        let sheet = NSObject()
        let screen = NSObject()
        let sheetOwner = ObjectIdentifier(sheet)
        let pushedScreen = ObjectIdentifier(screen)

        // The stop sheet appears.
        ScreenAwakeCoordinator.shared.acquire(owner: sheetOwner)
        // "View Full Trip" pushes an Idleable trip screen on top of it.
        ScreenAwakeCoordinator.shared.acquire(owner: pushedScreen)
        // The rider pops back to the sheet.
        ScreenAwakeCoordinator.shared.release(owner: pushedScreen)

        #expect(UIApplication.shared.isIdleTimerDisabled)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)

        ScreenAwakeCoordinator.shared.release(owner: sheetOwner)
        #expect(!UIApplication.shared.isIdleTimerDisabled)

        reset()
    }

    /// The reverse ordering, which was worse: the sheet's lease recorded a
    /// pre-existing hold of `true`, the pushed screen then switched the global
    /// off directly, and the sheet's final release restored `true` — leaving the
    /// timer disabled with nothing holding it and no failsafe armed.
    @Test func `A pushed screen popped under a sheet does not strand the timer`() {
        reset()
        let sheet = NSObject()
        let screen = NSObject()
        let sheetOwner = ObjectIdentifier(sheet)
        let pushedScreen = ObjectIdentifier(screen)

        // The pushed Idleable Stop page appears.
        ScreenAwakeCoordinator.shared.acquire(owner: pushedScreen)
        // The SwiftUI sheet opens over it.
        ScreenAwakeCoordinator.shared.acquire(owner: sheetOwner)
        // The pushed page is popped.
        ScreenAwakeCoordinator.shared.release(owner: pushedScreen)
        // Then the sheet closes.
        ScreenAwakeCoordinator.shared.release(owner: sheetOwner)

        #expect(!UIApplication.shared.isIdleTimerDisabled)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 0)

        reset()
    }

    /// `resetForTesting` has to clear `owners` as well as the count, or a stale
    /// `ObjectIdentifier` surviving a failed test makes the next test's
    /// `acquire` look like a repeat and silently take no lease at all.
    @Test func `Resetting forgets owners as well as the count`() {
        reset()
        let screen = NSObject()
        let owner = ObjectIdentifier(screen)

        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        reset()
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 0)

        // The same identity must be able to take a fresh lease.
        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)
        #expect(UIApplication.shared.isIdleTimerDisabled)

        reset()
    }
}
