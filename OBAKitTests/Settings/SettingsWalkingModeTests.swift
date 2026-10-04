//
//  SettingsWalkingModeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Eureka
import HealthKit
@testable import OBAKit
@testable import OBAKitCore
import Foundation
import Testing

/// Mirrors SettingsBikeModeTests for the walking row. `form.setValues` fires
/// `onChange` while it seeds, so both HealthKit rows ignore the seed via
/// `isSeedingForm`. Opening Settings must never sync, never downgrade the
/// source, and never toast. Only an explicit toggle-on reaches the manager.
@MainActor
@Suite(.serialized)
final class SettingsWalkingModeTests: OBATestCase {

    private final class SpyProvider: WalkingSpeedHealthKitProviding {
        var isAvailable = true
        var sampleSpeed: Double?
        private(set) var requestAuthorizationCount = 0

        func requestAuthorization() async throws {
            requestAuthorizationCount += 1
        }

        func fetchLatestWalkingSpeed() async -> Double? {
            sampleSpeed
        }
    }

    private var queue: OperationQueue!
    private var application: Application!
    private var provider: SpyProvider!

    private var store: UserDataStore { application.userDataStore }

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        provider = SpyProvider()
        application.walkingSpeedManager = WalkingSpeedManager(userDataStore: application.userDataStore, healthKit: provider)
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func makeLoadedController() -> SettingsViewController {
        let controller = SettingsViewController(application: application)
        controller.loadViewIfNeeded()
        return controller
    }

    private func row(_ controller: SettingsViewController, _ tag: String) throws -> SwitchRow {
        try #require(controller.form.rowBy(tag: tag) as? SwitchRow)
    }

    private func settle(until condition: () -> Bool = { true }) async throws {
        for _ in 0..<50 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func `Opening settings with walking on makes no health kit request`() async throws {
        store.walkingSpeedSource = .manual
        provider.sampleSpeed = nil

        _ = makeLoadedController()
        try await settle()

        #expect(self.provider.requestAuthorizationCount == 0)
        #expect(self.store.walkingSpeedSource == .manual)
    }

    /// Opening Settings must not sync at all. A walker with no samples in the
    /// last 30 days keeps the opt-in and sees no error toast. Only an explicit
    /// toggle-on sync may downgrade the source to `.manual`.
    @Test(.enabled(if: HKHealthStore.isHealthDataAvailable()))
    func `Opening settings with a stale walking health kit source keeps the opt-in`() async throws {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.65
        provider.sampleSpeed = nil
        let controller = makeLoadedController()

        try await settle()

        #expect(self.provider.requestAuthorizationCount == 0)
        #expect(self.store.walkingSpeedSource == .healthKit)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.65)
        #expect(try self.row(controller, "walkingSpeedUseHealthKit").value == true)
    }
}
