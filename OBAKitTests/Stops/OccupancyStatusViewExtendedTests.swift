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

    private func findLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel { return label }
        for subview in view.subviews {
            if let label = findLabel(in: subview) { return label }
        }
        return nil
    }

    @Test func `Reconfiguring view from one status to another updates accurately`() throws {
        let view = OccupancyStatusView()

        view.configure(occupancyStatus: .manySeatsAvailable, realtimeData: true)
        let label1 = try #require(findLabel(in: view))
        #expect(!label1.text.isNilOrEmpty)

        view.configure(occupancyStatus: .standingRoomOnly, realtimeData: true)
        let label2 = try #require(findLabel(in: view))
        #expect(!label2.text.isNilOrEmpty)

        view.configure(occupancyStatus: .unknown, realtimeData: true)
        #expect(view.isHidden)
    }

    @Test func `Switching from realtime to schedule updates tint color`() {
        let view = OccupancyStatusView()

        view.configure(occupancyStatus: .fewSeatsAvailable, realtimeData: true)
        #expect(view.tintColor == .label)

        view.configure(occupancyStatus: .fewSeatsAvailable, realtimeData: false)
        #expect(view.tintColor == .secondaryLabel)
    }

    @Test func `Not accepting passengers hides view when set to unknown`() {
        let view = OccupancyStatusView()
        view.configure(occupancyStatus: .notAcceptingPassengers, realtimeData: true)
        #expect(!view.isHidden)

        view.configure(occupancyStatus: .unknown, realtimeData: true)
        #expect(view.isHidden)
    }
}
