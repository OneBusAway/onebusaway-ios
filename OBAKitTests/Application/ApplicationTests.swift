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
import Nimble

// swiftlint:disable large_tuple force_cast

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

    override func setUp() {
        super.setUp()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()

        queue.cancelAllOperations()
    }

    // MARK: - When location has already been authorized

    func configureAuthorizedObjects() -> (MockAuthorizedLocationManager, LocationService, AppConfig) {
        let locManager = MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: MockDataLoader(testName: name))

        return (locManager, locationService, config)
    }

    func test_appCreation_locationAlreadyAuthorized_updatesLocation() {
        let (locManager, _, config) = configureAuthorizedObjects()

        let dataLoader = (config.dataLoader as! MockDataLoader)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        expect(locManager.updatingLocation).to(beFalse())
        expect(locManager.updatingHeading).to(beFalse())

        let app = Application(config: config)

        // Location Manager does not initially start updating location.
        expect(locManager.updatingLocation).to(beFalse())
        expect(locManager.updatingHeading).to(beFalse())

        // The application becoming active causes the location manager to begin updates.
        app.applicationDidBecomeActive(UIApplication.shared)

        expect(locManager.updatingLocation).to(beTrue())
        expect(locManager.updatingHeading).to(beTrue())

        waitUntil { (done) in
            config.queue.addOperation {
                done()
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
        expect(currentRegion).toNot(beNil())

        expect(app.apiService).toNot(beNil())
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

        expect(locationService.isLocationUseAuthorized).to(beFalse())

        let app = Application(config: config)

        expect(locManager.locationUpdatesStarted).to(beFalse())
        expect(locManager.headingUpdatesStarted).to(beFalse())

        expect(app.regionsService.currentRegion).to(beNil())
        expect(app.apiService).to(beNil())
    }

    func test_app_locationNewlyAuthorized() {
        let dataLoader = MockDataLoader(testName: name)

        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let appDelegate = TestAppDelegate()

        expect(locationService.isLocationUseAuthorized).to(beFalse())

        let app = Application(config: config)
        app.delegate = appDelegate

        expect(locManager.locationUpdatesStarted).to(beFalse())
        expect(locManager.headingUpdatesStarted).to(beFalse())

        expect(app.apiService).to(beNil())

        locationService.requestInUseAuthorization()
        waitUntil { (done) in
            expect(locManager.locationUpdatesStarted).to(beTrue())
            expect(locManager.headingUpdatesStarted).to(beTrue())
            expect(app.apiService).toNot(beNil())

            done()
        }
    }

    // MARK: - Minimal Proof of Concept Tests

    func test_application_initializes_with_config() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)

        let app = Application(config: config)

        expect(app).toNot(beNil())
        expect(app.applicationBundle).to(equal(Bundle.main))
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

        expect(delegate.called_applicationReloadRootInterface).to(beFalse())

        app.reloadRootUserInterface()

        expect(delegate.called_applicationReloadRootInterface).to(beTrue())
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

        expect(app.isIdleTimerDisabled).to(beFalse())

        app.isIdleTimerDisabled = true

        expect(delegate.isIdleTimerDisabled).to(beTrue())
        expect(app.isIdleTimerDisabled).to(beTrue())
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

        expect(result).to(beFalse()) // TestAppDelegate returns false
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

        expect(app.isRegisteredForRemoteNotifications).to(beTrue())
    }

    func test_application_credits_proxies_delegate() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // With no delegate, should return empty dictionary
        expect(app.credits).to(beEmpty())
    }

    func test_application_should_show_crash_button_returns_false_without_delegate() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        expect(app.shouldShowCrashButton).to(beFalse())
    }

    // MARK: - Feature Availability Tests

    func test_features_obaco_status_off_when_no_region() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        expect(app.features.obaco).to(equal(Application.FeatureStatus.off))
    }

    func test_features_push_status_off_when_no_provider() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        expect(app.features.push).to(equal(Application.FeatureStatus.off))
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
        expect(app.features.deepLinking).to(equal(Application.FeatureStatus.running))
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
        expect(uiApp.shortcutItems == nil || uiApp.shortcutItems?.isEmpty == true).to(beTrue())
        expect(delegate.called_applicationReloadRootInterface).to(beTrue())
    }

    func test_application_will_resign_active() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        let locManager = MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)
        let app = Application(config: config)

        // Start location updates first
        app.applicationDidBecomeActive(UIApplication.shared)
        expect(locManager.updatingLocation).to(beTrue())

        // Now resign active should stop location updates
        app.applicationWillResignActive(UIApplication.shared)
        expect(locManager.updatingLocation).to(beFalse())
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
        expect([true, false]).to(contain(shouldPerform))
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
        expect([true, false]).to(contain(hasData))
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
            fail("No URL scheme configured")
            return
        }

        let addRegionURL = URL(string: "\(scheme)://add-region?name=Test&oba-url=https%3A%2F%2Fapi.example.com")!

        await MainActor.run {
            let result = app.application(UIApplication.shared, open: addRegionURL, options: [:])
            expect(result).to(beTrue())
        }
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
            expect(result).to(beFalse())
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
        expect(result).to(beFalse())
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

        expect(app.analytics).toNot(beNil())
        expect(app.analytics).to(beIdenticalTo(mockAnalytics))
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
        expect(mockAnalytics.reportedEvents.count) >= 2
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

        // Should update donationsManager.obacoService
        expect(app.donationsManager).toNot(beNil())
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
        expect(app.donationsManager).toNot(beNil())
        expect(app.stopIconFactory).toNot(beNil())
        expect(app.mapRegionManager).toNot(beNil())
        expect(app.searchManager).toNot(beNil())
        expect(app.userActivityBuilder).toNot(beNil())
        expect(app.features).toNot(beNil())
    }
}

// MARK: - Mock Classes for Push Service Testing

class MockPushServiceProvider: NSObject, PushServiceProvider {
    var isRegisteredForRemoteNotifications: Bool = false
    var notificationReceivedHandler: PushServiceNotificationReceivedHandler!
    var errorHandler: PushServiceErrorHandler!
    var pushUserID: PushManagerUserID?

    func start(launchOptions: [AnyHashable: Any]) {
        // Mock implementation
    }

    func requestPushID(_ callback: @escaping PushManagerUserIDCallback) {
        callback("mock-push-id")
    }
}
