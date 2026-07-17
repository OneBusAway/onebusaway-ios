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
@MainActor
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

    // MARK: - Metadata single-source-of-truth

    /// Guards against the drift the fix for #1174 removes: every icon key the
    /// warning gate accepts must also produce a real condition string, not
    /// the "—" fallback. If a future key is added to the metadata table
    /// without a matching `ConditionKey` case, this fails.
    func test_isKnownIconKey_impliesConditionText() {
        let placeholder = OBALoc(
            "weather.condition.unknown",
            value: "—",
            comment: "Weather condition placeholder when the icon key is unknown."
        )
        for key in WeatherFormatter.knownIconKeys {
            expect(WeatherFormatter.isKnownIconKey(key)) == true
            expect(WeatherFormatter.conditionText(for: key)) != placeholder
        }
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

    // MARK: - formatTime

    func test_formatTime_usLocaleHasAmPmMarker() {
        // Don't pin to a specific hour — the formatter renders in the host
        // timezone, which varies across CI runners. The contract for en_US is
        // "12-hour clock with an AM/PM marker", which we can check regardless
        // of which hour the date lands on.
        let date = Date(timeIntervalSince1970: 1782525600)
        let result = WeatherFormatter.formatTime(date, locale: Locale(identifier: "en_US")).uppercased()
        expect(result.contains("AM") || result.contains("PM")) == true
    }

    func test_formatTime_24HourLocaleHasNoAmPm() {
        let date = Date(timeIntervalSince1970: 1782525600)
        let result = WeatherFormatter.formatTime(date, locale: Locale(identifier: "fr_FR")).uppercased()
        expect(result).toNot(contain("AM"))
        expect(result).toNot(contain("PM"))
    }

    // MARK: - highLow

    func test_highLow_returnsNilForEmptyForecasts() {
        expect(WeatherFormatter.highLow(from: [], locale: Locale(identifier: "en_US"))).to(beNil())
    }

    /// `highLow` summarises whatever window it's handed — `upcomingHourly` is
    /// the helper that caps at 24, drops past-hour entries, and de-dupes, so
    /// the cap test belongs there. This test pins the cap end-to-end: feed
    /// 25 raw entries with an outlier 25th, send them through `upcomingHourly`
    /// → `highLow`, and confirm the outlier is dropped.
    func test_highLow_throughUpcomingHourly_cappedAt24Entries() {
        // Anchor "now" at epoch 0 (UTC) so the upcomingHourly past-hour filter
        // sees the synthesised entries as upcoming.
        let now = Date(timeIntervalSince1970: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // First 24 entries stay in the 50–60°F band; entry 25 is a 200°F
        // outlier that must be ignored if the 24-cap holds.
        var json: [[String: Any]] = (0..<24).map { i in
            [
                "icon": "clear-day",
                "precip_per_hour": 0.0,
                "precip_probability": 0.0,
                "summary": "Clear",
                "temperature": 50.0 + Double(i % 10),
                "temperature_feels_like": 0.0,
                "time": TimeInterval(i * 3600),
                "wind_speed": 0.0
            ]
        }
        json.append([
            "icon": "clear-day",
            "precip_per_hour": 0.0,
            "precip_probability": 0.0,
            "summary": "Hot",
            "temperature": 200.0,
            "temperature_feels_like": 0.0,
            "time": TimeInterval(25 * 3600),
            "wind_speed": 0.0
        ])
        let data = try! JSONSerialization.data(withJSONObject: json)
        let hourly = try! JSONDecoder().decode([WeatherForecast.HourlyForecast].self, from: data)

        let window = WeatherFormatter.upcomingHourly(from: hourly, now: now, calendar: calendar)
        let result = WeatherFormatter.highLow(from: window, locale: Locale(identifier: "en_US"))

        expect(result).toNot(beNil())
        // 200°F would clearly show up if the cap weren't enforced.
        expect(result?.high).toNot(contain("200"))
        expect(result?.high).to(contain("59"))
        expect(result?.low).to(contain("50"))
    }
}
