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
@objc(OBAAnalyticsKeys)
public class AnalyticsKeys: NSObject {
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
}

/// Reported analytics events.
@objc(OBAAnalyticsEvent)
public enum AnalyticsEvent: Int {
    case userAction
}

/// Implement this protocol for reporting analytics events in order to be able to plug in a custom provider of your choosing.
///
/// `OBAFirebaseAnalytics`, located in `Apps/Shared/CommonClient`, implements this protocol, and you can
/// implement it similarly in order to use your own custom analytics provider.
@objc(OBAAnalytics)
public protocol Analytics: NSObjectProtocol {
    @objc optional func logEvent(name: String, parameters: [String: Any])
    @objc optional func reportEvent(_ event: AnalyticsEvent, label: String, value: Any?)

    @objc optional func reportSearchQuery(_ query: String)
    @objc optional func reportStopViewed(name: String, id: String, stopDistance: String)
    @objc optional func reportSetRegion(_ name: String)

    @objc optional func setReportingEnabled(_ enabled: Bool)
    @objc optional func reportingEnabled() -> Bool

    @objc optional func setUserProperty(key: String, value: String?)
}
