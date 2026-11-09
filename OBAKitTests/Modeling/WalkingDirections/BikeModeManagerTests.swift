//
//  BikeModeManagerTests.swift
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
final class BikeModeManagerTests: OBATestCase {

    private struct DummyError: Error {}

    private var store: UserDefaultsStore {
        UserDefaultsStore(userDefaults: userDefaults)
    }

    // MARK: - requestAuthorizationAndSync

    @Test func `Request and sync when sample missing returns false and forces manual`() async {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 4.5

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: nil)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
        // Speed left untouched even on failure.
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.5)
    }

    @Test func `Request and sync when sample in range writes value and marks synced`() async {
        store.bikeSpeedSource = .manual
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 5.5)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == true)
        #expect(self.store.bikeSpeedSource == .synced)
        expectClose(self.store.bikeSpeedMetersPerSecond, 5.5)
    }

    @Test func `Request and sync when sample out of range does not write and forces manual`() async {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 4.2

        // 30 m/s sits well outside BikeSpeed.validRange (2.0...20.0).
        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 30.0)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
        // Stored speed unchanged — the out-of-range sample must not leak in.
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.2)
    }

    @Test func `Request and sync when average is a walk-speed crawl rejects and forces manual`() async {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 4.2

        // 1.2 m/s passed the old 1.0 lower bound and rendered a bike ETA slower than
        // walking; the raised 2.0 bound (above the 1.8 fast-walk preset) rejects it (#1458.1).
        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 1.2)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.2)
    }

    @Test func `Opt-out while a sync is in flight wins over its trailing write`() async {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 4.2

        let gate = SpeedFetchGate()
        let manager = BikeModeManager(
            userDataStore: store,
            provider: GatedSpeedProvider(gate: gate)
        )

        async let sync = manager.requestAuthorizationAndSync()
        // Deterministic rendezvous: proceed only once the sync is parked in the fetch,
        // so cancellation always races the post-fetch guard (never the pre-fetch one).
        await gate.waitUntilFetching()

        // What Settings does when the user turns the sync switch off.
        manager.stopSyncing()

        await gate.resume(returning: 5.0)
        let result = await sync

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
        // The late 5.0 average must not leak in over the opt-out.
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.2)
    }

    @Test func `Request and sync when authorization throws forces manual`() async {
        store.bikeSpeedSource = .synced

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(authorizationError: DummyError(), sampleSpeed: 5.0)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
    }

    @Test func `Request and sync when provider unavailable forces manual`() async {
        store.bikeSpeedSource = .synced

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(isAvailable: false, sampleSpeed: 5.0)
        )

        let result = await manager.requestAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
    }

    // MARK: - refreshIfPossible

    @Test func `Passive refresh with no sample leaves source and speed untouched`() async {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 5.5

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: nil)
        )

        await manager.refreshIfPossible()

        // The asymmetry: passive refresh must never downgrade source to .manual.
        #expect(self.store.bikeSpeedSource == .synced)
        expectClose(self.store.bikeSpeedMetersPerSecond, 5.5)
    }

    @Test func `Passive refresh with in range sample updates speed`() async {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 6.0)
        )

        await manager.refreshIfPossible()

        #expect(self.store.bikeSpeedSource == .synced)
        expectClose(self.store.bikeSpeedMetersPerSecond, 6.0)
    }

    @Test func `Passive refresh with out of range sample is no op`() async {
        store.bikeSpeedSource = .synced
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            provider: FakeSpeedProvider(sampleSpeed: 0.5)
        )

        await manager.refreshIfPossible()

        #expect(self.store.bikeSpeedSource == .synced)
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.2)
    }
}
