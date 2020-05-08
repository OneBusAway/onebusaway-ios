//
//  ApplicationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/23/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import UIKit
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import CoreLocation
import Nimble

// swiftlint:disable large_tuple

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
    let obacoBaseURL = URL(string: "http://www.example.com")!
    var queue: OperationQueue!
    var dataLoader: MockDataLoader!
    var mockConnectivity: MockConnectivity!

    override func setUp() {
        super.setUp()

        mockConnectivity = MockConnectivity()

        dataLoader = MockDataLoader()

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
        let config = AppConfig(regionsBaseURL: regionsURL, obacoBaseURL: obacoBaseURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader, connectivity: mockConnectivity)

        return (locManager, locationService, config)
    }

    func test_appCreation_locationAlreadyAuthorized_updatesLocation() {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let (locManager, _, config) = configureAuthorizedObjects()

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
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let (_, locService, config) = configureAuthorizedObjects()
        locService.startUpdates()

        let app = Application(config: config)

        let regionsService = app.regionsService

        let currentRegion = regionsService.currentRegion
        expect(currentRegion).toNot(beNil())

        expect(app.restAPIService).toNot(beNil())
    }

    // MARK: - When location not been authorized

    func test_app_locationNotDetermined_init() {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = LocationManagerMock()
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)

        let config = AppConfig(regionsBaseURL: regionsURL, obacoBaseURL: obacoBaseURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader, connectivity: mockConnectivity)

        expect(locationService.isLocationUseAuthorized).to(beFalse())

        let app = Application(config: config)

        expect(locManager.locationUpdatesStarted).to(beFalse())
        expect(locManager.headingUpdatesStarted).to(beFalse())

        expect(app.restAPIService).to(beNil())
    }

    func test_app_locationNewlyAuthorized() {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsURL, obacoBaseURL: obacoBaseURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader, connectivity: mockConnectivity)
        let appDelegate = TestAppDelegate()

        expect(locationService.isLocationUseAuthorized).to(beFalse())

        let app = Application(config: config)
        app.delegate = appDelegate

        expect(locManager.locationUpdatesStarted).to(beFalse())
        expect(locManager.headingUpdatesStarted).to(beFalse())

        expect(app.restAPIService).to(beNil())

        locationService.requestInUseAuthorization()
        waitUntil { (done) in
            expect(locManager.locationUpdatesStarted).to(beTrue())
            expect(locManager.headingUpdatesStarted).to(beTrue())
            expect(app.restAPIService).toNot(beNil())

            done()
        }
    }
}
