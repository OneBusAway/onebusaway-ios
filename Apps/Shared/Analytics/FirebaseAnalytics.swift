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

class FirebaseAnalytics: NSObject {
    init(userID: String) {
        FirebaseApp.configure()
        Analytics.setUserID(userID)
    }

    private func logEvent(name: String, parameters: [String: Any]) {
        Analytics.logEvent(name, parameters: parameters)
    }

    public func reportEvent(label: String, value: Any?) {
        var parameters: [String: Any] = [:]
        parameters[AnalyticsParameterItemID] = label

        if let value = value as? String {
            parameters[AnalyticsParameterItemVariant] = value
        }

        logEvent(name: AnalyticsEventSelectContent, parameters: parameters)
    }

    public func reportSearchQuery(_ query: String) {
        Analytics.logEvent(AnalyticsEventSearch, parameters: [AnalyticsParameterSearchTerm: query])
    }

    public func reportStopViewed(name: String, id: String, stopDistance: String) {
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

    public func reportSetRegion(_ name: String) {
        setUserProperty(key: "RegionName", value: name)
    }

    public func setReportingEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }
    
    public func setUserProperty(key: String, value: String?) {
        Analytics.setUserProperty(value ?? "", forName: key)
    }
}
