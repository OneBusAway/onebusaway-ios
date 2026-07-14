//
//  BikeModeManagerTests.swift
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

@MainActor
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

        func fetchLatestBikeSpeed() async -> Double? {
            sampleSpeed
        }
    }

    private struct DummyError: Error {}

    private var store: UserDefaultsStore {
        UserDefaultsStore(userDefaults: userDefaults)
    }

    // MARK: - requestHealthKitAuthorizationAndSync

    func test_requestAndSync_whenSampleMissing_returnsFalseAndForcesManual() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.5

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: nil)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == false
        expect(self.store.bikeSpeedSource) == .manual
        // Speed left untouched even on failure.
        expect(self.store.bikeSpeedMetersPerSecond).to(beCloseTo(4.5))
    }

    func test_requestAndSync_whenSampleInRange_writesValueAndMarksHealthKit() async {
        store.bikeSpeedSource = .manual
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 5.5)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == true
        expect(self.store.bikeSpeedSource) == .healthKit
        expect(self.store.bikeSpeedMetersPerSecond).to(beCloseTo(5.5))
    }

    func test_requestAndSync_whenSampleOutOfRange_doesNotWriteAndForcesManual() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.2

        // 30 m/s sits well outside BikeSpeed.validRange (1.0...20.0).
        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 30.0)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == false
        expect(self.store.bikeSpeedSource) == .manual
        // Stored speed unchanged — the out-of-range sample must not leak in.
        expect(self.store.bikeSpeedMetersPerSecond).to(beCloseTo(4.2))
    }

    func test_requestAndSync_whenAuthorizationThrows_forcesManual() async {
        store.bikeSpeedSource = .healthKit

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(authorizationError: DummyError(), sampleSpeed: 5.0)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == false
        expect(self.store.bikeSpeedSource) == .manual
    }

    func test_requestAndSync_whenHealthKitUnavailable_forcesManual() async {
        store.bikeSpeedSource = .healthKit

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(isAvailable: false, sampleSpeed: 5.0)
        )

        let result = await manager.requestHealthKitAuthorizationAndSync()

        expect(result) == false
        expect(self.store.bikeSpeedSource) == .manual
    }

    // MARK: - refreshFromHealthKitIfPossible

    func test_passiveRefresh_withNoSample_leavesSourceAndSpeedUntouched() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 5.5

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: nil)
        )

        await manager.refreshFromHealthKitIfPossible()

        // The asymmetry: passive refresh must never downgrade source to .manual.
        expect(self.store.bikeSpeedSource) == .healthKit
        expect(self.store.bikeSpeedMetersPerSecond).to(beCloseTo(5.5))
    }

    func test_passiveRefresh_withInRangeSample_updatesSpeed() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 6.0)
        )

        await manager.refreshFromHealthKitIfPossible()

        expect(self.store.bikeSpeedSource) == .healthKit
        expect(self.store.bikeSpeedMetersPerSecond).to(beCloseTo(6.0))
    }

    func test_passiveRefresh_withOutOfRangeSample_isNoOp() async {
        store.bikeSpeedSource = .healthKit
        store.bikeSpeedMetersPerSecond = 4.2

        let manager = BikeModeManager(
            userDataStore: store,
            healthKit: FakeProvider(sampleSpeed: 0.5)
        )

        await manager.refreshFromHealthKitIfPossible()

        expect(self.store.bikeSpeedSource) == .healthKit
        expect(self.store.bikeSpeedMetersPerSecond).to(beCloseTo(4.2))
    }
}
