//
//  DepartureTimeBadgeExtendedTests.swift
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
final class DepartureTimeBadgeExtendedTests {

    private func makeFormatters() -> Formatters {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        return Formatters(locale: Locale(identifier: "en_US"), calendar: calendar, themeColors: ThemeColors())
    }

    // MARK: - Early Schedule Status

    @Test func `Badge configuration indicates early arrival deviation in accessibility label`() {
        let formatters = makeFormatters()

        let config = DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: 4,
            arrivalDepartureStatus: .arriving,
            temporalState: .future,
            scheduleStatus: .early,
            scheduleDeviation: -2,
            formatters: formatters
        )

        #expect(config.displayText == "4m")
        #expect(config.backgroundColor == ThemeColors().departureEarlyBackground.cgColor)
        #expect(config.accessibilityLabel.contains("2 min early"))
    }

    // MARK: - Present Temporal State (Now)

    @Test func `Badge configuration displays NOW when arriving currently`() {
        let formatters = makeFormatters()

        let config = DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: 0,
            arrivalDepartureStatus: .arriving,
            temporalState: .present,
            scheduleStatus: .onTime,
            scheduleDeviation: 0,
            formatters: formatters
        )

        #expect(config.displayText == "NOW")
        #expect(config.backgroundColor == ThemeColors().departureOnTimeBackground.cgColor)
    }

    // MARK: - Past Temporal State

    @Test func `Badge configuration displays departed minutes for past departures`() {
        let formatters = makeFormatters()

        let config = DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: -3,
            arrivalDepartureStatus: .departing,
            temporalState: .past,
            scheduleStatus: .onTime,
            scheduleDeviation: 0,
            formatters: formatters
        )

        #expect(config.displayText == "-3m")
        #expect(config.accessibilityLabel.contains("Departed 3 min ago") || config.accessibilityLabel.contains("3 min ago"))
    }

    // MARK: - Large Minute Thresholds

    @Test func `Badge configuration formats large arrival minutes properly`() {
        let formatters = makeFormatters()

        let config = DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: 75,
            arrivalDepartureStatus: .arriving,
            temporalState: .future,
            scheduleStatus: .unknown,
            scheduleDeviation: 0,
            formatters: formatters
        )

        #expect(config.displayText == "75m")
        #expect(config.backgroundColor == ThemeColors().departureUnknownBackground.cgColor)
    }

    // MARK: - Application to Badge View

    @Test func `Configuring badge applies text and background colors accurately`() {
        let badge = DepartureTimeBadge(frame: .zero)
        let config = DepartureTimeBadge.Configuration(
            accessibilityLabel: "Test Label",
            displayText: "12m",
            backgroundColor: UIColor.purple.cgColor
        )

        badge.configure(config)

        #expect(badge.text == "12m")
        #expect(badge.accessibilityLabel == "Test Label")
        #expect(badge.layer.backgroundColor == UIColor.purple.cgColor)
    }
}
