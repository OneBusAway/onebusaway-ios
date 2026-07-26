//
//  StopViewModelEnvironment.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// The narrow slice of `Application` that `StopViewModel` actually uses.
///
/// `Application` conforms via a retroactive extension below. The protocol boundary
/// makes `StopViewModel` testable and previewable without a full `Application` stack.
@MainActor
protocol StopViewModelEnvironment: AnyObject {

    // MARK: - Networking services (all optional so nil = no-op in stubs)

    var apiService: RESTAPIService? { get }
    var obacoService: ObacoAPIService? { get }
    var pushService: PushService? { get }
    /// Needed to construct `SurveyOrchestrator` and `ExternalSurveyLauncher`.
    var surveyService: SurveyService { get }

    // MARK: - Alarm data (individual operations, not the full UserDataStore)

    var userAlarms: [Alarm] { get }
    func addAlarm(_ alarm: Alarm)
    func deleteAlarm(_ alarm: Alarm)
    func deleteExpiredAlarms()
    func recordRecentStop(_ stop: Stop, region: Region)
    var defaultAlarmLeadTimeMinutes: Int { get }
    var walkingSpeedMetersPerSecond: CLLocationSpeed { get }

    // MARK: - Stop preferences (individual operations, not the full StopPreferencesStore)

    func stopPreferences(stopID: StopID, region: Region) -> StopPreferences
    func setStopPreferences(_ prefs: StopPreferences, stop: Stop, region: Region)
    func hasStopPreferences(stopID: StopID, region: Region) -> Bool

    // MARK: - Scalar extractions (avoid concrete service types in the protocol)

    /// `locationService.currentLocation`
    var currentUserLocation: CLLocation? { get }
    /// `donationsManager.shouldRequestDonations`
    var shouldRequestDonations: Bool { get }
    /// `features.obaco`
    var obacoFeatureStatus: Application.FeatureStatus { get }
    /// `features.push`
    var pushFeatureStatus: Application.FeatureStatus { get }

    /// Counts successful real-time stop views toward the feedback prompt.
    var reviewPromptPolicy: ReviewPromptPolicy { get }

    /// Records that a stop load failed, suppressing the feedback prompt for the
    /// rest of this foreground session.
    func noteStopLoadFailed()

    /// Shared interruption budget, so survey engagement defers the feedback prompt.
    var promptCoordinator: PromptCoordinator { get }

    // MARK: - Utilities

    var analytics: Analytics? { get }
    var formatters: Formatters { get }
    var currentRegion: Region? { get }
    var currentRegionName: String? { get }
    var isCellularDataRestricted: Bool { get }
}

// MARK: - Application conformance

extension Application: StopViewModelEnvironment {

    var userAlarms: [Alarm] { userDataStore.alarms }
    func addAlarm(_ alarm: Alarm) { userDataStore.add(alarm: alarm) }
    func deleteAlarm(_ alarm: Alarm) { userDataStore.delete(alarm: alarm) }
    func deleteExpiredAlarms() { userDataStore.deleteExpiredAlarms() }
    func recordRecentStop(_ stop: Stop, region: Region) { userDataStore.addRecentStop(stop, region: region) }
    var defaultAlarmLeadTimeMinutes: Int { userDataStore.defaultAlarmLeadTimeMinutes }
    var walkingSpeedMetersPerSecond: CLLocationSpeed { userDataStore.walkingSpeedMetersPerSecond }

    func stopPreferences(stopID: StopID, region: Region) -> StopPreferences {
        stopPreferencesDataStore.preferences(stopID: stopID, region: region)
    }
    func setStopPreferences(_ prefs: StopPreferences, stop: Stop, region: Region) {
        stopPreferencesDataStore.set(stopPreferences: prefs, stop: stop, region: region)
    }
    func hasStopPreferences(stopID: StopID, region: Region) -> Bool {
        stopPreferencesDataStore.hasPreferences(stopID: stopID, region: region)
    }

    var currentUserLocation: CLLocation? { locationService.currentLocation }

    var shouldRequestDonations: Bool {
        // `canShowInlineCards()` is session-scoped and flipped by an event that
        // fires at most once per session, so reading it from a property the stop
        // page re-evaluates on every refresh tick is safe — it can't erase a card
        // the rider is currently looking at mid-view.
        donationsManager.shouldRequestDonations && promptCoordinator.canShowInlineCards()
    }

    var obacoFeatureStatus: Application.FeatureStatus { features.obaco }
    var pushFeatureStatus: Application.FeatureStatus { features.push }

    func noteStopLoadFailed() { promptCoordinator.sawErrorThisSession = true }
}

// MARK: - Preview stub

#if DEBUG
/// Lightweight environment for SwiftUI previews. All networking services return
/// `nil` so no fetches fire; the view model stays in its initial loading state,
/// which is the right starting point for previewing sheet-mode chrome.
@MainActor
final class PreviewStopViewModelEnvironment: StopViewModelEnvironment {

    let apiService: RESTAPIService? = nil
    let obacoService: ObacoAPIService? = nil
    let pushService: PushService? = nil

    lazy var surveyService = SurveyService(
        apiService: nil,
        userDataStore: UserDefaultsStore(userDefaults: .standard)
    )

    var userAlarms: [Alarm] = []
    func addAlarm(_ alarm: Alarm) {}
    func deleteAlarm(_ alarm: Alarm) {}
    func deleteExpiredAlarms() {}
    func recordRecentStop(_ stop: Stop, region: Region) {}
    var defaultAlarmLeadTimeMinutes: Int { 2 }
    var walkingSpeedMetersPerSecond: CLLocationSpeed { 1.4 }

    func stopPreferences(stopID: StopID, region: Region) -> StopPreferences { .init() }
    func setStopPreferences(_ prefs: StopPreferences, stop: Stop, region: Region) {}
    func hasStopPreferences(stopID: StopID, region: Region) -> Bool { false }

    var currentUserLocation: CLLocation? { nil }
    var shouldRequestDonations: Bool { false }
    var obacoFeatureStatus: Application.FeatureStatus { .off }
    var pushFeatureStatus: Application.FeatureStatus { .off }

    lazy var reviewPromptPolicy = ReviewPromptPolicy(
        userDefaults: UserDefaults(suiteName: "StopViewModelPreview")!
    )
    func noteStopLoadFailed() {}

    lazy var promptCoordinator = PromptCoordinator(
        userDefaults: UserDefaults(suiteName: "StopViewModelPreview")!
    )

    var analytics: Analytics? { nil }
    var formatters = Formatters(
        locale: .autoupdatingCurrent,
        calendar: .autoupdatingCurrent,
        themeColors: .shared
    )
    var currentRegion: Region? { nil }
    var currentRegionName: String? { nil }
    var isCellularDataRestricted: Bool { false }
}
#endif
