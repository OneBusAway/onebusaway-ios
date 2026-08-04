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

/// The lease arithmetic behind `keepsScreenAwake()`.
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

    /// A hold placed by something else — a UIKit `Idleable` screen underneath —
    /// must survive our leases coming and going.
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

    /// Parity with `Idleable`, whose `disableIdleTimer()` arms a failsafe of the
    /// same length. Without it an abandoned screen holds the display awake until
    /// the battery runs down.
    @Test func `The failsafe matches Idleable's ten minute interval`() {
        #expect(ScreenAwakeCoordinator.failsafeInterval == 600)
    }
}
