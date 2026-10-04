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

    private struct FakeProvider: BikeSpeedHealthKitProviding {
        var isAvailable: Bool = true
        var authorizationError: Error?
        var sampleSpeed: Double?

        func requestAuthorization() async throws {
            if let authorizationError {
                throw authorizationError
            }
        }

        func fetchAverageBikeSpeed() async -> Double? {
            sampleSpeed
        }
    }

    /// Defers the average until the test releases it, so an opt-out can race a sync in flight.
    private actor FetchGate {
        private var continuation: CheckedContinuation<Double?, Never>?
        private var fetchingContinuation: CheckedContinuation<Void, Never>?

        func wait() async -> Double? {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                // Signal arrival: a test awaiting `waitUntilFetching()` now proceeds.
                self.fetchingContinuation?.resume()
                self.fetchingContinuation = nil
            }
        }

        /// Returns only after `wait()` has stored its continuation, so the test knows
        /// the sync is parked in the fetch (and not still before it) before cancelling.
        func waitUntilFetching() async {
            guard continuation == nil else { return }
            await withCheckedContinuation { continuation in
                self.fetchingContinuation = continuation
            }
        }

        func resume(returning value: Double?) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    private struct GatedProvider: BikeSpeedHealthKitProviding {
        var isAvailable: Bool = true
        let gate: FetchGate

        func requestAuthorization() async throws {}

        func fetchAverageBikeSpeed() async -> Double? {
            await gate.wait()
        }
    }

    private struct DummyError: Error {}

    private var store: UserDefaultsStore {
        UserDefaultsStore(userDefaults: userDefaults)
    }

    // MARK: - requestHealthKitAuthorizationAndSync

    @Test func `Request and sync when sample missing returns false and forces manual`() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.5

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: nil)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
        // Speed left untouched even on failure.
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.5)
    }

    @Test func `Request and sync when sample in range writes value and marks health kit`() async {
        store.bikeSpeedSource = .manual
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 5.5)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == true)
        #expect(self.store.bikeSpeedSource == .healthKit)
        expectClose(self.store.bikeSpeedMetersPerSecond, 5.5)
    }

    @Test func `Request and sync when sample out of range does not write and forces manual`() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.2

        // 30 m/s sits well outside BikeSpeed.validRange (2.0...20.0).
        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 30.0)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
        // Stored speed unchanged — the out-of-range sample must not leak in.
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.2)
    }

    @Test func `Request and sync when average is a walk-speed crawl rejects and forces manual`() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.2

        // 1.2 m/s passed the old 1.0 lower bound and rendered a bike ETA slower than
        // walking; the raised 2.0 bound (above the 1.8 fast-walk preset) rejects it (#1458.1).
        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 1.2)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.2)
    }

    @Test func `Opt-out while a sync is in flight wins over its trailing write`() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.2

        let gate = FetchGate()
        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: GatedProvider(gate: gate)
        )

        async let sync = manager.requestHealthKitAuthorizationAndSync()
        // Deterministic rendezvous: proceed only once the sync is parked in the fetch,
        // so cancellation always races the post-fetch guard (never the pre-fetch one).
        await gate.waitUntilFetching()

        // What `saveBikeModeValues` does when the user turns "Use Health app data" off.
        manager.cancelPendingSync()
        store.bikeSpeedSource = .manual

        await gate.resume(returning: 5.0)
        let result = await sync

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
        // The late 5.0 average must not leak in over the opt-out.
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.2)
    }

    @Test func `Request and sync when authorization throws forces manual`() async {
        store.bikeSpeedSource = .healthKit

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(authorizationError: DummyError(), sampleSpeed: 5.0)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
    }

    @Test func `Request and sync when health kit unavailable forces manual`() async {
        store.bikeSpeedSource = .healthKit

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(isAvailable: false, sampleSpeed: 5.0)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        #expect(result == false)
        #expect(self.store.bikeSpeedSource == .manual)
    }

    // MARK: - refreshFromHealthKitIfPossible

    @Test func `Passive refresh with no sample leaves source and speed untouched`() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 5.5

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: nil)
        )

        await manager.refreshFromHealthKitIfPossible()

        // The asymmetry: passive refresh must never downgrade source to .manual.
        #expect(self.store.bikeSpeedSource == .healthKit)
        expectClose(self.store.bikeSpeedMetersPerSecond, 5.5)
    }

    @Test func `Passive refresh with in range sample updates speed`() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 6.0)
        )

        await manager.refreshFromHealthKitIfPossible()

        #expect(self.store.bikeSpeedSource == .healthKit)
        expectClose(self.store.bikeSpeedMetersPerSecond, 6.0)
    }

    @Test func `Passive refresh with out of range sample is no op`() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 0.5)
        )

        await manager.refreshFromHealthKitIfPossible()

        #expect(self.store.bikeSpeedSource == .healthKit)
        expectClose(self.store.bikeSpeedMetersPerSecond, 4.2)
    }
}
