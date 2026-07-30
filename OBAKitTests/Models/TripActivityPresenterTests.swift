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
    private let presenter = TripActivityPresenter(
        formatters: Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
    )

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
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
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
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
        let state = TripAttributes.ContentState(arrivals: [])
        #expect(presenter.primaryColor(for: state) == formatters.colorForScheduleStatus(.unknown))
    }
}
