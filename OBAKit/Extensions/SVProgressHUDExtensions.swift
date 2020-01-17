//
//  SVProgressHUDExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/16/19.
//

import UIKit

extension SVProgressHUD {
    /// Displays the 'success' indicator with an optional message, and then dismisses the HUD `dismissAfter` seconds later.
    /// - Parameter message: Optional message to show the user. Defaults to `nil`.
    /// - Parameter dismissAfter: How many seconds until the HUD should be dismissed. Defaults to `3.0`.
    class func showSuccessAndDismiss(message: String? = nil, dismissAfter: TimeInterval = 3.0) {
        SVProgressHUD.showSuccess(withStatus: message)
        SVProgressHUD.dismiss(withDelay: dismissAfter)
    }
}
