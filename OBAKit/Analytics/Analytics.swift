//
//  Analytics.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/2/19.
//

import Foundation

@objc(OBAAnalyticsKeys)
public class AnalyticsKeys: NSObject {
    @objc public static let reportingEnabledUserDefaultsKey = "reportingEnabledUserDefaultsKey"
}

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

    public class func addRemoveBookmarkValue(routeID: String, headsign: String?, stopID: String) -> String {
        return "\(routeID)_\(headsign ?? "") for \(stopID)"
    }

    /// Label used when search mode is entered in the app.
    @objc public static let searchSelected = "Search box selected"

    /// Label used when a map annotation view is chosen.
    @objc public static let mapStopAnnotationTapped = "Clicked MapStopIcon"

    /// Label used when 'show my location' button is tapped.'
    @objc public static let mapShowUserLocationButtonTapped = "Clicked My Location Button"
}

@objc(OBAAnalyticsEvent)
public enum AnalyticsEvent: Int {
    case userAction
}

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
