//
//  ViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

@MainActor
protocol AppContext where Self: UIViewController {
    var application: Application { get }
}

/// Describes a class that can disable and reenable the UIApplication idle timer.
@MainActor
public protocol Idleable: NSObjectProtocol {
    /// The OBA application object, which is used to retrieve the `UIApplication`.
    var application: Application { get }

    /// Takes a hold on the idle timer, so the display stays awake while this
    /// screen is visible.
    func disableIdleTimer()

    /// Returns this screen's hold on the idle timer.
    func enableIdleTimer()
}

/// A view controller that can disable and reenable the UIApplication idle timer.
///
/// Both sides delegate to `ScreenAwakeCoordinator` rather than writing
/// `isIdleTimerDisabled` directly. That global has SwiftUI screens holding
/// leases on it too (`keepsScreenAwake()`), and one screen unconditionally
/// switching it back on as it leaves would let the display sleep out from under
/// a screen that is still up. The coordinator restores it exactly once, when the
/// last holder goes away, and owns the failsafe that caps the hold.
@MainActor
public extension Idleable where Self: UIViewController {
    func disableIdleTimer() {
        ScreenAwakeCoordinator.shared.acquire(owner: ObjectIdentifier(self))
    }

    nonisolated func enableIdleTimer() {
        // Captured up front rather than through a `weak self` inside the hop: a
        // controller deallocated before the hop runs would otherwise never
        // return its lease, stranding the timer disabled.
        let owner = ObjectIdentifier(self)
        Task { @MainActor in
            ScreenAwakeCoordinator.shared.release(owner: owner)
        }
    }
}
