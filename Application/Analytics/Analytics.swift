//
//  Analytics.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/2/19.
//

import Foundation

@objc(OBAAnalyticsCategory)
public enum AnalyticsCategory: Int {
    case UIAction
}

@objc(OBAAnalytics)
public protocol Analytics: NSObjectProtocol {
    func logEvent(name: String, parameters: [String: Any])
    func reportEvent(category: AnalyticsCategory, action: String, label: String, value: Any?)
}
