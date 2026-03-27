//
//  RegionsServiceTests.swift
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

// swiftlint:disable weak_delegate

private class RegionsServiceTestDelegate: NSObject, RegionsServiceDelegate {
    private(set) var unableToSelectRegion: DelegateTestingHelper.DidCallDelegateMethod<Void> = .didNotCall
    private(set) var updatedRegionsList: DelegateTestingHelper.DidCallDelegateMethod<[Region]> = .didNotCall
    private(set) var newRegionSelected: DelegateTestingHelper.DidCallDelegateMethod<Region> = .didNotCall
    private(set) var regionUpdateCancelled: DelegateTestingHelper.DidCallDelegateMethod<Void> = .didNotCall

    func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        unableToSelectRegion = .called(Void())
    }

    func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        updatedRegionsList = .called(regions)
    }

    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        newRegionSelected = .called(region)
    }

    func regionsServiceListUpdateCancelled(_ service: RegionsService) {
        regionUpdateCancelled = .called(Void())
    }
}

// MARK: - Mock File Storage

private class MockRegionsFileStorage: RegionsFileStorageProtocol {
    var storedDefaultRegions: [Region]?
    var storedCustomRegions: [Region] = []
    var loadDefaultRegionsError: Error?

    func loadDefaultRegions() throws -> [Region]? {
        if let error = loadDefaultRegionsError { throw error }
        return storedDefaultRegions
    }

    func saveDefaultRegions(_ regions: [Region]) throws {
        storedDefaultRegions = regions
    }

    func loadCustomRegions() -> [Region] {
        return storedCustomRegions
    }

    func saveCustomRegion(_ region: Region) throws {
        storedCustomRegions.removeAll { $0.regionIdentifier == region.regionIdentifier }
        storedCustomRegions.append(region)
    }

    func deleteCustomRegion(identifier: RegionIdentifier) throws {
        storedCustomRegions.removeAll { $0.regionIdentifier == identifier }
    }
}

// MARK: - Test Case

class RegionsServiceTests: OBATestCase {
    private var testDelegate: RegionsServiceTestDelegate!
    var locationManagerMock: LocationManagerMock!
    var locationService: LocationService!
    var dataLoader: MockDataLoader!
    private var mockFileStorage: MockRegionsFileStorage!

    override func setUp() {
        super.setUp()

        testDelegate = RegionsServiceTestDelegate()
        locationManagerMock = LocationManagerMock()
        locationService = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        dataLoader = (regionsAPIService.dataLoader as! MockDataLoader)
        mockFileStorage = MockRegionsFileStorage()
    }

    // MARK: - Convenience builder

