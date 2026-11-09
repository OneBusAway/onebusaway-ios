//
//  SettingsWalkingModeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit
@testable import OBAKitCore
import Foundation
import Testing

/// Mirrors SettingsBikeModeTests for the walking switch. Opening Settings must
/// never sync, never downgrade the source, and never toast. Only an explicit
/// toggle-on reaches the manager.
@MainActor
@Suite(.serialized)
final class SettingsWalkingModeTests: OBATestCase {

    private var queue: OperationQueue!
    private var application: Application!
    private var provider: SpySpeedProvider!

    private var store: UserDataStore { application.userDataStore }

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        provider = SpySpeedProvider()
        application.walkingSpeedManager = WalkingSpeedManager(userDataStore: application.userDataStore, provider: provider)
        application.config.speedSync = .stub(provider)
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func makeViewModel() -> SettingsViewModel {
        SettingsViewModel(application: application)
    }

    private func settle(until condition: () -> Bool = { true }) async throws {
        for _ in 0..<50 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func `Opening settings with walking on makes no sync request`() async throws {
        store.walkingSpeedSource = .manual
        provider.sampleSpeed = nil

        _ = makeViewModel()
        try await settle()

        #expect(self.provider.requestAuthorizationCount == 0)
        #expect(self.store.walkingSpeedSource == .manual)
    }

    /// Opening Settings must not sync at all. A walker with no samples in the
    /// last 30 days keeps the opt-in and sees no error toast. Only an explicit
    /// toggle-on sync may downgrade the source to `.manual`.
    @Test func `Opening settings with a stale walking synced source keeps the opt-in`() async throws {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.65
        provider.sampleSpeed = nil
        let vm = makeViewModel()

        try await settle()

        #expect(self.provider.requestAuthorizationCount == 0)
        #expect(self.store.walkingSpeedSource == .synced)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.65)
        #expect(vm.walkingSpeedIsSynced == true)
    }
}
