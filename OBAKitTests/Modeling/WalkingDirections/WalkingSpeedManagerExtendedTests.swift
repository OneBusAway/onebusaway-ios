//
//  WalkingSpeedManagerExtendedTests.swift
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

/// Extended tests for `WalkingSpeedManager` rapid successive calls,
/// speed boundary conditions, and state transitions.
@MainActor
@Suite(.serialized)
final class WalkingSpeedManagerExtendedTests: OBATestCase {

    private var store: UserDefaultsStore {
        UserDefaultsStore(userDefaults: userDefaults)
    }

    @Test func `Calling stopSyncing repeatedly remains idempotent and stable on manual`() {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.7

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: nil)
        )

        manager.stopSyncing()
        let speed1 = store.walkingSpeedMetersPerSecond
        let source1 = store.walkingSpeedSource

        manager.stopSyncing()
        let speed2 = store.walkingSpeedMetersPerSecond
        let source2 = store.walkingSpeedSource

        #expect(source1 == .manual)
        #expect(source2 == .manual)
        #expect(speed1 == speed2)
        #expect(speed1 == WalkingSpeedPreset.fast.rawValue)
    }

    @Test func `Sample exactly at lower valid range bound is accepted as synced`() async {
        store.walkingSpeedSource = .manual
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: WalkingSpeed.validRange.lowerBound) // 0.5
        )

        let success = await manager.requestAuthorizationAndSync()

        #expect(success == true)
        #expect(store.walkingSpeedSource == .synced)
        expectClose(store.walkingSpeedMetersPerSecond, 0.5)
    }

    @Test func `Sample exactly at upper valid range bound is accepted as synced`() async {
        store.walkingSpeedSource = .manual
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: WalkingSpeed.validRange.upperBound) // 5.0
        )

        let success = await manager.requestAuthorizationAndSync()

        #expect(success == true)
        #expect(store.walkingSpeedSource == .synced)
        expectClose(store.walkingSpeedMetersPerSecond, 5.0)
    }

    @Test func `Sample slightly below lower bound is rejected`() async {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 0.49)
        )

        let success = await manager.requestAuthorizationAndSync()

        #expect(success == false)
        #expect(store.walkingSpeedSource == .manual)
        expectClose(store.walkingSpeedMetersPerSecond, 1.4)
    }

    @Test func `Sample slightly above upper bound is rejected`() async {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 5.01)
        )

        let success = await manager.requestAuthorizationAndSync()

        #expect(success == false)
        #expect(store.walkingSpeedSource == .manual)
        expectClose(store.walkingSpeedMetersPerSecond, 1.4)
    }

    @Test func `Passive refresh with exact lower bound updates speed`() async {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 0.5)
        )

        await manager.refreshIfPossible()

        #expect(store.walkingSpeedSource == .synced)
        expectClose(store.walkingSpeedMetersPerSecond, 0.5)
    }
}
