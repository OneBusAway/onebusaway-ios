//
//  DepartureTimeBadgeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class DepartureTimeBadgeTests {
    
    @Test func testConfigurationInitialization() {
        let expectedLabel = "Accessibility Label"
        let expectedText = "5m"
        let expectedColor = UIColor.blue.cgColor
        
        let config = DepartureTimeBadge.Configuration(
            accessibilityLabel: expectedLabel,
            displayText: expectedText,
            backgroundColor: expectedColor
        )
        
        #expect(config.accessibilityLabel == expectedLabel)
        #expect(config.displayText == expectedText)
        #expect(config.backgroundColor == expectedColor)
    }

    @Test func testParameterizedConfigurationInitialization() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: calendar, themeColors: ThemeColors())
        
        let config = DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: 5,
            arrivalDepartureStatus: .departing,
            temporalState: .future,
            scheduleStatus: .onTime,
            formatters: formatters
        )
        
        #expect(config.accessibilityLabel == formatters.explanationForArrivalDeparture(tempuraState: .future, arrivalDepartureStatus: .departing, arrivalDepartureMinutes: 5))
        #expect(config.displayText == formatters.shortFormattedTime(untilMinutes: 5, temporalState: .future))
        #expect(config.backgroundColor == formatters.backgroundColorForScheduleStatus(.onTime).cgColor)
    }

    @Test func testBadgeInitialization() {
        let badge = DepartureTimeBadge(frame: .zero)
        
        #expect(badge.textColor == ThemeColors.shared.lightText)
        #expect(badge.textAlignment == .center)
        #expect(badge.adjustsFontSizeToFitWidth == true)
        #expect(badge.layer.masksToBounds == true)
        #expect(badge.layer.cornerRadius == 8)
    }

    @Test func testIntrinsicContentSize() {
        let badge = DepartureTimeBadge(frame: .zero)
        badge.text = "NOW"
        badge.font = UIFont.systemFont(ofSize: 15)
        badge.sizeToFit()
        
        let size = badge.intrinsicContentSize
        
        let plainLabel = UILabel()
        plainLabel.text = badge.text
        plainLabel.font = badge.font
        let superSize = plainLabel.intrinsicContentSize
        
        #expect(size.width == superSize.width + badge.contentMargin.left + badge.contentMargin.right)
        #expect(size.height == superSize.height + badge.contentMargin.top + badge.contentMargin.bottom)
    }

    @Test func testConfigureAppliesConfiguration() {
        let badge = DepartureTimeBadge(frame: .zero)
        let config = DepartureTimeBadge.Configuration(
            accessibilityLabel: "Departing soon",
            displayText: "10m",
            backgroundColor: UIColor.red.cgColor
        )
        
        badge.configure(config)
        
        #expect(badge.accessibilityLabel == "Departing soon")
        #expect(badge.text == "10m")
        #expect(badge.layer.backgroundColor == UIColor.red.cgColor)
    }

    @Test func testPrepareForReuse() {
        let badge = DepartureTimeBadge(frame: .zero)
        badge.accessibilityLabel = "Departing soon"
        badge.text = "10m"
        badge.layer.backgroundColor = UIColor.red.cgColor
        
        badge.prepareForReuse()
        
        #expect(badge.accessibilityLabel == nil)
        #expect(badge.text == nil)
        #expect(badge.layer.backgroundColor == nil)
    }
}
