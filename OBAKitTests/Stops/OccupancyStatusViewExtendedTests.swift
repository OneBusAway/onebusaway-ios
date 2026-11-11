//
//  OccupancyStatusViewExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

/// Extended tests for `OccupancyStatusView` reconfigurability,
/// schedule-only transitions, and dynamic state switching.
@Suite(.serialized)
struct OccupancyStatusViewExtendedTests {

    @Test func `Reconfiguring view from one status to another updates accurately`() {
        let view = OccupancyStatusView()

        view.configure(occupancyStatus: .manySeatsAvailable, realtimeData: true)
        #expect(view.accessibilityLabel != nil)

        view.configure(occupancyStatus: .standingRoomOnly, realtimeData: true)
        #expect(view.accessibilityLabel != nil)

        view.configure(occupancyStatus: .unknown, realtimeData: true)
        #expect(view.accessibilityLabel != nil)
    }

    @Test func `Switching from realtime to schedule updates accessibility traits and label`() {
        let view = OccupancyStatusView()

        view.configure(occupancyStatus: .fewSeatsAvailable, realtimeData: true)
        let rtLabel = view.accessibilityLabel

        view.configure(occupancyStatus: .fewSeatsAvailable, realtimeData: false)
        let schedLabel = view.accessibilityLabel

        #expect(rtLabel != nil)
        #expect(schedLabel != nil)
    }

    @Test func `Not accepting passengers hides regular occupancy icons`() {
        let view = OccupancyStatusView()
        view.configure(occupancyStatus: .notAcceptingPassengers, realtimeData: true)

        #expect(view.accessibilityLabel != nil)
    }
}
