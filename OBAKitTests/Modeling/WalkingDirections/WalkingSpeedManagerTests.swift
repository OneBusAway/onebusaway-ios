//
//  WalkingSpeedManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class WalkingSpeedManagerTests: OBATestCase {

    private struct FakeProvider: WalkingSpeedHealthKitProviding {
        var isAvailable: Bool = true
        var authorizationError: Error?
        var sampleSpeed: Double?

        func requestAuthorization() async throws {
            if let authorizationError {
                throw authorizationError
            }
        }

        func fetchLatestWalkingSpeed() async -> Double? {
            sampleSpeed
        }
    }

    private struct DummyError: Error {}

    private var store: UserDefaultsStore {
        UserDefaultsStore(userDefaults: userDefaults)
    }

    // MARK: - requestHealthKitAuthorizationAndSync

    @Test func `Request and sync when sample missing returns false and forces manual`() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.6

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: nil)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
        // Speed left untouched even on failure.
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.6)
    }

    @Test func `Request and sync when sample in range writes value and marks health kit`() async {
        store.walkingSpeedSource = .manual
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 1.65)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == true)
        #expect(self.store.walkingSpeedSource == .healthKit)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.65)
    }

    @Test func `Request and sync when sample out of range does not write and forces manual`() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.4

        // 10 m/s sits well outside WalkingSpeed.validRange (0.5...5.0).
        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 10.0)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
        // Stored speed unchanged — the out-of-range sample must not leak in.
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.4)
    }

    @Test func `Request and sync when authorization throws forces manual`() async {
        store.walkingSpeedSource = .healthKit

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(authorizationError: DummyError(), sampleSpeed: 1.5)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
    }

    @Test func `Request and sync when health kit unavailable forces manual`() async {
        store.walkingSpeedSource = .healthKit

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(isAvailable: false, sampleSpeed: 1.5)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
    }

    // MARK: - refreshFromHealthKitIfPossible

    @Test func `Passive refresh with no sample leaves source and speed untouched`() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.65

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: nil)
        )

        await manager.refreshFromHealthKitIfPossible()

        // The asymmetry: passive refresh must never downgrade source to .manual.
        #expect(self.store.walkingSpeedSource == .healthKit)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.65)
    }

    @Test func `Passive refresh with in range sample updates speed`() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 1.7)
        )

        await manager.refreshFromHealthKitIfPossible()

        #expect(self.store.walkingSpeedSource == .healthKit)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.7)
    }

    @Test func `Passive refresh with out of range sample is no op`() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 0.1)
        )

        await manager.refreshFromHealthKitIfPossible()

        #expect(self.store.walkingSpeedSource == .healthKit)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.4)
    }
}
