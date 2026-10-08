//
//  SettingsViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import HealthKit
import Observation
import OBAKitCore

/// State and rules for the Settings screen.
///
/// Every setting is seeded from where it's stored in `init`, and written back the
/// moment it changes. Seeding in `init` is what keeps opening Settings free of side
/// effects: `didSet` doesn't run there, so no HealthKit sync starts, no source is
/// downgraded and no toast appears until the rider actually flips a switch (#1458.2).
/// Writing on change means nothing is lost when the rider kills the app to make an
/// Experimental or Debug setting take effect.
@MainActor
@Observable
final class SettingsViewModel {

    @ObservationIgnored private let application: Application

    /// Shows an error toast. Set by the hosting controller, which owns the toast UI.
    @ObservationIgnored var showErrorToast: (String) -> Void = { _ in }

    /// Identifies the latest HealthKit sync per switch. Minted on every toggle-on; a
    /// stale completion (off → on while an older sync was still in flight) sees a
    /// mismatched ID and leaves the switch and toast alone.
    @ObservationIgnored private var walkingHealthKitSyncID = 0
    @ObservationIgnored private var bikeHealthKitSyncID = 0

    // MARK: - Static Context

    /// Whether the HealthKit switches are offered at all.
    let isHealthKitAvailable: Bool

    /// Whether the Privacy section is shown: there's nothing to opt out of without analytics.
    let hasAnalytics: Bool

    /// Whether this build can deliberately crash, for the Debug section's crash row.
    let canCrash: Bool

    /// Data from an older app version is waiting to be migrated.
    let hasDataToMigrate: Bool

    /// The push service's user ID, or `nil` if push isn't set up.
    let pushUserID: String?

    /// Map layers offered as switches, in display order.
    let mapLayers: [(id: String, title: String)]

    // MARK: - Init

