//
//  FirebaseAnalytics.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import OBAKit
import FirebaseCore
import FirebaseAnalytics

@objc(OBAFirebaseAnalytics) public class FirebaseAnalytics: NSObject, OBAKit.Analytics {
    private let userDefaults: UserDefaults

    required public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }
    
    public func configure(userID: String) {
        FirebaseApp.configure()
        Analytics.setUserID(userID)
    }
    
    public func updateServer(defaultDomainURL: URL, analyticsServerURL: URL?) {
        // abxoxo todo
    }

    @objc public func logEvent(name: String, parameters: [String: Any]) {
        Analytics.logEvent(name, parameters: parameters)
    }

    @objc public func reportEvent(_ event: AnalyticsEvent, label: String, value: Any?) {
        guard event == .userAction else {
            Logger.error("Invalid call to -reportEventWithCategory: \(event) label: \(label) value: \(value ?? "")")
            return
        }

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
        userDefaults.set(enabled, forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey)
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }

    @objc public func reportingEnabled() -> Bool {
        return userDefaults.bool(forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey)
    }

    @objc public func setUserProperty(key: String, value: String?) {
        Analytics.setUserProperty(value ?? "", forName: key)
    }
}
