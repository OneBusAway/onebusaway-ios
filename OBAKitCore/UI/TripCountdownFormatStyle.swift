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
    /// Spell the unit out ("8 minutes") instead of abbreviating it ("8m").
    /// VoiceOver reads a bare `8m` as "8 meters" or "8 m", so every spoken
    /// countdown uses this form. Same boundaries as the visual form, so the
    /// two flip together.
    public var isSpoken: Bool

    public init(departure: Date, isSpoken: Bool = false) {
        self.departure = departure
        self.isSpoken = isSpoken
    }

    /// The spoken form of the countdown, for accessibility labels.
    public static func spoken(departure: Date) -> TripCountdownFormatStyle {
        TripCountdownFormatStyle(departure: departure, isSpoken: true)
    }

    public func format(_ now: Date) -> String {
        let minutes = Int(departure.timeIntervalSince(now) / 60.0)
        if isSpoken {
            return spokenFormat(minutes: minutes)
        }
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

    /// Reuses the keys `Formatters.formattedTimeUntilArrivalDeparture` speaks
    /// on the Stop page, so the Live Activity and the app say the same thing.
    private func spokenFormat(minutes: Int) -> String {
        if minutes <= 0 {
            return OBALoc("formatters.now", value: "NOW", comment: "Short formatted time text for arrivals/departures occurring now.")
        }
        if minutes == 1 {
            return OBALoc("formatters.one_minute", value: "One minute", comment: "Formatted time text for arrivals/departures that occur in one minute.")
        }
        let formatString = OBALoc("formatters.time_fmt", value: "%d minutes", comment: "Formatted time text for arrivals/departures. Used for accessibility labels, so be sure to spell out the word for 'minute'. Example: 7 minutes means that this event happens 7 minutes in the future. -7 minutes means 7 minutes in the past.")
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

/// `8m` / `NOW` that self-updates on a Live Activity. Dim Lock Screen uses a
/// static snapshot so a custom format style is not redacted to dashes.
///
/// `opacity` and `accessibilityLabel` are first-class so Live Activity stale
/// chrome (#1379) can compose on this type instead of re-wrapping modifiers
/// around every call site.
public struct TickingCountdownText: View {
    public let departure: Date
    public let font: Font
    public let color: Color
    /// Stale Live Activity chrome dims minutes via `LiveActivityStaleChrome.contentOpacity`.
    public let opacity: Double
    /// When set (e.g. minimal Island + stale warning), overrides the spoken
    /// countdown. When `nil`, VoiceOver hears the spelled-out countdown
    /// ("8 minutes"), never the visual `8m`.
    public let accessibilityLabel: String?

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(
        departure: Date,
        font: Font,
        color: Color,
        opacity: Double = 1.0,
        accessibilityLabel: String? = nil
    ) {
        self.departure = departure
        self.font = font
        self.color = color
        self.opacity = opacity
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        let style = TripCountdownFormatStyle(departure: departure)
        let label = Group {
            if isLuminanceReduced {
                Text(style.format(Date()))
            } else {
                Text(.currentDate, format: style)
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(color)
        .opacity(opacity)

        if let accessibilityLabel {
            label.accessibilityLabel(accessibilityLabel)
        } else {
            label.accessibilityLabel(Self.spokenText(departure: departure, isLuminanceReduced: isLuminanceReduced))
        }
    }

    /// The spelled-out countdown as a `Text`, ticking on the same minute
    /// boundaries as the visual one. Static under reduced luminance for the
    /// same redaction reason as the visual text. Public so a combined
    /// accessibility label (the Live Activity card) can splice it in.
    public static func spokenText(departure: Date, isLuminanceReduced: Bool = false) -> Text {
        let style = TripCountdownFormatStyle.spoken(departure: departure)
        if isLuminanceReduced {
            return Text(verbatim: style.format(Date()))
        }
        return Text(.currentDate, format: style)
    }
}
