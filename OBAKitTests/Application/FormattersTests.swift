//
//  FormattersTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

enum ModelDecodingError: Error {
    case invalidData
    case invalidReferences
    case invalidModelList
}

@Suite(.serialized)
final class FormattersTests: OBATestCase {
    let usLocale = Locale(identifier: "en_US")
    let calendar = Calendar(identifier: .gregorian)

    @Test func example() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let stopArrivals = try! Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_75414.json")
        let arrDep = stopArrivals.arrivalsAndDepartures.first!

        let str = formatters.explanation(from: arrDep)

        // Deliberately stricter than what it replaced. Nimble's `match` was
        // `range(of:options:.regularExpression)` -- an UNANCHORED substring
        // search -- whereas `SELF MATCHES` anchors to the whole string, so this
        // also asserts nothing surrounds the phrase. That's the intent here.
        #expect(NSPredicate(format: "SELF MATCHES %@", "Arrived \\d+ min ago").evaluate(with: str))
    }

    // MARK: - Transfer-Relative Time

    @Test func `Short formatted transfer time positive minutes`() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let result = formatters.shortFormattedTransferTime(minutes: 4)
        #expect(result == "4m")
    }

    @Test func `Short formatted transfer time negative minutes`() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let result = formatters.shortFormattedTransferTime(minutes: -3)
        #expect(result == "-3m")
    }

    @Test func `Short formatted transfer time zero`() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let result = formatters.shortFormattedTransferTime(minutes: 0)
        #expect(result == "NOW")
    }

    @Test func `Transfer arrival banner text`() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())

        let arrivalTime = Date(timeIntervalSince1970: 1_000_000)
        // Get the expected time string from the same formatter that the banner uses,
        // so the test is timezone-agnostic and passes on any machine (local or CI).
        let expectedTime = formatters.timeFormatter.string(from: arrivalTime)

        let result = formatters.transferArrivalBannerText(arrivalTime: arrivalTime, routeDisplay: "10 - Capitol Hill")

        #expect(result.contains("10 - Capitol Hill"), "Banner should contain route display: \(result)")
        #expect(result.contains(expectedTime), "Banner should contain formatted time '\(expectedTime)': \(result)")
    }

    // MARK: - Stop accessibility label

    @Test func `Formatted accessibility label omits the bookmark name by default`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let label = Formatters.formattedAccessibilityLabel(stop: stop)

        #expect(label.hasPrefix(stop.name))
    }

    /// A bookmark pin shows the user's chosen name visually, so VoiceOver has to
    /// announce it too — otherwise the pin reads identically to a regular stop.
    @Test func `Formatted accessibility label leads with the bookmark name`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let label = Formatters.formattedAccessibilityLabel(stop: stop, bookmarkName: "Home")

        #expect(label.hasPrefix("Home; "))
        // The stop's own details still follow, so nothing is lost by bookmarking.
        #expect(label.contains(stop.name))
        #expect(label.contains(stop.code))
    }

    /// Bookmarks default to the stop's own name, and hearing it twice in a row
    /// is noise rather than information.
    @Test func `Formatted accessibility label does not repeat a bookmark name matching the stop`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        let label = Formatters.formattedAccessibilityLabel(stop: stop, bookmarkName: stop.name)

        #expect(label == Formatters.formattedAccessibilityLabel(stop: stop))
    }

    // MARK: - Deviation Label

    /// With a real-time prediction, the label is the plain deviation phrase.
    ///
    /// `Fixtures.dictionaryToModel` decodes with a plain `JSONDecoder`, whose
    /// default date strategy reads these numbers as seconds since the 2001
    /// reference date — so the instants land in Nov 2054, temporal state
    /// `.future`, and the default stop sequence means `.arriving`. A +120 s
    /// prediction therefore reads "arrives 2 min late" on any machine until
    /// that date passes; pinning the phrase to the wall clock outright would
    /// require injecting a clock into `ArrivalDeparture.temporalState`, which
    /// reads `Date()` directly.
    @Test func `Deviation label uses the deviation phrase for predicted trips`() throws {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let arrivalDeparture = try Fixtures.arrivalDeparture(
            predictedArrival: 1_700_000_120,
            predictedDeparture: 1_700_000_120
        )

        #expect(formatters.deviationLabel(for: arrivalDeparture) == "arrives 2 min late")
    }

    /// The inverse direction: an early prediction formats with the magnitude
    /// of the deviation, not its sign.
    @Test func `Deviation label uses the early phrase for predicted-early trips`() throws {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let arrivalDeparture = try Fixtures.arrivalDeparture(
            predictedArrival: 1_699_999_880,
            predictedDeparture: 1_699_999_880
        )

        #expect(formatters.deviationLabel(for: arrivalDeparture) == "arrives 2 min early")
    }

    /// A schedule-only trip has a deviation of zero by definition, so the
    /// deviation phrase would falsely claim "on time". The label must say the
    /// trip is schedule data instead — the widget pairs it with a concrete
    /// clock time, which makes a false real-time claim louder.
    @Test func `Deviation label says scheduled for unpredicted trips`() throws {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let arrivalDeparture = try Fixtures.arrivalDeparture(predicted: false)

        #expect(formatters.deviationLabel(for: arrivalDeparture) == Strings.scheduledNotRealTime)
    }

    /// A payload can carry predicted timestamps while declaring
    /// `predicted: false`; the gate is the flag, not the fields — the same rule
    /// `DepartureTimeDisplay` applies before striking through a time.
    @Test func `Deviation label ignores stale predicted times when feed says not predicted`() throws {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let arrivalDeparture = try Fixtures.arrivalDeparture(
            predicted: false,
            predictedArrival: 1_700_000_120,
            predictedDeparture: 1_700_000_120
        )

        #expect(formatters.deviationLabel(for: arrivalDeparture) == Strings.scheduledNotRealTime)
    }
}
