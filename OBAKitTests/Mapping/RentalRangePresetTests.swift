//
//  RentalRangePresetTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit

/// The range-filter menu ladder. Rungs are whole numbers in the rider's own units
/// rather than a metric ladder converted from miles, because "8 km" reads as a bug.
@MainActor
@Suite(.serialized)
final class RentalRangePresetTests {

    @Test func imperialLadderUsesWholeMiles() {
        let titles = RentalRangePreset.presets(measurementSystem: .us, locale: Locale(identifier: "en_US")).map(\.title)
        #expect(titles == ["Any", "1 mi", "2 mi", "5 mi", "10 mi", "15 mi"])
    }

    @Test func metricLadderUsesWholeKilometres() {
        let titles = RentalRangePreset.presets(measurementSystem: .metric, locale: Locale(identifier: "en_US")).map(\.title)
        #expect(titles == ["Any", "2 km", "5 km", "10 km", "15 km", "25 km"])
    }

    /// UK road distances are in miles even though the UK is otherwise metric.
    @Test func unitedKingdomGetsMiles() {
        let titles = RentalRangePreset.presets(measurementSystem: .uk, locale: Locale(identifier: "en_US")).map(\.title)
        #expect(titles == ["Any", "1 mi", "2 mi", "5 mi", "10 mi", "15 mi"])
    }

    /// `Locale.MeasurementSystem` is a struct constructible from any BCP-47
    /// identifier, so it can never be switched exhaustively. Anything unrecognized
    /// must land on metric — that's right for most of the world.
    @Test func unknownSystemFallsBackToMetric() {
        let titles = RentalRangePreset.presets(measurementSystem: Locale.MeasurementSystem("nonsense"), locale: Locale(identifier: "en_US")).map(\.title)
        #expect(titles == ["Any", "2 km", "5 km", "10 km", "15 km", "25 km"])
    }

    @Test func anyRungIsZeroMetres() {
        let presets = RentalRangePreset.presets(measurementSystem: .us, locale: Locale(identifier: "en_US"))
        #expect(presets.first?.meters == 0)
    }

    @Test func imperialRungsConvertToMetres() {
        let meters = RentalRangePreset.presets(measurementSystem: .us, locale: Locale(identifier: "en_US")).map(\.meters)
        #expect(meters == [0, 1609, 3219, 8047, 16093, 24140])
    }

    @Test func metricRungsConvertToMetres() {
        let meters = RentalRangePreset.presets(measurementSystem: .metric, locale: Locale(identifier: "en_US")).map(\.meters)
        #expect(meters == [0, 2000, 5000, 10000, 15000, 25000])
    }

    @Test func identifierIsTheMetreValue() {
        let presets = RentalRangePreset.presets(measurementSystem: .us, locale: Locale(identifier: "en_US"))
        #expect(presets.map(\.id) == presets.map(\.meters))
    }

    @Test func nearestRungMatchesExactly() {
        let presets = RentalRangePreset.presets(measurementSystem: .us, locale: Locale(identifier: "en_US"))
        #expect(RentalRangePreset.nearest(toMeters: 8047, in: presets)?.meters == 8047)
    }

    /// A stored value from another locale's ladder highlights the closest rung,
    /// without the stored preference being rewritten.
    @Test func nearestRungSnapsAnOffLadderValue() {
        let presets = RentalRangePreset.presets(measurementSystem: .us, locale: Locale(identifier: "en_US"))
        #expect(RentalRangePreset.nearest(toMeters: 10_000, in: presets)?.meters == 8047)
    }

    @Test func nearestRungHandlesZero() {
        let presets = RentalRangePreset.presets(measurementSystem: .us, locale: Locale(identifier: "en_US"))
        #expect(RentalRangePreset.nearest(toMeters: 0, in: presets)?.meters == 0)
    }

    @Test func nearestRungOnEmptyLadderIsNil() {
        #expect(RentalRangePreset.nearest(toMeters: 5000, in: []) == nil)
    }

    /// Titles are rendered in the caller's locale, not the process's ambient one.
    /// Without an injected locale this assertion would silently depend on the test
    /// host's system settings — the same ambient-global trap the GMT pin in
    /// OBATestCase exists to close. `de_DE` doesn't prove this: its "km" is
    /// byte-identical to `en_US`'s, so the assertion would still pass even if
    /// `formatter.locale = locale` were deleted from production code. `ar` was
    /// chosen to actually differ — measured on iPhone 17 Pro / iOS 26.3, it
    /// keeps Western digits here (Arabic-Indic numerals turn out to be a
    /// region-specific default, e.g. `ar_SA`, not part of the bare `ar` locale
    /// data) but does localize the unit abbreviation ("كم"), which is enough to
    /// make the assertion fail if the injected locale is ever dropped. "Any"
    /// stays English because it comes from `OBALoc`, which reads the app
    /// bundle's language, not the formatter's locale.
    @Test func titlesFollowTheProvidedLocale() {
        let titles = RentalRangePreset.presets(
            measurementSystem: .metric,
            locale: Locale(identifier: "ar")
        ).map(\.title)
        #expect(titles == ["Any", "2 كم", "5 كم", "10 كم", "15 كم", "25 كم"])
    }
}
