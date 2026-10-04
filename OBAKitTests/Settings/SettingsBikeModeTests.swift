//
//  SettingsBikeModeTests.swift
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

/// Eureka fires a row's `onChange` when `form.setValues` seeds it from nil, so anything hung off
/// a switch would run on every Settings open. Both HealthKit rows therefore ignore the seed
/// via `isSeedingForm`: opening Settings never syncs, never downgrades the source, and never
/// toasts. Only an explicit toggle-on reaches the manager. These tests drive the real
/// controller with a spy HealthKit provider and pin down which user actions — and which
/// non-actions — reach the manager.
@MainActor
@Suite(.serialized)
final class SettingsBikeModeTests: OBATestCase {

    /// Records authorization requests so a test can assert that merely opening Settings makes none.
    private final class SpyProvider: BikeSpeedHealthKitProviding {
        var isAvailable = true
        var sampleSpeed: Double?
        private(set) var requestAuthorizationCount = 0

        func requestAuthorization() async throws {
            requestAuthorizationCount += 1
        }

        func fetchAverageBikeSpeed() async -> Double? {
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
        application.bikeModeManager = BikeModeManager(userDataStore: application.userDataStore, healthKit: provider)
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

    /// The HealthKit row's `onChange` hops into a `Task`; give it a bounded window to land.
    private func settle(until condition: () -> Bool = { true }) async throws {
        for _ in 0..<50 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        // One extra beat so a *negative* assertion (nothing happened) isn't just racing the Task.
        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Bike Mode switch

    @Test func `Bike mode switch seeds from the store`() throws {
        store.bikeModeEnabled = true
        let controller = makeLoadedController()

        #expect(try self.row(controller, "bikeModeEnabled").value == true)
    }

    /// The regression: opening Settings with Bike Mode on used to start a HealthKit sync (and,
    /// when it failed, a toast) every single time, because seeding the switch fired its `onChange`.
    @Test func `Opening settings with bike mode on makes no health kit request`() async throws {
        store.bikeModeEnabled = true
        store.bikeSpeedSource = .manual
        provider.sampleSpeed = nil

        _ = makeLoadedController()
        try await settle()

        #expect(self.provider.requestAuthorizationCount == 0)
        #expect(self.store.bikeSpeedSource == .manual)
    }

    @Test func `Toggling bike mode persists on dismissal without touching health kit`() async throws {
        store.bikeModeEnabled = false
        let controller = makeLoadedController()

        try row(controller, "bikeModeEnabled").value = true
        controller.viewWillDisappear(false)
        try await settle()

        #expect(self.store.bikeModeEnabled == true)
        #expect(self.provider.requestAuthorizationCount == 0)
    }

    // MARK: - Use Health app data switch

    @Test(.enabled(if: HKHealthStore.isHealthDataAvailable()))
    func `Health kit switch seeds from the speed source`() throws {
        store.bikeSpeedSource = .healthKit
        provider.sampleSpeed = 5.0
        let controller = makeLoadedController()

        #expect(try self.row(controller, "bikeSpeedUseHealthKit").value == true)
    }

    @Test(.enabled(if: HKHealthStore.isHealthDataAvailable()))
    func `Turning health kit on syncs and marks the source`() async throws {
        store.bikeSpeedSource = .manual
        provider.sampleSpeed = 5.0
        let controller = makeLoadedController()

        try row(controller, "bikeSpeedUseHealthKit").value = true
        try await settle { self.store.bikeSpeedSource == .healthKit }

        #expect(self.provider.requestAuthorizationCount == 1)
        #expect(self.store.bikeSpeedSource == .healthKit)
        expectClose(self.store.bikeSpeedMetersPerSecond, 5.0)
        #expect(try self.row(controller, "bikeSpeedUseHealthKit").value == true)
    }

    @Test(.enabled(if: HKHealthStore.isHealthDataAvailable()))
    func `Turning health kit on with no sample reverts the switch`() async throws {
        store.bikeSpeedSource = .manual
        provider.sampleSpeed = nil
        let controller = makeLoadedController()

        try row(controller, "bikeSpeedUseHealthKit").value = true
        try await settle { (try? self.row(controller, "bikeSpeedUseHealthKit").value) == false }

        #expect(self.provider.requestAuthorizationCount == 1)
        #expect(self.store.bikeSpeedSource == .manual)
        #expect(try self.row(controller, "bikeSpeedUseHealthKit").value == false)
    }

    /// Opening Settings must not sync at all: a rider with no samples in the last 30 days
    /// (common in winter) keeps their opt-in and sees no error toast. Only an explicit
    /// toggle-on sync may downgrade the source to `.manual` (#1458.2).
    @Test(.enabled(if: HKHealthStore.isHealthDataAvailable()))
    func `Opening settings with a stale health kit source keeps the opt-in`() async throws {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 5.0
        provider.sampleSpeed = nil
        let controller = makeLoadedController()

        try await settle()

        #expect(self.provider.requestAuthorizationCount == 0)
        #expect(self.store.bikeSpeedSource == .healthKit)
        expectClose(self.store.bikeSpeedMetersPerSecond, 5.0)
        #expect(try self.row(controller, "bikeSpeedUseHealthKit").value == true)
    }

    @Test(.enabled(if: HKHealthStore.isHealthDataAvailable()))
    func `Turning health kit off persists manual on dismissal and keeps the speed`() async throws {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 5.0
        provider.sampleSpeed = 5.0
        let controller = makeLoadedController()
        try await settle()

        try row(controller, "bikeSpeedUseHealthKit").value = false
        controller.viewWillDisappear(false)

        #expect(self.store.bikeSpeedSource == .manual)
        expectClose(self.store.bikeSpeedMetersPerSecond, 5.0)
    }
}
