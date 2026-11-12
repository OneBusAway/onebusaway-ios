//
//  AnalyticsOrchestrator.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import OBAKit
import FirebaseCrashlytics
import Synchronization

nonisolated final class AnalyticsReportingState: Sendable {
    private let state: Mutex<Bool>

    init(_ initialValue: Bool) {
        state = Mutex(initialValue)
    }

    var value: Bool {
        state.withLock { $0 }
    }

    func set(_ value: Bool) {
        state.withLock { $0 = value }
    }

    func toggle() {
        state.withLock { $0.toggle() }
    }
}

@objc(OBAAnalyticsOrchestrator) public class AnalyticsOrchestrator: NSObject, OBAKit.Analytics {
    private let userDefaults: UserDefaults
    private let reportingState: AnalyticsReportingState
    private var firebaseAnalytics: FirebaseAnalytics?
    private var umami: UmamiAnalytics?
    /// The region Umami was last built for, so turning reporting back on
    /// can rebuild it without waiting for a relaunch.
    private var currentRegion: Region?

    @objc required public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        self.reportingState = AnalyticsReportingState(userDefaults.bool(forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey))
    }

    @objc public func configure(userID: String) {
        firebaseAnalytics = FirebaseAnalytics(userID: userID)

        DecodingErrorReporter.reportHandler = { [weak self] error, url, httpMethod, message in
            guard let self = self else { return }
            guard self.reportingEnabled() else {
                #if DEBUG
                print("[DecodingErrorReporter] Reporting disabled by user preference")
                #endif
                return
            }

            let crashlytics = Crashlytics.crashlytics()

            let errorType: String
            switch error {
            case .keyNotFound:
                errorType = "keyNotFound"
            case .typeMismatch:
                errorType = "typeMismatch"
            case .valueNotFound:
                errorType = "valueNotFound"
            case .dataCorrupted:
                errorType = "dataCorrupted"
            @unknown default:
                errorType = "unknown"
            }

            crashlytics.setCustomValue(url.absoluteString, forKey: "request_url")
            crashlytics.setCustomValue(httpMethod, forKey: "http_method")
            crashlytics.setCustomValue(errorType, forKey: "decoding_error_type")
            crashlytics.setCustomValue(message, forKey: "decoding_error_detail")

            crashlytics.record(error: error)
        }
    }

    public func updateServer(region: Region) {
        currentRegion = region
        // Rebuild Umami from scratch on every region change.
        umami = nil

        guard reportingEnabled() else { return }

        if let umamiConfig = region.umamiAnalytics {
            // One install ID for every region, read once per process.
            umami = UmamiAnalytics(serverURL: umamiConfig.url,
                                   websiteID: umamiConfig.id,
                                   hostname: region.OBABaseURL.host ?? "",
                                   installID: AnalyticsInstallID.current)
        }
    }

    @objc public func reportError(_ error: any Error) {
        firebaseAnalytics?.reportError(error)

        // TODO: figure out how to report errors to an Umami-compatible destination.
    }

    @objc public func reportEvent(pageURL: String, label: String, value: Any?) {
        firebaseAnalytics?.reportEvent(label: label, value: value)
        Task { await umami?.reportEvent(pageURL: pageURL, label: label, value: value) }
    }

    @objc public func reportSearchQuery(_ query: String) {
        firebaseAnalytics?.reportSearchQuery(query)

        Task { await umami?.reportSearchQuery(query) }
    }

    @objc public func reportStopViewed(name: String, id: String, stopDistance: String) {
        firebaseAnalytics?.reportStopViewed(name: name, id: id, stopDistance: stopDistance)

        Task { await umami?.reportStopViewed(name: name, id: id, stopDistance: stopDistance) }
    }

    @objc public func reportSetRegion(_ name: String) {
        setUserProperty(key: "RegionName", value: name)
    }

    @objc public func setReportingEnabled(_ enabled: Bool) {
        reportingState.set(enabled)
        userDefaults.set(enabled, forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey)
        firebaseAnalytics?.setReportingEnabled(enabled)
        if enabled, let currentRegion {
            // Settings saves as the switch flips, so off-then-on in one visit is
            // normal; without this Umami stayed off until relaunch.
            updateServer(region: currentRegion)
            // The rebuilt Umami starts with empty default properties; restore the
            // region name that `Application` set on the old instance after `updateServer`.
            reportSetRegion(currentRegion.name)
        } else if !enabled {
            umami = nil
        }
    }

    @objc nonisolated public func reportingEnabled() -> Bool {
        reportingState.value
    }

    @objc public func setUserProperty(key: String, value: String?) {
        firebaseAnalytics?.setUserProperty(key: key, value: value)
        umami?.setUserProperty(key: key, value: value)
    }
}
