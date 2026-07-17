//
//  UIViewController+LiveActivityAlerts.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// The error outcome of starting a Live Activity. Shown as an alert because an error
/// requires explicit acknowledgement from the user.
extension UIViewController {

    func showLiveActivityErrorAlert() {
        let title = OBALoc("live_activity.error.title", value: "Unable to Start Tracking", comment: "Alert title when Live Activity fails to start")
        let message = OBALoc("live_activity.error.message", value: "Please check your Live Activities settings in Settings.", comment: "Alert message for Live Activity error. \"Settings\" is the iOS Settings app.")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
        present(alert, animated: true)
    }
}
