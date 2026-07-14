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

/// The user-facing outcome of starting a Live Activity. Shared by every screen that can start
/// one — currently the bookmarks list and the stop page — so the copy stays identical between
/// them rather than drifting apart in two private copies.
extension UIViewController {

    func showLiveActivityStartedAlert() {
        let title = OBALoc("live_activity.started.title", value: "Tracking on Lock Screen", comment: "Alert title when a Live Activity starts")
        let message = OBALoc("live_activity.started.message", value: "You'll see live arrival updates on your Lock Screen and Dynamic Island.", comment: "Alert message explaining where to find the Live Activity")
        showLiveActivityAlert(title: title, message: message)
    }

    func showLiveActivityErrorAlert() {
        let title = OBALoc("live_activity.error.title", value: "Unable to Start Tracking", comment: "Alert title when Live Activity fails to start")
        let message = OBALoc("live_activity.error.message", value: "Please check your Live Activities settings in System Preferences.", comment: "Alert message for Live Activity error")
        showLiveActivityAlert(title: title, message: message)
    }

    private func showLiveActivityAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
        present(alert, animated: true)
    }
}
