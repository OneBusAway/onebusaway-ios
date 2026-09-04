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

    /// The component overload exists for callers holding a view model rather than
    /// the `ArrivalDeparture` it came from — `ArrivalDepartureItem` carries the
    /// four values and not the model. Same gate, so `.unknown` must produce the
    /// same string the model form does.
    @Test func `Deviation label component form says scheduled for unknown status`() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())

        let label = formatters.deviationLabel(
            scheduleStatus: .unknown,
            temporalState: .future,
            arrivalDepartureStatus: .arriving,
            scheduleDeviation: 0)

        #expect(label == Strings.scheduledNotRealTime)
    }

    /// And with a real prediction it must fall through to the deviation phrase
    /// rather than short-circuiting — otherwise the gate would swallow every case.
    @Test func `Deviation label component form uses the deviation phrase when predicted`() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())

        let label = formatters.deviationLabel(
            scheduleStatus: .delayed,
            temporalState: .future,
            arrivalDepartureStatus: .arriving,
            scheduleDeviation: 2)

        #expect(label == "arrives 2 min late")
    }

    /// The two forms are one implementation, so they must agree on the same trip.
    /// A drift here is exactly what the third hand-rolled copy in
    /// `StopArrivalItem` used to allow.
    @Test func `Deviation label forms agree on the same trip`() throws {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        let arrivalDeparture = try Fixtures.arrivalDeparture(
            predictedArrival: 1_700_000_120,
            predictedDeparture: 1_700_000_120
        )

        let fromModel = formatters.deviationLabel(for: arrivalDeparture)
        let fromComponents = formatters.deviationLabel(
            scheduleStatus: arrivalDeparture.scheduleStatus,
            temporalState: arrivalDeparture.temporalState,
            arrivalDepartureStatus: arrivalDeparture.arrivalDepartureStatus,
            scheduleDeviation: arrivalDeparture.deviationFromScheduleInMinutes)

        #expect(fromModel == fromComponents)
        #expect(fromModel == "arrives 2 min late")
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

    // MARK: - Arrival vs departure caption (#447)

    @Test func `Caption is Arrives for a vehicle arriving at this stop`() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        #expect(formatters.arrivalDepartureCaption(for: .arriving, temporalState: .future) == "Arrives")
    }

    @Test func `Caption is Departs for a vehicle leaving this stop`() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        #expect(formatters.arrivalDepartureCaption(for: .departing, temporalState: .future) == "Departs")
    }

    @Test func `Past caption uses arrived or departed`() {
        let formatters = Formatters(locale: usLocale, calendar: calendar, themeColors: ThemeColors())
        #expect(formatters.arrivalDepartureCaption(for: .arriving, temporalState: .past) == "Arrived")
        #expect(formatters.arrivalDepartureCaption(for: .departing, temporalState: .past) == "Departed")
    }

    // MARK: - Map route labels (#132)

    @Test func `Formatted map routes within the limit lists every route`() throws {
        let routes = try makeRoutes(shortNames: ["10", "20", "30"])
        let label = try #require(Formatters.formattedMapRoutes(routes, limit: 3))
        #expect(label == "10, 20, 30")
        #expect(!label.contains("..."))
        #expect(!label.hasPrefix("Routes:"))
    }

    /// U+2026, not three ASCII periods: `StopAnnotationView.titleLabel` truncates
    /// with UIKit's own `…`, and mixing the two glyphs is the inconsistency #514
    /// is about. The marker lives in `OBALoc` so translators can substitute
    /// locale-conventional overflow marks (zh-Hans `……`).
    @Test func `Formatted map routes over the limit appends ellipsis`() throws {
        let routes = try makeRoutes(shortNames: ["10", "20", "30", "40", "62"])
        let label = try #require(Formatters.formattedMapRoutes(routes, limit: 3))
        #expect(label == "10, 20, 30…")
        #expect(label.contains("\u{2026}"))
        #expect(!label.contains("..."))
        #expect(!label.contains("more"))
        #expect(!label.hasPrefix("Routes:"))
    }

    /// The pin label and the callout must agree. Home/Recent still use
    /// `Stop.subtitle` (`"Routes: …"` with every route) — that is not a map
    /// surface, so it is left alone.
    @Test func `Map callout uses the overflowing map route list, not plus-more`() throws {
        let stop = try #require(Fixtures.loadSomeStops().first)
        stop.routes = try makeRoutes(shortNames: ["10", "20", "30", "40", "62"])

        let callout = stop.mapCalloutText
        #expect(callout == "#\(stop.code)\n10, 20, 30…")
        #expect(!callout.contains("Routes:"))

        let subtitle = try #require(stop.subtitle)
        #expect(subtitle.hasPrefix("#\(stop.code)"))
        #expect(subtitle.contains("Routes:"))
        #expect(subtitle.contains("62"))
        #expect(!subtitle.contains("\u{2026}"))
    }

    private func makeRoutes(shortNames: [String]) throws -> [Route] {
        try shortNames.enumerated().map { index, shortName in
            try Fixtures.dictionaryToModel(type: Route.self, dictionary: [
                "agencyId": "test_agency",
                "id": "route_\(index)",
                "shortName": shortName,
                "type": 3
            ])
        }
    }
}
