//
//  WalkingSpeedSettingsDecisionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class WalkingSpeedSettingsDecisionTests {

    // MARK: - Toggle absent (form row not shown)

    @Test func `No toggle segment speed updates manual speed`() {
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .manual,
            currentSpeed: 1.4,
            useHealthKit: nil,
            segmentSpeed: 0.9
        )
        #expect(decision.source == .manual)
        expectClose(decision.speed, 0.9)
    }

    @Test func `No toggle no segment speed leaves everything untouched`() {
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .healthKit,
            currentSpeed: 1.65,
            useHealthKit: nil,
            segmentSpeed: nil
        )
        #expect(decision.source == .healthKit)
        expectClose(decision.speed, 1.65)
    }

    // MARK: - Toggle ON

    @Test func `Toggle on keeps current speed and switches to health kit`() {
        // When HK is toggled on, the manager has already written the synced speed.
        // saveWalkingSpeedValues must not overwrite it with the (now-disabled) segment value.
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .manual,
            currentSpeed: 1.65,
            useHealthKit: true,
            segmentSpeed: 1.4
        )
        #expect(decision.source == .healthKit)
        expectClose(decision.speed, 1.65)
    }

    // MARK: - Toggle OFF

    @Test func `Toggle off snaps current speed to nearest preset`() {
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .healthKit,
            currentSpeed: 1.73,   // closer to .fast (1.8)
            useHealthKit: false,
            segmentSpeed: nil
        )
        #expect(decision.source == .manual)
        expectClose(decision.speed, WalkingSpeedPreset.fast.rawValue)
    }

    @Test func `Toggle off with segment speed prefers segment then snaps`() {
        // When the toggle flips off, the segment row also has whatever the user landed on —
        // it should win over currentSpeed, then snap.
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .healthKit,
            currentSpeed: 1.65,
            useHealthKit: false,
            segmentSpeed: 0.9
        )
        #expect(decision.source == .manual)
        expectClose(decision.speed, WalkingSpeedPreset.slow.rawValue)
    }
}