    init(application: Application, isHealthKitAvailable: Bool = HKHealthStore.isHealthDataAvailable()) {
        self.application = application
        self.isHealthKitAvailable = isHealthKitAvailable

        let defaults = application.userDefaults
        let store = application.userDataStore
        let mapRegionManager = application.mapRegionManager

        hasAnalytics = application.analytics != nil
        canCrash = application.shouldShowCrashButton
        hasDataToMigrate = application.hasDataToMigrate
        pushUserID = application.pushService?.pushUserID

        mapShowsScale = mapRegionManager.mapViewShowsScale
        mapShowsTraffic = mapRegionManager.mapViewShowsTraffic
        mapShowsHeading = mapRegionManager.mapViewShowsHeading
        mapShowsPointsOfInterest = mapRegionManager.mapViewShowsPointsOfInterest
        let layers = mapRegionManager.mapLayers.filter { $0.availability != .unsupported }
        mapLayers = layers.map { (id: $0.id, title: $0.title) }
        mapLayerEnabled = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, mapRegionManager.isMapLayerEnabled(id: $0.id)) })

        arrivalDepartureFilter = application.effectiveArrivalDepartureFilter
        showsTransferArrivalBanner = store.showTransferArrivalBanner
        showsRegionTimeZone = store.showRegionTimeZone

        usesMapPanelExperience = defaults.bool(forKey: FeatureFlags.useMapPanelExperienceKey)
        usesNewStopPage = FeatureFlags.isNewStopPageEnabled(userDefaults: defaults)

        hapticFeedbackOnReload = defaults.bool(forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)
        alwaysShowsFullSheetOnVoiceOver = defaults.bool(forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey)
        showsStopAnnotationLabels = defaults.bool(forKey: MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey)
        reducesStopColors = store.stopUIReducedColors
        compactsStopAndTripPages = store.stopTripCompactMode

        walkingSpeed = WalkingSpeedPreset.nearest(to: store.walkingSpeedMetersPerSecond)
        walkingSpeedUsesHealthKit = store.walkingSpeedSource == .healthKit

        bikeModeEnabled = store.bikeModeEnabled
        bikeSpeedUsesHealthKit = store.bikeSpeedSource == .healthKit

        alwaysShowsSurveysOnStops = store.alwaysShowSurveysOnStops
        reportingEnabled = application.analytics?.reportingEnabled() ?? false

        alwaysShowsFeedbackPrompt = application.reviewPromptPolicy.alwaysShowPrompt

        debugMode = store.debugMode
        alwaysRefreshesRegionsOnLaunch = defaults.bool(forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey)
        testDeviceName = defaults.string(forKey: PushRegistrationManager.testDeviceDescriptionDefaultsKey) ?? ""
        displaysTestAlerts = defaults.bool(forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
    }

    // MARK: - Map

    var mapShowsScale: Bool {
        didSet { application.mapRegionManager.mapViewShowsScale = mapShowsScale }
    }

    var mapShowsTraffic: Bool {
        didSet { application.mapRegionManager.mapViewShowsTraffic = mapShowsTraffic }
    }

    var mapShowsHeading: Bool {
        didSet { application.mapRegionManager.mapViewShowsHeading = mapShowsHeading }
    }

    /// Mirrors the Map sheet's Points of Interest toggle (#1246); the Map sheet is canonical.
    var mapShowsPointsOfInterest: Bool {
        didSet { application.mapRegionManager.mapViewShowsPointsOfInterest = mapShowsPointsOfInterest }
    }

    /// Map layer switches mirror the Map sheet, through the same `MapRegionManager`
    /// storage. The Map sheet is canonical; Settings does not own this state.
    private(set) var mapLayerEnabled: [String: Bool]

    func setMapLayer(_ id: String, enabled: Bool) {
        mapLayerEnabled[id] = enabled
        application.mapRegionManager.setMapLayerEnabled(enabled, id: id)
    }

    // MARK: - Arrival & Departure Display

    var arrivalDepartureFilter: ArrivalDepartureFilter {
        didSet { application.setArrivalDepartureFilter(arrivalDepartureFilter) }
    }

    var showsTransferArrivalBanner: Bool {
        didSet { application.userDataStore.showTransferArrivalBanner = showsTransferArrivalBanner }
    }

    var showsRegionTimeZone: Bool {
        didSet {
            guard showsRegionTimeZone != oldValue else { return }
            application.setShowRegionTimeZone(showsRegionTimeZone)
        }
    }

    // MARK: - Experimental

    var usesMapPanelExperience: Bool {
        didSet { application.userDefaults.set(usesMapPanelExperience, forKey: FeatureFlags.useMapPanelExperienceKey) }
    }

    var usesNewStopPage: Bool {
        didSet { application.userDefaults.set(usesNewStopPage, forKey: FeatureFlags.useNewStopPageKey) }
    }

    // MARK: - Accessibility

    var hapticFeedbackOnReload: Bool {
        didSet { application.userDefaults.set(hapticFeedbackOnReload, forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey) }
    }

    var alwaysShowsFullSheetOnVoiceOver: Bool {
        didSet { application.userDefaults.set(alwaysShowsFullSheetOnVoiceOver, forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey) }
    }

    var showsStopAnnotationLabels: Bool {
        didSet { application.userDefaults.set(showsStopAnnotationLabels, forKey: MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey) }
    }

    var reducesStopColors: Bool {
        didSet { application.userDataStore.stopUIReducedColors = reducesStopColors }
    }

    var compactsStopAndTripPages: Bool {
        didSet { application.userDataStore.stopTripCompactMode = compactsStopAndTripPages }
    }

    // MARK: - Walking Speed

    /// The manual speed. Read-only in the UI while `walkingSpeedUsesHealthKit` is on.
    var walkingSpeed: WalkingSpeedPreset {
        didSet { saveWalkingSpeed() }
    }

    var walkingSpeedUsesHealthKit: Bool {
        didSet {
            guard walkingSpeedUsesHealthKit != oldValue else { return }
            if walkingSpeedUsesHealthKit {
                syncWalkingSpeedFromHealthKit()
            } else {
                // Invalidate a sync still in flight before persisting `.manual`, so its
                // trailing write can't resurrect `.healthKit` (#1458.3).
                application.walkingSpeedManager.cancelPendingSync()
            }
            saveWalkingSpeed()
        }
    }

    private func saveWalkingSpeed() {
        let store = application.userDataStore
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: store.walkingSpeedSource,
            currentSpeed: store.walkingSpeedMetersPerSecond,
            useHealthKit: isHealthKitAvailable ? walkingSpeedUsesHealthKit : nil,
            segmentSpeed: walkingSpeed.rawValue
        )
        store.walkingSpeedSource = decision.source
        store.walkingSpeedMetersPerSecond = decision.speed
        // Turning HealthKit off snaps the speed to a preset; show the one it snapped to.
        let preset = WalkingSpeedPreset.nearest(to: decision.speed)
        if preset != walkingSpeed { walkingSpeed = preset }
    }

    private func syncWalkingSpeedFromHealthKit() {
        walkingHealthKitSyncID += 1
        let syncID = walkingHealthKitSyncID
        Task {
            let granted = await application.walkingSpeedManager.requestHealthKitAuthorizationAndSync()
            // A newer toggle-on owns the switch now; or the rider already opted
            // back out, in which case no toast is owed.
            guard !granted, syncID == walkingHealthKitSyncID, walkingSpeedUsesHealthKit else { return }
            walkingSpeedUsesHealthKit = false
            showErrorToast(OBALoc(
                "settings_controller.walking_speed.healthkit_unavailable",
                value: "Couldn't sync walking speed from Health. Check Settings > Privacy & Security > Health to allow access.",
                comment: "Settings > Walking Speed > HealthKit denial or no-data toast"
            ))
        }
    }

    // MARK: - Bike Mode

    var bikeModeEnabled: Bool {
        didSet { application.userDataStore.bikeModeEnabled = bikeModeEnabled }
    }

    var bikeSpeedUsesHealthKit: Bool {
        didSet {
            guard bikeSpeedUsesHealthKit != oldValue else { return }
            if bikeSpeedUsesHealthKit {
                // The manager writes `.healthKit` itself once a usable sample lands.
                syncBikeSpeedFromHealthKit()
            } else {
                // Cancel first so a sync in flight can't write `.healthKit` back over
                // this opt-out when it lands (#1458.3). Unlike walking there's no
                // manual speed to snap to; the stored speed stays as it is.
                application.bikeModeManager.cancelPendingSync()
                application.userDataStore.bikeSpeedSource = .manual
            }
        }
    }

    private func syncBikeSpeedFromHealthKit() {
        bikeHealthKitSyncID += 1
        let syncID = bikeHealthKitSyncID
        Task {
            let granted = await application.bikeModeManager.requestHealthKitAuthorizationAndSync()
            guard !granted, syncID == bikeHealthKitSyncID, bikeSpeedUsesHealthKit else { return }
            bikeSpeedUsesHealthKit = false
            showErrorToast(OBALoc(
                "settings_controller.bike_mode.healthkit_unavailable",
                value: "Couldn't sync cycling speed from Health. Using a standard biking speed instead.",
                comment: "Settings > Bike Mode > HealthKit denial or no-data toast"
            ))
        }
    }

    // MARK: - Surveys and Privacy

    var alwaysShowsSurveysOnStops: Bool {
        didSet { application.userDataStore.alwaysShowSurveysOnStops = alwaysShowsSurveysOnStops }
    }

    var reportingEnabled: Bool {
        didSet { application.analytics?.setReportingEnabled(reportingEnabled) }
    }

    // MARK: - Feedback (debug only)

    var alwaysShowsFeedbackPrompt: Bool {
        didSet { application.reviewPromptPolicy.alwaysShowPrompt = alwaysShowsFeedbackPrompt }
    }

    func resetFeedbackPrompt() {
        application.reviewPromptPolicy.reset()
        // Also clear the coordinator's 14-day engagement cooldown, or a reset
        // leaves QA blocked for two weeks.
        application.promptCoordinator.reset()
    }

    // MARK: - Debug

    var debugMode: Bool {
        didSet {
            application.userDataStore.debugMode = debugMode
            guard !debugMode else { return }
            // Turning Debug Mode off also turns off the debug-only behaviors it
            // exposed. The feedback override matters most: hidden with its section,
            // it would otherwise keep bypassing every prompt gate on what now looks
            // like an ordinary install.
            alwaysRefreshesRegionsOnLaunch = false
            displaysTestAlerts = false
            alwaysShowsFeedbackPrompt = false
        }
    }

    var alwaysRefreshesRegionsOnLaunch: Bool {
        didSet { application.userDefaults.set(alwaysRefreshesRegionsOnLaunch, forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey) }
    }

    /// Names this device for test push notifications.
    var testDeviceName: String {
        didSet {
            application.userDefaults.set(testDeviceName, forKey: PushRegistrationManager.testDeviceDescriptionDefaultsKey)
            // Clearing the name revokes test-device status, so test alerts go with it.
            if !hasTestDeviceName { displaysTestAlerts = false }
        }
    }

    /// Test alerts only display for a named test device (see
    /// `AgencyAlertsStore.shouldDisplayTestAlerts`), so the switch is inert without one.
    var hasTestDeviceName: Bool {
        !testDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displaysTestAlerts: Bool {
        didSet { application.userDefaults.set(displaysTestAlerts, forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts) }
    }

    func crashApp() {
        application.performTestCrash()
    }

    // MARK: - Data

    func migrateData() {
        application.performDataMigration()
    }

    /// Writes every user default to a property list for sharing.
    func exportUserDefaults() throws -> URL {
        let dict = application.userDefaults.dictionaryRepresentation()
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("userdefaults.xml")
        try data.write(to: url)
        return url
    }
}
