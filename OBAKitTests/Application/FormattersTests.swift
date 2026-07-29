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
import Testing
@testable import OBAKit
@testable import OBAKitCore

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

        // Deliberately stricter than what it replaced. Nimble's `match` was
        // `range(of:options:.regularExpression)` -- an UNANCHORED substring
        // search -- whereas `SELF MATCHES` anchors to the whole string, so this
        // also asserts nothing surrounds the phrase. That's the intent here.
        #expect(NSPredicate(format: "SELF MATCHES %@", "Arrived \\d+ min ago").evaluate(with: str))
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

        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        // Get the expected time string from the same formatter that the banner uses,
        // so the test is timezone-agnostic and passes on any machine (local or CI).
        let expectedTime = formatters.timeFormatter.string(from: arrivalTime)

        let result = formatters.transferArrivalBannerText(arrivalTime: arrivalTime, routeDisplay: "10 - Capitol Hill")

        XCTAssertTrue(result.contains("10 - Capitol Hill"), "Banner should contain route display: \(result)")
        XCTAssertTrue(result.contains(expectedTime), "Banner should contain formatted time '\(expectedTime)': \(result)")
    }
}
