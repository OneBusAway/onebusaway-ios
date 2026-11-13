//
//  BikeModeManagerExtendedTests.swift
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

/// Extended edge-case tests for `BikeModeManager` velocity bounds,
/// authorization failures, and race recovery.
@MainActor
@Suite(.serialized)
final class BikeModeManagerExtendedTests: OBATestCase {

    private struct DummyError: Error {}

    private var store: UserDefaultsStore {
        UserDefaultsStore(userDefaults: userDefaults)
    }

    @Test func `Request and sync when authorization throws forces manual`() async {
        store.bikeSpeedSource = .synced

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(authorizationError: DummyError(), sampleSpeed: 5.0)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(store.bikeSpeedSource == .manual)
    }

    @Test func `Request and sync when sample exactly at lower valid range bound succeeds`() async {
        store.bikeSpeedSource = .manual
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: BikeSpeed.validRange.lowerBound) // 2.0
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == true)
        #expect(store.bikeSpeedSource == .synced)
        expectClose(store.bikeSpeedMetersPerSecond, 2.0)
    }

    @Test func `Request and sync when sample exactly at upper valid range bound succeeds`() async {
        store.bikeSpeedSource = .manual
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: BikeSpeed.validRange.upperBound) // 20.0
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == true)
        #expect(store.bikeSpeedSource == .synced)
        expectClose(store.bikeSpeedMetersPerSecond, 20.0)
    }

    @Test func `Request and sync when sample slightly below lower bound fails and forces manual`() async {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 1.99)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(store.bikeSpeedSource == .manual)
        expectClose(store.bikeSpeedMetersPerSecond, 4.2)
    }

    @Test func `Request and sync when sample slightly above upper bound fails and forces manual`() async {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 20.01)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(store.bikeSpeedSource == .manual)
        expectClose(store.bikeSpeedMetersPerSecond, 4.2)
    }

    @Test func `Calling stopSyncing repeatedly remains idempotent and leaves bike speed untouched`() {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 6.0

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: nil)
        )

        manager.stopSyncing()
        #expect(store.bikeSpeedSource == .manual)
        #expect(store.bikeSpeedMetersPerSecond == 6.0)

        manager.stopSyncing()
        #expect(store.bikeSpeedSource == .manual)
        #expect(store.bikeSpeedMetersPerSecond == 6.0)
    }
}
