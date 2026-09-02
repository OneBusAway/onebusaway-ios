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

    /// Already on a boundary: `after` must move forward, not return the same instant
    /// (that would spin the renderer).
    @Test func `discreteInput after an exact minute boundary advances to the next one`() {
        let now = departure.addingTimeInterval(-480)
        let next = style.discreteInput(after: now)
        #expect(next == departure.addingTimeInterval(-420))
    }

    @Test func `discreteInput after NOW is nil so it does not count up past departure`() {
        #expect(style.discreteInput(after: departure.addingTimeInterval(-30)) == nil)
        #expect(style.discreteInput(after: departure.addingTimeInterval(10)) == nil)
    }

    /// At remaining == 60s the label is still `1m`. The next flip is NOW, which
    /// starts the instant remaining drops below 60. Returning the same instant
    /// would spin the renderer; returning `departure` would freeze `1m` for a
    /// full minute.
    @Test func `discreteInput after the 1m boundary advances into NOW`() {
        let now = departure.addingTimeInterval(-60)
        let next = style.discreteInput(after: now)
        #expect(next != nil)
        #expect(next! > now)
        #expect(style.format(next!) == "NOW")
    }
}
