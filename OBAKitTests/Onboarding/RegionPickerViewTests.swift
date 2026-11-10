//
//  RegionPickerViewTests.swift
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

/// Tests for `RegionPickerView.filteredRegions`. The "show inactive" and "show
/// experimental" toggles are `@State`, so outside a hosted view only their
/// default (off) is reachable.
@MainActor
@Suite(.serialized)
final class RegionPickerViewTests: OBATestCase {

    @Test func `Region list hides inactive and experimental regions by default`() throws {
        let fixture = try Fixtures.loadSomeRegions()
        // Each filter needs regions only it removes, or dropping one filter could go unnoticed.
        #expect(fixture.contains { !$0.isActive && !$0.isExperimental })
        #expect(fixture.contains { $0.isActive && $0.isExperimental })

        let service = RegionsService(
            apiService: regionsAPIService,
            locationService: LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock()),
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: MockRegionsFileStorage(defaultRegions: fixture)
        )
        let coordinator = RegionPickerCoordinator(regionsService: service, userDataStore: UserDefaultsStore(userDefaults: userDefaults))
        let view = RegionPickerView(regionProvider: coordinator)

        // The active, non-experimental regions in regions-v3.json, in file order.
        #expect(view.filteredRegions.map(\.regionIdentifier) == [0, 1, 2, 4, 11, 12, 15])
    }
}
