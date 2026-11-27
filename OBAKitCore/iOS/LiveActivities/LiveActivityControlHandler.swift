//
//  LiveActivityControlHandler.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import ActivityKit
import Foundation

/// ActivityKit-decoupled control logic and localized labels for the interactive
/// Refresh and End buttons on the Live Activity Lock Screen card.
///
/// Lives in `OBAKitCore/iOS/LiveActivities/` so both `OBAWidget` (via `LiveActivityIntent`)
/// and `OBAKitTests` can share and test it without `OBAKitCore` importing `AppIntents`
/// or `WidgetKit`.
public struct LiveActivityControlHandler: Sendable {
    public typealias EndActivity = @Sendable (_ activityID: String, _ dismissalPolicy: ActivityUIDismissalPolicy) async -> Bool
    public typealias OnDidEnd = @Sendable (_ activityID: String, _ regionID: Int) async -> Void
    public typealias LoadStaticData = @Sendable (_ activityID: String) -> TripAttributes.StaticData?
    public typealias FetchStopArrivals = @Sendable (_ stopID: StopID, _ regionID: Int) async throws -> [ArrivalDeparture]
    public typealias UpdateActivity = @Sendable (_ activityID: String, _ state: TripAttributes.ContentState, _ staleDate: Date?) async -> Bool

    public enum EndResult: Equatable, Sendable {
        case ended
        case notFound
    }

    public enum RefreshResult: Equatable, Sendable {
        case updated(TripAttributes.ContentState, staleDate: Date)
        case notFound
        case missingConfiguration
        case noMatchingArrivals
        case failed
    }

    private enum ConfigurationError: Error {
        case missingUserDefaults
        case missingAPIKey
        case missingRegion
    }

    /// Interactive End always dismisses immediately so the card leaves the Lock Screen
    /// right when the rider taps End.
    public static let endDismissalPolicy: ActivityUIDismissalPolicy = .immediate

    /// Default freshness window applied when a rider manually refreshes a Live Activity.
    public static let defaultRefreshStaleInterval: TimeInterval = 5 * 60

    // MARK: - Localized Labels

    public static var refreshTitle: String {
        Strings.refresh
    }

    public static var endTitle: String {
        OBALoc(
            "live_activity.end",
            value: "End",
            comment: "Button on a Live Activity Lock Screen card that stops tracking and dismisses the Live Activity."
        )
    }

    public static var refreshAccessibilityLabel: String {
        OBALoc(
            "live_activity.a11y_refresh",
            value: "Refresh arrivals",
            comment: "VoiceOver accessibility label for the Refresh button on a Live Activity card."
        )
    }

    public static var endAccessibilityLabel: String {
        OBALoc(
            "live_activity.a11y_end",
            value: "End Live Activity",
            comment: "VoiceOver accessibility label for the End button on a Live Activity card."
        )
    }

    // MARK: - Dependencies

