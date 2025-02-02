//
//  FirebaseAnalytics.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 2/2/25.
//

import Foundation
import OBAKit
import FirebaseCore
import FirebaseAnalytics

class FirebaseAnalytics: NSObject, OBAKit.Analytics {
    init(userID: String) {
        FirebaseApp.configure()
        Analytics.setUserID(userID)
    }

    @objc public func logEvent(name: String, parameters: [String: Any]) {
        Analytics.logEvent(name, parameters: parameters)
    }

    @objc public func reportEvent(_ event: AnalyticsEvent, label: String, value: Any?) {
        let eventName = AnalyticsEventSelectContent

        var parameters: [String: Any] = [:]
        parameters[AnalyticsParameterItemID] = label

        if let value = value as? String {
            parameters[AnalyticsParameterItemVariant] = value
        }

        logEvent(name: eventName, parameters: parameters)
    }

    @objc public func reportSearchQuery(_ query: String) {
        Analytics.logEvent(AnalyticsEventSearch, parameters: [AnalyticsParameterSearchTerm: query])
    }

    @objc public func reportStopViewed(name: String, id: String, stopDistance: String) {
        logEvent(
            name: AnalyticsEventViewItem,
            parameters: [
                AnalyticsParameterItemID: id,
                AnalyticsParameterItemName: name,
                AnalyticsParameterItemCategory: "stops",
                AnalyticsParameterLocationID: stopDistance
            ]
        )
    }

    @objc public func reportSetRegion(_ name: String) {
        setUserProperty(key: "RegionName", value: name)
    }

    @objc public func setReportingEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }

    @objc public func reportingEnabled() -> Bool {
        return true
    }

    @objc public func setUserProperty(key: String, value: String?) {
        Analytics.setUserProperty(value ?? "", forName: key)
    }
}
