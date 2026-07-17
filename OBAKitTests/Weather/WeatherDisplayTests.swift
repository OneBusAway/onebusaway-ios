//
//  WeatherDisplayTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import Foundation
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `WeatherDisplay` and `HourlyEntry.list`. Covers the rules the
/// review pinned down: past-hour filtering, "Now" labelling, the 24-entry cap,
/// Date-based identity, and the empty-input edge case.
@MainActor
final class WeatherDisplayTests: XCTestCase {

    // MARK: - Fixtures

    private let usLocale = Locale(identifier: "en_US")

    /// A deterministic "now" used for every hourly test so we don't depend on
    /// wall-clock time. Calendar is also pinned to UTC for the same reason.
    private let now: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 23
        components.hour = 14
        components.minute = 32
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }()

    private var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Builds a fake hourly forecast from raw fixture JSON for the given epoch.
    /// Decoding through the real model exercises the same path production uses.
    private func makeHourly(
        epochs: [TimeInterval],
        precipProbability: Double = 0.0,
        temperatures: [Double]? = nil
    ) -> [WeatherForecast.HourlyForecast] {
        let json: [[String: Any]] = epochs.enumerated().map { idx, ts in
            [
                "icon": "clear-day",
                "precip_per_hour": 0.0,
                "precip_probability": precipProbability,
                "summary": "Clear",
                "temperature": temperatures?[idx] ?? 60.0,
                "temperature_feels_like": 58.0,
                "time": ts,
                "wind_speed": 5.0
            ]
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode([WeatherForecast.HourlyForecast].self, from: data)
    }

    // MARK: - WeatherFormatter.upcomingHourly

    /// The Obaco API sometimes ships the previous full hour at index 0.
    /// `upcomingHourly` must drop it so the "Now" cell aligns with the actual
    /// current hour, not an hour ago.
    func test_upcomingHourly_dropsHoursBeforeCurrentHourBucket() {
        let oneHourAgo = now.addingTimeInterval(-3600)
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let nextHour = currentHour.addingTimeInterval(3600)
        let hourly = makeHourly(epochs: [oneHourAgo.timeIntervalSince1970,
                                         currentHour.timeIntervalSince1970,
                                         nextHour.timeIntervalSince1970])

        let window = WeatherFormatter.upcomingHourly(from: hourly, now: now, calendar: utcCalendar)

        expect(window.count) == 2
        expect(window.first?.time) == currentHour
    }

    /// Even when the API ships 48 hours, the window is capped at 24.
    func test_upcomingHourly_cappedAt24Entries() {
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let hourly = makeHourly(epochs: (0..<48).map { currentHour.addingTimeInterval(Double($0) * 3600).timeIntervalSince1970 })

        let window = WeatherFormatter.upcomingHourly(from: hourly, now: now, calendar: utcCalendar)

        expect(window.count) == 24
    }

    /// Even if the API delivers hourly entries out of chronological order, the
    /// window must still start at the current hour (sort before slicing).
    func test_upcomingHourly_sortsOutOfOrderInput() {
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let inOrder = (0..<3).map { currentHour.addingTimeInterval(Double($0) * 3600).timeIntervalSince1970 }
        let shuffled = [inOrder[2], inOrder[0], inOrder[1]]
        let hourly = makeHourly(epochs: shuffled)

        let window = WeatherFormatter.upcomingHourly(from: hourly, now: now, calendar: utcCalendar)

        expect(window.first?.time) == currentHour
        let timestamps = window.map(\.time)
        expect(timestamps) == timestamps.sorted()
    }

    /// If every entry is in the past, none survive the filter.
    func test_upcomingHourly_allPastEntriesReturnsEmpty() {
        let past = (1...3).map { now.addingTimeInterval(-Double($0) * 3600).timeIntervalSince1970 }
        let hourly = makeHourly(epochs: past)

        let window = WeatherFormatter.upcomingHourly(from: hourly, now: now, calendar: utcCalendar)

        expect(window).to(beEmpty())
    }

    /// A glitch that ships the same hour twice would otherwise give `ForEach`
    /// duplicate `id`s and mark both cells `isNow`. The window de-dupes.
    func test_upcomingHourly_dedupesRepeatedTimestamps() {
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let nextHour = currentHour.addingTimeInterval(3600)
        let hourly = makeHourly(epochs: [currentHour.timeIntervalSince1970,
                                         currentHour.timeIntervalSince1970,
                                         nextHour.timeIntervalSince1970])

        let window = WeatherFormatter.upcomingHourly(from: hourly, now: now, calendar: utcCalendar)

        expect(window.count) == 2
        expect(window.map(\.time)) == [currentHour, nextHour]
    }

    // MARK: - HourlyEntry.list

    /// First entry of a pre-windowed slice should be labelled "Now" and
    /// flagged `isNow`.
    func test_list_firstEntryIsNow() {
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let upcoming = makeHourly(epochs: (0..<3).map { currentHour.addingTimeInterval(Double($0) * 3600).timeIntervalSince1970 })

        let entries = HourlyEntry.list(from: upcoming, locale: usLocale)

        expect(entries.first?.timeLabel) == "Now"
        expect(entries.first?.isNow) == true
        expect(entries.dropFirst().allSatisfy { !$0.isNow }) == true
    }

    /// Identity is the hour timestamp, not the array index. This is what keeps
    /// `ForEach`/`LazyHStack` from reusing the same cell view for a different
    /// hour across refreshes.
    func test_list_identityIsHourTimestamp() {
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let upcoming = makeHourly(epochs: (0..<3).map { currentHour.addingTimeInterval(Double($0) * 3600).timeIntervalSince1970 })

        let entries = HourlyEntry.list(from: upcoming, locale: usLocale)

        let expectedIds = (0..<3).map { currentHour.addingTimeInterval(Double($0) * 3600) }
        expect(entries.map(\.id)) == expectedIds
    }

    func test_list_emptyUpcomingReturnsEmpty() {
        let entries = HourlyEntry.list(from: [], locale: usLocale)
        expect(entries).to(beEmpty())
    }

    // MARK: - WeatherFormatter unit gaps

    /// `conditionText` collapses day/night, but the test that asserted
    /// `day == night` never pinned an actual mapping — a regression that
    /// returned the unknown-key fallback for every key would still satisfy
    /// it. Lock down at least one concrete mapping.
    func test_conditionText_mapsKnownIconKeys() {
        expect(WeatherFormatter.conditionText(for: "snow")) == "Snow"
        expect(WeatherFormatter.conditionText(for: "clear-day")) == "Clear"
        expect(WeatherFormatter.conditionText(for: "rain")) == "Rain"
    }

    func test_isKnownIconKey_distinguishesMappedFromUnmapped() {
        expect(WeatherFormatter.isKnownIconKey("clear-day")) == true
        expect(WeatherFormatter.isKnownIconKey("partly-cloudy-night")) == true
        expect(WeatherFormatter.isKnownIconKey("thunderstorm")) == false
    }

    /// The SwiftUI color palette in `WeatherIcon` is layered on top of
    /// `WeatherFormatter`'s icon table. This asserts the palette covers every
    /// key the formatter models, so adding a new condition to the metadata
    /// without a matching palette entry fails here instead of silently
    /// rendering as gray.
    func test_weatherIconPalette_coversAllKnownIconKeys() {
        let paletteKeys = Set(WeatherIconPalette.colors.keys)
        let missing = WeatherFormatter.knownIconKeys.subtracting(paletteKeys)
        expect(missing) == []
    }

    // MARK: - Full WeatherDisplay (fixture-driven)

    private func loadPugetSoundForecast() throws -> WeatherForecast {
        let data = Fixtures.loadData(file: "pugetsound-weather.json")
        return try JSONDecoder.obacoServiceDecoder.decode(WeatherForecast.self, from: data)
    }

    /// Aligned with the Puget Sound fixture's `hourly_forecast` window (first
    /// entry is 2018-10-17 17:00 UTC) so that `WeatherFormatter.upcomingHourly`
    /// doesn't filter every fixture entry out as "in the past" relative to
    /// today's wall clock.
    private let pugetSoundNow = Date(timeIntervalSince1970: 1539810000)

    /// `WeatherDisplay` exists so the UIKit and SwiftUI surfaces can't drift —
    /// both consume the same Header/Stats/HourlyEntry slices. Pinning the
    /// derived strings from a fixture locks the contract so a formatter tweak
    /// that only updates one surface would fail here.
    func test_init_populatesHeaderStatsAndHourlyFromFixture() throws {
        let forecast = try loadPugetSoundForecast()
        let display = WeatherDisplay(forecast: forecast, locale: usLocale, now: pugetSoundNow, calendar: utcCalendar)

        // Header — derived from `current_forecast` + `region_name` + the
        // hourly window's hi/lo, not the calendar-day hi/lo.
        expect(display.header.regionName) == "Puget Sound"
        expect(display.header.iconName) == "clear-day"
        expect(display.header.currentTemp) == "71°"
        expect(display.header.chanceOfRainText) == "Chance of Rain: 0%"
        expect(display.header.highLowText).toNot(beNil())

        // Stats — current-hour wind / precip / feels-like.
        expect(display.stats.feelsLikeText) == "71°"
        expect(display.stats.precipText) == "0%"
        expect(display.stats.windText).to(contain("mph"))

        // Button pill mirrors the current temperature.
        expect(display.buttonTitle) == "71°"

        // Hourly strip — non-empty, first cell labelled "Now" and flagged as
        // the current hour, later cells fall through to formatted times.
        expect(display.hourly).toNot(beEmpty())
        let firstHour = try XCTUnwrap(display.hourly.first)
        expect(firstHour.timeLabel) == "Now"
        expect(firstHour.isNow) == true
        if display.hourly.count > 1 {
            expect(display.hourly[1].isNow) == false
            expect(display.hourly[1].timeLabel) != "Now"
        }
    }

    // MARK: - Stats / Header derived strings

    /// The Puget Sound fixture happens to have `precip_probability == 0`, so
    /// truncation never bites in the fixture test. Cover the typical case so
    /// a regression that flips truncation to rounding (or vice-versa) trips.
    func test_stats_precipTextTruncatesToInteger() throws {
        let json: [String: Any] = [
            "icon": "rain",
            "precip_per_hour": 1.2,
            "precip_probability": 0.456,
            "summary": "Rain",
            "temperature": 60.0,
            "temperature_feels_like": 58.0,
            "time": 0,
            "wind_speed": 5.0
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let hourly = try JSONDecoder().decode(WeatherForecast.HourlyForecast.self, from: data)

        let stats = WeatherDisplay.Stats(forecast: hourly, locale: usLocale)

        // `Int(0.456 * 100)` truncates to 45 rather than rounding to 46.
        expect(stats.precipText) == "45%"
    }

    /// Header owns the `"H:%@  L:%@"` join (the only formatting it does on
    /// hi/lo). The fixture test only asserts non-nil, so an upstream tweak
    /// that swapped the order or dropped the prefix would slip through.
    func test_header_highLowTextJoinsWithLocalisedFormat() throws {
        let forecast = try loadPugetSoundForecast()
        let display = WeatherDisplay(forecast: forecast, locale: usLocale, now: pugetSoundNow, calendar: utcCalendar)
        let highLowText = try XCTUnwrap(display.header.highLowText)

        expect(highLowText).to(beginWith("H:"))
        expect(highLowText).to(contain("  L:"))
        // Two spaces between the two halves — the format is deliberately wide.
        expect(highLowText.components(separatedBy: "  ").count) == 2
    }
}
