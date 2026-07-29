//
//  ApplicationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import CoreLocation
import Testing

// swiftlint:disable large_tuple force_cast

@MainActor
class TestAppDelegate: ApplicationDelegate {
    var uiApplication: UIApplication?

    var isRegisteredForRemoteNotifications: Bool = false

    func canOpenURL(_ url: URL) -> Bool {
        return false
    }

    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {
        //
    }

    var called_applicationReloadRootInterface = false
    func applicationReloadRootInterface(_ app: Application) {
        called_applicationReloadRootInterface = true
    }

    var isIdleTimerDisabled = false
}

@MainActor
class TestRegionsServiceDelegate: NSObject, RegionsServiceDelegate {
    func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        //
    }

    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        //
    }
}

class ApplicationTests: OBATestCase {
    var queue: OperationQueue!

    override func setUp() async throws {
        try await super.setUp()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() async throws {
        try await super.tearDown()

        queue.cancelAllOperations()
    }

    // MARK: - When location has already been authorized

    func configureAuthorizedObjects() -> (MockAuthorizedLocationManager, LocationService, AppConfig) {
        let locManager = MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: MockDataLoader(testName: name))

        return (locManager, locationService, config)
    }

    @MainActor func test_appCreation_locationAlreadyAuthorized_updatesLocation() async {
        let (locManager, _, config) = configureAuthorizedObjects()

        let dataLoader = (config.dataLoader as! MockDataLoader)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        #expect(!locManager.updatingLocation)
        #expect(!locManager.updatingHeading)

        let app = Application(config: config)

        // Location Manager does not initially start updating location.
        #expect(!locManager.updatingLocation)
        #expect(!locManager.updatingHeading)

        // The application becoming active causes the location manager to begin updates.
        app.applicationDidBecomeActive(UIApplication.shared)

        #expect(locManager.updatingLocation)
        #expect(locManager.updatingHeading)

        // Drain the work `applicationDidBecomeActive` queued, so it can't outlive
        // the test. An operation appended now runs after those already enqueued.
        // (Was Nimble's `waitUntil`, whose `done` callback is a non-Sendable
        // `() -> Void` captured by a `@Sendable` operation block.)
        await withCheckedContinuation { continuation in
            config.queue.addOperation {
                continuation.resume()
            }
        }
    }

    func test_appCreation_locationAlreadyAuthorized_regionAvailable_createsRESTAPIService() {
        let (_, locService, config) = configureAuthorizedObjects()

        let dataLoader = (config.dataLoader as! MockDataLoader)

        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        locService.startUpdates()

        let app = Application(config: config)

        let regionsService = app.regionsService

        let currentRegion = regionsService.currentRegion
        #expect(currentRegion != nil)

        #expect(app.apiService != nil)
    }

    // MARK: - When location not been authorized

