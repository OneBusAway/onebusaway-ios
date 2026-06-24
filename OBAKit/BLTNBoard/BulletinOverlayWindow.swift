//
//  BulletinOverlayWindow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import BLTNBoard

/// Owns a dedicated `UIWindow` for hosting `BLTNItemManager` presentations.
///
/// Bulletins originally rode `keyWindowFromScene?.topViewController`. That walk
/// lands inside the SwiftUI map-panel home sheet's hosting controller, which is
/// constrained by `UISheetPresentationController` to its current detent (~80pt
/// when collapsed) — so a `present(_:animated:)` from there squeezes the bulletin
/// into the sheet's height and wedges the floating sheet.
///
/// A dedicated window at `.alert` level dodges the sheet hierarchy entirely.
/// Teardown is wired into BLTN's per-item `dismissalHandler` (its official
/// dismissal hook), so the window retires exactly when the bulletin finishes
/// animating out — no timers, no `dismiss(_:animated:)` overrides.
///
/// Single-page bulletins only: BLTN fires the dismissal handler on the
/// `currentItem`, which equals `rootItem` until something is pushed. OBA's
/// bulletins are all single-page today; revisit if that changes.
@MainActor
final class BulletinOverlayWindow {

    static let shared = BulletinOverlayWindow()

    private var window: UIWindow?

    private init() {}

    /// Installs the overlay window (if not already up) and returns its host
    /// controller for `showBulletin(above:)`. Hooks `rootItem.dismissalHandler`
    /// to tear the window down once the bulletin dismisses, chaining any
    /// handler the caller already set.
    func install(in scene: UIWindowScene, rootItem: BLTNItem) -> UIViewController {
        if let host = window?.rootViewController {
            return host
        }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert
        window.backgroundColor = .clear

        let host = UIViewController()
        host.view.backgroundColor = .clear
        window.rootViewController = host
        // Non-key intentionally: iOS hit-tests top-down by window level, so the
        // bulletin's buttons still receive touches without us hijacking key
        // status from the main app window.
        window.isHidden = false

        self.window = window

        let originalDismissal = rootItem.dismissalHandler
        rootItem.dismissalHandler = { [weak self] item in
            originalDismissal?(item)
            self?.teardown()
        }

        return host
    }

    private func teardown() {
        let scene = window?.windowScene
        window?.rootViewController = nil
        window?.isHidden = true
        window?.windowScene = nil
        window = nil

        // iOS doesn't always rebind key status when an alert-level window
        // hides — force the main app window to reclaim it so the visible UI
        // resumes receiving touches.
        scene?.windows
            .first(where: { !$0.isHidden && $0.windowLevel == .normal })?
            .makeKey()
    }
}
