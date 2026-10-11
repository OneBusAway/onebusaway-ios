//
//  TripCountdownFormatStyleTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// `discreteInput(after:)` is how SwiftUI knows when to redraw a Live Activity
/// `Text`. Wrong boundaries → the card never ticks, or it re-renders constantly.
/// Minute boundaries are anchored on `departure`, not on wall-clock minutes.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1187
@Suite(.serialized)
struct TripCountdownFormatStyleTests {

    private let departure = Date(timeIntervalSince1970: 1_700_000_000)
    private var style: TripCountdownFormatStyle { TripCountdownFormatStyle(departure: departure) }

    @Test func `Eight and a half minutes formats as 8m`() {
        let now = departure.addingTimeInterval(-510)
        #expect(style.format(now) == "8m")
    }

    /// The Dynamic Island used to go through `presenter.minuteText` →
    /// `Formatters.shortFormattedTime` → `formatters.short_time_fmt`. Keep that
    /// coupling so ar/fr/ko/ru/vi/zh don't fall back to a hardcoded English `m`.
    @Test func `Future minutes match Formatters.shortFormattedTime`() {
        let now = departure.addingTimeInterval(-510)
        let formatters = Formatters(
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            themeColors: ThemeColors.shared
        )
        #expect(style.format(now) == formatters.shortFormattedTime(untilMinutes: 8, temporalState: .future))
    }

    // MARK: - Spoken form

    private var spoken: TripCountdownFormatStyle { .spoken(departure: departure) }

    /// VoiceOver reads the visual "8m" as "8 meters"; the spoken form spells
    /// the unit out, matching what the Stop page speaks.
    @Test func `Spoken form spells out minutes`() {
        #expect(spoken.format(departure.addingTimeInterval(-510)) == "8 minutes")
    }

    @Test func `Spoken form says one minute in the singular`() {
        #expect(spoken.format(departure.addingTimeInterval(-90)) == "One minute")
    }

    @Test func `Spoken form says now under a minute`() {
        #expect(spoken.format(departure.addingTimeInterval(-30)) == "NOW")
    }

    /// The spoken label must flip on the same instants as the visible text, or
    /// a focused element says a different number than the screen shows.
    @Test func `Spoken form ticks on the same boundaries as the visual form`() {
        let now = departure.addingTimeInterval(-510)
        #expect(spoken.discreteInput(after: now) == style.discreteInput(after: now))
        #expect(spoken.discreteInput(before: now) == style.discreteInput(before: now))
    }

    @Test func `Under a minute formats as NOW`() {
        #expect(style.format(departure.addingTimeInterval(-30)) == "NOW")
        #expect(style.format(departure) == "NOW")
        #expect(style.format(departure.addingTimeInterval(90)) == "NOW")
    }

    /// Next redraw is the instant `Int(remaining/60)` drops, i.e. remaining == 8*60.
    @Test func `discreteInput after a city-block wait is the next whole minute before departure`() {
        let now = departure.addingTimeInterval(-510)
        let next = style.discreteInput(after: now)
        #expect(next == departure.addingTimeInterval(-480))
    }

    /// Already on a boundary: `after` must step into the lower truncating
    /// bucket so `format` flips. Returning the next whole-minute floor left
    /// TimeDataSource showing N while remaining was already in N-1.
    @Test func `discreteInput after an exact minute boundary flips format immediately`() {
        let now = departure.addingTimeInterval(-480)
        #expect(style.format(now) == "8m")
        let next = style.discreteInput(after: now)
        #expect(next == now.addingTimeInterval(1))
        #expect(style.format(next!) == "7m")
    }

    @Test func `discreteInput after NOW is nil so it does not count up past departure`() {
        #expect(style.discreteInput(after: departure.addingTimeInterval(-30)) == nil)
        #expect(style.discreteInput(after: departure.addingTimeInterval(10)) == nil)
    }

    /// At remaining == 60s the label is still `1m`. The next flip is NOW.
    @Test func `discreteInput after the 1m boundary advances into NOW`() {
        let now = departure.addingTimeInterval(-60)
        let next = style.discreteInput(after: now)
        #expect(next != nil)
        #expect(next! > now)
        #expect(style.format(next!) == "NOW")
    }

    /// The rider-facing bug: with 61s left the card must already read `1m`,
    /// not sit on a precomputed `2m` until the 60s floor.
    @Test func `discreteInput after the 2m boundary flips to 1m not the next floor`() {
        let now = departure.addingTimeInterval(-120)
        #expect(style.format(now) == "2m")
        let next = style.discreteInput(after: now)
        #expect(next != nil)
        #expect(style.format(next!) == "1m")
        #expect(next! < departure.addingTimeInterval(-60))
    }
}
