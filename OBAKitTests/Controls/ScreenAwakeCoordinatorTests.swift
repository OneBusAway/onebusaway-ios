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
/// (`UIApplication.isIdleTimerDisabled`), so this suite restores the idle timer
/// itself and drains any leases it takes.
@MainActor
@Suite(.serialized)
struct ScreenAwakeCoordinatorTests {

    private func drain() {
        while ScreenAwakeCoordinator.shared.activeLeases > 0 {
            ScreenAwakeCoordinator.shared.release()
        }
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @Test func `One lease disables the timer and returning it restores`() {
        drain()

        ScreenAwakeCoordinator.shared.acquire()
        #expect(UIApplication.shared.isIdleTimerDisabled)

        ScreenAwakeCoordinator.shared.release()
        #expect(!UIApplication.shared.isIdleTimerDisabled)

        drain()
    }

    /// The regression the lease count exists for: a second screen appears before
    /// the first goes away, and the first's departure must not put the display
    /// back to sleep under the second.
    @Test func `An overlapping screen keeps the timer off when the first leaves`() {
        drain()

        // CurrentTripView appears.
        ScreenAwakeCoordinator.shared.acquire()
        // The stop sheet appears on top of it — SwiftUI runs the incoming
        // onAppear before the outgoing onDisappear.
        ScreenAwakeCoordinator.shared.acquire()
        // CurrentTripView goes away.
        ScreenAwakeCoordinator.shared.release()

        #expect(UIApplication.shared.isIdleTimerDisabled)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)

        // Only when the last screen leaves does the timer come back.
        ScreenAwakeCoordinator.shared.release()
        #expect(!UIApplication.shared.isIdleTimerDisabled)

        drain()
    }

    /// A hold placed by something outside the coordinator entirely must survive
    /// our leases coming and going.
    @Test func `Releasing the last lease restores a pre-existing hold`() {
        drain()
        UIApplication.shared.isIdleTimerDisabled = true

        ScreenAwakeCoordinator.shared.acquire()
        ScreenAwakeCoordinator.shared.release()

        #expect(UIApplication.shared.isIdleTimerDisabled)

        drain()
    }

    /// An unbalanced release would drive the count negative and strand the timer
    /// disabled for the rest of the session.
    @Test func `An unbalanced release is ignored`() {
        drain()

        ScreenAwakeCoordinator.shared.release()
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 0)

        ScreenAwakeCoordinator.shared.acquire()
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)
        #expect(UIApplication.shared.isIdleTimerDisabled)

        drain()
    }

    /// Without it an abandoned screen holds the display awake until the battery
    /// runs down.
    @Test func `The failsafe caps a hold at ten minutes`() {
        #expect(ScreenAwakeCoordinator.failsafeInterval == 600)
    }

    // MARK: - Owner-keyed leases

    /// UIKit does not guarantee `viewWillAppear`/`viewWillDisappear` alternate
    /// strictly, and `Idleable` calls straight through from both. A second
    /// appear without an intervening disappear must not leak a lease.
    @Test func `A repeated acquire for one owner takes a single lease`() {
        drain()
        // The object must stay alive: `ObjectIdentifier` is just its address,
        // and a temporary's address is free for the next allocation to reuse.
        let screen = NSObject()
        let owner = ObjectIdentifier(screen)

        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        ScreenAwakeCoordinator.shared.acquire(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)

        ScreenAwakeCoordinator.shared.release(owner: owner)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 0)
        #expect(!UIApplication.shared.isIdleTimerDisabled)

        drain()
    }

    @Test func `Releasing an owner that holds no lease is a no-op`() {
        drain()
        let holderScreen = NSObject()
        let strangerScreen = NSObject()
        let holder = ObjectIdentifier(holderScreen)
        let stranger = ObjectIdentifier(strangerScreen)

        ScreenAwakeCoordinator.shared.acquire(owner: holder)
        ScreenAwakeCoordinator.shared.release(owner: stranger)

        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)
        #expect(UIApplication.shared.isIdleTimerDisabled)

        ScreenAwakeCoordinator.shared.release(owner: holder)
        drain()
    }

    /// The cross-boundary regression: a pushed `Idleable` screen opened over a
    /// SwiftUI screen that holds a lease used to write `isIdleTimerDisabled =
    /// false` on its way out, letting the display sleep while the SwiftUI screen
    /// was still showing live departures.
    @Test func `An Idleable screen leaving keeps a SwiftUI screen's hold`() {
        drain()
        let screen = NSObject()
        let pushedScreen = ObjectIdentifier(screen)

        // The stop sheet appears.
        ScreenAwakeCoordinator.shared.acquire()
        // "View Full Trip" pushes an Idleable trip screen on top of it.
        ScreenAwakeCoordinator.shared.acquire(owner: pushedScreen)
        // The rider pops back to the sheet.
        ScreenAwakeCoordinator.shared.release(owner: pushedScreen)

        #expect(UIApplication.shared.isIdleTimerDisabled)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 1)

        ScreenAwakeCoordinator.shared.release()
        #expect(!UIApplication.shared.isIdleTimerDisabled)

        drain()
    }

    /// The reverse ordering, which was worse: the sheet's lease recorded a
    /// pre-existing hold of `true`, the pushed screen then switched the global
    /// off directly, and the sheet's final release restored `true` — leaving the
    /// timer disabled with nothing holding it and no failsafe armed.
    @Test func `A pushed screen popped under a sheet does not strand the timer`() {
        drain()
        let screen = NSObject()
        let pushedScreen = ObjectIdentifier(screen)

        // The pushed Idleable Stop page appears.
        ScreenAwakeCoordinator.shared.acquire(owner: pushedScreen)
        // The SwiftUI sheet opens over it.
        ScreenAwakeCoordinator.shared.acquire()
        // The pushed page is popped.
        ScreenAwakeCoordinator.shared.release(owner: pushedScreen)
        // Then the sheet closes.
        ScreenAwakeCoordinator.shared.release()

        #expect(!UIApplication.shared.isIdleTimerDisabled)
        #expect(ScreenAwakeCoordinator.shared.activeLeases == 0)

        drain()
    }
}
