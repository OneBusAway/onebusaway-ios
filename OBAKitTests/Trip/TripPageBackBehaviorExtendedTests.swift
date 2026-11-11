//
//  TripPageBackBehaviorExtendedTests.swift
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

/// Extended tests for `TripPageBackBehavior` accessibility formatting,
/// system image constants, and depth resolution boundaries.
@Suite(.serialized)
struct TripPageBackBehaviorExtendedTests {

    @Test func `BackBehavior for negative or zero depth returns dismiss`() {
        #expect(TripPageBackBehavior.forStackDepth(-1) == .dismiss)
        #expect(TripPageBackBehavior.forStackDepth(-10) == .dismiss)
        #expect(TripPageBackBehavior.forStackDepth(0) == .dismiss)
    }

    @Test func `BackBehavior for exactly depth 1 returns dismiss`() {
        #expect(TripPageBackBehavior.forStackDepth(1) == .dismiss)
    }

    @Test func `BackBehavior for depth greater than 1 returns pop`() {
        #expect(TripPageBackBehavior.forStackDepth(2) == .pop)
        #expect(TripPageBackBehavior.forStackDepth(3) == .pop)
        #expect(TripPageBackBehavior.forStackDepth(10) == .pop)
    }

    @Test func `Accessibility label for pop with empty or whitespace string falls back to default back`() {
        #expect(TripPageBackBehavior.pop.accessibilityLabel(originTitle: "") == Strings.back)
        #expect(TripPageBackBehavior.pop.accessibilityLabel(originTitle: nil) == Strings.back)
    }

    @Test func `Accessibility label for pop with non-empty origin title formats with destination name`() {
        let label = TripPageBackBehavior.pop.accessibilityLabel(originTitle: "Pine St & 5th Ave")
        #expect(label.contains("Pine St & 5th Ave"))
        #expect(label.contains("Back to"))
    }

    @Test func `Accessibility label for dismiss always returns close regardless of originTitle`() {
        #expect(TripPageBackBehavior.dismiss.accessibilityLabel(originTitle: nil) == Strings.close)
        #expect(TripPageBackBehavior.dismiss.accessibilityLabel(originTitle: "") == Strings.close)
        #expect(TripPageBackBehavior.dismiss.accessibilityLabel(originTitle: "Some Screen") == Strings.close)
    }

    @Test func `BackBehavior systemImage glyph invariants`() {
        #expect(TripPageBackBehavior.pop.systemImage == "chevron.backward")
        #expect(TripPageBackBehavior.dismiss.systemImage == "xmark")
    }
}
