//
//  AlertPresenter.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/16/19.
//

import UIKit

/// Provides a UI-independent way to display error messages and other alerts to the user.
public class AlertPresenter: NSObject {

    /// Displays an error message to the user
    /// - Parameter error: The error to show to the user.
    /// - Parameter presentingController: The view controller that will act as the host for the presented error alert UI.
    public class func show(error: Error, presentingController: UIViewController) {
        let alert = UIAlertController(title: Strings.error, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.dismiss, style: .default, handler: nil))
        presentingController.present(alert, animated: true, completion: nil)
    }
}
