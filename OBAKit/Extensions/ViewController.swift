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
    /// The timer that turns the UIApplication idle timer back on after a 10 minute time period.
    var idleTimerFailsafe: Timer? { get set }

    /// The OBA application object, which is used to retrieve the `UIApplication`.
    var application: Application { get }

    /// Disables the idle timer and creates the `idleTimerFailsafe`.
    func disableIdleTimer()

    /// Reenables the idle timer and invalidates the `idleTimerFailsafe`.
    func enableIdleTimer()
}

/// A view controller that can disable and reenable the UIApplication idle timer.
@MainActor
public extension Idleable where Self: UIViewController {
    func disableIdleTimer() {
        application.isIdleTimerDisabled = true

        idleTimerFailsafe?.invalidate()
        let idleTimerFailsafeInterval: TimeInterval = 600 // 10 minutes.
        self.idleTimerFailsafe = Timer.scheduledTimer(withTimeInterval: idleTimerFailsafeInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.application.isIdleTimerDisabled = false
            }
        }
    }

    nonisolated func enableIdleTimer() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.application.isIdleTimerDisabled = false
            self.idleTimerFailsafe?.invalidate()
            self.idleTimerFailsafe = nil
        }
    }
}
