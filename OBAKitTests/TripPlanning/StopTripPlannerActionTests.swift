//
//  StopTripPlannerActionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Gates the stop-page "Directions to/from Here" affordances on OTP availability
/// and the per-region trip-planning preference.
@MainActor
@Suite(.serialized)
final class StopTripPlannerActionTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test func `isAvailable is true when OTP is running and trip planning is enabled`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let maybeRegion = await waitForRegion(application)
        let region = try #require(maybeRegion)

        #expect(region.supportsOTP)
        #expect(application.features.tripPlanning == .running)
        #expect(application.userDataStore.isTripPlanningEnabled(for: region))
        #expect(StopTripPlannerAction.isAvailable(application: application))
    }

    @Test func `isAvailable is false when trip planning is disabled for the region`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let maybeRegion = await waitForRegion(application)
        let region = try #require(maybeRegion)

        application.userDataStore.setTripPlanningEnabled(false, for: region)

        #expect(application.features.tripPlanning == .running)
        #expect(!StopTripPlannerAction.isAvailable(application: application))
    }

    @Test func `isAvailable is false when the region has no OTP`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        // Seed a non-OTP region before Application init so RegionsService loads it.
        userDefaults.set(2, forKey: "OBACurrentRegionIdentifierUserDefaultsKey") // MTA New York — no OTP
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: URL(string: "https://bustime.mta.info/")!)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader
        )
        let application = Application(config: config)
        let maybeRegion = await waitForRegion(application)
        let region = try #require(maybeRegion)

        #expect(!region.supportsOTP)
        #expect(application.features.tripPlanning == .off)
        #expect(!StopTripPlannerAction.isAvailable(application: application))
    }

    /// `fixedRegionName` selects the region during Application init; poll briefly
    /// in case regions load finishes after construction.
    private func waitForRegion(_ application: Application) async -> Region? {
        for _ in 0..<40 {
            if let region = application.currentRegion ?? application.regionsService.currentRegion {
                return region
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return application.currentRegion ?? application.regionsService.currentRegion
    }
}
