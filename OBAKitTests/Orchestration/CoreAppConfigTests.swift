//
//  CoreAppConfigTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
@MainActor
final class CoreAppConfigTests {

    @Test func `Initialization sets properties correctly`() {
        let userDefaults = UserDefaults(suiteName: "org.opentransit.onebusaway-ios.CoreAppConfigTests")!
        let queue = OperationQueue()
        let locService = LocationService(userDefaults: userDefaults, locationManager: CLLocationManager())
        let dataLoader = URLSession.shared
        
        let url = URL(string: "https://regions.onebusaway.org")!
        
        let config = CoreAppConfig(
            regionsBaseURL: url,
            apiKey: "TEST_API_KEY",
            appVersion: "1.0.0",
            userDefaults: userDefaults,
            queue: queue,
            locationService: locService,
            bundledRegionsFilePath: "test_regions.json",
            regionsAPIPath: "/regions",
            dataLoader: dataLoader,
            fixedRegionName: "Puget Sound",
            fixedRegionOBABaseURL: URL(string: "https://api.pugetsound.onebusaway.org"),
            defaultArrivalDepartureFilter: .all
        )
        
        #expect(config.regionsBaseURL == url)
        #expect(config.apiKey == "TEST_API_KEY")
        #expect(config.appVersion == "1.0.0")
        #expect(config.bundledRegionsFilePath == "test_regions.json")
        #expect(config.regionsAPIPath == "/regions")
        #expect(config.fixedRegionName == "Puget Sound")
        #expect(config.fixedRegionOBABaseURL?.absoluteString == "https://api.pugetsound.onebusaway.org")
        #expect(config.defaultArrivalDepartureFilter == .all)
    }
}