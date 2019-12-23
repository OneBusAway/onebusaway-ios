//
//  Analytics.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/2/19.
//

import Foundation

@objc(OBAAnalyticsEvent)
public enum AnalyticsEvent: Int {
    case userAction
}

@objc(OBAAnalytics)
public protocol Analytics: NSObjectProtocol {
    func logEvent(name: String, parameters: [String: Any])
    func reportEvent(_ event: AnalyticsEvent, label: String, value: Any?)
}
