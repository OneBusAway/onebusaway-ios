//
//  AppConfigTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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

    func testAppConfig_creation_propertiesWork() {
        let queue = OperationQueue()

        let locationManager = MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locationManager)
        let analytics = AnalyticsMock()
        let dataLoader = MockDataLoader(testName: name)

        let appConfig = AppConfig(regionsBaseURL: regionsBaseURL, obacoBaseURL: obacoBaseURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: analytics, queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: dataLoader)

        expect(appConfig.regionsBaseURL) == regionsBaseURL
        expect(appConfig.obacoBaseURL) == obacoBaseURL
        expect(appConfig.apiKey) == apiKey
        expect(appConfig.appVersion) == appVersion
        expect(appConfig.queue) == queue
        expect(appConfig.userDefaults) == userDefaults
    }
}
