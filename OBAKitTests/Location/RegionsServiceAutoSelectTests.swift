//
//  RegionsServiceAutoSelectTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore
import CoreLocation

// MARK: - Auto Region Selection Tests
// See: https://github.com/OneBusAway/onebusaway-ios/issues/608

@Suite(.serialized)
final class RegionsServiceAutoSelectTests: OBATestCase {
    var locationManagerMock: LocationManagerMock!
    var locationService: LocationService!
    var dataLoader: MockDataLoader!
    var mockFileStorage: MockRegionsFileStorage!

    override init() async throws {
        try await super.init()

        locationManagerMock = LocationManagerMock()
        locationService = LocationService(userDefaults: userDefaults, locationManager: locationManagerMock)
        dataLoader = (regionsAPIService.dataLoader as! MockDataLoader)
        mockFileStorage = MockRegionsFileStorage()
    }

    // MARK: - Fixed Region by Name

    @Test func `Fixed region name matches bundled region`() throws {
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

        let currentRegion = try #require(service.currentRegion)
        #expect(currentRegion.name == "Puget Sound")
    }

    @Test func `Fixed region name no match falls to URL`() throws {
        stubRegions(dataLoader: dataLoader)

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            fixedRegionName: "Nonexistent Region",
            fixedRegionOBABaseURL: URL(string: "https://api.tampa.onebusawaycloud.com/")
        )

        let currentRegion = try #require(service.currentRegion)
        #expect(currentRegion.name == "Tampa Bay")
    }

    @Test func `Fixed region name no match no URL region remains nil`() {
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

        #expect(service.currentRegion == nil)
    }

    @Test func `Fixed region disables auto select`() throws {
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

        #expect(service.currentRegion != nil)
        #expect(!service.automaticallySelectRegion, "Auto-select should be disabled when a fixed region is matched")
    }

    @Test func `Fixed region only applies when current region nil`() throws {
        stubRegions(dataLoader: dataLoader)

        let tampaBay = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Tampa Bay" }))
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

        let currentRegion = try #require(service.currentRegion)
        #expect(currentRegion.name == "Tampa Bay", "Fixed region should not override a previously selected region")
    }

    // MARK: - Single Active Region Auto-Select

    @Test func `Single active region auto selected`() throws {
        stubRegionsJustPugetSound(dataLoader: dataLoader)

        // Seed file storage with just one region so it's the only active region available.
        let pugetSound = try #require(Fixtures.loadSomeRegions().first(where: { $0.name == "Puget Sound" }))
        mockFileStorage.storedDefaultRegions = [pugetSound]

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage
        )

        let currentRegion = try #require(service.currentRegion)
        #expect(currentRegion.name == "Puget Sound", "The only active region should be auto-selected")
    }

    @Test func `Multiple active regions no auto select`() {
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

        #expect(service.currentRegion == nil, "Region should not be auto-selected when multiple active regions exist")
    }

    // MARK: - Location-Based Selection Priority

    @Test func `Location based selection takes priority`() throws {
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

        let currentRegion = try #require(service.currentRegion)
        #expect(currentRegion.name == "Puget Sound", "Location-based selection should take priority over fixed region config")
    }

    // MARK: - Fixed Region with URL Match

    @Test func `Fixed region URL matches bundled region`() throws {
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
            fixedRegionOBABaseURL: URL(string: "https://api.tampa.onebusawaycloud.com/")
        )

        let currentRegion = try #require(service.currentRegion)
        #expect(currentRegion.name == "Tampa Bay")
    }

    // MARK: - No Config, No Location, Multiple Regions

    @Test func `No fixed region no location multiple regions remains nil`() {
        stubRegions(dataLoader: dataLoader)

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage
        )

        #expect(service.currentRegion == nil, "Without config, location, or single region, currentRegion should remain nil")
    }
}
