//
//  RegionsServiceTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import CoreLocation
import Nimble
import OHHTTPStubs

// swiftlint:disable force_cast force_try weak_delegate

class RegionsServiceTestDelegate: NSObject, RegionsServiceDelegate {
    var unableToSelectRegionsCallbacks = [(() -> Void)]()
    var updatedRegionsListCallbacks = [(() -> Void)]()
    var newRegionSelectedCallbacks = [(() -> Void)]()
    var regionUpdateCancelledCallbacks = [(() -> Void)]()

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

    override func setUp() {
        super.setUp()

        testDelegate = RegionsServiceTestDelegate()
        locationManagerMock = LocationManagerMock()
        locationService = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
    }

    override func tearDown() {
        super.tearDown()
        testDelegate.tearDown()
        testDelegate = nil
    }

    // MARK: - OHHTTPStubs

    private func stubRegionsJustPugetSound() {
        stub(condition: isHost(self.regionsHost) && isPath(self.regionsPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "regions-just-puget-sound.json")
        }
    }

    private func stubRegions() {
        stub(condition: isHost(self.regionsHost) && isPath(self.regionsPath)) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "regions-v3.json")
        }
    }

    // MARK: - Upon creating the Regions Service

    // It loads bundled regions from its framework when no other data exists
    func test_init_loadsBundledRegions() {
        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: "/regions-v3.json")

        expect(regionsService.regions.count) == 13
    }

    // It loads regions saved to the user defaults when they exist
    func test_init_loadsSavedRegions() {
        let customRegion = customMinneapolisRegion
        let plistData = try! PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistData, forKey: RegionsService.storedRegionsUserDefaultsKey)

        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: "/regions-v3.json")

        expect(regionsService.regions.first!.name) == "Custom Region"
        expect(regionsService.regions.count) == 1
    }

    // It loads the current region from user defaults when it exists
    func test_init_loadsCurrentRegion_autoSelectDisabled() {
        let customRegion = customMinneapolisRegion
        let plistArrayData = try! PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistArrayData, forKey: RegionsService.storedRegionsUserDefaultsKey)
        userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)

        let plistData = try! PropertyListEncoder().encode(customRegion)
        userDefaults.set(plistData, forKey: RegionsService.currentRegionUserDefaultsKey)

        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: "/regions-v3.json")

        expect(regionsService.currentRegion) == customRegion
    }

    func test_init_loadsCurrentRegion_autoSelectEnabled() {
        let plistData = try! PropertyListEncoder().encode(customMinneapolisRegion)
        userDefaults.set(plistData, forKey: RegionsService.currentRegionUserDefaultsKey)
        locationManagerMock.location = CLLocation(latitude: 47.632445, longitude: -122.312607)

        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: "/regions-v3.json")

        expect(regionsService.currentRegion!.name) == "Puget Sound"
    }

    /// It immediately downloads an up-to-date list of regions if that list hasn't been updated in at least a week.
    func test_init_updateRegionsList() {
        stubRegionsJustPugetSound()

        var regionsService: RegionsService!

        waitUntil { done in
            let callback = {
                expect(regionsService.regions.count) == 1
                done()
            }
            self.testDelegate.updatedRegionsListCallbacks.append(callback)

            regionsService = RegionsService(modelService: self.regionsModelService, locationService: self.locationService, userDefaults: self.userDefaults, bundledRegionsFilePath: self.bundledRegionsPath, apiPath: self.regionsAPIPath, delegate: self.testDelegate)
        }
    }

    /// It *does not* download a list of regions if the list was last updated less than a week ago.
    func test_init_skipUpdateRegionsList() {
        stubRegionsJustPugetSound()
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: "/regions-v3.json", delegate: self.testDelegate)

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
        stubRegionsJustPugetSound()
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: "/regions-v3.json", delegate: self.testDelegate)

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
        stubRegionsJustPugetSound()
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)

        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: "/regions-v3.json", delegate: self.testDelegate)

        waitUntil { done in
            self.testDelegate.updatedRegionsListCallbacks.append {
                let regions: [Region]! = try! self.userDefaults.decodeUserDefaultsObjects(type: [Region].self, key: RegionsService.storedRegionsUserDefaultsKey)
                expect(regions.count) == 1
                expect(regions?.first!.name) == "Puget Sound"
                done()
            }
            regionsService.updateRegionsList(forceUpdate: true)
        }
    }

    /// It loads the bundled regions when the data in the user defaults is corrupted.
    func test_corruptedDefaults() {
        self.userDefaults.set(["hello world!"], forKey: RegionsService.storedRegionsUserDefaultsKey)
        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: "/regions-v3.json", delegate: self.testDelegate)

        expect(regionsService.regions.count) == 13
    }

    /// It calls delegates to tell them that the current region is updated when that property is written.
    func test_regionUpdated_notifications() {
        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegionsPath, apiPath: "/regions-v3.json", delegate: self.testDelegate)

        let newRegion = customMinneapolisRegion

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
        stubRegionsJustPugetSound()
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
            service = RegionsService(modelService: self.regionsModelService, locationService: self.locationService, userDefaults: self.userDefaults, bundledRegionsFilePath: self.bundledRegionsPath, apiPath: "/regions-v3.json", delegate: self.testDelegate)
        }
    }

    // It updates the current region when the regions list is downloaded.

    // MARK: - Location Services

    // It updates the current region when the user's location changes

    // It does not update the user's current region or call `regionsServiceUnableToSelectRegion` when the user's location is nil

    // It calls `regionsServiceUnableToSelectRegion` if the user's current location does not match a known region.
}
