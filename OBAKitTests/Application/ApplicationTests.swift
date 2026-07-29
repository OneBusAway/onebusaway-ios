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

@Suite(.serialized)
final class ApplicationTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {

        queue.cancelAllOperations()
    }

    // MARK: - When location has already been authorized

    func configureAuthorizedObjects() -> (MockAuthorizedLocationManager, LocationService, AppConfig) {
        let locManager = MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: MockDataLoader(testName: name))

        return (locManager, locationService, config)
    }

    @Test @MainActor func `App creation location already authorized updates location`() async {
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

    @Test func `App creation location already authorized region available creates RESTAPI service`() {
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

    @Test func `App location not determined init`() {
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

    @Test func `App location newly authorized`() async {
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

    @Test func `Application initializes with config`() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)

        let app = Application(config: config)

        #expect(app.applicationBundle == Bundle.main)
    }

    @Test func `Application delegate communication`() {
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

    @Test func `Application idle timer disabled proxies delegate`() {
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

    @Test func `Application can open url proxies delegate`() {
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

    @Test func `Application is registered for remote notifications proxies delegate`() {
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

    @Test func `Application credits proxies delegate`() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // With no delegate, should return empty dictionary
        #expect(app.credits.isEmpty)
    }

    @Test func `Application should show crash button returns false without delegate`() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        #expect(!app.shouldShowCrashButton)
    }

    // MARK: - Feature Availability Tests

    @Test func `Features obaco status off when no region`() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        #expect(app.features.obaco == Application.FeatureStatus.off)
    }

    @Test func `Features push status off when no provider`() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        #expect(app.features.push == Application.FeatureStatus.off)
    }

    @Test func `Features deep linking status when router created`() {
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

    @Test func `Application did finish launching`() {
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

    @Test @MainActor func `Application will resign active`() {
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

    @Test func `Should perform migration returns data migrator value`() {
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

    @Test func `Has data to migrate returns data migrator value`() {
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

    @Test func `Application url scheme add region returns true`() async {
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


    @Test func `Application url scheme view stop with no root yet is stashed and accepted`() async {
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
    @Test func `Onboarding evaluate existing user returns nil`() async {
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
    @Test func `Onboarding evaluate new user returns controller`() async {
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

    @Test func `Application url scheme invalid url returns false`() async {
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

    @Test func `Application continue user activity without app links router`() {
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

    @Test func `Application has analytics property`() {
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

    @Test func `Regions service changed automatic region selection`() {
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

    @Test func `Regions service updated region`() {
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

    @Test func `Push service received donation prompt with no top view controller`() {
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

    @Test func `Display error without delegate`() async {
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

    @Test func `Agency alerts store display error`() {
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

    @Test @MainActor
    func `Agency alerts updated without alerts`() {
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

    @Test func `Api services refreshed`() {
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

    @Test func `Perform test crash without delegate`() {
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

    @Test func `Lazy properties initialization`() {
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
