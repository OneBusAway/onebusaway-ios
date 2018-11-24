//
//  ApplicationTests.swift
//  OBAAppKitTests
//
//  Created by Aaron Brethorst on 11/23/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import XCTest
import OBATestHelpers
import OBANetworkingKit
import OBALocationKit
@testable import OBAAppKit
import CoreLocation
import Nimble

class ApplicationTests: OBATestCase {
    let regionsBaseURL = URL(string: "http://www.example.com")!
    let apiKey = "apikey"
    let uuid = "uuid-string"
    let appVersion = "app-version"
    var userDefaults: UserDefaults!
    let queue = OperationQueue()

    override func setUp() {
        super.setUp()

        userDefaults = UserDefaults(suiteName: "apptests")
    }

    override func tearDown() {
        super.tearDown()

        queue.cancelAllOperations()
        userDefaults.removeSuite(named: "apptests")
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
        let (_, _, config) = configureAuthorizedObjects()

        expect(config.regionsService.currentRegion).toNot(beNil())

        let app = Application(config: config)

        expect(app.restAPIModelService).toNot(beNil())
    }

    // MARK: - When location not been authorized

//    func test_appCreation_locationNotDetermined_updatesLocation() {
//        let locManager =
//        let locManager = AuthorizedMockLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
//        let locationService = LocationService(locationManager: locManager)
//        let  config = AppConfig(regionsBaseURL: regionsBaseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, userDefaults: userDefaults, queue: queue, locationService: locationService)
//
//        expect(locManager.updatingLocation).to(beFalse())
//        expect(locManager.updatingHeading).to(beFalse())
//
//        _ = Application(config: config)
//
//        // Creating the Application object causes location updates to begin if the app is authorized.
//        expect(locManager.updatingLocation).to(beTrue())
//        expect(locManager.updatingHeading).to(beTrue())
//    }
}


//public extension OBATestCase {
//
//    public var regionsModelService: RegionsModelService {
//        return RegionsModelService(apiService: regionsAPIService, dataQueue: OperationQueue())
//    }
//
//    public var regionsAPIService: RegionsAPIService {
//        return RegionsAPIService(baseURL: regionsURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31")
//    }
//}