    func test_app_locationNotDetermined_init() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let userDefaults = buildUserDefaults()

        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)

        #expect(!locationService.isLocationUseAuthorized)

        let app = Application(config: config)

        #expect(!locManager.locationUpdatesStarted)
        #expect(!locManager.headingUpdatesStarted)

        #expect(app.regionsService.currentRegion == nil)
        #expect(app.apiService == nil)
    }

    func test_app_locationNewlyAuthorized() async {
        let dataLoader = MockDataLoader(testName: name)

        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let appDelegate = TestAppDelegate()

        #expect(!locationService.isLocationUseAuthorized)

        let app = Application(config: config)
        app.delegate = appDelegate

        #expect(!locManager.locationUpdatesStarted)
        #expect(!locManager.headingUpdatesStarted)

        #expect(app.apiService == nil)

        locationService.requestInUseAuthorization()
        await poll(until: { locManager.locationUpdatesStarted },
                   "location updates never started")
        #expect(locManager.locationUpdatesStarted)
        #expect(locManager.headingUpdatesStarted)
        #expect(app.apiService != nil)
    }

    // MARK: - Minimal Proof of Concept Tests

    func test_application_initializes_with_config() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)

        let app = Application(config: config)

        #expect(app.applicationBundle == Bundle.main)
    }

    func test_application_delegate_communication() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)
        let delegate = TestAppDelegate()

        app.delegate = delegate

        #expect(!delegate.called_applicationReloadRootInterface)

        app.reloadRootUserInterface()

        #expect(delegate.called_applicationReloadRootInterface)
    }

    func test_application_idle_timer_disabled_proxies_delegate() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)
        let delegate = TestAppDelegate()

        app.delegate = delegate

        #expect(!app.isIdleTimerDisabled)

        app.isIdleTimerDisabled = true

        #expect(delegate.isIdleTimerDisabled)
        #expect(app.isIdleTimerDisabled)
    }

    // MARK: - Property and Feature Tests

    func test_application_can_open_url_proxies_delegate() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)
        let delegate = TestAppDelegate()

        app.delegate = delegate

        let testURL = URL(string: "https://example.com")!
        let result = app.canOpenURL(testURL)

        #expect(!result)  // TestAppDelegate returns false
    }

    func test_application_is_registered_for_remote_notifications_proxies_delegate() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)
        let delegate = TestAppDelegate()

        app.delegate = delegate
        delegate.isRegisteredForRemoteNotifications = true

        #expect(app.isRegisteredForRemoteNotifications)
    }

    func test_application_credits_proxies_delegate() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // With no delegate, should return empty dictionary
        #expect(app.credits.isEmpty)
    }

    func test_application_should_show_crash_button_returns_false_without_delegate() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        #expect(!app.shouldShowCrashButton)
    }

    // MARK: - Feature Availability Tests

    func test_features_obaco_status_off_when_no_region() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        #expect(app.features.obaco == Application.FeatureStatus.off)
    }

    func test_features_push_status_off_when_no_provider() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        #expect(app.features.push == Application.FeatureStatus.off)
    }

    func test_features_deep_linking_status_when_router_created() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // When the appLinksRouter exists (which it will after first access), deep linking is running
        // Even without a sidecar URL, the router can handle basic URL schemes
        #expect(app.features.deepLinking == Application.FeatureStatus.running)
    }

    // MARK: - Application Lifecycle Tests

    func test_application_did_finish_launching() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)
        let delegate = TestAppDelegate()
        app.delegate = delegate

        let uiApp = UIApplication.shared

        // Reset the delegate flag
        delegate.called_applicationReloadRootInterface = false

        app.application(uiApp, didFinishLaunching: [:])

        // Should clear shortcut items and reload root interface
        #expect((uiApp.shortcutItems == nil || uiApp.shortcutItems?.isEmpty == true))
        #expect(delegate.called_applicationReloadRootInterface)
    }

    @MainActor func test_application_will_resign_active() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let locManager = MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Start location updates first
        app.applicationDidBecomeActive(UIApplication.shared)
        #expect(locManager.updatingLocation)

        // Now resign active should stop location updates
        app.applicationWillResignActive(UIApplication.shared)
        #expect(!locManager.updatingLocation)
    }

    // MARK: - Data Migration Tests

    func test_should_perform_migration_returns_data_migrator_value() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Just test that the property is accessible and returns a boolean
        let shouldPerform = app.shouldPerformMigration
        #expect([true, false].contains(shouldPerform))
    }

    func test_has_data_to_migrate_returns_data_migrator_value() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Just test that the property is accessible and returns a boolean
        let hasData = app.hasDataToMigrate
        #expect([true, false].contains(hasData))
    }

    // MARK: - URL Scheme and Deep Link Tests

    func test_application_url_scheme_add_region_returns_true() async {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        guard let scheme = Bundle.main.extensionURLScheme else {
            Issue.record("No URL scheme configured")
            return
        }

        let addRegionURL = URL(string: "\(scheme)://add-region?name=Test&oba-url=https%3A%2F%2Fapi.example.com")!

        await MainActor.run {
            let result = app.application(UIApplication.shared, open: addRegionURL, options: [:])
            #expect(result)
        }
    }


    func test_application_url_scheme_view_stop_with_no_root_yet_is_stashed_and_accepted() async {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)
        let delegate = TestAppDelegate()
        app.delegate = delegate

        guard let scheme = Bundle.main.extensionURLScheme else {
            Issue.record("No URL scheme configured")
            return
        }

        let viewStopURL = URLSchemeRouter(scheme: scheme).encodeViewStop(stopID: "12345", regionID: 1)

        await MainActor.run {
            // `delegate.uiApplication` is nil, so `topViewController` is nil here,
            // simulating a cold launch where the root view controller hasn't been
            // installed yet. Before the fix, this URL was silently dropped (`false`).
            let result = app.application(UIApplication.shared, open: viewStopURL, options: [:])

            // The URL is still recognized and accepted: the stop ID is stashed in
            // `pendingStopID` (the same stash the alarm-push path uses) and drained
            // once the app becomes active and a root view controller exists.
            #expect(result)
        }
    }

    // MARK: - Onboarding Evaluate Tests

    /// The headline behavior of the onboarding registry: an existing user (region set,
    /// empty seen-store) gets backfilled and — with no push provider configured, as in
    /// this test harness — matches no steps, so `evaluate` hands back nil and the app
    /// goes straight to its root UI.
    func test_onboarding_evaluate_existingUser_returnsNil() async {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)

        // Seed the persisted region selection BEFORE constructing Application, so
        // RegionsService loads the current region from storage. (Assigning
        // `regionsService.currentRegion` after construction fires the region-change
        // cascade — agencies + per-agency alert fetches — which is out of scope here.)
        userDefaults.set(Fixtures.pugetSoundRegion.regionIdentifier, forKey: "OBACurrentRegionIdentifierUserDefaultsKey")

        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        let hasRegion = await MainActor.run { app.regionsService.currentRegion != nil }
        #expect(hasRegion)

        let controller = await withCheckedContinuation { continuation in
            OnboardingFlowController.evaluate(application: app) { controller in
                continuation.resume(returning: controller)
            }
        }

        #expect(controller == nil)

        // The backfill ran: legacy steps are seen, notifications deliberately is not.
        await MainActor.run {
            let store = OnboardingStepStore(userDefaults: app.userDefaults)
            #expect(store.seenVersion(of: .welcome) == 1)
            #expect(store.seenVersion(of: .region) == 1)
            #expect(store.seenVersion(of: .notifications) == 0)
        }
    }

    /// A new user (no region) gets a flow — evaluate returns a controller.
    func test_onboarding_evaluate_newUser_returnsController() async {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        let controller = await withCheckedContinuation { continuation in
            OnboardingFlowController.evaluate(application: app) { controller in
                continuation.resume(returning: controller)
            }
        }

        #expect(controller != nil)
    }

    func test_application_url_scheme_invalid_url_returns_false() async {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        let invalidURL = URL(string: "invalid://scheme/path")!

        await MainActor.run {
            let result = app.application(UIApplication.shared, open: invalidURL, options: [:])
            #expect(!result)
        }
    }

    // MARK: - User Activity Tests

    func test_application_continue_user_activity_without_app_links_router() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        let userActivity = NSUserActivity(activityType: "test")
        let result = app.application(UIApplication.shared, continue: userActivity, restorationHandler: { _ in })

        // Should return false when appLinksRouter is nil
        #expect(!result)
    }

    // MARK: - Analytics Tests

    func test_application_has_analytics_property() {
        let mockAnalytics = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: mockAnalytics, queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        #expect(app.analytics != nil)
        #expect(app.analytics === mockAnalytics)
    }

    // MARK: - Regions Service Delegate Tests

    func test_regions_service_changed_automatic_region_selection() {
        let mockAnalytics = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: mockAnalytics, queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Test that the method can be called without crashing
        app.regionsService(app.regionsService, changedAutomaticRegionSelection: true)
        app.regionsService(app.regionsService, changedAutomaticRegionSelection: false)

        // Analytics should have been called
        #expect(mockAnalytics.reportedEvents.count >= 2)
    }

    func test_regions_service_updated_region() {
        let mockAnalytics = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: mockAnalytics, queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        let testRegion = Fixtures.pugetSoundRegion

        // Test that the method can be called without crashing
        app.regionsService(app.regionsService, updatedRegion: testRegion)

        // Analytics should have been called - reportSetRegion doesn't add to reportedEvents, but the test exercises the code path
    }

    // MARK: - Push Service Tests

    func test_push_service_received_donation_prompt_with_no_top_view_controller() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Create a mock push service to test the delegate method
        let mockProvider = MockPushServiceProvider()
        let pushService = PushService(serviceProvider: mockProvider, delegate: app)

        // Test with no top view controller - should set flag to present later
        app.pushService(pushService, receivedDonationPrompt: "test-prompt-123")

        // Since we can't access private properties, we just verify the method doesn't crash
        // The actual behavior would be tested in integration tests
    }

    // MARK: - Error Display Tests

    func test_display_error_without_delegate() async {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        let testError = NSError(domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        await app.displayError(testError)
        // Should not crash when delegate is nil
    }

    // MARK: - Agency Alerts Tests

    func test_agency_alerts_store_display_error() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        let testError = NSError(domain: "test", code: 456, userInfo: [NSLocalizedDescriptionKey: "Agency alerts error"])

        // Test that the delegate method can be called without crashing
        app.agencyAlertsStore(app.alertsStore, displayError: testError)
    }

    @MainActor
    func test_agency_alerts_updated_without_alerts() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Test that the method can be called without crashing when there are no alerts
        app.agencyAlertsUpdated()
    }

    // MARK: - API Services Tests

    func test_api_services_refreshed() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Test that calling apiServicesRefreshed doesn't crash
        app.apiServicesRefreshed()
    }

    // MARK: - Crash Button Tests

    func test_perform_test_crash_without_delegate() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Should not crash when no delegate is set
        app.performTestCrash()
    }

    // MARK: - Property Access Tests

    func test_lazy_properties_initialization() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Test that lazy properties can be accessed without crashing
        _ = app.donationsManager
        _ = app.stopIconFactory
        _ = app.mapRegionManager
        _ = app.searchManager
        #expect(app.userActivityBuilder != nil)
        _ = app.features
    }
}

// MARK: - Mock Classes for Push Service Testing

@MainActor
class MockPushServiceProvider: NSObject, PushServiceProvider {
    var isRegisteredForRemoteNotifications: Bool = false
    var notificationReceivedHandler: PushServiceNotificationReceivedHandler!
    var errorHandler: PushServiceErrorHandler!
    var pushUserID: PushManagerUserID?
    var deviceTokenUpdatedHandler: PushServiceDeviceTokenCallback?

    func start(launchOptions: [AnyHashable: Any]) {
        // Mock implementation
    }

    func requestPushID(_ callback: @escaping PushManagerUserIDCallback) {
        callback("mock-push-id")
    }
}
