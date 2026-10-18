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

/// The `8m` / `NOW` countdown as a `DiscreteFormatStyle`.
///
/// Format it to a `String`; never hand it to `Text(.currentDate, format:)` in a
/// Live Activity. The Lock Screen renders a ticking `Text` out of process, and
/// at full brightness it drew this custom style as a redacted placeholder card
/// (#1583). `TickingCountdownText` ticks with a SwiftUI system style instead.
///
/// The minute boundaries are anchored on `departure`, not on the wall clock;
/// past departure it stays `NOW` rather than counting up.
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

/// "in 8 minutes" / "now" that self-updates on a Live Activity, using a
/// SwiftUI system style (see `liveFormat`). Dim Lock Screen draws a static
/// snapshot of the same wording.
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
        let label = Group {
            if isLuminanceReduced {
                Text(verbatim: Self.snapshot(departure: departure, now: Date(), locale: locale))
            } else {
                Text(.currentDate, format: Self.liveFormat(departure: departure, locale: locale))
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(color)
        .opacity(opacity)

        if let accessibilityLabel {
            label.accessibilityLabel(accessibilityLabel)
        } else {
            label.accessibilityLabel(Self.spokenText(departure: departure, isLuminanceReduced: isLuminanceReduced, locale: locale))
        }
    }

    @Environment(\.locale) private var locale

    /// "in 8 minutes" / "now", ticking on its own.
    ///
    /// It must be one of SwiftUI's system styles. The Lock Screen renders a
    /// ticking `Text` out of process; at full brightness it drew our custom
    /// `TripCountdownFormatStyle` as a redacted placeholder card (#1583). The
    /// output is already spelled out, so VoiceOver speaks it as is.
    public static func liveFormat(departure: Date, locale: Locale = .autoupdatingCurrent) -> SystemFormatStyle.DateReference {
        SystemFormatStyle.DateReference(to: departure, allowedFields: [.minute], maxFieldCount: 1, thresholdField: .minute)
            .locale(locale)
    }

    /// What `liveFormat` says at `now`, for the dim Lock Screen's static text,
    /// so raising the phone doesn't change the wording.
    public static func snapshot(departure: Date, now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        String(liveFormat(departure: departure, locale: locale).format(now).characters)
    }

    /// The countdown as a `Text` for VoiceOver, ticking with the visual one.
    /// Static under reduced luminance, like the visual text. Public so a
    /// combined accessibility label (the Live Activity card) can splice it in.
    public static func spokenText(departure: Date, isLuminanceReduced: Bool = false, locale: Locale = .autoupdatingCurrent) -> Text {
        if isLuminanceReduced {
            return Text(verbatim: snapshot(departure: departure, now: Date(), locale: locale))
        }
        return Text(.currentDate, format: liveFormat(departure: departure, locale: locale))
    }
}
