//
//  Application+ExternalNavigation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

extension Application {
    /// Calls `push` with a controller that a stop or trip page can be pushed from,
    /// for navigation that starts outside the visible UI: deep links, push
    /// notifications, and the cold-launch drain.
    ///
    /// `topViewController` is often a modal with no navigation controller (the
    /// weather popup, a TipKit popover, an alert). Pushing from one trips
    /// `ViewRouter.navigate(to:from:)`'s assert in debug and does nothing in
    /// release. The rider asked for this page from outside the app, so close
    /// the whole presentation stack and push onto the tab underneath.
    ///
    /// Map-panel mode has no classic root, and its sheets are presented
    /// controllers that must not be torn down, so there it logs and drops; see
    /// the deep-link TODO on `ViewRouter.rootNavigateTo(page:)`.
    @MainActor
    func withPushableTopViewController(_ push: @escaping @MainActor (UIViewController) -> Void) {
        guard let top = topViewController else { return }
        if top.navigationController != nil {
            push(top)
            return
        }

        guard viewRouter.rootController != nil, let presenter = Self.basePresenter(of: top) else {
            Logger.error("Dropping navigation: \(type(of: top)) has no navigation controller to push from.")
            return
        }

        presenter.dismiss(animated: true) { [weak self] in
            guard let top = self?.topViewController, top.navigationController != nil else {
                Logger.error("Dropping navigation: nothing to push from after dismissing the presented controller.")
                return
            }
            push(top)
        }
    }

    /// The controller at the bottom of `controller`'s presentation chain, or nil
    /// if `controller` is not presented. Dismissing it closes the whole stack.
    ///
    /// Usually that is the tab root, which presents on behalf of its children.
    /// A child that sets `definesPresentationContext` (a search controller's
    /// host) presents for itself, though, and the root sees nothing presented.
    @MainActor
    static func basePresenter(of controller: UIViewController) -> UIViewController? {
        guard var base = controller.presentingViewController else { return nil }
        while let next = base.presentingViewController {
            base = next
        }
        return base
    }
}
