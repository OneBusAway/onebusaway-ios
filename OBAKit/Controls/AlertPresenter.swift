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

    /// Displays an error message to the user, classifying it via `ErrorClassifier` when possible.
    /// - Parameters:
    ///   - error: The error to classify and show to the user.
    ///   - regionName: The display name of the user's current transit region.
    ///   - presentingController: The view controller that will host the error alert.
    @MainActor
    public class func show(error: Error, regionName: String? = nil, presentingController: UIViewController) async {
        let classified = ErrorClassifier.classify(error, regionName: regionName)
        await show(errorMessage: classified.localizedDescription, presentingController: presentingController)
    }

    /// Displays an error message to the user.
    /// - Parameters:
    ///   - errorMessage: The error message that will be shown.
    ///   - presentingController: The view controller that will act as the host for the presented error alert UI.
    @MainActor
    public class func show(errorMessage: String, presentingController: UIViewController) async {
        await showDismissableAlert(title: Strings.error, message: errorMessage, presentingController: presentingController)
    }

    /// Displays an alert with a Dismiss button, presented from `presentingController`.
    /// - Parameters:
    ///   - title: Optional alert title.
    ///   - message: Optional alert message.
    ///   - presentingController: The presenting view controller.
    @MainActor
    public class func showDismissableAlert(title: String?, message: String?, presentingController: UIViewController) async {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.dismiss, style: .default, handler: nil))
        presentingController.present(alert, animated: true, completion: nil)
    }
}
