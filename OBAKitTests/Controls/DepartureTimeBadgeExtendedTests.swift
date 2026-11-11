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

/// Extended tests for `DepartureTimeBadge.Configuration` temporal states,
/// deviation formatting, and color mappings.
@MainActor
@Suite(.serialized)
final class DepartureTimeBadgeExtendedTests {

    private let formatters = Formatters(
        locale: Locale(identifier: "en_US"),
        calendar: Calendar(identifier: .gregorian),
        themeColors: ThemeColors()
    )

    @Test func `Departure time badge with zero minutes formats as now`() {
        let config = DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: 0,
            arrivalDepartureStatus: .departing,
            temporalState: .present,
            scheduleStatus: .onTime,
            scheduleDeviation: 0,
            formatters: formatters
        )

        #expect(config.displayText == "NOW")
        #expect(config.accessibilityLabel.contains("NOW"))
    }

    @Test func `Departure time badge with negative minutes formats past departure`() {
        let config = DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: -4,
            arrivalDepartureStatus: .departing,
            temporalState: .past,
            scheduleStatus: .onTime,
            scheduleDeviation: 0,
            formatters: formatters
        )

        #expect(config.displayText == "-4m")
        #expect(config.accessibilityLabel.contains("Departed 4 min ago"))
    }

    @Test func `Early arrival badge configures early color and description`() {
        let config = DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: 8,
            arrivalDepartureStatus: .arriving,
            temporalState: .future,
            scheduleStatus: .early,
            scheduleDeviation: -120,
            formatters: formatters
        )

        #expect(config.displayText == "8m")
        #expect(config.accessibilityLabel.contains("early"))
        #expect(config.backgroundColor == ThemeColors().departureEarlyBackground.cgColor)
    }

    @Test func `Unknown schedule status badge configures scheduled color`() {
        let config = DepartureTimeBadge.Configuration(
            arrivalDepartureMinutes: 15,
            arrivalDepartureStatus: .departing,
            temporalState: .future,
            scheduleStatus: .unknown,
            scheduleDeviation: nil,
            formatters: formatters
        )

        #expect(config.displayText == "15m")
        #expect(config.backgroundColor == ThemeColors().departureUnknownBackground.cgColor)
    }
}
