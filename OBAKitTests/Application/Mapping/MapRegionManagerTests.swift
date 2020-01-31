//
//  MapRegionManagerTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 7/9/19.
//

import Foundation
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import Nimble

// swiftlintXdisable force_try

class MapRegionManagerTests: OBATestCase {
    let regionsBaseURL = URL(string: "http://www.example.com")!
    let obacoBaseURL = URL(string: "http://www.example.com")!
    let apiKey = "apikey"
    let appVersion = "app-version"
    let queue = OperationQueue()

    var application: Application!

    override func setUp() {
        super.setUp()

        let locManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)

        let bundledRegions = Bundle.main.path(forResource: "regions", ofType: "json")!

        let config = AppConfig(regionsBaseURL: regionsBaseURL, obacoBaseURL: obacoBaseURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegions, regionsAPIPath: "/regions-v3.json")

        expect(locationService.isLocationUseAuthorized).to(beFalse())

        application = Application(config: config)
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    func test_init() {
        let mgr = MapRegionManager(application: application)

        expect(mgr.mapView).toNot(beNil())
        expect(mgr.mapView.showsScale).to(beTrue())
        expect(mgr.mapView.showsTraffic).to(beTrue())
    }

    /// When `currentRegion` is nil, `visibleMapRect` also returns `nil`.
    func test_visibleMapRect_nilRegion() {
        let mgr = MapRegionManager(application: application)
        expect(self.application.currentRegion).to(beNil())
        expect(mgr.lastVisibleMapRect).to(beNil())
    }
}
