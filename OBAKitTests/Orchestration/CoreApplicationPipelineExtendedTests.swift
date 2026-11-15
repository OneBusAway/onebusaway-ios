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

    private func createTestApplication(
        fixedRegionName: String? = Fixtures.pugetSoundRegion.name,
        defaultFilter: ArrivalDepartureFilter = .departures
    ) -> Application {
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
            defaultArrivalDepartureFilter: defaultFilter,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: restService.dataLoader as! MockDataLoader,
            fixedRegionName: fixedRegionName
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
        let app = createTestApplication(defaultFilter: .departures)

        app.setArrivalDepartureFilter(.arrivals)
        #expect(app.effectiveArrivalDepartureFilter == .arrivals)

        let storedValue = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        #expect(storedValue == ArrivalDepartureFilter.arrivals.rawValue)

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

    @Test func `UserDataStore and StopPreferencesDataStore are accessible and backed by store`() {
        let app = createTestApplication()
        #expect(app.userDataStore.bookmarkGroups.isEmpty)

        let stop = StopPreferences(sort: .route, filter: .departures)
        app.stopPreferencesDataStore.set(stopPreferences: stop, forStopID: "1_100")
        let retrieved = app.stopPreferencesDataStore.stopPreferences(forStopID: "1_100")

        #expect(retrieved.sort == .route)
        #expect(retrieved.filter == .departures)
    }
}
