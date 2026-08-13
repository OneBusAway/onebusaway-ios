//
//  Strings+Donations.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Strings for the donation-dismiss action sheet, which `StopViewController` and
/// `StopPageViewController` both present. Other donation strings live with their
/// own views (`DonationCell`, `DonationLearnMoreView`, `Strings.donationThankYou*`).
public extension Strings {

    // MARK: - Dismiss Alert

    static let donationsDismissAlertTitle = OBALoc(
        "donations.donations_dismiss_alert.title",
        value: "Please don't dismiss this request",
        comment: "Title of the alert that appears when the user chooses to dismiss the donations request UI on a stop page"
    )

    static let donationsDismissAlertMessage = String(
        format: OBALoc(
            "donations.donations_dismiss_alert.message",
            value: "%@ is a volunteer-run organization with almost no funding. We need your help to keep this app running.",
            comment: "Body of the alert that appears when the user chooses to dismiss the donations request UI on a stop page. %@ is the app name."
        ),
        Bundle.main.appName
    )

    static let donationsDismissAlertButtonDismiss = OBALoc(
        "donations.donations_dismiss_alert.button_dismiss",
        value: "I Don't Want to Help Right Now",
        comment: "Button on the donation-dismiss alert that permanently stops donation requests."
    )

    static let donationsDismissAlertButtonRemindLater = OBALoc(
        "donations.donations_dismiss_alert.button_remind_later",
        value: "Remind Me Later",
        comment: "Button on the donation-dismiss alert that defers donation requests rather than stopping them."
    )
}
