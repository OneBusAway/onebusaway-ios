//
//  SpeedSyncRetirementTests.swift
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

/// A rider who synced a speed, then updates to a build with no speed provider, must end
/// up on a manual speed: Settings has no switch left for them to turn sync off with.
@MainActor
@Suite(.serialized)
final class SpeedSyncRetirementTests: OBATestCase {

    private struct NoSpeedProvider: SpeedProviding {
        var isAvailable = true
        func requestAuthorization() async throws {}
        func fetchSpeed() async -> Double? { nil }
    }

    private var queue: OperationQueue!
    private var application: Application!

    private var store: UserDataStore { application.userDataStore }

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func installProvider(isAvailable: Bool = true) {
        let provider = NoSpeedProvider(isAvailable: isAvailable)
        application.config.speedSync = SpeedSyncConfiguration(
            walkingProvider: provider,
            bikeProvider: provider,
            text: SpeedSyncText(toggleTitle: "", walkingFooter: "", walkingFailureMessage: "", bikeFooter: "", bikeFailureMessage: "")
        )
    }

    @Test func `Without a provider a synced walking speed becomes the nearest manual preset`() {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.65

        application.retireSyncedSpeedsIfUnsupported()

        #expect(store.walkingSpeedSource == .manual)
        #expect(store.walkingSpeedMetersPerSecond == WalkingSpeedPreset.fast.rawValue)
    }

    @Test func `Without a provider a synced bike speed stays but becomes manual`() {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 5.5

        application.retireSyncedSpeedsIfUnsupported()

        #expect(store.bikeSpeedSource == .manual)
        #expect(store.bikeSpeedMetersPerSecond == 5.5)
    }

    @Test func `Without a provider a manual walking speed is left alone`() {
        store.walkingSpeedSource = .manual
        store.walkingSpeedMetersPerSecond = 1.65

        application.retireSyncedSpeedsIfUnsupported()

        #expect(store.walkingSpeedMetersPerSecond == 1.65)
    }

    @Test func `With a provider a synced speed stays synced`() {
        installProvider()
        store.walkingSpeedSource = .synced
        store.bikeSpeedSource = .synced

        application.retireSyncedSpeedsIfUnsupported()

        #expect(store.walkingSpeedSource == .synced)
        #expect(store.bikeSpeedSource == .synced)
    }

    @Test func `Settings offers no sync switches without a provider`() {
        #expect(SettingsViewModel(application: application).speedSyncText == nil)
    }

    @Test func `Settings offers no sync switches when the provider is unavailable`() {
        installProvider(isAvailable: false)

        #expect(SettingsViewModel(application: application).speedSyncText == nil)
    }

    @Test func `Settings offers the sync switches with an available provider`() {
        installProvider()

        #expect(SettingsViewModel(application: application).speedSyncText != nil)
    }
}
