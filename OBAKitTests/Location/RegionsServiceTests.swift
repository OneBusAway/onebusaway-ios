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

class RegionsServiceTests: OBATestCase {
    private var testDelegate: RegionsServiceTestDelegate!
    var locationManagerMock: LocationManagerMock!
    var locationService: LocationService!
    var dataLoader: MockDataLoader!
    var fileManager: RegionsServiceFileManagerProtocol!

    override func setUp() {
        super.setUp()

        testDelegate = RegionsServiceTestDelegate()
        locationManagerMock = LocationManagerMock()
        locationService = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        dataLoader = (regionsAPIService.dataLoader as! MockDataLoader)
        fileManager = RegionsServiceFileManagerMock()
    }

    // MARK: - Upon creating the Regions Service

    // It loads bundled regions from its framework when no other data exists
    func test_init_loadsBundledRegions() {
        stubRegions(dataLoader: dataLoader)

        let service = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsPath)
        XCTAssertEqual(service.regions.count, 13)
    }

    // It loads regions saved to the user defaults when they exist
    func test_init_loadsSavedRegions() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        try fileManager.save([customRegion], to: RegionsService.defaultRegionsPath)
        
        let service = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsPath)

        let firstRegion = try XCTUnwrap(service.regions.first)
        XCTAssertEqual(firstRegion.name, "Custom Region", "Expected the first region to be the custom region")
        XCTAssertEqual(service.regions.count, 1)
    }

    // It loads the current region from user defaults when it exists
    func test_init_loadsCurrentRegion_autoSelectDisabled() throws {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        try fileManager.save(customRegion, to: RegionsService.defaultRegionsPath)
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)

        let plistData = try PropertyListEncoder().encode(customRegion)
        userDefaults.set(plistData, forKey: RegionsService.currentRegionUserDefaultsKey)

        let service = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsPath)

        XCTAssertEqual(service.currentRegion, customRegion)
    }

    func test_init_loadsCurrentRegion_autoSelectEnabled() throws {
        stubRegions(dataLoader: dataLoader)

        let plistData = try JSONEncoder().encode(Fixtures.customMinneapolisRegion)
        userDefaults.set(plistData, forKey: RegionsService.currentRegionUserDefaultsKey)
        locationManagerMock.location = CLLocation(latitude: 47.632445, longitude: -122.312607)

        let service = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsPath)

        let currentRegion = try XCTUnwrap(service.currentRegion)
        XCTAssertEqual(currentRegion.name, "Puget Sound")
    }

    /// It downloads an up-to-date list of regions if that list hasn't been updated in at least a week.
    func test_init_updateRegionsList() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        await regionsService.updateRegionsList()

        XCTAssertTrue(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")
    }

    /// It *does not* download a list of regions if the list was last updated less than a week ago.
    func test_init_skipUpdateRegionsList() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        await regionsService.updateRegionsList()

        XCTAssertTrue(testDelegate.regionUpdateCancelled.didCall, "Expected RegionsService to inform delegates that the region update was cancelled")
        XCTAssertEqual(regionsService.regions.count, 13)
    }

    /// It *does* download a list of regions—even if the list was last updated less than a week ago—if the update is forced..
    func test_init_forceUpdateRegionsList() async {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

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

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        await regionsService.updateRegionsList()
        XCTAssertTrue(testDelegate.updatedRegionsList.didCall, "Expected RegionsService to inform delegates that the regionsList was updated")
        XCTAssertEqual(regionsService.regions.count, 1)
    }

    // MARK: - Persistence

    // It stores downloaded region data in user defaults when the regions property is set.
    func test_persistence() async throws {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        await regionsService.updateRegionsList(forceUpdate: true)
        XCTAssertTrue(testDelegate.updatedRegionsList.didCall)

        // Get regions from Persistence to ensure they were saved.
        let regions = try XCTUnwrap(
            try fileManager.load([Region].self, from: RegionsService.defaultRegionsPath),
            "Expected to get [Region] from \(RegionsService.defaultRegionsPath.path)"
        )

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions.first?.name, "Puget Sound")
    }

    /// It loads the bundled regions when the data in the user defaults is corrupted.
    func test_corruptedDefaults() throws {
        stubRegions(dataLoader: dataLoader)

        try XCTUnwrap(fileManager.save(["hello world!"], to: RegionsService.defaultRegionsPath))

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        XCTAssertEqual(regionsService.regions.count, 13)
    }

    /// It calls delegates to tell them that the current region is updated when that property is written.
    func test_regionUpdated_notifications() {
        stubRegions(dataLoader: dataLoader)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        let newRegion = Fixtures.customMinneapolisRegion

        regionsService.currentRegion = newRegion

        XCTAssertDidCallDelegateMethodWithValue(testDelegate.newRegionSelected, newRegion, "Expected RegionsService to inform delegates of the new region selection")
        XCTAssertEqual(regionsService.currentRegion, newRegion, "Expected RegionsService to update its currentRegion property to the new region")
    }

    // MARK: - Network Data

    // It updates the 'last updated at' date in user defaults when the regions list is downloaded.
    func test_regionListUpdated_updatedAtDateIsWritten() async throws {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date.distantPast, forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, fileManager: fileManager, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

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

    // It updates the current region when the regions list is downloaded.

    // MARK: - Location Services

    // It updates the current region when the user's location changes

    // It does not update the user's current region or call `regionsServiceUnableToSelectRegion` when the user's location is nil

    // It calls `regionsServiceUnableToSelectRegion` if the user's current location does not match a known region.
}
