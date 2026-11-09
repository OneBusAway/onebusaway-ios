//
//  WalkTimeViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import CoreLocation
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class WalkTimeViewTests {

    private func makeFormatters() -> Formatters {
        Formatters(
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            themeColors: ThemeColors()
        )
    }

    private func extractSubviews(from view: WalkTimeView) -> (label: UILabel?, imageView: UIImageView?) {
        var foundLabel: UILabel?
        var foundImageView: UIImageView?
        for subview in view.subviews {
            if let label = subview as? UILabel {
                foundLabel = label
            } else if let iv = subview as? UIImageView {
                foundImageView = iv
            }
        }
        return (foundLabel, foundImageView)
    }

    @Test func testSuppressedWhenDistanceIsFortyMetersOrLess() {
        let view = WalkTimeView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        view.formatters = makeFormatters()

        view.set(distance: 40.0, timeToWalk: 60, isBikeMode: false)

        let (label, imageView) = extractSubviews(from: view)
        #expect(label?.text == nil)
        #expect(imageView?.image == nil)
        #expect(!view.isAccessibilityElement)

        view.set(distance: 25.0, timeToWalk: 30, isBikeMode: true)
        #expect(label?.text == nil)
        #expect(imageView?.image == nil)
        #expect(!view.isAccessibilityElement)
    }

    @Test func testWalkModeConfigurationAboveThreshold() {
        let view = WalkTimeView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let formatters = makeFormatters()
        view.formatters = formatters

        let distance: CLLocationDistance = 500.0
        let timeToWalk: TimeInterval = 300.0 // 5 minutes

        view.set(distance: distance, timeToWalk: timeToWalk, isBikeMode: false)

        let (label, imageView) = extractSubviews(from: view)
        #expect(label?.text != nil)
        #expect(imageView?.image != nil)
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == OBALoc("walk_time_view.accessibility_label", value: "Time to walk to stop", comment: ""))
        #expect(view.accessibilityTraits.contains(.staticText))

        let accessibilityValue = view.accessibilityValue
        #expect(accessibilityValue != nil)
    }

    @Test func testBikeModeConfigurationAboveThreshold() {
        let view = WalkTimeView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let formatters = makeFormatters()
        view.formatters = formatters

        let distance: CLLocationDistance = 1600.0
        let timeToBike: TimeInterval = 360.0 // 6 minutes

        view.set(distance: distance, timeToWalk: timeToBike, isBikeMode: true)

        let (label, imageView) = extractSubviews(from: view)
        #expect(label?.text != nil)
        #expect(imageView?.image == UIImage(systemName: "bicycle"))
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == OBALoc("walk_time_view.accessibility_label_bike", value: "Time to bike to stop", comment: ""))
        #expect(view.accessibilityTraits.contains(.staticText))

        let accessibilityValue = view.accessibilityValue
        #expect(accessibilityValue != nil)
    }

    @Test func testTransferArrivalConfiguration() {
        let view = WalkTimeView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let formatters = makeFormatters()
        view.formatters = formatters

        let arrivalTime = Date(timeIntervalSince1970: 1700000000)
        view.setTransferArrival(arrivalTime: arrivalTime, routeDisplay: "44")

        let (label, imageView) = extractSubviews(from: view)
        #expect(label?.text != nil)
        #expect(imageView?.image == Icons.vehiclesSelectedTabIcon)
        #expect(view.isAccessibilityElement)
        #expect(view.accessibilityLabel == OBALoc("walk_time_view.transfer_accessibility_label", value: "Transfer arrival time", comment: ""))
        #expect(view.accessibilityValue == label?.text)
        #expect(view.accessibilityTraits.contains(.staticText))
    }

    @Test func testReuseResetWhenSwitchingBetweenModesAndSuppression() {
        let view = WalkTimeView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        view.formatters = makeFormatters()

        // First configure bike mode
        view.set(distance: 800.0, timeToWalk: 180.0, isBikeMode: true)
        let (label, imageView) = extractSubviews(from: view)
        #expect(imageView?.image == UIImage(systemName: "bicycle"))

        // Then reuse for a stop <= 40m
        view.set(distance: 30.0, timeToWalk: 10.0, isBikeMode: false)
        #expect(label?.text == nil)
        #expect(imageView?.image == nil)
        #expect(!view.isAccessibilityElement)
    }
}
