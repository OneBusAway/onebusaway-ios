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

    /// Defers the sample until the test releases it, so an opt-out can race a sync in flight.
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

    private struct GatedProvider: WalkingSpeedHealthKitProviding {
        var isAvailable: Bool = true
        let gate: FetchGate

        func requestAuthorization() async throws {}

        func fetchLatestWalkingSpeed() async -> Double? {
            await gate.wait()
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

    @Test func `Opt-out while a sync is in flight wins over its trailing write`() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.4

        let gate = FetchGate()
        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: GatedProvider(gate: gate)
        )

        async let sync = manager.requestHealthKitAuthorizationAndSync()
        // Deterministic rendezvous: proceed only once the sync is parked in the fetch,
        // so cancellation always races the post-fetch guard (never the pre-fetch one).
        await gate.waitUntilFetching()

        // What `saveWalkingSpeedValues` does when the user turns "Use Health app data" off.
        manager.cancelPendingSync()
        store.walkingSpeedSource = .manual

        await gate.resume(returning: 1.7)
        let result = await sync

        #expect(result == false)
        #expect(self.store.walkingSpeedSource == .manual)
        // The late 1.7 sample must not leak in over the opt-out.
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
