//
//  StopDirectionsPillTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import OBAKitCore
import OTPKit
@testable import OBAKit

/// What tapping the stop header's walk and bike pills does (#1546).
@Suite(.serialized)
struct StopDirectionsPillTests {

    /// The header pills and the walk divider share this one behavior.
    @Test func `With a trip planner, both pills offer directions in their own mode`() {
        #expect(StopDirectionsPill.walk.behavior(tripPlannerAvailable: true) == .offerDirections(.walk))
        #expect(StopDirectionsPill.bike.behavior(tripPlannerAvailable: true) == .offerDirections(.bike))
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
            StopDirectionsPill.Behavior.offerDirections(.walk),
            .offerDirections(.bike),
            .openMapsWalkingDirections
        ].map(\.accessibilityHint)

        #expect(Set(hints).count == 3)
        #expect(hints[0] == "Offers walking directions to this stop.")
        #expect(hints[2] == "Opens walking directions to this stop.")
    }

    // MARK: - Directions sheet and walk divider

    @Test func `The directions sheet's first action names the mode`() {
        #expect(StopDirectionsPill.walk.showDirectionsTitle == "Show Walking Directions")
        #expect(StopDirectionsPill.bike.showDirectionsTitle == "Show Bike Directions")
        #expect(StopDirectionsPill.walk.offerTitle == "Walk to this stop")
        #expect(StopDirectionsPill.bike.offerTitle == "Bike to this stop")
    }

    @Test func `The divider's minutes text matches the header pill's`() {
        #expect(StopDirectionsPill.walk.text(minutes: 4) == "4 min walk")
        #expect(StopDirectionsPill.bike.text(minutes: 12) == "12 min bike")
    }

    /// "at stop" carries the clock time the rider would reach the stop, through
    /// the same region-aware formatter as the departure rows.
    @Test func `The divider says when the rider would reach the stop`() {
        let arrival = Date(timeIntervalSince1970: 1_800_000_000)
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
        let text = WalkLineDivider.atStopText(arrival: arrival, formatters: formatters)
        #expect(text == "at stop \(formatters.formattedClockTime(arrival))")
    }
}
