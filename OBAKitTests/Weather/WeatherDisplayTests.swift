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
    private func makeHourly(epochs: [TimeInterval]) -> [WeatherForecast.HourlyForecast] {
        let json: [[String: Any]] = epochs.map { ts in
            [
                "icon": "clear-day",
                "precip_per_hour": 0.0,
                "precip_probability": 0.0,
                "summary": "Clear",
                "temperature": 60.0,
                "temperature_feels_like": 58.0,
                "time": ts,
                "wind_speed": 5.0
            ]
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode([WeatherForecast.HourlyForecast].self, from: data)
    }

    // MARK: - HourlyEntry.list

    /// The Obaco API sometimes ships the previous full hour at index 0.
    /// `list` must drop it so the "Now" cell aligns with the actual current
    /// hour, not an hour ago.
    func test_list_dropsHoursBeforeCurrentHourBucket() {
        let oneHourAgo = now.addingTimeInterval(-3600)
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let nextHour = currentHour.addingTimeInterval(3600)
        let hourly = makeHourly(epochs: [oneHourAgo.timeIntervalSince1970,
                                         currentHour.timeIntervalSince1970,
                                         nextHour.timeIntervalSince1970])

        let entries = HourlyEntry.list(from: hourly, locale: usLocale, now: now, calendar: utcCalendar)

        expect(entries.count) == 2
        expect(entries.first?.id) == currentHour
        expect(entries.first?.isNow) == true
    }

    /// First surviving entry should be labelled "Now" and flagged `isNow`.
    func test_list_firstEntryIsNow() {
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let hourly = makeHourly(epochs: (0..<3).map { currentHour.addingTimeInterval(Double($0) * 3600).timeIntervalSince1970 })

        let entries = HourlyEntry.list(from: hourly, locale: usLocale, now: now, calendar: utcCalendar)

        expect(entries.first?.timeLabel) == "Now"
        expect(entries.first?.isNow) == true
        expect(entries.dropFirst().allSatisfy { !$0.isNow }) == true
    }

    /// Even when the API ships 48 hours, the strip is capped at 24.
    func test_list_cappedAt24Entries() {
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let hourly = makeHourly(epochs: (0..<48).map { currentHour.addingTimeInterval(Double($0) * 3600).timeIntervalSince1970 })

        let entries = HourlyEntry.list(from: hourly, locale: usLocale, now: now, calendar: utcCalendar)

        expect(entries.count) == 24
    }

    /// Identity is the hour timestamp, not the array index. This is what keeps
    /// `ForEach`/`LazyHStack` from reusing the same cell view for a different
    /// hour across refreshes.
    func test_list_identityIsHourTimestamp() {
        let currentHour = utcCalendar.dateInterval(of: .hour, for: now)!.start
        let hourly = makeHourly(epochs: (0..<3).map { currentHour.addingTimeInterval(Double($0) * 3600).timeIntervalSince1970 })

        let entries = HourlyEntry.list(from: hourly, locale: usLocale, now: now, calendar: utcCalendar)

        let expectedIds = (0..<3).map { currentHour.addingTimeInterval(Double($0) * 3600) }
        expect(entries.map(\.id)) == expectedIds
    }

    func test_list_emptyHourlyForecastsReturnsEmpty() {
        let entries = HourlyEntry.list(from: [], locale: usLocale, now: now, calendar: utcCalendar)
        expect(entries).to(beEmpty())
    }

    /// If every entry is in the past, none survive the filter.
    func test_list_allPastEntriesReturnsEmpty() {
        let past = (1...3).map { now.addingTimeInterval(-Double($0) * 3600).timeIntervalSince1970 }
        let hourly = makeHourly(epochs: past)

        let entries = HourlyEntry.list(from: hourly, locale: usLocale, now: now, calendar: utcCalendar)

        expect(entries).to(beEmpty())
    }
}
