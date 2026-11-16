//
//  CoreApplicationPipelineExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Extended pipeline and state tests for `CoreApplication`.
///
/// Focuses on arrival/departure filter defaults vs saved state, region display
/// naming, user data store exposure, and preference persistence.
@MainActor
@Suite(.serialized)
final class CoreApplicationPipelineExtendedTests: OBATestCase {

    var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func createTestApplication(
        fixedRegionName: String? = Fixtures.pugetSoundRegion.name,
        defaultFilter: ArrivalDepartureFilter = .estimatedOnly
    ) -> Application {
        let loader = restService.dataLoader as! MockDataLoader
        stubRegions(dataLoader: loader)

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
            dataLoader: loader,
            fixedRegionName: fixedRegionName,
            defaultArrivalDepartureFilter: defaultFilter
        )
        return Application(config: config)
    }

    // MARK: - Arrival Departure Filter Pipeline

    @Test func `Effective filter returns brand default when no user preference is stored`() {
        let app = createTestApplication(defaultFilter: .all)
        userDefaults.removeObject(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)

        #expect(app.defaultArrivalDepartureFilter == .all)
        #expect(app.effectiveArrivalDepartureFilter == .all)
    }

    @Test func `Setting arrival departure filter persists value and updates effective filter`() {
        let app = createTestApplication(defaultFilter: .estimatedOnly)

        app.setArrivalDepartureFilter(.scheduledOnly)
        #expect(app.effectiveArrivalDepartureFilter == .scheduledOnly)

        let storedValue = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        #expect(storedValue == ArrivalDepartureFilter.scheduledOnly.rawValue)

        app.setArrivalDepartureFilter(.all)
        #expect(app.effectiveArrivalDepartureFilter == .all)
        #expect(userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey) == ArrivalDepartureFilter.all.rawValue)
    }

    // MARK: - Current Region Display Name

    @Test func `Current region name returns region name when region is selected`() {
        let app = createTestApplication(fixedRegionName: Fixtures.pugetSoundRegion.name)
        #expect(app.currentRegionName == Fixtures.pugetSoundRegion.name)
    }

    @Test func `Current region name returns nil when no region is selected`() {
        let app = createTestApplication(fixedRegionName: nil)
        #expect(app.currentRegionName == nil)
    }

    // MARK: - Data Stores Consistency

    @Test func `UserDataStore and StopPreferencesDataStore are accessible and backed by store`() throws {
        let app = createTestApplication()
        #expect(app.userDataStore.bookmarkGroups.isEmpty)

        let stop = try #require(Fixtures.loadSomeStops().first)
        let region = Fixtures.pugetSoundRegion
        var customPrefs = StopPreferences(sortType: .route, hiddenRoutes: ["1_100"])

        app.stopPreferencesDataStore.set(stopPreferences: customPrefs, stop: stop, region: region)
        let retrieved = app.stopPreferencesDataStore.preferences(stopID: stop.id, region: region)

        #expect(retrieved.sortType == .route)
        #expect(retrieved.hiddenRoutes == ["1_100"])
    }
}
