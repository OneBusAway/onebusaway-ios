//
//  TripCountdownFormatStyle.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI

/// The `8m` / `NOW` countdown, ticking in-process: the watch's arrival rows.
///
/// Not for a Live Activity. The Lock Screen renders a ticking `Text` out of
/// process, and at full brightness it drew this custom style as a redacted
/// placeholder card (#1583); `TickingCountdownText` ticks there with a system
/// style instead. In the app's own process it works, and keeps the compact
/// typography a narrow row needs.
///
/// A custom `DiscreteFormatStyle` is how SwiftUI schedules the next redraw:
/// minute boundaries *anchored on `departure`*, not on the wall clock. Past
/// departure it stays `NOW` rather than counting up.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1187
public struct TripCountdownFormatStyle: DiscreteFormatStyle, Sendable {
    public typealias FormatInput = Date
    public typealias FormatOutput = String

    public var departure: Date

    public init(departure: Date) {
        self.departure = departure
    }

    public func format(_ now: Date) -> String {
        let minutes = Int(departure.timeIntervalSince(now) / 60.0)
        if minutes <= 0 {
            return OBALoc(
                "stop_page.countdown.now",
                value: "NOW",
                comment: "Shown in place of the minutes countdown when the vehicle is departing now"
            )
        }

        // Same key as `Formatters.shortFormattedTime` so it keeps the
        // ar/fr/ko/ru/vi/zh suffixes instead of a hardcoded English `m`.
        let formatString = OBALoc(
            "formatters.short_time_fmt",
            value: "%dm",
            comment: "Short formatted time text for arrivals/departures. Example: 7m means that this event happens 7 minutes in the future. -7m means 7 minutes in the past."
        )
        return String(format: formatString, minutes)
    }

    public func discreteInput(after date: Date) -> Date? {
        let minutes = Int(departure.timeIntervalSince(date) / 60.0)
        guard minutes > 0 else { return nil }

        // Truncating `format` flips from N → N-1 the instant remaining drops
        // *below* N*60, i.e. just after `departure - N*60`. Returning the
        // floor itself leaves TimeDataSource displaying `format(floor)` (== N)
        // for a full minute — so 2m shows while only 61s remain (#1187 follow-up).
        let boundary = departure.addingTimeInterval(-TimeInterval(minutes) * 60)
        if boundary > date { return boundary }

        // On the floor: step one second into the lower bucket so `format` flips
        // (same treatment for every N, including 1m → NOW).
        return date.addingTimeInterval(1)
    }

    public func discreteInput(before date: Date) -> Date? {
        let minutes = Int(departure.timeIntervalSince(date) / 60.0)
        if minutes < 0 { return nil }

        if minutes == 0 {
            let start = departure.addingTimeInterval(-60)
            return start < date ? start : nil
        }

        let startOfCurrent = departure.addingTimeInterval(-TimeInterval(minutes + 1) * 60)
        return startOfCurrent < date ? startOfCurrent : nil
    }
}
