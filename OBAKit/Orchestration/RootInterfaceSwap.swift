//
//  RootInterfaceSwap.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// Replaces a window's root view controller mid-session.
///
/// In the map panel experience the old root is presenting the floating sheet, with More or
/// Settings stacked on it. Whether assigning `window.rootViewController` takes that chain down
/// is up to UIKit (the iOS 27 simulator does), so the chain is dismissed here first, and the
/// new root is built and installed once nothing of the old one is on screen.
public enum RootInterfaceSwap {

    private final class PendingSwap {
        weak var oldRoot: UIViewController?
        weak var presented: UIViewController?
        var makeRoot: () -> UIViewController
        var completions: [() -> Void]

        init(
            oldRoot: UIViewController,
            presented: UIViewController,
            makeRoot: @escaping () -> UIViewController,
            completions: [() -> Void]
        ) {
            self.oldRoot = oldRoot
            self.presented = presented
            self.makeRoot = makeRoot
            self.completions = completions
        }
    }

    /// Windows that currently have a dismissal in flight. Back-to-back calls
    /// coalesce onto the existing dismissal instead of calling `dismiss` again
    /// while the first is still running, which UIKit can drop without firing
    /// the second completion (#1731).
    private static let inFlight = NSMapTable<UIWindow, PendingSwap>.weakToStrongObjects()

    /// Dismisses everything the window's current root presents, then installs the root that
    /// `makeRoot` builds.
    ///
    /// If another call arrives for the same window while a dismissal is already in flight,
    /// the reload is coalesced: only the latest `makeRoot` is called once the dismissal finishes,
    /// and every caller's `completion` runs in order after the new root is in place.
    ///
    /// - Parameters:
    ///   - window: The window whose root is replaced.
    ///   - makeRoot: Builds the new root. Called once the old chain is gone, so the new root
    ///     is never created while the old one is still on screen.
    ///   - completion: Called after the new root is in place: at once when the old root presents
    ///     nothing, otherwise from the dismissal's completion.
    public static func replaceRoot(
        of window: UIWindow,
        with makeRoot: @escaping () -> UIViewController,
        completion: (() -> Void)? = nil
    ) {
        var completions: [() -> Void] = []

        if let existing = inFlight.object(forKey: window) {
            if let oldRoot = existing.oldRoot,
               let presented = existing.presented,
               window.rootViewController === oldRoot,
               oldRoot.presentedViewController === presented {
                existing.makeRoot = makeRoot
                if let completion {
                    existing.completions.append(completion)
                }
                return
            }

            // The prior dismissal's root or presentation is gone (for example,
            // if UIKit dropped a dismissal completion). Evict the stale entry so later
            // swaps are never wedged, and carry its pending completions forward.
            inFlight.removeObject(forKey: window)
            completions = existing.completions
        }

        if let completion {
            completions.append(completion)
        }

        guard let oldRoot = window.rootViewController,
              let presented = oldRoot.presentedViewController else {
            install(makeRoot, on: window, completions: completions)
            return
        }

        let pending = PendingSwap(
            oldRoot: oldRoot,
            presented: presented,
            makeRoot: makeRoot,
            completions: completions
        )
        inFlight.setObject(pending, forKey: window)

        oldRoot.dismiss(animated: false) {
            guard inFlight.object(forKey: window) === pending else { return }
            inFlight.removeObject(forKey: window)
            install(pending.makeRoot, on: window, completions: pending.completions)
        }
    }

    private static func install(
        _ makeRoot: () -> UIViewController,
        on window: UIWindow,
        completions: [() -> Void]
    ) {
        window.rootViewController = makeRoot()
        for callback in completions {
            callback()
        }
    }
}
