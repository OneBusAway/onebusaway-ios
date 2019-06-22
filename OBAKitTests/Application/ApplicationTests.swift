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
import CoreLocation
import Nimble

// swiftlint:disable large_tuple

class TestAppDelegate: ApplicationDelegate {
    func canOpenURL(_ url: URL) -> Bool {
        return false
    }

    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {
        //
    }

    var called_applicationDisplayRegionPicker = false
    func application(_ app: Application, displayRegionPicker picker: RegionPickerViewController) {
        called_applicationDisplayRegionPicker = true
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
    let regionsBaseURL = URL(string: "http://www.example.com")!
    let apiKey = "apikey"
    let uuid = "uuid-string"
    let appVersion = "app-version"
    let queue = OperationQueue()

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()

        queue.cancelAllOperations()
    }

    // MARK: - When location has already been authorized

    func configureAuthorizedObjects() -> (AuthorizedMockLocationManager, LocationService, AppConfig) {
        let locManager = AuthorizedMockLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsBaseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, userDefaults: userDefaults, queue: queue, locationService: locationService)

        return (locManager, locationService, config)
    }

    func test_appCreation_locationAlreadyAuthorized_updatesLocation() {
        let (locManager, _, config) = configureAuthorizedObjects()

        expect(locManager.updatingLocation).to(beFalse())
        expect(locManager.updatingHeading).to(beFalse())

        _ = Application(config: config)

        // Creating the Application object causes location updates to begin if the app is authorized.
        expect(locManager.updatingLocation).to(beTrue())
        expect(locManager.updatingHeading).to(beTrue())
    }

    func test_appCreation_locationAlreadyAuthorized_regionAvailable_createsRESTAPIModelService() {
        let (_, locService, config) = configureAuthorizedObjects()
        locService.startUpdates()

        let regionsService = config.regionsService

        let currentRegion = regionsService.currentRegion
        expect(currentRegion).toNot(beNil())

        let app = Application(config: config)

        expect(app.restAPIModelService).toNot(beNil())
    }

    // MARK: - When location not been authorized

    func test_app_locationNotDetermined_init() {
        let locManager = LocationManagerMock()
        let locationService = LocationService(locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsBaseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, userDefaults: userDefaults, queue: queue, locationService: locationService)

        expect(locationService.isLocationUseAuthorized).to(beFalse())

        let app = Application(config: config)

        expect(locManager.locationUpdatesStarted).to(beFalse())
        expect(locManager.headingUpdatesStarted).to(beFalse())

        expect(app.restAPIModelService).to(beNil())
    }

    func test_app_locationNewlyAuthorized() {
        let locManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(locationManager: locManager)
        let config = AppConfig(regionsBaseURL: regionsBaseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, userDefaults: userDefaults, queue: queue, locationService: locationService)
        let appDelegate = TestAppDelegate()

        expect(locationService.isLocationUseAuthorized).to(beFalse())

        let app = Application(config: config)
        app.delegate = appDelegate

        expect(locManager.locationUpdatesStarted).to(beFalse())
        expect(locManager.headingUpdatesStarted).to(beFalse())

        expect(app.restAPIModelService).to(beNil())

        locationService.requestInUseAuthorization()
        waitUntil { (done) in
            expect(appDelegate.called_applicationReloadRootInterface).to(beTrue())

            expect(locManager.locationUpdatesStarted).to(beTrue())
            expect(locManager.headingUpdatesStarted).to(beTrue())
            expect(app.restAPIModelService).toNot(beNil())

            done()
        }
    }
}
