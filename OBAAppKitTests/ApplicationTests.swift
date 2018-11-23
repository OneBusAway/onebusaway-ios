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

    override func setUp() {
        super.setUp()

        userDefaults = UserDefaults(suiteName: "apptests")
    }

    override func tearDown() {
        super.tearDown()

        userDefaults.removeSuite(named: "apptests")
    }

    func testFoo() {
        let queue = OperationQueue()
        let locManager = AuthorizedMockLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(locationManager: locManager)
        let appConfig = AppConfig(regionsBaseURL: regionsBaseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, userDefaults: userDefaults, queue: queue, locationService: locationService)

        // abxoxo - todo add tests

    }
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
