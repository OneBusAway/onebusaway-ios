//
//  ErrorBulletin.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import BLTNBoard
import OBAKitCore
import UIKit

/// Displays a modal card UI that presents an error.
class ErrorBulletin: NSObject {
    private let bulletinManager: BLTNItemManager
    private let error: Error
    private let page: ThemedBulletinPage
    private let application: Application

    init(application: Application, message: String? = nil, error: Error, regionName: String? = nil, image: UIImage? = nil, title: String? = nil) {
        self.application = application

        let classified = ErrorClassifier.classify(error, regionName: regionName, isCellularDataRestricted: application.isCellularDataRestricted)
        self.error = classified

        let displayMessage = message ?? classified.localizedDescription

        page = ThemedBulletinPage(title: title ?? Strings.error)
        page.descriptionText = displayMessage
        page.isDismissable = false

        let squircleRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.errorColor)
        page.image = squircleRenderer.drawImageOnRoundedRect(image ?? Icons.errorOutline)

        bulletinManager = BLTNItemManager(rootItem: page)

        super.init()

        configureDismissal()
    }

    /// Creates a bulletin from an already-classified error, skipping re-classification.
    init(application: Application, classifiedError: Error, image: UIImage? = nil, title: String? = nil) {
        self.application = application
        self.error = classifiedError

        page = ThemedBulletinPage(title: title ?? Strings.error)
        page.descriptionText = classifiedError.localizedDescription
        page.isDismissable = false

        let squircleRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.errorColor)
        page.image = squircleRenderer.drawImageOnRoundedRect(image ?? Icons.errorOutline)

        bulletinManager = BLTNItemManager(rootItem: page)

        super.init()

        configureDismissal()
    }

    /// Convenience initializer for call sites that pass an explicit message.
    convenience init(application: Application, message: String, error: Error, image: UIImage? = nil, title: String? = nil) {
        self.init(
            application: application,
            message: Optional(message),
            error: error,
            regionName: application.currentRegionName,
            image: image,
            title: title
        )
    }

    /// Wires up the Dismiss button and the release of `presentationRetain`.
    ///
    /// Runs in `init` rather than in `show` because `BulletinOverlayWindow`
    /// snapshots `dismissalHandler` when it installs, and wraps whatever it
    /// finds — so ours has to already be in place by then.
    private func configureDismissal() {
        page.actionButtonTitle = Strings.dismiss
        page.actionHandler = { [weak self] _ in
            guard let self else { return }
            self.bulletinManager.dismissBulletin()
        }
        page.dismissalHandler = { [weak self] _ in
            // The card is gone; give up the reference taken in `show`.
            self?.presentationRetain = nil
        }
    }

    @MainActor
    func show(in app: UIApplication) {
        present { bulletinManager.show(in: app, rootItem: page) }
    }

    /// Presents above an explicit view controller.
    ///
    /// `show(in:)` resolves the host itself — the overlay window under the
    /// map-panel experience, the key window's top view controller otherwise.
    /// Tests present into a controller they own instead, so assertions about
    /// the presented card don't depend on key-window discovery inside a test
    /// host.
    @MainActor
    func show(above presentingViewController: UIViewController, animated: Bool = true) {
        present { bulletinManager.showBulletin(above: presentingViewController, animated: animated) }
    }

    /// Runs `present` under the guard and ownership rules every presentation
    /// path shares.
    ///
    /// **Ownership.** Everything UIKit holds onto afterwards points *back* here
    /// weakly: `BulletinViewController.manager` and `BLTNItem.manager` are
    /// `weak`, and `UIControl` holds its targets weakly too. The presented
    /// controller and its views, by contrast, are retained by the presenting
    /// view controller. So without `presentationRetain`, dropping the last
    /// reference held elsewhere — `Application.errorBulletin` is a single slot,
    /// reassigned by the next error to arrive — deallocates the manager and the
    /// page out from under a card that is still on screen. Dismiss is left with
    /// neither a target nor a handler, and `page.isDismissable == false` rules
    /// out swipe and the close button, so the app is wedged until it's
    /// force-quit (#1421, #1429).
    @MainActor
    private func present(_ present: () -> Void) {
        // Re-entrant while this manager's card is already up: no-op. Callers that
        // create a *new* ErrorBulletin each time must also gate on `isShowing`
        // (see `Application.displayError`) — a fresh manager always reports
        // `isShowingBulletin == false`.
        guard !isShowing else { return }
        present()

        // Take the self-reference only once the card is actually up: presenting
        // can bail (no window scene, no key window), and then no dismissal is
        // coming to release it. A card torn down without going through
        // `dismissBulletin` — its presenter disappearing, say — does leak this
        // one object, which is the deliberate trade against wedging the UI.
        presentationRetain = isShowing ? self : nil
    }

    /// Holds `self` alive while the card is presented; see `present(_:)`.
    /// Cleared by the `dismissalHandler` set in `configureDismissal`.
    private var presentationRetain: ErrorBulletin?

    /// The Dismiss button on the presented card.
    ///
    /// `nil` outside a presentation: BLTN builds the button in `prepare()` and
    /// drops it again in `tearDown()`, so this is only non-`nil` between `show`
    /// and dismissal.
    @MainActor
    var dismissButton: UIButton? {
        page.actionButton
    }

    /// `true` while this bulletin's `BLTNItemManager` is presenting.
    @MainActor
    var isShowing: Bool {
        bulletinManager.isShowingBulletin
    }
}