    private let endActivity: EndActivity
    private let onDidEnd: OnDidEnd?
    private let loadStaticData: LoadStaticData
    private let fetchStopArrivals: FetchStopArrivals
    private let updateActivity: UpdateActivity
    private let staleInterval: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        endActivity: @escaping EndActivity = liveEndActivity,
        onDidEnd: OnDidEnd? = nil,
        loadStaticData: @escaping LoadStaticData = liveLoadStaticData,
        fetchStopArrivals: @escaping FetchStopArrivals,
        updateActivity: @escaping UpdateActivity = liveUpdateActivity,
        staleInterval: TimeInterval = defaultRefreshStaleInterval,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.endActivity = endActivity
        self.onDidEnd = onDidEnd
        self.loadStaticData = loadStaticData
        self.fetchStopArrivals = fetchStopArrivals
        self.updateActivity = updateActivity
        self.staleInterval = staleInterval
        self.now = now
    }

    /// Configures a handler backed by the app group defaults and bundle settings
    /// available to either the app or widget extension process.
    public init(
        appGroupIdentifier: String?,
        bundledRegionsFilePath: String?,
        restServerAPIKey: String?,
        appVersion: String,
        dataLoader: URLDataLoader = URLSession.shared,
        staleInterval: TimeInterval = defaultRefreshStaleInterval,
        now: @escaping @Sendable () -> Date = Date.init,
        endActivity: @escaping EndActivity = liveEndActivity,
        loadStaticData: @escaping LoadStaticData = liveLoadStaticData,
        updateActivity: @escaping UpdateActivity = liveUpdateActivity
    ) {
        let trimmedAPIKey = restServerAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetch = Self.makeStopArrivalsFetcher(
            appGroupIdentifier: appGroupIdentifier,
            bundledRegionsFilePath: bundledRegionsFilePath,
            apiKey: trimmedAPIKey,
            appVersion: appVersion,
            dataLoader: dataLoader
        )
        let didEnd = Self.makeOnDidEnd(
            appGroupIdentifier: appGroupIdentifier,
            bundledRegionsFilePath: bundledRegionsFilePath,
            apiKey: trimmedAPIKey,
            appVersion: appVersion,
            dataLoader: dataLoader
        )

        self.init(
            endActivity: endActivity,
            onDidEnd: didEnd,
            loadStaticData: loadStaticData,
            fetchStopArrivals: fetch,
            updateActivity: updateActivity,
            staleInterval: staleInterval,
            now: now
        )
    }

    private static func makeStopArrivalsFetcher(
        appGroupIdentifier: String?,
        bundledRegionsFilePath: String?,
        apiKey: String?,
        appVersion: String,
        dataLoader: URLDataLoader
    ) -> FetchStopArrivals {
        { stopID, regionID in
            guard let appGroupIdentifier, let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
                throw ConfigurationError.missingUserDefaults
            }
            guard let apiKey, !apiKey.isEmpty else {
                throw ConfigurationError.missingAPIKey
            }
            guard let region = Self.resolveRegion(
                regionID: regionID,
                userDefaults: userDefaults,
                bundledRegionsFilePath: bundledRegionsFilePath
            ) else {
                throw ConfigurationError.missingRegion
            }

            let service = RESTAPIService.standalone(
                region: region,
                apiKey: apiKey,
                appVersion: appVersion,
                uuid: UserUUID.value(in: userDefaults),
                dataLoader: dataLoader
            )

            let response = try await service.getArrivalsAndDeparturesForStop(
                id: stopID,
                minutesBefore: 0,
                minutesAfter: 90,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
            return response.entry.arrivalsAndDepartures
        }
    }

    private static func makeOnDidEnd(
        appGroupIdentifier: String?,
        bundledRegionsFilePath: String?,
        apiKey: String?,
        appVersion: String,
        dataLoader: URLDataLoader
    ) -> OnDidEnd {
        { activityID, regionID in
            guard let appGroupIdentifier,
                  let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
                  let apiKey,
                  !apiKey.isEmpty else {
                return
            }

            let registry = LiveActivityRegistry(
                userDefaults: userDefaults,
                obacoServiceProvider: {
                    guard let region = Self.resolveRegion(
                        regionID: regionID,
                        userDefaults: userDefaults,
                        bundledRegionsFilePath: bundledRegionsFilePath
                    ),
                    let sidecarURL = region.sidecarBaseURL else {
                        return nil
                    }
                    let configuration = APIServiceConfiguration(
                        baseURL: sidecarURL,
                        apiKey: apiKey,
                        uuid: UserUUID.value(in: userDefaults),
                        appVersion: appVersion,
                        regionIdentifier: region.regionIdentifier
                    )
                    return ObacoAPIService(configuration, dataLoader: dataLoader)
                }
            )
            await registry.unregister(activityID: activityID)
        }
    }

    // MARK: - Actions

    @discardableResult
    public func end(activityID: String) async -> EndResult {
        guard !activityID.isEmpty else {
            return .notFound
        }

        let regionID = loadStaticData(activityID)?.regionID ?? 0

        let ended = await endActivity(activityID, Self.endDismissalPolicy)
        guard ended else {
            Logger.info("Live Activity \(activityID) not found; skipping end.")
            return .notFound
        }

        await onDidEnd?(activityID, regionID)
        Logger.info("Ended Live Activity \(activityID) with immediate dismissal.")
        return .ended
    }

    @discardableResult
    public func refresh(activityID: String) async -> RefreshResult {
        guard !activityID.isEmpty, let staticData = loadStaticData(activityID) else {
            Logger.info("Live Activity \(activityID) not found or not live; skipping refresh.")
            return .notFound
        }

        let stopArrivals: [ArrivalDeparture]
        do {
            stopArrivals = try await fetchStopArrivals(staticData.stopID, staticData.regionID)
        } catch is ConfigurationError {
            Logger.error("Live Activity \(activityID) refresh skipped: missing configuration.")
            return .missingConfiguration
        } catch {
            Logger.error("Live Activity \(activityID) refresh failed: \(error)")
            return .failed
        }

        let refreshDate = now()
        guard let contentState = Self.contentState(for: staticData, from: stopArrivals, now: refreshDate) else {
            Logger.info("Live Activity \(activityID) refresh found no matching upcoming arrivals; leaving existing content untouched.")
            return .noMatchingArrivals
        }
        let staleDate = Self.staleDate(from: refreshDate, interval: staleInterval)

        let updated = await updateActivity(activityID, contentState, staleDate)
        guard updated else {
            Logger.info("Live Activity \(activityID) ended before refresh update could apply.")
            return .notFound
        }

        Logger.info("Refreshed Live Activity \(activityID) with \(contentState.arrivals.count) arrival(s).")
        return .updated(contentState, staleDate: staleDate)
    }

    // MARK: - Pure Helpers

    /// Filters and orders upcoming arrivals from a stop response for `staticData`.
    public static func matchingUpcomingArrivals(
        for staticData: TripAttributes.StaticData,
        from stopArrivals: [ArrivalDeparture],
        now: Date = Date()
    ) -> [ArrivalDeparture] {
        TripActivityContentBuilder.matchingUpcomingArrivals(for: staticData, from: stopArrivals, now: now)
    }

    /// Maps up to the next three matching upcoming arrivals into `TripAttributes.ContentState`,
    /// returning `nil` if no matching upcoming arrivals exist.
    public static func contentState(
        for staticData: TripAttributes.StaticData,
        from stopArrivals: [ArrivalDeparture],
        now: Date = Date()
    ) -> TripAttributes.ContentState? {
        TripActivityContentBuilder.refreshContentState(for: staticData, from: stopArrivals, now: now)
    }

    public static func staleDate(from now: Date, interval: TimeInterval = defaultRefreshStaleInterval) -> Date {
        now.addingTimeInterval(interval)
    }

    public static func resolveRegion(
        regionID: Int,
        userDefaults: UserDefaults,
        bundledRegionsFilePath: String?
    ) -> Region? {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        let resolved = store.region(bundledRegionsFilePath: bundledRegionsFilePath)

        if regionID != 0 {
            if let resolved, resolved.regionIdentifier == regionID {
                return resolved
            }
            if let bundledRegionsFilePath,
               let data = FileManager.default.contents(atPath: bundledRegionsFilePath) {
                let bundled: [Region]? = if let response = try? JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[Region]>.self, from: data) {
                    response.list
                } else {
                    try? JSONDecoder.RESTDecoder().decode([Region].self, from: data)
                }
                if let match = bundled?.first(where: { $0.regionIdentifier == regionID }) {
                    return match
                }
            }
        }

        return resolved
    }

    // MARK: - Live ActivityKit Adapters

    public static func liveLoadStaticData(activityID: String) -> TripAttributes.StaticData? {
        guard let activity = Activity<TripAttributes>.activities.first(where: { $0.id == activityID }),
              LiveActivityRegistry.isLive(activity.activityState) else {
            return nil
        }
        return activity.attributes.staticData
    }

    public static func liveUpdateActivity(
        activityID: String,
        state: TripAttributes.ContentState,
        staleDate: Date?
    ) async -> Bool {
        guard let activity = Activity<TripAttributes>.activities.first(where: { $0.id == activityID }),
              LiveActivityRegistry.isLive(activity.activityState) else {
            return false
        }

        let content = TripLiveActivityRelevance.contentPreservingRelevance(
            state: state,
            staleDate: staleDate,
            existing: activity.content
        )
        await activity.update(content)
        return true
    }

    public static func liveEndActivity(
        activityID: String,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async -> Bool {
        guard let activity = Activity<TripAttributes>.activities.first(where: { $0.id == activityID }) else {
            return false
        }
        await activity.end(nil, dismissalPolicy: dismissalPolicy)
        return true
    }
}

#endif // os(iOS)
