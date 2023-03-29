//
//  AlertPresenter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// Provides a UI-independent way to display error messages and other alerts to the user.
class AlertPresenter: NSObject {

    /// Displays an error message to the user
    /// - Parameter error: The error to show to the user.
    /// - Parameter presentingController: The view controller that will act as the host for the presented error alert UI.
    @MainActor
    public class func show(error: Error, presentingController: UIViewController) async {
        await show(errorMessage: error.localizedDescription, presentingController: presentingController)
    }

    /// Displays an error message to the user.
    /// - Parameter errorMessage: The error message that will be shown.
    /// - Parameter presentingController: The view controller that will act as the host for the presented error alert UI.
    @MainActor
    public class func show(errorMessage: String, presentingController: UIViewController) async {
        await showDismissableAlert(title: Strings.error, message: errorMessage, presentingController: presentingController)
    }

    /// Displays an alert with a Dismiss button, presented from `presentingController`.
    /// - Parameter title: Optional alert title.
    /// - Parameter message: Optional alert message.
    /// - Parameter presentingController: The presenting view controller.
    @MainActor
    public class func showDismissableAlert(title: String?, message: String?, presentingController: UIViewController) async {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.dismiss, style: .default, handler: nil))
        presentingController.present(alert, animated: true, completion: nil)
    }
}
