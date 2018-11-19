//
//  RegionsServiceTests.swift
//  OBALocationKitTests
//
//  Created by Aaron Brethorst on 11/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import XCTest
import OBATestHelpers
@testable import OBALocationKit
import CoreLocation
import Nimble

class RegionsServiceTests: OBATestCase {
    let userDefaults = UserDefaults.standard

    public override func tearDown() {
        super.tearDown()

        UserDefaults.resetStandardUserDefaults()
    }

    // MARK: - Upon creating the Regions Service

    // It loads bundled regions from its framework when no other data exists

    // It loads regions saved to the user defaults when they exist

    // It loads the current region from user defaults when it exists

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
