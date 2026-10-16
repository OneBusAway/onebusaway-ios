//
//  StopDirectionsPillTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import OTPKit
@testable import OBAKit

/// What tapping the stop header's walk and bike pills does (#1546).
@Suite(.serialized)
struct StopDirectionsPillTests {

    @Test func `With a trip planner, both pills ask, then plan the trip in their own mode`() {
        #expect(StopDirectionsPill.walk.behavior(tripPlannerAvailable: true) == .askThenPlanTrip(.walk))
        #expect(StopDirectionsPill.bike.behavior(tripPlannerAvailable: true) == .askThenPlanTrip(.bike))
    }

    /// Without one, nothing changes: walking directions open in a maps app, and the
    /// bike pill stays a plain value, since no maps app takes a cycling deep link.
    @Test func `Without a trip planner, walk opens a maps app and bike does nothing`() {
        #expect(StopDirectionsPill.walk.behavior(tripPlannerAvailable: false) == .openMapsWalkingDirections)
        #expect(StopDirectionsPill.bike.behavior(tripPlannerAvailable: false) == nil)
    }

    /// VoiceOver says what a tap will actually do, which differs with the planner.
    @Test func `Each behaviour's VoiceOver hint says what a tap does`() {
        let hints = [
            StopDirectionsPill.Behavior.askThenPlanTrip(.walk),
            .askThenPlanTrip(.bike),
            .openMapsWalkingDirections
        ].map(\.accessibilityHint)

        #expect(Set(hints).count == 3)
        #expect(hints[2] == "Opens walking directions to this stop.")
    }
}
