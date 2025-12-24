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

@objc(OBAAnalyticsOrchestrator) public class AnalyticsOrchestrator: NSObject, OBAKit.Analytics {
    private let userDefaults: UserDefaults
    private var firebaseAnalytics: FirebaseAnalytics?
    private var plausibleAnalytics: PlausibleAnalytics?

    @objc required public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }
    
    @objc public func configure(userID: String) {
        firebaseAnalytics = FirebaseAnalytics(userID: userID)
    }
    
    public func updateServer(defaultDomainURL: URL, analyticsServerURL: URL?) {
        plausibleAnalytics = nil

        guard let analyticsServerURL else {
            return
        }

        if reportingEnabled() {
            plausibleAnalytics = PlausibleAnalytics(defaultDomainURL: defaultDomainURL, analyticsServerURL: analyticsServerURL)
        }
    }

    @objc public func reportError(_ error: any Error) {
        firebaseAnalytics?.reportError(error)

        // TODO: figure out how to report errors to a plausible-compatible destination.
    }

    @objc public func reportEvent(pageURL: String, label: String, value: Any?) {
        firebaseAnalytics?.reportEvent(label: label, value: value)
        Task {
            await plausibleAnalytics?.reportEvent(pageURL: pageURL, label: label, value: value)
        }
    }

    @objc public func reportSearchQuery(_ query: String) {
        firebaseAnalytics?.reportSearchQuery(query)

        Task {
            await plausibleAnalytics?.reportSearchQuery(query)
        }
    }

    @objc public func reportStopViewed(name: String, id: String, stopDistance: String) {
        firebaseAnalytics?.reportStopViewed(name: name, id: id, stopDistance: stopDistance)

        Task {
            await plausibleAnalytics?.reportStopViewed(name: name, id: id, stopDistance: stopDistance)
        }
    }

    @objc public func reportSetRegion(_ name: String) {
        setUserProperty(key: "RegionName", value: name)
        // n/a for Plausible since it'll be constrained on a per-region basis by the server URL.
    }

    @objc public func setReportingEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey)
        firebaseAnalytics?.setReportingEnabled(enabled)
        if !enabled {
            plausibleAnalytics = nil
        }
    }

    @objc public func reportingEnabled() -> Bool {
        return userDefaults.bool(forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey)
    }

    @objc public func setUserProperty(key: String, value: String?) {
        firebaseAnalytics?.setUserProperty(key: key, value: value)
        plausibleAnalytics?.setUserProperty(key: key, value: value)
    }
}
