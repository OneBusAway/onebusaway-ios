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
    /// controllers that must not be torn down, so this drops there. Stop and trip
    /// pages go to `externalNavigationHost` instead; see `pushStopFromOutside`
    /// and `openTripFromOutside`.
    ///
    /// UIKit ignores a `dismiss` issued while a presentation or dismissal is still
    /// animating, and never calls its completion, so a call that lands mid-transition
    /// (a cold-launch popup still sliding in, a second link right behind the first)
    /// waits for that transition and tries again.
    ///
    /// - Parameter afterDismissal: runs once a dismissal started here has finished,
    ///   whether or not `push` could then be called.
    /// - Returns: true when `push` waits on a dismissal, so `topViewController` is
    ///   still the outgoing modal and nothing else should be presented from it yet.
    @MainActor
    @discardableResult
    func withPushableTopViewController(
        _ push: @escaping @MainActor (UIViewController) -> Void,
        afterDismissal: (@MainActor () -> Void)? = nil
    ) -> Bool {
        guard let top = topViewController else { return false }
        if top.navigationController != nil {
            push(top)
            return false
        }

        guard viewRouter.rootController != nil, let presenter = Self.basePresenter(of: top) else {
            Logger.error("Dropping navigation: \(type(of: top)) has no navigation controller to push from.")
            return false
        }

        if let transition = top.transitionCoordinator ?? presenter.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self else { return }
                if !self.withPushableTopViewController(push, afterDismissal: afterDismissal) {
                    afterDismissal?()
                }
            }
            return true
        }

        presenter.dismiss(animated: true) { [weak self] in
            defer { afterDismissal?() }
            guard let top = self?.topViewController, top.navigationController != nil else {
                Logger.error("Dropping navigation: nothing to push from after dismissing the presented controller.")
                return
            }
            push(top)
        }
        return true
    }

    /// Whether a stop or trip page asked for from outside can be shown now,
    /// rather than stashed until the root UI exists.
    @MainActor
    var canNavigateFromOutside: Bool {
        externalNavigationHost != nil || topViewController != nil
    }

    /// Opens the stop page for `stopID`: on the map panel when it is the root,
    /// otherwise by way of `withPushableTopViewController`.
    @MainActor
    @discardableResult
    func pushStopFromOutside(_ stopID: StopID, afterDismissal: (@MainActor () -> Void)? = nil) -> Bool {
        if let externalNavigationHost {
            return externalNavigationHost.openStop(stopID, afterDismissal: afterDismissal)
        }
        return withPushableTopViewController({ [weak self] from in
            self?.viewRouter.navigateTo(stopID: stopID, from: from)
        }, afterDismissal: afterDismissal)
    }

    /// Opens the trip page for `arrivalDeparture`, the trip counterpart of
    /// `pushStopFromOutside`.
    ///
    /// - Parameter destinationStopID: Where the sharer said they will step off,
    ///   when this came from a shared trip link that named one. See #449.
    @MainActor
    func openTripFromOutside(_ arrivalDeparture: ArrivalDeparture, destinationStopID: StopID?) {
        if let externalNavigationHost {
            externalNavigationHost.openTrip(arrivalDeparture, destinationStopID: destinationStopID)
            return
        }
        withPushableTopViewController { [weak self] from in
            self?.viewRouter.navigateTo(
                arrivalDeparture: arrivalDeparture,
                from: from,
                destinationStopID: destinationStopID
            )
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
