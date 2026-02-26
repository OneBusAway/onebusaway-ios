//
//  FormattersTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import Nimble

// swiftlint:disable force_try

enum ModelDecodingError: Error {
    case invalidData
    case invalidReferences
    case invalidModelList
}

class FormattersTests: OBATestCase {
    let usLocale = Locale(identifier: "en_US")
    let calendar = Calendar(identifier: .gregorian)

    func testExample() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let stopArrivals = try! Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_75414.json")
        let arrDep = stopArrivals.arrivalsAndDepartures.first!

        let str = formatters.explanation(from: arrDep)

        expect(str).to(match("Arrived \\d+ min ago"))
    }

    // MARK: - Transfer-Relative Time

    func test_shortFormattedTransferTime_positiveMinutes() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let result = formatters.shortFormattedTransferTime(minutes: 4)
        XCTAssertEqual(result, "4m")
    }

    func test_shortFormattedTransferTime_negativeMinutes() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let result = formatters.shortFormattedTransferTime(minutes: -3)
        XCTAssertEqual(result, "-3m")
    }

    func test_shortFormattedTransferTime_zero() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let result = formatters.shortFormattedTransferTime(minutes: 0)
        XCTAssertEqual(result, "NOW")
    }

    func test_transferArrivalBannerText() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())

        // Use a fixed date to avoid locale-dependent time formatting issues.
        // 2023-10-15 16:10:00 UTC
        var dateComponents = DateComponents()
        dateComponents.year = 2023
        dateComponents.month = 10
        dateComponents.day = 15
        dateComponents.hour = 16
        dateComponents.minute = 10
        dateComponents.timeZone = TimeZone(identifier: "America/Los_Angeles")
        let arrivalTime = calendar.date(from: dateComponents)!

        let result = formatters.transferArrivalBannerText(arrivalTime: arrivalTime, routeDisplay: "10 - Capitol Hill")

        // The time format depends on locale but for en_US should contain "4:10 PM"
        XCTAssertTrue(result.contains("10 - Capitol Hill"), "Banner should contain route display: \(result)")
        XCTAssertTrue(result.contains("4:10"), "Banner should contain formatted time: \(result)")
    }
}
