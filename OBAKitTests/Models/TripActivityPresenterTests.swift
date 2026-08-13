//
//  TripActivityPresenterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class TripActivityPresenterTests {
    private static let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
    private let formatters = TripActivityPresenterTests.formatters
    private let presenter = TripActivityPresenter(formatters: TripActivityPresenterTests.formatters)

    private func arrival(offsetSeconds: Int, status: TripAttributes.ContentState.ScheduleStatusValue = .onTime, deviation: Int = 0, now: Date) -> TripAttributes.ContentState.ArrivalInfo {
        TripAttributes.ContentState.ArrivalInfo(
            departureTime: Int(now.timeIntervalSince1970) + offsetSeconds,
            scheduleStatus: status,
            scheduleDeviation: deviation,
            isArrival: false
        )
    }

    /// Whole-second epoch date so departureTime (an Int of epoch seconds)
    /// represents the offset exactly — a fractional `now` would truncate to
    /// just under the offset and shift the minute math down by one.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func `Minute text for future departure`() {
        let text = presenter.minuteText(for: arrival(offsetSeconds: 300, now: now), now: now)
        #expect(text.contains("5"), "expected a 5-minute chip, got \(text)")
    }

    @Test func `Color matches formatters schedule status color`() {
        #expect(presenter.color(for: arrival(offsetSeconds: 300, status: .delayed, now: now)) == formatters.colorForScheduleStatus(.delayed))
    }

    @Test func `Status text for unknown status says scheduled`() {
        let text = presenter.statusText(for: arrival(offsetSeconds: 300, status: .unknown, now: now), now: now)
        #expect(text.contains(Strings.scheduledNotRealTime))
    }

    /// Server-pushed deviations are raw seconds (e.g. 95s). Truncating division
    /// would report "1 min late"; the app-wide convention (see
    /// ArrivalDeparture.deviationFromScheduleInMinutes) is to round, which for
    /// 95s should report "2 min late".
    @Test func `Status text rounds deviation minutes`() {
        let text = presenter.statusText(for: arrival(offsetSeconds: 300, status: .delayed, deviation: 95, now: now), now: now)
        #expect(text.contains("2 min late"), "95s should round to 2 min late, got \(text)")
    }

    @Test func `Primary color for empty arrivals is unknown status color`() {
        let state = TripAttributes.ContentState(arrivals: [])
        #expect(presenter.primaryColor(for: state) == formatters.colorForScheduleStatus(.unknown))
    }

    // MARK: - timeDisplay

    /// `ContentState` doesn't carry the scheduled instant, so `timeDisplay`
    /// derives it by walking the deviation back off the departure time: five
    /// minutes late means the timetable said five minutes earlier.
    @Test func `Time display derives scheduled time from deviation`() {
        let display = presenter.timeDisplay(for: arrival(offsetSeconds: 600, status: .delayed, deviation: 300, now: now))

        #expect(display.expectedTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(600)))
        #expect(display.scheduledTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(300)))
    }

    /// The inverse direction: an early arrival's timetable time sits *after*
    /// the prediction (negative deviation walks forward).
    @Test func `Time display early derives scheduled time after predicted`() {
        let display = presenter.timeDisplay(for: arrival(offsetSeconds: 300, status: .early, deviation: -240, now: now))

        #expect(display.expectedTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(300)))
        #expect(display.scheduledTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(540)))
    }

    /// `.unknown` means the feed offered no prediction; a struck-through time
    /// would imply a correction that never happened — even when a stale
    /// deviation value rides along.
    @Test func `Time display unknown status shows no strikethrough`() {
        let display = presenter.timeDisplay(for: arrival(offsetSeconds: 600, status: .unknown, deviation: 300, now: now))

        #expect(display.scheduledTimeText == nil)
        #expect(display.expectedTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(600)))
    }

    /// A deviation that lands in the same clock minute must not strike
    /// anything: "10:42 10:42" with one struck through reads as a bug.
    ///
    /// `now` sits at :20 past the minute (1_700_000_000 % 60 == 20), so a 20s
    /// deviation walks the schedule back to exactly :00 of the *same* minute —
    /// the largest deviation that stays same-minute from this epoch. Changing
    /// either constant moves the test off this boundary.
    @Test func `Time display same minute deviation shows one time`() {
        let display = presenter.timeDisplay(for: arrival(offsetSeconds: 600, status: .onTime, deviation: 20, now: now))

        #expect(display.scheduledTimeText == nil)
        #expect(display.expectedTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(600)))
    }
}
