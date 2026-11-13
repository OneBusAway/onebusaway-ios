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

    /// Dismisses everything the window's current root presents, then installs the root that
    /// `makeRoot` builds.
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
        let install = {
            window.rootViewController = makeRoot()
            completion?()
        }

        guard let oldRoot = window.rootViewController, oldRoot.presentedViewController != nil else {
            install()
            return
        }

        oldRoot.dismiss(animated: false, completion: install)
    }
}
