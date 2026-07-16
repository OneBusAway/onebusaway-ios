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

@objc(OBAAnalyticsOrchestrator) public class AnalyticsOrchestrator: NSObject, OBAKit.Analytics {
    /// nonisolated(unsafe): read by the nonisolated `reportingEnabled()`;
    /// UserDefaults is documented thread-safe.
    nonisolated(unsafe) private let userDefaults: UserDefaults
    private var firebaseAnalytics: FirebaseAnalytics?
    private var plausibleAnalytics: PlausibleAnalytics?
    private var umami: UmamiAnalytics?

    @objc required public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
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
        // Rebuild per-region analytics backends from scratch on every region change.
        plausibleAnalytics = nil
        umami = nil

        guard reportingEnabled() else { return }

        if let plausibleURL = region.plausibleAnalyticsServerURL {
            plausibleAnalytics = PlausibleAnalytics(defaultDomainURL: region.OBABaseURL, analyticsServerURL: plausibleURL)
        }

        if let umamiConfig = region.umamiAnalytics {
            umami = UmamiAnalytics(serverURL: umamiConfig.url,
                                   websiteID: umamiConfig.id,
                                   hostname: region.OBABaseURL.host ?? "")
        }
    }

    @objc public func reportError(_ error: any Error) {
        firebaseAnalytics?.reportError(error)

        // TODO: figure out how to report errors to an umami/plausible-compatible destination.
    }

    @objc public func reportEvent(pageURL: String, label: String, value: Any?) {
        firebaseAnalytics?.reportEvent(label: label, value: value)
        // Independent Tasks so a stall in one backend can't delay the other.
        Task { await plausibleAnalytics?.reportEvent(pageURL: pageURL, label: label, value: value) }
        Task { await umami?.reportEvent(pageURL: pageURL, label: label, value: value) }
    }

    @objc public func reportSearchQuery(_ query: String) {
        firebaseAnalytics?.reportSearchQuery(query)

        Task { await plausibleAnalytics?.reportSearchQuery(query) }
        Task { await umami?.reportSearchQuery(query) }
    }

    @objc public func reportStopViewed(name: String, id: String, stopDistance: String) {
        firebaseAnalytics?.reportStopViewed(name: name, id: id, stopDistance: stopDistance)

        Task { await plausibleAnalytics?.reportStopViewed(name: name, id: id, stopDistance: stopDistance) }
        Task { await umami?.reportStopViewed(name: name, id: id, stopDistance: stopDistance) }
    }

    @objc public func reportSetRegion(_ name: String) {
        setUserProperty(key: "RegionName", value: name)
        // n/a for Plausible since it'll be constrained on a per-region basis by the server URL.
        // n/a for Umami (no per-region forwarding needed).
    }

    @objc public func setReportingEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey)
        firebaseAnalytics?.setReportingEnabled(enabled)
        if !enabled {
            plausibleAnalytics = nil
            umami = nil
        }
    }

    // nonisolated: called from the nonisolated DecodingErrorReporter handler;
    // only touches UserDefaults, which is thread-safe.
    @objc nonisolated public func reportingEnabled() -> Bool {
        return userDefaults.bool(forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey)
    }

    @objc public func setUserProperty(key: String, value: String?) {
        firebaseAnalytics?.setUserProperty(key: key, value: value)
        plausibleAnalytics?.setUserProperty(key: key, value: value)
        umami?.setUserProperty(key: key, value: value)
    }
}