    private func makeRegionsService(delegate: RegionsServiceTestDelegate? = nil) -> RegionsService {
        RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsPath,
            fileStorage: mockFileStorage,
            delegate: delegate
        )
    }

    // MARK: - Upon creating the Regions Service

    // It loads bundled regions from its framework when no other data exists
    func test_init_loadsBundledRegions() {
        stubRegions(dataLoader: dataLoader)

        let service = makeRegionsService()
        XCTAssertEqual(service.regions.count, 17)
    }

    // It loads regions saved to disk when they exist
    func test_init_loadsSavedRegions() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        mockFileStorage.storedDefaultRegions = [customRegion]

        let service = makeRegionsService()

        let firstRegion = try XCTUnwrap(service.regions.first)
        XCTAssertEqual(firstRegion.name, "Custom Region", "Expected the first region to be the custom region")
        XCTAssertEqual(service.regions.count, 1)
    }

    // It loads the current region identifier from user defaults when it exists (auto-select disabled)
    func test_init_loadsCurrentRegion_autoSelectDisabled() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        mockFileStorage.storedDefaultRegions = [customRegion]
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)
        userDefaults.set(customRegion.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)

        let service = makeRegionsService()

        XCTAssertEqual(service.currentRegion, customRegion)
    }

    func test_init_loadsCurrentRegion_autoSelectEnabled() throws {
        stubRegions(dataLoader: dataLoader)

        // Store the Minneapolis region identifier, but location points to Puget Sound —
        // auto-select should override and pick Puget Sound.
        let minneapolis = Fixtures.customMinneapolisRegion
        userDefaults.set(minneapolis.regionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        locationManagerMock.location = CLLocation(latitude: 47.632445, longitude: -122.312607)

        let service = makeRegionsService()

        let currentRegion = try XCTUnwrap(service.currentRegion)
        XCTAssertEqual(currentRegion.name, "Puget Sound")
    }

    /// It downloads an up-to-date list of regions if that list hasn't been updated in at least a week.
    func test_init_updateRegionsList() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList()

        XCTAssertTrue(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")
    }

    /// It *does not* download a list of regions if the list was last updated less than a week ago.
    func test_init_skipUpdateRegionsList() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList()

        XCTAssertTrue(testDelegate.regionUpdateCancelled.didCall, "Expected RegionsService to inform delegates that the region update was cancelled")
        XCTAssertEqual(regionsService.regions.count, 17)
    }

    /// It *does* download a list of regions—even if the list was last updated less than a week ago—if the update is forced.
    func test_init_forceUpdateRegionsList() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList(forceUpdate: true)
        XCTAssertFalse(testDelegate.regionUpdateCancelled.didCall, "Expected RegionsService to not inform delegates that a region update was cancelled")
        XCTAssertTrue(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")
        XCTAssertEqual(regionsService.regions.count, 1)
    }

    /// It *does* download a list of regions—even if the list was last updated less than a week ago—if alwaysRefreshRegionsOnLaunchUserDefaultsKey is true.
    func test_init_alwaysRefreshRegionsOnLaunch() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)
        userDefaults.set(true, forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList()
        XCTAssertTrue(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")
        XCTAssertEqual(regionsService.regions.count, 1)
    }

    // MARK: - Persistence

    // It stores downloaded region data in file storage when the regions property is set.
    func test_persistence() async throws {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList(forceUpdate: true)
        XCTAssertTrue(testDelegate.updatedRegionsList.didCall)

        // Verify regions were saved to file storage (not UserDefaults).
        let regions = try XCTUnwrap(
            mockFileStorage.storedDefaultRegions,
            "Expected regions to be saved to file storage"
        )

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions.first?.name, "Puget Sound")
    }

    /// It loads the bundled regions when file storage returns an error (e.g. corrupted data).
    func test_corruptedStorage() {
        stubRegions(dataLoader: dataLoader)

        mockFileStorage.loadDefaultRegionsError = CocoaError(.fileReadCorruptFile)

        let regionsService = makeRegionsService()

        XCTAssertEqual(regionsService.regions.count, 17)
    }

    /// It calls delegates to tell them that the current region is updated when that property is written.
    func test_regionUpdated_notifications() {
        stubRegions(dataLoader: dataLoader)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        let newRegion = Fixtures.customMinneapolisRegion
        // Put the region in file storage so it can be looked up by identifier.
        mockFileStorage.storedCustomRegions = [newRegion]

        regionsService.currentRegion = newRegion

        XCTAssertDidCallDelegateMethodWithValue(testDelegate.newRegionSelected, newRegion, "Expected RegionsService to inform delegates of the new region selection")
        XCTAssertEqual(regionsService.currentRegion, newRegion, "Expected RegionsService to update its currentRegion property to the new region")
    }

    // MARK: - Network Data

    // It updates the 'last updated at' date in user defaults when the regions list is downloaded.
    func test_regionListUpdated_updatedAtDateIsWritten() async throws {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date.distantPast, forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: mockFileStorage,
            delegate: testDelegate
        )

        await regionsService.updateRegionsList()
        XCTAssertTrue(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")

        let newDate = try XCTUnwrap(
            userDefaults.value(forKey: RegionsService.regionsUpdatedAtUserDefaultsKey) as? Date,
            "Expected \(RegionsService.regionsUpdatedAtUserDefaultsKey) to be of type Date"
        )

        let interval = newDate.timeIntervalSince(.now)
        XCTAssertEqual(interval, 0.0, accuracy: 2.0, "Expected the regionsUpdatedAt time to be near the current time")
        XCTAssertEqual(regionsService.regions.first?.name, "Puget Sound", "Expected a region to exist in the regionsService")
    }

    // MARK: - Migration

    /// It migrates downloaded regions from UserDefaults to disk storage on first launch.
    func test_migration_defaultRegions() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistData, forKey: RegionsService.legacyStoredRegionsUserDefaultsKey)

        _ = makeRegionsService()

        // After init, the region should have been migrated to file storage.
        let migratedRegions = try XCTUnwrap(mockFileStorage.storedDefaultRegions, "Expected regions to be migrated to file storage")
        XCTAssertEqual(migratedRegions.count, 1)
        XCTAssertEqual(migratedRegions.first?.name, "Custom Region")

        // Legacy UserDefaults key should be cleared.
        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyStoredRegionsUserDefaultsKey), "Expected legacy UserDefaults key to be cleared after migration")
    }

    /// It migrates custom regions from UserDefaults to individual disk files on first launch.
    func test_migration_customRegions() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistData, forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey)

        _ = makeRegionsService()

        XCTAssertEqual(mockFileStorage.storedCustomRegions.count, 1)
        XCTAssertEqual(mockFileStorage.storedCustomRegions.first?.name, "Custom Region")

        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyStoredCustomRegionsUserDefaultsKey), "Expected legacy custom regions key to be cleared after migration")
    }

    /// It migrates the current region from a full Region object to just the identifier.
    func test_migration_currentRegion() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try PropertyListEncoder().encode(customRegion)
        userDefaults.set(plistData, forKey: RegionsService.legacyCurrentRegionUserDefaultsKey)

        _ = makeRegionsService()

        let migratedIdentifier = userDefaults.integer(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        XCTAssertEqual(migratedIdentifier, customRegion.regionIdentifier, "Expected current region identifier to be migrated")

        XCTAssertNil(userDefaults.data(forKey: RegionsService.legacyCurrentRegionUserDefaultsKey), "Expected legacy current region key to be cleared after migration")
    }

    // MARK: - Location Services

    // It updates the current region when the user's location changes

    // It does not update the user's current region or call `regionsServiceUnableToSelectRegion` when the user's location is nil

    // It calls `regionsServiceUnableToSelectRegion` if the user's current location does not match a known region.
}
