//
//  TripSegmentViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class TripSegmentViewTests {

    private var destinationLabel: String {
        OBALoc("trip_stop.user_destination.accessibility_label", value: "Your destination", comment: "")
    }

    private var boardingLabel: String {
        OBALoc("trip_stop.boarding_stop.accessibility_label", value: "Boarding stop", comment: "")
    }

    private var vehicleLocationLabel: String {
        OBALoc("trip_stop.vehicle_location.accessibility_label", value: "Vehicle is here", comment: "")
    }

    @Test func testDestinationStatusAccessibilityLabelCombinations() {
        let view = TripSegmentView()

        // 1. None set
        view.setDestinationStatus(user: false, vehicle: false, boarding: false)
        #expect(!view.isAccessibilityElement)
        #expect(view.accessibilityLabel == nil)

        // 2. User destination only
        view.setDestinationStatus(user: true, vehicle: false, boarding: false)
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == destinationLabel)

        // 3. Boarding stop only
        view.setDestinationStatus(user: false, vehicle: false, boarding: true)
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == boardingLabel)

        // 4. Vehicle location only
        view.setDestinationStatus(user: false, vehicle: true, boarding: false)
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == vehicleLocationLabel)

        // 5. Multiple flags (User destination + vehicle location)
        view.setDestinationStatus(user: true, vehicle: true, boarding: false)
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == "\(destinationLabel), \(vehicleLocationLabel)")

        // 6. User destination + boarding stop + vehicle location
        view.setDestinationStatus(user: true, vehicle: true, boarding: true)
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == "\(destinationLabel), \(boardingLabel), \(vehicleLocationLabel)")
    }

    @Test func testTopLineColorTransitionsBasedOnTemporalStateAndRideBounds() {
        let view = TripSegmentView()
        let customBrand = UIColor.systemPurple
        view.lineColor = customBrand

        // Past and current always use pastLineColor
        view.temporalState = .past
        #expect(view.topLineColor == view.pastLineColor)

        view.temporalState = .current
        #expect(view.topLineColor == view.pastLineColor)

        // Future stop: normal active stop uses lineColor
        view.temporalState = .future
        view.isOutsideRide = false
        view.setDestinationStatus(user: false, vehicle: false, boarding: false)
        #expect(view.topLineColor == customBrand)

        // Future stop: outside shared ride fades to pastLineColor
        view.isOutsideRide = true
        #expect(view.topLineColor == view.pastLineColor)

        // Future stop: boarding stop uses pastLineColor because connector leads into boarding from outside
        view.isOutsideRide = false
        view.setDestinationStatus(user: false, vehicle: false, boarding: true)
        #expect(view.topLineColor == view.pastLineColor)
    }

    @Test func testBottomLineColorTransitions() {
        let view = TripSegmentView()
        let customBrand = UIColor.systemBlue
        view.lineColor = customBrand

        // Standard future stop inside ride
        view.temporalState = .future
        view.isOutsideRide = false
        view.isRideDestination = false
        #expect(view.bottomLineColor == customBrand)

        // Stop in the past
        view.temporalState = .past
        #expect(view.bottomLineColor == view.pastLineColor)

        // Current stop outside ride
        view.temporalState = .current
        view.isOutsideRide = true
        #expect(view.bottomLineColor == view.pastLineColor)

        // Future stop that is ride destination
        view.temporalState = .future
        view.isOutsideRide = false
        view.isRideDestination = true
        #expect(view.bottomLineColor == view.pastLineColor)
    }

    @Test func testIntrinsicContentSizeCalculatesFromRadiusAndLineWidth() {
        let view = TripSegmentView()
        let expectedWidth: CGFloat = 30.0 + (2.0 * 1.0)
        #expect(view.intrinsicContentSize.width == expectedWidth)
        #expect(view.intrinsicContentSize.height == UIView.noIntrinsicMetric)
    }
}
