//
//  WalkingSpeedManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

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

    func test_requestAndSync_whenSampleMissing_returnsFalseAndForcesManual() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.6

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: nil)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == false
        expect(self.store.walkingSpeedSource) == .manual
        // Speed left untouched even on failure.
        expect(self.store.walkingSpeedMetersPerSecond).to(beCloseTo(1.6))
    }

    func test_requestAndSync_whenSampleInRange_writesValueAndMarksHealthKit() async {
        store.walkingSpeedSource = .manual
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 1.65)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == true
        expect(self.store.walkingSpeedSource) == .healthKit
        expect(self.store.walkingSpeedMetersPerSecond).to(beCloseTo(1.65))
    }

    func test_requestAndSync_whenSampleOutOfRange_doesNotWriteAndForcesManual() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.4

        // 10 m/s sits well outside WalkingSpeed.validRange (0.5...5.0).
        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 10.0)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == false
        expect(self.store.walkingSpeedSource) == .manual
        // Stored speed unchanged — the out-of-range sample must not leak in.
        expect(self.store.walkingSpeedMetersPerSecond).to(beCloseTo(1.4))
    }

    func test_requestAndSync_whenAuthorizationThrows_forcesManual() async {
        store.walkingSpeedSource = .healthKit

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(authorizationError: DummyError(), sampleSpeed: 1.5)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == false
        expect(self.store.walkingSpeedSource) == .manual
    }

    func test_requestAndSync_whenHealthKitUnavailable_forcesManual() async {
        store.walkingSpeedSource = .healthKit

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(isAvailable: false, sampleSpeed: 1.5)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == false
        expect(self.store.walkingSpeedSource) == .manual
    }

    // MARK: - refreshFromHealthKitIfPossible

    func test_passiveRefresh_withNoSample_leavesSourceAndSpeedUntouched() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.65

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: nil)
        )

        await manager.refreshFromHealthKitIfPossible()

        // The asymmetry: passive refresh must never downgrade source to .manual.
        expect(self.store.walkingSpeedSource) == .healthKit
        expect(self.store.walkingSpeedMetersPerSecond).to(beCloseTo(1.65))
    }

    func test_passiveRefresh_withInRangeSample_updatesSpeed() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 1.7)
        )

        await manager.refreshFromHealthKitIfPossible()

        expect(self.store.walkingSpeedSource) == .healthKit
        expect(self.store.walkingSpeedMetersPerSecond).to(beCloseTo(1.7))
    }

    func test_passiveRefresh_withOutOfRangeSample_isNoOp() async {
        store.walkingSpeedSource = .healthKit
        store.walkingSpeedMetersPerSecond = 1.4

        let manager = WalkingSpeedManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 0.1)
        )

        await manager.refreshFromHealthKitIfPossible()

        expect(self.store.walkingSpeedSource) == .healthKit
        expect(self.store.walkingSpeedMetersPerSecond).to(beCloseTo(1.4))
    }
}
