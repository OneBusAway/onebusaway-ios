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
import Nimble

// swiftlint:disable force_cast force_try weak_delegate

class RegionsServiceTestDelegate: NSObject, RegionsServiceDelegate {
    var unableToSelectRegionsCallbacks = [VoidBlock]()
    var updatedRegionsListCallbacks = [VoidBlock]()
    var newRegionSelectedCallbacks = [VoidBlock]()
    var regionUpdateCancelledCallbacks = [VoidBlock]()

    func tearDown() {
        unableToSelectRegionsCallbacks.removeAll()
        updatedRegionsListCallbacks.removeAll()
        newRegionSelectedCallbacks.removeAll()
        regionUpdateCancelledCallbacks.removeAll()
    }

    func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        for callback in unableToSelectRegionsCallbacks {
            callback()
        }
    }

    func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        for callback in updatedRegionsListCallbacks {
            callback()
        }
    }

    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        for callback in newRegionSelectedCallbacks {
            callback()
        }
    }

    func regionsServiceListUpdateCancelled(_ service: RegionsService) {
        for callback in regionUpdateCancelledCallbacks {
            callback()
        }
    }
}

class RegionsServiceTests: OBATestCase {
    var testDelegate: RegionsServiceTestDelegate!
    var locationManagerMock: LocationManagerMock!
    var locationService: LocationService!
    var dataLoader: MockDataLoader!

    override func setUp() {
        super.setUp()

        testDelegate = RegionsServiceTestDelegate()
        locationManagerMock = LocationManagerMock()
        locationService = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        regionsAPIService.networkQueue.maxConcurrentOperationCount = 1
        dataLoader = (regionsAPIService.dataLoader as! MockDataLoader)
    }

    override func tearDown() {
        super.tearDown()
        testDelegate.tearDown()
        testDelegate = nil
    }

    // MARK: - Upon creating the Regions Service

