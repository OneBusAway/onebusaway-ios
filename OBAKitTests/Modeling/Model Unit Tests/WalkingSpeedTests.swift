//
//  WalkingSpeedTests.swift
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

/// Tests for `WalkingSpeed` and `WalkingSpeedSource` bounds, persistence invariants,
/// and default configurations.
@Suite(.serialized)
final class WalkingSpeedTests: OBATestCase {

    @Test func `WalkingSpeed default speed is within valid range`() {
        #expect(WalkingSpeed.defaultMetersPerSecond == 1.4)
        #expect(WalkingSpeed.validRange.lowerBound == 0.5)
        #expect(WalkingSpeed.validRange.upperBound == 5.0)
        #expect(WalkingSpeed.validRange.contains(WalkingSpeed.defaultMetersPerSecond))
    }

    @Test func `WalkingSpeed valid range boundary tests`() {
        #expect(WalkingSpeed.validRange.contains(0.5))
        #expect(WalkingSpeed.validRange.contains(5.0))
        #expect(!WalkingSpeed.validRange.contains(0.499))
        #expect(!WalkingSpeed.validRange.contains(5.001))
        #expect(!WalkingSpeed.validRange.contains(-1.0))
    }

    @Test func `WalkingSpeedSource raw integer values remain backward compatible`() {
        #expect(WalkingSpeedSource.manual.rawValue == 0)
        #expect(WalkingSpeedSource.synced.rawValue == 1)
        #expect(WalkingSpeedSource(rawValue: 0) == .manual)
        #expect(WalkingSpeedSource(rawValue: 1) == .synced)
        #expect(WalkingSpeedSource(rawValue: 99) == nil)
    }
}
