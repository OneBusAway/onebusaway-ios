//
//  SpeedSyncConfigurationExtendedTests.swift
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

/// Tests for `SpeedSyncConfiguration`, `SpeedSyncText`, and availability invariants.
@Suite(.serialized)
struct SpeedSyncConfigurationExtendedTests {

    private final class MockSpeedProvider: SpeedProviding {
        let isAvailable: Bool
        init(isAvailable: Bool = true) {
            self.isAvailable = isAvailable
        }
        func requestAuthorization() async throws {}
        func fetchSpeed() async -> Double? { nil }
    }

    private func makeText() -> SpeedSyncText {
        SpeedSyncText(
            toggleTitle: "Sync speed",
            walkingFooter: "Calculates walking travel times",
            walkingFailureMessage: "Failed to read walking samples",
            bikeFooter: "Calculates cycling travel times",
            bikeFailureMessage: "Failed to read cycling samples"
        )
    }

    @Test func `SpeedSyncText initializes and preserves all messages`() {
        let text = makeText()
        #expect(text.toggleTitle == "Sync speed")
        #expect(text.walkingFooter == "Calculates walking travel times")
        #expect(text.walkingFailureMessage == "Failed to read walking samples")
        #expect(text.bikeFooter == "Calculates cycling travel times")
        #expect(text.bikeFailureMessage == "Failed to read cycling samples")
    }

    @Test func `SpeedSyncConfiguration is available when both walking and bike providers are available`() {
        let walking = MockSpeedProvider(isAvailable: true)
        let bike = MockSpeedProvider(isAvailable: true)
        let config = SpeedSyncConfiguration(walkingProvider: walking, bikeProvider: bike, text: makeText())

        #expect(config.isAvailable == true)
    }

    @Test func `SpeedSyncConfiguration is unavailable when walking provider is unavailable`() {
        let walking = MockSpeedProvider(isAvailable: false)
        let bike = MockSpeedProvider(isAvailable: true)
        let config = SpeedSyncConfiguration(walkingProvider: walking, bikeProvider: bike, text: makeText())

        #expect(config.isAvailable == false)
    }

    @Test func `SpeedSyncConfiguration is unavailable when bike provider is unavailable`() {
        let walking = MockSpeedProvider(isAvailable: true)
        let bike = MockSpeedProvider(isAvailable: false)
        let config = SpeedSyncConfiguration(walkingProvider: walking, bikeProvider: bike, text: makeText())

        #expect(config.isAvailable == false)
    }

    @Test func `SpeedSyncConfiguration is unavailable when both providers are unavailable`() {
        let walking = MockSpeedProvider(isAvailable: false)
        let bike = MockSpeedProvider(isAvailable: false)
        let config = SpeedSyncConfiguration(walkingProvider: walking, bikeProvider: bike, text: makeText())

        #expect(config.isAvailable == false)
    }
}
