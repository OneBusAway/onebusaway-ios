//
//  ProgressHUDExtensions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

extension ProgressHUD {
    /// The pending auto-dismiss from the most recent `showSuccessAndDismiss` call.
    /// Superseded (cancelled) by each new call, so a HUD shown while a prior one
    /// is still on screen gets its full display window instead of being hidden
    /// early by the prior call's timer. MainActor-isolated via `ProgressHUD`.
    private static var pendingDismiss: DispatchWorkItem?

    /// Displays the 'success' indicator with an optional message, and then dismisses the HUD `dismissAfter` seconds later.
    /// - Parameter message: Optional message to show the user. Defaults to `nil`.
    /// - Parameter dismissAfter: How many seconds until the HUD should be dismissed. Defaults to `3.0`.
    class func showSuccessAndDismiss(message: String? = nil, dismissAfter: TimeInterval = 3.0) {
        pendingDismiss?.cancel()
        ProgressHUD.showSuccess(message, image: nil, interaction: false)
        let dismiss = DispatchWorkItem { ProgressHUD.dismiss() }
        pendingDismiss = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter, execute: dismiss)
    }
}
