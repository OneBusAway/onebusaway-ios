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

    /// The item currently being presented, held weakly so we can restore
    /// its original `dismissalHandler` on teardown without extending its
    /// lifetime. Items outlive this window in practice (they're stored
    /// properties on bulletin classes like `ReachabilityBulletin`), but the
    /// weak reference is correct regardless.
    private weak var savedRootItem: BLTNItem?

    /// The `dismissalHandler` the caller had on `rootItem` before `install`
    /// swapped in the overlay's wrapper. Restored verbatim on teardown so
    /// the item goes back to exactly the state we found it in — no matter
    /// how many prior presentations occurred.
    private var savedDismissalHandler: ((BLTNItem) -> Void)?

    private init() {}

    /// Installs the overlay window and returns its host controller for
    /// `showBulletin(above:)`. Snapshots `rootItem.dismissalHandler` and
    /// replaces it with a wrapper that dispatches to the original then
    /// tears the window down. On teardown the original handler is restored,
    /// so a reused item (e.g. `ReachabilityBulletin.connectivityPage` re-shown
    /// across connectivity flaps) never accumulates nested wrappers.
    ///
    /// One bulletin at a time. Each `BLTNItemManager` already guards on
    /// `isShowingBulletin`, but those guards are per-manager; this singleton is
    /// shared across every OBA bulletin manager, so two managers can call
    /// `install` while a third is mid-presentation. The DEBUG assert flags the
    /// violation at the point it occurs; release builds still return the
    /// existing host so the second bulletin at worst piggybacks on the first's
    /// window rather than crashing.
    func install(in scene: UIWindowScene, rootItem: BLTNItem) -> UIViewController {
        // Single-page only: teardown rides `rootItem.dismissalHandler`, but
        // BLTN fires the dismissal handler on `currentItem` — which only
        // equals `rootItem` until something gets pushed. A multi-page item
        // would tear the window down on the first page's dismissal rather
        // than the flow's final dismissal. Catch the violation at install
        // time so a future contributor sees the contract instead of debugging
        // a teardown-mid-flow weirdness in the wild.
        assert(rootItem.next == nil, "BulletinOverlayWindow only supports single-page bulletins — multi-page flows would tear down on the first page's dismissal. See type docstring.")

        if let host = window?.rootViewController {
            assertionFailure("BulletinOverlayWindow already in use — concurrent bulletin presentations aren't supported (shared singleton, single-bulletin-at-a-time).")
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

        swapDismissalHandler(on: rootItem)

        return host
    }

    /// Snapshots the item's current `dismissalHandler` and swaps in a wrapper
    /// that fires the original handler then tears down. Extracted from
    /// `install` so tests can exercise the handler-management contract without
    /// synthesizing a `UIWindowScene`.
    internal func swapDismissalHandler(on rootItem: BLTNItem) {
        savedRootItem = rootItem
        savedDismissalHandler = rootItem.dismissalHandler
        rootItem.dismissalHandler = { [weak self] item in
            self?.savedDismissalHandler?(item)
            self?.teardown()
        }
    }

    /// Restores the previously-saved `dismissalHandler` onto the tracked item
    /// and clears the saved state. Extracted from `teardown` for testability.
    internal func restoreDismissalHandler() {
        savedRootItem?.dismissalHandler = savedDismissalHandler
        savedRootItem = nil
        savedDismissalHandler = nil
    }

    private func teardown() {
        restoreDismissalHandler()

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
