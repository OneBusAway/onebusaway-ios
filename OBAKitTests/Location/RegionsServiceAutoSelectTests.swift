//
//  RegionsServiceAutoSelectTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import CoreLocation

// MARK: - Auto Region Selection Tests
// See: https://github.com/OneBusAway/onebusaway-ios/issues/608

class RegionsServiceAutoSelectTests: OBATestCase {
    var locationManagerMock: LocationManagerMock!
    var locationService: LocationService!
    var dataLoader: MockDataLoader!
    var mockFileStorage: MockRegionsFileStorage!

    override func setUp() {
        super.setUp()

        locationManagerMock = LocationManagerMock()
        locationService = LocationService(userDefaults: userDefaults, locationManager: locationManagerMock)
        dataLoader = (regionsAPIService.dataLoader as! MockDataLoader)
        mockFileStorage = MockRegionsFileStorage()
    }

    // MARK: - Fixed Region by Name

    func test_fixedRegionName_matchesBundledRegion() throws {
        stubRegions(dataLoader: dataLoader)

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            fixedRegionName: "Puget Sound"
        )

        let currentRegion = try XCTUnwrap(service.currentRegion)
        XCTAssertEqual(currentRegion.name, "Puget Sound")
    }

    func test_fixedRegionName_noMatch_fallsToURL() throws {
        stubRegions(dataLoader: dataLoader)

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            fixedRegionName: "Nonexistent Region",
            fixedRegionOBABaseURL: URL(string: "https://api.tampa.onebusaway.org/api/")
        )

        let currentRegion = try XCTUnwrap(service.currentRegion)
        XCTAssertEqual(currentRegion.name, "Tampa Bay")
    }

    func test_fixedRegionName_noMatch_noURL_regionRemainsNil() {
        stubRegions(dataLoader: dataLoader)

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            fixedRegionName: "Nonexistent Region"
        )

        XCTAssertNil(service.currentRegion)
    }

    func test_fixedRegion_disablesAutoSelect() throws {
        stubRegions(dataLoader: dataLoader)

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            fixedRegionName: "Puget Sound"
        )

        XCTAssertNotNil(service.currentRegion)
        XCTAssertFalse(service.automaticallySelectRegion, "Auto-select should be disabled when a fixed region is matched")
    }

    func test_fixedRegion_onlyAppliesWhenCurrentRegionNil() throws {
        stubRegions(dataLoader: dataLoader)

        let tampaBay = try XCTUnwrap(Fixtures.loadSomeRegions().first(where: { $0.name == "Tampa Bay" }))
        userDefaults.set(tampaBay.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            fixedRegionName: "Puget Sound"
        )

        let currentRegion = try XCTUnwrap(service.currentRegion)
        XCTAssertEqual(currentRegion.name, "Tampa Bay", "Fixed region should not override a previously selected region")
    }

    // MARK: - Single Active Region Auto-Select

    func test_singleActiveRegion_autoSelected() throws {
        stubRegionsJustPugetSound(dataLoader: dataLoader)

        // Seed file storage with just one region so it's the only active region available.
        let pugetSound = try XCTUnwrap(Fixtures.loadSomeRegions().first(where: { $0.name == "Puget Sound" }))
        mockFileStorage.storedDefaultRegions = [pugetSound]

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage
        )

        let currentRegion = try XCTUnwrap(service.currentRegion)
        XCTAssertEqual(currentRegion.name, "Puget Sound", "The only active region should be auto-selected")
    }

    func test_multipleActiveRegions_noAutoSelect() {
        stubRegions(dataLoader: dataLoader)

        // The bundled regions-v3.json has multiple active regions.
        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage
        )

        XCTAssertNil(service.currentRegion, "Region should not be auto-selected when multiple active regions exist")
    }

    // MARK: - Location-Based Selection Priority

    func test_locationBasedSelection_takesPriority() throws {
        stubRegions(dataLoader: dataLoader)

        // Set location inside Puget Sound region.
        locationManagerMock.location = CLLocation(latitude: 47.632445, longitude: -122.312607)

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            fixedRegionName: "Tampa Bay"
        )

        let currentRegion = try XCTUnwrap(service.currentRegion)
        XCTAssertEqual(currentRegion.name, "Puget Sound", "Location-based selection should take priority over fixed region config")
    }

    // MARK: - Fixed Region with URL Match

    func test_fixedRegionURL_matchesBundledRegion() throws {
        stubRegions(dataLoader: dataLoader)

        // Use a name that won't match, but provide the correct Tampa Bay URL.
        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            fixedRegionName: "Tampa Bay (Renamed)",
            fixedRegionOBABaseURL: URL(string: "https://api.tampa.onebusaway.org/api/")
        )

        let currentRegion = try XCTUnwrap(service.currentRegion)
        XCTAssertEqual(currentRegion.name, "Tampa Bay")
    }

    // MARK: - No Config, No Location, Multiple Regions

    func test_noFixedRegion_noLocation_multipleRegions_remainsNil() {
        stubRegions(dataLoader: dataLoader)

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage
        )

        XCTAssertNil(service.currentRegion, "Without config, location, or single region, currentRegion should remain nil")
    }
}
