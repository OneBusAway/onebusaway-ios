//
//  WeatherFormatterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKitCore

/// Tests for `WeatherFormatter`: pure-function helpers feeding both the UIKit
/// weather button and the SwiftUI weather card.
final class WeatherFormatterTests: XCTestCase {

    // MARK: - systemImageName

    func test_systemImageName_knownKeys() {
        let cases: [(key: String, symbol: String)] = [
            ("clear-day", "sun.max.fill"),
            ("clear-night", "moon.stars.fill"),
            ("partly-cloudy-day", "cloud.sun.fill"),
            ("partly-cloudy-night", "cloud.moon.fill"),
            ("cloudy", "cloud.fill"),
            ("rain", "cloud.rain.fill"),
            ("sleet", "cloud.sleet.fill"),
            ("snow", "cloud.snow.fill"),
            ("wind", "wind"),
            ("fog", "cloud.fog.fill")
        ]
        for c in cases {
            expect(WeatherFormatter.systemImageName(for: c.key)) == c.symbol
        }
    }

    func test_systemImageName_unknownKeyFallsBackToCloud() {
        expect(WeatherFormatter.systemImageName(for: "tornado")) == "cloud.fill"
        expect(WeatherFormatter.systemImageName(for: "")) == "cloud.fill"
    }

    // MARK: - conditionText

    func test_conditionText_groupsDayAndNightVariants() {
        expect(WeatherFormatter.conditionText(for: "clear-day")) == WeatherFormatter.conditionText(for: "clear-night")
        expect(WeatherFormatter.conditionText(for: "partly-cloudy-day")) == WeatherFormatter.conditionText(for: "partly-cloudy-night")
    }

    func test_conditionText_unknownKeyReturnsPlaceholder() {
        expect(WeatherFormatter.conditionText(for: "tornado")) == "—"
    }

    // MARK: - formatTemp (locale-dependent)

    func test_formatTemp_usLocaleKeepsFahrenheit() {
        let result = WeatherFormatter.formatTemp(50, locale: Locale(identifier: "en_US"))
        expect(result).to(contain("50"))
    }

    func test_formatTemp_metricLocaleConvertsToCelsius() {
        // 50°F == 10°C
        let result = WeatherFormatter.formatTemp(50, locale: Locale(identifier: "fr_FR"))
        expect(result).to(contain("10"))
    }

    // MARK: - formatWindSpeed

    func test_formatWindSpeed_usLocaleUsesMph() {
        let result = WeatherFormatter.formatWindSpeed(16.0934, locale: Locale(identifier: "en_US"))
        expect(result) == "10 mph"
    }

    func test_formatWindSpeed_ukLocaleUsesMph() {
        let result = WeatherFormatter.formatWindSpeed(16.0934, locale: Locale(identifier: "en_GB"))
        expect(result) == "10 mph"
    }

    func test_formatWindSpeed_metricLocaleUsesKmh() {
        let result = WeatherFormatter.formatWindSpeed(10, locale: Locale(identifier: "fr_FR"))
        expect(result) == "10 km/h"
    }

    // MARK: - highLow

    func test_highLow_returnsNilForEmptyForecasts() {
        expect(WeatherFormatter.highLow(from: [], locale: Locale(identifier: "en_US"))).to(beNil())
    }
}
