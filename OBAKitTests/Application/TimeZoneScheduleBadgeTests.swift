//
//  TimeZoneScheduleBadgeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Pins #332: clock times follow the transit region's zone, and the badge
/// never uses `TimeZone.NameStyle.shortGeneric` — that was PR #1102's
/// failure mode (`Poland Time` / `United Kingdom Time` on every row).
@Suite(.serialized)
struct TimeZoneScheduleBadgeTests {

    /// 2024-01-15 20:00 UTC. Winter: PST, CET, IST. Not Date() — DST would
    /// make the expected abbreviation a function of the CI calendar.
    private let winterAfternoonUTC = Date(timeIntervalSince1970: 1_705_348_800)

    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let taipei = TimeZone(identifier: "Asia/Taipei")!
    private let gmt = TimeZone(secondsFromGMT: 0)!

    @Test func `Same offset produces no badge`() {
        #expect(losAngeles.scheduleBadge(at: winterAfternoonUTC, versus: losAngeles) == nil)
        #expect(gmt.scheduleBadge(at: winterAfternoonUTC, versus: TimeZone(identifier: "UTC")!) == nil)
    }

    @Test func `Puget Sound from Taipei shows a short US abbreviation`() throws {
        let badge = try #require(losAngeles.scheduleBadge(at: winterAfternoonUTC, versus: taipei))
        #expect(badge == "PST")
        #expect(!badge.contains("Time"))
        #expect(!badge.contains("Pacific"))
    }

    /// The #1102 blocker: `.shortGeneric` + `en_US` yields "Poland Time"
    /// for Europe/Warsaw. A letter-only 2–5 char abbreviation (CET) or a
    /// GMT offset is acceptable; a long localized name is not.
    @Test func `Warsaw never renders as Poland Time`() throws {
        let badge = try #require(warsaw.scheduleBadge(at: winterAfternoonUTC, versus: taipei))
        // Foundation on this SDK reports `GMT+1` for Warsaw in winter, not `CET`.
        // Either is a short offset/abbr; "Poland Time" is the #1102 failure.
        #expect(badge == "CET" || badge == "GMT+1")
        #expect(!badge.localizedCaseInsensitiveContains("poland"))
        #expect(!badge.localizedCaseInsensitiveContains("time"))
    }

    @Test func `Half-hour offset falls back to a GMT label when abbreviation is not letters`() throws {
        let badge = try #require(kolkata.scheduleBadge(at: winterAfternoonUTC, versus: gmt))
        // IST is a valid 3-letter abbr; if Foundation ever stops issuing it,
        // the GMT fallback must still be a short offset, never a long name.
        #expect(badge == "IST" || badge == "GMT+5:30")
        #expect(!badge.localizedCaseInsensitiveContains("india"))
        #expect(!badge.contains("Time"))
    }

    @Test func `Preferred zone is the most common identifier`() {
        let tz = TimeZone.preferredScheduleTimeZone(identifiers: [
            "America/Los_Angeles",
            "America/Los_Angeles",
            "America/New_York"
        ])
        #expect(tz?.identifier == "America/Los_Angeles")
    }

    @Test func `Preferred zone skips invalid identifiers`() {
        let tz = TimeZone.preferredScheduleTimeZone(identifiers: [
            "",
            "Not/AZone",
            "Europe/Warsaw"
        ])
        #expect(tz?.identifier == "Europe/Warsaw")
    }

    @Test func `Preferred zone is nil when nothing resolves`() {
        #expect(TimeZone.preferredScheduleTimeZone(identifiers: []) == nil)
        #expect(TimeZone.preferredScheduleTimeZone(identifiers: ["", "bogus"]) == nil)
    }

    @Test func `Agency resolvedTimeZone parses IANA identifiers`() throws {
        let agency = try Fixtures.dictionaryToModel(type: Agency.self, dictionary: [
            "id": "1",
            "name": "King County Metro",
            "url": "https://kingcounty.gov/metro",
            "timezone": "America/Los_Angeles",
            "lang": "en",
            "phone": "206-553-3000",
            "privateService": false
        ])
        #expect(agency.resolvedTimeZone?.identifier == "America/Los_Angeles")
    }

    @Test func `Agency resolvedTimeZone is nil for garbage identifiers`() throws {
        let agency = try Fixtures.dictionaryToModel(type: Agency.self, dictionary: [
            "id": "x",
            "name": "X",
            "url": "https://example.com",
            "timezone": "",
            "lang": "en",
            "phone": "",
            "privateService": false
        ])
        #expect(agency.resolvedTimeZone == nil)
    }

    @Test func `Clock time omits badge when the device is already in the region zone`() {
        let formatters = Formatters(
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            themeColors: ThemeColors()
        )
        formatters.timeZone = losAngeles
        let clock = formatters.formattedClockTime(winterAfternoonUTC, deviceTimeZone: losAngeles)
        #expect(!clock.contains("("))
        #expect(clock == formatters.timeFormatter.string(from: winterAfternoonUTC))
    }

    @Test func `Clock time appends a parenthetical badge when the device zone differs`() {
        let formatters = Formatters(
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            themeColors: ThemeColors()
        )
        formatters.timeZone = losAngeles
        let clock = formatters.formattedClockTime(winterAfternoonUTC, deviceTimeZone: taipei)
        #expect(clock.hasSuffix(" (PST)"))
        // The clock itself is Pacific noon, not Taipei 04:00 the next morning.
        #expect(clock.contains("12:00"))
        #expect(!clock.localizedCaseInsensitiveContains("time"))
    }

    @Test func `Assigning timeZone updates the shared time formatter`() {
        let formatters = Formatters(
            locale: Locale(identifier: "en_US"),
            calendar: Calendar(identifier: .gregorian),
            themeColors: ThemeColors()
        )
        formatters.timeZone = gmt
        let gmtText = formatters.timeFormatter.string(from: winterAfternoonUTC)
        formatters.timeZone = losAngeles
        let pacificText = formatters.timeFormatter.string(from: winterAfternoonUTC)
        #expect(gmtText != pacificText)
        #expect(pacificText.contains("12:00"))
    }
}