    // It loads bundled regions from its framework when no other data exists
    func test_init_loadsBundledRegions() {
        stubRegions(dataLoader: dataLoader)

        let service = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsPath)
        expect(service.regions.count) == 13
        service.cancelRequests()
    }

    // It loads regions saved to the user defaults when they exist
    func test_init_loadsSavedRegions() {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try! PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistData, forKey: RegionsService.storedRegionsUserDefaultsKey)

        let service = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsPath)

        expect(service.regions.first!.name) == "Custom Region"
        expect(service.regions.count) == 1

        service.cancelRequests()
    }

    // It loads the current region from user defaults when it exists
    func test_init_loadsCurrentRegion_autoSelectDisabled() {
        stubRegions(dataLoader: dataLoader)

        let customRegion = Fixtures.customMinneapolisRegion
        let plistArrayData = try! PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistArrayData, forKey: RegionsService.storedRegionsUserDefaultsKey)
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)

        let plistData = try! PropertyListEncoder().encode(customRegion)
        userDefaults.set(plistData, forKey: RegionsService.currentRegionUserDefaultsKey)

        let service = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsPath)

        expect(service.currentRegion) == customRegion

        service.cancelRequests()
    }

    func test_init_loadsCurrentRegion_autoSelectEnabled() {
        stubRegions(dataLoader: dataLoader)

        let plistData = try! PropertyListEncoder().encode(Fixtures.customMinneapolisRegion)
        userDefaults.set(plistData, forKey: RegionsService.currentRegionUserDefaultsKey)
        locationManagerMock.location = CLLocation(latitude: 47.632445, longitude: -122.312607)

        let service = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsPath)

        expect(service.currentRegion!.name) == "Puget Sound"

        service.cancelRequests()
    }

    /// It downloads an up-to-date list of regions if that list hasn't been updated in at least a week.
    func test_init_updateRegionsList() {
        stubRegionsJustPugetSound(dataLoader: dataLoader)

        var regionsService: RegionsService!

        waitUntil { done in
            let callback = {
                expect(regionsService.regions.count) == 1
                done()
            }
            self.testDelegate.updatedRegionsListCallbacks.append(callback)

            regionsService = RegionsService(apiService: self.regionsAPIService, locationService: self.locationService, userDefaults: self.userDefaults, bundledRegionsFilePath: self.bundledRegionsPath, apiPath: self.regionsAPIPath, delegate: self.testDelegate)

            regionsService.updateRegionsList()
        }
    }

    /// It *does not* download a list of regions if the list was last updated less than a week ago.
    func test_init_skipUpdateRegionsList() {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        waitUntil { done in
            self.testDelegate.regionUpdateCancelledCallbacks.append {
                expect(regionsService.regions.count) == 13
                done()
            }
            regionsService.updateRegionsList()
        }
    }

    /// It *does* download a list of regions—even if the list was last updated less than a week ago—if the update is forced..
    func test_init_forceUpdateRegionsList() {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        waitUntil { done in
            self.testDelegate.updatedRegionsListCallbacks.append {
                expect(regionsService.regions.count) == 1
                done()
            }
            regionsService.updateRegionsList(forceUpdate: true)
        }
    }

    // MARK: - Persistence

    // It stores downloaded region data in user defaults when the regions property is set.
    func test_persistence() {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        waitUntil { done in
            self.testDelegate.updatedRegionsListCallbacks.append {
                let regions: [Region]! = try! self.userDefaults.decodeUserDefaultsObjects(type: [Region].self, key: RegionsService.storedRegionsUserDefaultsKey)
                expect(regions.count) == 1
                expect(regions!.first!.name) == "Puget Sound"
                done()
            }
            regionsService.updateRegionsList(forceUpdate: true)
        }
    }

    /// It loads the bundled regions when the data in the user defaults is corrupted.
    func test_corruptedDefaults() {
        stubRegions(dataLoader: dataLoader)

        self.userDefaults.set(["hello world!"], forKey: RegionsService.storedRegionsUserDefaultsKey)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        expect(regionsService.regions.count) == 13

        regionsService.cancelRequests()
    }

    /// It calls delegates to tell them that the current region is updated when that property is written.
    func test_regionUpdated_notifications() {
        stubRegions(dataLoader: dataLoader)

        let regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: regionsAPIPath, delegate: testDelegate)

        let newRegion = Fixtures.customMinneapolisRegion

        waitUntil { done in
            self.testDelegate.newRegionSelectedCallbacks.append {
                expect(regionsService.currentRegion) == newRegion
                done()
            }
            regionsService.currentRegion = newRegion
        }
    }

    // MARK: - Network Data

    // It updates the 'last updated at' date in user defaults when the regions list is downloaded.
    func test_regionListUpdated_updatedAtDateIsWritten() {
        stubRegionsJustPugetSound(dataLoader: dataLoader)
        userDefaults.set(Date.distantPast, forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        var service: RegionsService!

        waitUntil { done in
            self.testDelegate.updatedRegionsListCallbacks.append {
                let newDate = self.userDefaults.value(forKey: RegionsService.regionsUpdatedAtUserDefaultsKey) as! Date
                let interval = newDate.timeIntervalSince(Date())
                expect(interval).to(beCloseTo(0.0, within: 2.0))
                expect(service.regions.first!.name) == "Puget Sound"
                done()
            }
            service = RegionsService(apiService: self.regionsAPIService, locationService: self.locationService, userDefaults: self.userDefaults, bundledRegionsFilePath: self.bundledRegionsPath, apiPath: self.regionsAPIPath, delegate: self.testDelegate)

            service.updateRegionsList()
        }
    }

    // It updates the current region when the regions list is downloaded.

    // MARK: - Location Services

    // It updates the current region when the user's location changes

    // It does not update the user's current region or call `regionsServiceUnableToSelectRegion` when the user's location is nil

    // It calls `regionsServiceUnableToSelectRegion` if the user's current location does not match a known region.
}
