//
//  StandaloneAPIServiceProviderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class StandaloneAPIServiceProviderTests: OBATestCase {

    private var locationManager: LocationManagerMock!
    private var locationService: LocationService!
    private var dataLoader: MockDataLoader!

    override init() async throws {
        try await super.init()
        locationManager = LocationManagerMock()
        locationService = LocationService(userDefaults: userDefaults, locationManager: locationManager, startsUpdatesOnAuthorization: false)
        dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
    }

    private func makeRegionsService() -> RegionsService {
        RegionsService(
            apiService: buildRegionsAPIService(dataLoader: dataLoader),
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: MockRegionsFileStorage()
        )
    }

    private func makeProvider(_ regionsService: RegionsService) -> StandaloneAPIServiceProvider {
        StandaloneAPIServiceProvider(regionsService: regionsService, apiKey: apiKey, appVersion: appVersion, uuid: uuid, dataLoader: dataLoader)
    }

    @Test func `Seeds from the current region at init`() {
        userDefaults.set(pugetSoundRegionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let regionsService = makeRegionsService()
        #expect(regionsService.currentRegion?.name == "Puget Sound")

        let provider = makeProvider(regionsService)

        #expect(provider.apiService != nil)
    }

    @Test func `Is nil with no region`() {
        let regionsService = makeRegionsService()
        #expect(regionsService.currentRegion == nil)

        let provider = makeProvider(regionsService)

        #expect(provider.apiService == nil)
    }

    @Test func `Rebuilds on updatedRegion`() throws {
        let regionsService = makeRegionsService()
        let provider = makeProvider(regionsService)

        let tampa = try #require(regionsService.regions.first { $0.name == "Tampa Bay" })
        regionsService.currentRegion = tampa

        #expect(provider.apiService != nil)
    }

    @Test func `Rebuilds on updatedRegionsList`() async throws {
        userDefaults.set(pugetSoundRegionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let regionsService = makeRegionsService()
        let provider = makeProvider(regionsService)
        let before = try #require(provider.apiService)

        try await regionsService.refreshRegions()

        let after = try #require(provider.apiService)
        #expect(before !== after)
    }

    @Test func `Is retained by nothing but its owner`() {
        let regionsService = makeRegionsService()
        weak var weakProvider: StandaloneAPIServiceProvider?
        do {
            let provider = makeProvider(regionsService)
            weakProvider = provider
            #expect(weakProvider != nil)
        }
        #expect(weakProvider == nil, "RegionsService holds delegates weakly; the host must retain the provider")
    }
}
