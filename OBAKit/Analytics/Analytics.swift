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

@objc(OBAAnalyticsEvent)
public enum AnalyticsEvent: Int {
    case userAction
}

@objc(OBAAnalytics)
public protocol Analytics: NSObjectProtocol {
    func logEvent(name: String, parameters: [String: Any])
    func reportEvent(_ event: AnalyticsEvent, label: String, value: Any?)

    func setReportingEnabled(_ enabled: Bool)
    func reportingEnabled() -> Bool
}
