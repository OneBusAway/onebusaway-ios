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

/// Live Activity countdown that keeps the `8m` / `NOW` typography and still
/// ticks without a keepalive push.
///
/// `Text.timer` was tried in #1263 and rejected: `0:00` is not how this app
/// shows a departure. A custom `DiscreteFormatStyle` is how SwiftUI schedules
/// the next redraw (minute boundaries *anchored on `departure`*, not on the
/// wall clock). Past departure it stays `NOW` rather than counting up.
///
/// Always-on display redacts unknown format styles. `TickingCountdownText`
/// falls back to a static `format(Date())` when `isLuminanceReduced` is set,
/// so dim Lock Screen shows dashes-free digits from the last evaluation.
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

        // Same key as `Formatters.shortFormattedTime` so the Dynamic Island
        // keeps ar/fr/ko/ru/vi/zh suffixes instead of a hardcoded English `m`.
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

        let boundary = departure.addingTimeInterval(-TimeInterval(minutes) * 60)
        if boundary > date { return boundary }

        // Sitting on this minute's boundary. Next flip is the next lower
        // minute, except 1m → NOW which starts the instant remaining < 60s.
        if minutes == 1 {
            return date.addingTimeInterval(1)
        }
        return departure.addingTimeInterval(-TimeInterval(minutes - 1) * 60)
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

/// `8m` / `NOW` that self-updates on a Live Activity. Dim Lock Screen uses a
/// static snapshot so a custom format style is not redacted to dashes.
public struct TickingCountdownText: View {
    public let departure: Date
    public let font: Font
    public let color: Color

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(departure: Date, font: Font, color: Color) {
        self.departure = departure
        self.font = font
        self.color = color
    }

    public var body: some View {
        let style = TripCountdownFormatStyle(departure: departure)
        Group {
            if isLuminanceReduced {
                Text(style.format(Date()))
            } else {
                Text(.currentDate, format: style)
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(color)
    }
}
