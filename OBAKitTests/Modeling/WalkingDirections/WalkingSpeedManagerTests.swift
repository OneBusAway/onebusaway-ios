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

    private struct DummyError: Error {}

    private var store: UserDefaultsStore {
        UserDefaultsStore(userDefaults: userDefaults)
    }

    // MARK: - requestAuthorizationAndSync

    @Test func `Request and sync when sample missing returns false and forces manual`() async {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.6

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: nil)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
        // Speed left untouched even on failure.
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.6)
    }

    @Test func `Request and sync when sample in range writes value and marks synced`() async {
        store.walkingSpeedSource = .manual
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 1.65)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == true)
        #expect(self.store.walkingSpeedSource == .synced)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.65)
    }

    @Test func `Request and sync when sample out of range does not write and forces manual`() async {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.4

        // 10 m/s sits well outside WalkingSpeed.validRange (0.5...5.0).
        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 10.0)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
        // Stored speed unchanged — the out-of-range sample must not leak in.
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.4)
    }

    @Test func `Opt-out while a sync is in flight wins over its trailing write`() async {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.4

        let gate = SpeedFetchGate()
        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: GatedSpeedProvider(gate: gate)
        )

        async let sync = manager.requestAuthorizationAndSync()
        // Deterministic rendezvous: proceed only once the sync is parked in the fetch,
        // so cancellation always races the post-fetch guard (never the pre-fetch one).
        await gate.waitUntilFetching()

        // What Settings does when the user turns the sync switch off.
        manager.stopSyncing()

        await gate.resume(returning: 1.7)
        let result = await sync

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
        // The late 1.7 sample must not leak in over the opt-out.
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.4)
    }

    @Test func `Request and sync when authorization throws forces manual`() async {
        store.walkingSpeedSource = .synced

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(authorizationError: DummyError(), sampleSpeed: 1.5)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
    }

    @Test func `Request and sync when provider unavailable forces manual`() async {
        store.walkingSpeedSource = .synced

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(isAvailable: false, sampleSpeed: 1.5)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
    }

    // MARK: - refreshIfPossible

    @Test func `Passive refresh with no sample leaves source and speed untouched`() async {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.65

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: nil)
        )

        await manager.refreshIfPossible()

        // The asymmetry: passive refresh must never downgrade source to .manual.
        #expect(self.store.walkingSpeedSource == .synced)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.65)
    }

    @Test func `Passive refresh with in range sample updates speed`() async {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 1.7)
        )

        await manager.refreshIfPossible()

        #expect(self.store.walkingSpeedSource == .synced)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.7)
    }

    @Test func `Passive refresh with out of range sample is no op`() async {
        store.walkingSpeedSource = .synced
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 0.1)
        )

        await manager.refreshIfPossible()

        #expect(self.store.walkingSpeedSource == .synced)
        expectClose(self.store.walkingSpeedMetersPerSecond, 1.4)
    }
}
