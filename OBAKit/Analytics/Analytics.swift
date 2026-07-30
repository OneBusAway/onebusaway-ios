//
//  Analytics.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// User Defaults keys for configuring analytics behavior in OBAKit.
/// nonisolated: a constants namespace; read from nonisolated analytics paths.
@objc(OBAAnalyticsKeys)
nonisolated public class AnalyticsKeys: NSObject {
    @objc public static let reportingEnabledUserDefaultsKey = "reportingEnabledUserDefaultsKey"
}

/// Standard labels for reporting analytics.
@objc(OBAAnalyticsLabels)
public class AnalyticsLabels: NSObject {

    /// Report a stop/trip problem, or contact transit agency/app developers.
    @objc public static let reportProblem = "report_problem"

    /// Label used when Automatically Selection Region is enabled.
    @objc public static let setRegionAutomatically = "Set region automatically"

    /// Label used when Automatically Selection Region is disabled.
    @objc public static let setRegionManually = "Set region manually"

    /// Label used when the region is selected manually, and its value changes.
    @objc public static let manuallySelectedRegionChanged = "selected manually"

    /// Label used for fare payment options.
    @objc public static let farePayment = "fare_payment"

    /// Label used for adding bookmarks.
    @objc public static let addBookmark = "Starred route"

    /// Label used for removing bookmarks.
    @objc public static let removeBookmark = "Unstarred route"

    public class func addRemoveBookmarkValue(routeID: String, headsign: String?, stopID: StopID) -> String {
        return "\(routeID)_\(headsign ?? "") for \(stopID)"
    }

    /// Label used when search mode is entered in the app.
    @objc public static let searchSelected = "Search box selected"

    /// Label used when a map annotation view is chosen.
    @objc public static let mapStopAnnotationTapped = "Clicked MapStopIcon"

    /// Label used when 'show my location' button is tapped.'
    @objc public static let mapShowUserLocationButtonTapped = "Clicked My Location Button"

    /// Label used when a map layer is toggled in the Map sheet. Value: "<layerID>:<on|off>".
    @objc public static let mapLayerToggled = "Map Layer Toggled"

    /// Label used when a rental vehicle or cluster annotation is tapped on the map.
    @objc public static let rentalVehicleSelected = "Rental Vehicle Selected"

    /// Label used when the rider taps "Plan a trip using this bike" — the browse
    /// layer's conversion into trip planning.
    @objc public static let rentalPlanTripTapped = "Rental Plan Trip Tapped"

    /// Label used when the rental minimum-range filter changes. Value: the
    /// threshold in meters, or "0" for no minimum.
    @objc public static let rentalRangeFilterChanged = "Rental Range Filter Changed"

    /// Label used when 'Learn More About Donations' screen is displayed
    @objc public static let donationLearnMoreShown = "Donation Learn More Shown"

    /// Label used when 'Donate button' is tapped
    @objc public static let donateButtonTapped = "Donation Button Tapped"

    /// Label used when a donation succeeds
    @objc public static let donationSuccess = "Donation Success"

    /// Label used when a donation fails due to an unrecoverable system error.
    @objc public static let donationError = "Donation Error"

    /// Label used when a donation fails due to the user canceling it.
    @objc public static let donationCanceled = "Donation Canceled"

    /// Label used when a push notification associated with a call for donations is tapped.
    @objc public static let donationPushNotificationTapped = "Donation Push Notification Tapped"

    /// Label used when a push notification results in a donation
    @objc public static let donationPushNotificationSuccess = "Donation Push Notification Success"

    /// Label used when the sentiment feedback prompt is displayed.
    @objc public static let feedbackPromptShown = "Feedback Prompt Shown"

    /// Label used when a rider answers the feedback prompt positively.
    @objc public static let feedbackPositive = "Feedback Positive"

    /// Label used when a rider answers the feedback prompt negatively.
    @objc public static let feedbackNegative = "Feedback Negative"

    /// Label used when a rider defers the feedback prompt.
    @objc public static let feedbackDeferred = "Feedback Deferred"

    /// Label used when the feedback email composer is opened.
    @objc public static let feedbackEmailOpened = "Feedback Email Opened"

    /// Label used when a feedback email is actually sent.
    @objc public static let feedbackEmailSent = "Feedback Email Sent"

    /// Label used when the rider wanted to send feedback but the device can't compose
    /// mail. Distinct from `feedbackEmailOpened` so this population — riders who
    /// structurally cannot reach us — doesn't hide inside opened-then-abandoned.
    @objc public static let feedbackEmailUnavailable = "Feedback Email Unavailable"

    /// Label used when the mail composer reports a send failure.
    @objc public static let feedbackEmailFailed = "Feedback Email Failed"

    /// Label used when the More tab's 'Rate' row is tapped.
    @objc public static let rateAppRowTapped = "Rate App Row Tapped"
}

/// Implement this protocol for reporting analytics events in order to be able to plug in a custom provider of your choosing.
///
/// `AnalyticsOrchestrator`, located in `Apps/Shared/CommonClient`, implements this protocol, and you can
/// implement it similarly in order to use your own custom analytics provider.
@objc(OBAAnalytics)
public protocol Analytics: NSObjectProtocol {
    @objc optional func updateServer(region: Region)

    @objc func reportEvent(pageURL: String, label: String, value: Any?)

    @objc func reportSearchQuery(_ query: String)
    @objc func reportStopViewed(name: String, id: String, stopDistance: String)
    @objc func reportSetRegion(_ name: String)

    @objc func setReportingEnabled(_ enabled: Bool)
    @objc func reportingEnabled() -> Bool

    @objc func setUserProperty(key: String, value: String?)

    @objc optional func reportError(_ error: Error)
}
