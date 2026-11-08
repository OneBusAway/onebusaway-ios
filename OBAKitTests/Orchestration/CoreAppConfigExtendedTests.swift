//
//  CoreAppConfigExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `CoreAppConfig` configuration matrix: optional bundled regions path,
/// fixed region overrides, custom API keys, and custom default arrival filters.
@Suite(.serialized)
@MainActor
final class CoreAppConfigExtendedTests {

    private let suiteName = "org.opentransit.tests.CoreAppConfigExtendedTests"

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func makeConfig(
        regionsURL: URL? = URL(string: "https://regions.opentransit.org")!,
        apiKey: String = "CUSTOM_KEY_123",
        appVersion: String = "26.5.0",
        bundledPath: String = "regions.json",
        apiPath: String? = "/api/v3/regions",
        fixedRegionName: String? = nil,
        fixedRegionURL: URL? = nil,
        filter: ArrivalDepartureFilter = .estimatedOnly
    ) -> CoreAppConfig {
        let userDefaults = UserDefaults(suiteName: suiteName)!
        let queue = OperationQueue()
        let locService = LocationService(userDefaults: userDefaults, locationManager: CLLocationManager())
        let dataLoader = URLSession.shared

        return CoreAppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            queue: queue,
            locationService: locService,
            bundledRegionsFilePath: bundledPath,
            regionsAPIPath: apiPath,
            dataLoader: dataLoader,
            fixedRegionName: fixedRegionName,
            fixedRegionOBABaseURL: fixedRegionURL,
            defaultArrivalDepartureFilter: filter
        )
    }

    // MARK: - Nil Optional Fields

    @Test func `CoreAppConfig with nil optional parameters sets expected defaults`() {
        let config = makeConfig(
            regionsURL: nil,
            bundledPath: "test_bundled.json",
            apiPath: nil,
            fixedRegionName: nil,
            fixedRegionURL: nil,
            filter: .all
        )

        #expect(config.regionsBaseURL == nil)
        #expect(config.bundledRegionsFilePath == "test_bundled.json")
        #expect(config.regionsAPIPath == nil)
        #expect(config.fixedRegionName == nil)
        #expect(config.fixedRegionOBABaseURL == nil)
        #expect(config.defaultArrivalDepartureFilter == .all)
    }

    // MARK: - Fixed Region Configuration

    @Test func `CoreAppConfig preserves fixed region settings when provided`() {
        let fixedURL = URL(string: "https://api.tampa.opentransit.org")!
        let config = makeConfig(
            fixedRegionName: "Tampa",
            fixedRegionURL: fixedURL,
            filter: .scheduledOnly
        )

        #expect(config.fixedRegionName == "Tampa")
        #expect(config.fixedRegionOBABaseURL == fixedURL)
        #expect(config.defaultArrivalDepartureFilter == .scheduledOnly)
    }

    // MARK: - Regions API Paths and Versions

    @Test func `CoreAppConfig stores custom regions API path and version string`() {
        let config = makeConfig(
            appVersion: "3.2.1-beta",
            bundledPath: "fallback_regions.json",
            apiPath: "/custom/regions.json"
        )

        #expect(config.appVersion == "3.2.1-beta")
        #expect(config.bundledRegionsFilePath == "fallback_regions.json")
        #expect(config.regionsAPIPath == "/custom/regions.json")
    }
}
