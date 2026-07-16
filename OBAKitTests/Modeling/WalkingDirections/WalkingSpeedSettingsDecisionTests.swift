//
//  WalkingSpeedSettingsDecisionTests.swift
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
final class WalkingSpeedSettingsDecisionTests: XCTestCase {

    // MARK: - Toggle absent (form row not shown)

    func test_noToggle_segmentSpeed_updatesManualSpeed() {
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .manual,
            currentSpeed: 1.4,
            useHealthKit: nil,
            segmentSpeed: 0.9
        )
        expect(decision.source) == .manual
        expect(decision.speed).to(beCloseTo(0.9))
    }

    func test_noToggle_noSegmentSpeed_leavesEverythingUntouched() {
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .healthKit,
            currentSpeed: 1.65,
            useHealthKit: nil,
            segmentSpeed: nil
        )
        expect(decision.source) == .healthKit
        expect(decision.speed).to(beCloseTo(1.65))
    }

    // MARK: - Toggle ON

    func test_toggleOn_keepsCurrentSpeedAndSwitchesToHealthKit() {
        // When HK is toggled on, the manager has already written the synced speed.
        // saveWalkingSpeedValues must not overwrite it with the (now-disabled) segment value.
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .manual,
            currentSpeed: 1.65,
            useHealthKit: true,
            segmentSpeed: 1.4
        )
        expect(decision.source) == .healthKit
        expect(decision.speed).to(beCloseTo(1.65))
    }

    // MARK: - Toggle OFF

    func test_toggleOff_snapsCurrentSpeedToNearestPreset() {
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .healthKit,
            currentSpeed: 1.73,   // closer to .fast (1.8)
            useHealthKit: false,
            segmentSpeed: nil
        )
        expect(decision.source) == .manual
        expect(decision.speed).to(beCloseTo(WalkingSpeedPreset.fast.rawValue))
    }

    func test_toggleOff_withSegmentSpeed_prefersSegmentThenSnaps() {
        // When the toggle flips off, the segment row also has whatever the user landed on —
        // it should win over currentSpeed, then snap.
        let decision = WalkingSpeedSettingsDecision.compute(
            currentSource: .healthKit,
            currentSpeed: 1.65,
            useHealthKit: false,
            segmentSpeed: 0.9
        )
        expect(decision.source) == .manual
        expect(decision.speed).to(beCloseTo(WalkingSpeedPreset.slow.rawValue))
    }
}
