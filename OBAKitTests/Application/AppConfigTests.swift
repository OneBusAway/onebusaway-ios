//
//  AppConfigTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/23/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

import Foundation
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import CoreLocation
import Nimble

class AppConfigTests: OBATestCase {
    let regionsBaseURL = URL(string: "http://www.example.com")!
    let obacoBaseURL = URL(string: "http://www.example.com")!
    let apiKey = "apikey"
    let uuid = "uuid-string"
    let appVersion = "app-version"

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testAppConfig_creation_propertiesWork() {
        let queue = OperationQueue()

        let locationManager = MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(locationManager: locationManager)
        let analytics = AnalyticsMock()
        let appConfig = AppConfig(regionsBaseURL: regionsBaseURL, obacoBaseURL: obacoBaseURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: analytics, queue: queue, locationService: locationService)

        expect(appConfig.regionsBaseURL) == regionsBaseURL
        expect(appConfig.obacoBaseURL) == obacoBaseURL
        expect(appConfig.apiKey) == apiKey
        expect(appConfig.appVersion) == appVersion
        expect(appConfig.queue) == queue
        expect(appConfig.userDefaults) == userDefaults
    }
}
