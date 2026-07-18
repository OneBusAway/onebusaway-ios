//
//  WalkingSpeedPresetTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit

@MainActor
class WalkingSpeedPresetTests: XCTestCase {

    func test_nearest_exactMatch() {
        expect(WalkingSpeedPreset.nearest(to: 0.9)) == .slow
        expect(WalkingSpeedPreset.nearest(to: 1.4)) == .average
        expect(WalkingSpeedPreset.nearest(to: 1.8)) == .fast
    }

    func test_nearest_picksClosestPreset() {
        // 1.0 → halfway-ish, closer to 0.9 (slow)
        expect(WalkingSpeedPreset.nearest(to: 1.0)) == .slow
        // 1.3 closer to 1.4 (average)
        expect(WalkingSpeedPreset.nearest(to: 1.3)) == .average
        // 1.7 closer to 1.8 (fast)
        expect(WalkingSpeedPreset.nearest(to: 1.7)) == .fast
    }

    func test_nearest_outOfRange_clampsToNearestEnd() {
        // Below slow → still slow
        expect(WalkingSpeedPreset.nearest(to: 0.1)) == .slow
        // Above fast → still fast
        expect(WalkingSpeedPreset.nearest(to: 5.0)) == .fast
    }
}
