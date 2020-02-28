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
    let apiKey = "apikey"
    let appVersion = "app-version"
    let queue = OperationQueue()

    var config: AppConfig!

    override func setUp() {
        super.setUp()

        let locManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)

        let bundledRegions = Bundle.main.path(forResource: "regions", ofType: "json")!

        config = AppConfig(regionsBaseURL: regionsURL, obacoBaseURL: obacoURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegions, regionsAPIPath: regionsPath)

        expect(locationService.isLocationUseAuthorized).to(beFalse())
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    func test_init() {
        stubRegions()

        let application = Application(config: config)
        let mgr = MapRegionManager(application: application)

        expect(mgr.mapView).toNot(beNil())
        expect(mgr.mapView.showsScale).to(beTrue())
        expect(mgr.mapView.showsTraffic).to(beTrue())
    }

    /// When `currentRegion` is nil, `visibleMapRect` also returns `nil`.
    func test_visibleMapRect_nilRegion() {
        stubRegions()

        let application = Application(config: config)
        let mgr = MapRegionManager(application: application)
        expect(application.currentRegion).to(beNil())
        expect(mgr.lastVisibleMapRect).to(beNil())
    }
}
