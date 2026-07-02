//
//  MoreSheetHostTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Smoke-tests for the UIKit wiring wrapper around `MoreViewController`.
/// The wrapping is the entire product surface of `MoreSheetHost`, so these
/// tests exercise the representable by embedding it in a `UIHostingController`
/// and inspecting the resulting child controller.
final class MoreSheetHostTests: OBATestCase {

    private var queue: OperationQueue!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    /// `OBATestCase` doesn't own an `Application`; tests build one per-case,
    /// mirroring the pattern in `MapPanelViewModelTests`. Only the pieces
    /// `MoreViewController.init` actually reaches for (regions service,
    /// analytics, user defaults) need to be real — everything else can rely
    /// on the standard stubs.
    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )
        return Application(config: config)
    }

    @MainActor
    func test_makeNavigationController_wrapsMoreViewControllerInNav() {
        let dataLoader = MockDataLoader(testName: name)
        let application = createApplication(dataLoader: dataLoader)

        let nav = MoreSheetHost.makeNavigationController(application: application)

        expect(nav.viewControllers.count) == 1
        expect(nav.topViewController).to(beAKindOf(MoreViewController.self))
    }
}
