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
import CoreLocation
import Nimble

// swiftlint:disable force_try

class RegionsServiceTests: OBATestCase {

    // MARK: - Upon creating the Regions Service

    // It loads bundled regions from its framework when no other data exists
    func test_init_loadsBundledRegions() {
        let locationManager = LocationManagerMock()
        let locationService = LocationService(locationManager: locationManager)
        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults)

        expect(regionsService.regions.count) == 12
    }

    // It loads regions saved to the user defaults when they exist
    func test_init_loadsSavedRegions() {
        let customRegion = customMinneapolisRegion
        let plistData = try! PropertyListEncoder().encode([customRegion])
        userDefaults.set(plistData, forKey: RegionsService.storedRegionsUserDefaultsKey)

        let locationManager = LocationManagerMock()
        let locationService = LocationService(locationManager: locationManager)
        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults)

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

        let locationManager = LocationManagerMock()
        let locationService = LocationService(locationManager: locationManager)
        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults)

        expect(regionsService.currentRegion) == customRegion
    }

    func test_init_loadsCurrentRegion_autoSelectEnabled() {
        let customRegion = customMinneapolisRegion
        let plistData = try! PropertyListEncoder().encode(customRegion)
        userDefaults.set(plistData, forKey: RegionsService.currentRegionUserDefaultsKey)
        let locationManager = LocationManagerMock()

        locationManager.location = CLLocation(latitude: 47.632445, longitude: -122.312607)

        let locationService = LocationService(locationManager: locationManager)
        let regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults)

        expect(regionsService.currentRegion!.name) == "Puget Sound"
    }

    // It immediately downloads an up-to-date list of regions if that list hasn't been updated in at least a week.

    // It *does not* download a list of regions if the list was last updated less than a week ago.

    // MARK: - Persistence

    // It stores downloaded region data in user defaults when the regions property is set.

    // It loads the bundled regions when the data in the user defaults is corrupted.

    // It stores the current region in user defaults when that property is written.

    // It calls delegates to tell them that the current region is updated when that property is written.

    // MARK: - Network Data

    // It updates the 'last updated at' date in user defaults when the regions list is downloaded.

    // It updates the current region when the regions list is downloaded.

    // MARK: - Location Services

    // It updates the current region when the user's location changes

    // It does not update the user's current region or call `regionsServiceUnableToSelectRegion` when the user's location is nil

    // It calls `regionsServiceUnableToSelectRegion` if the user's current location does not match a known region.
}
