//
//  OnDemandServiceSummaryTests.swift
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

// swiftlint:disable force_cast

@Suite(.serialized)
final class OnDemandServiceSummaryTests: OBATestCase {

    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let enUS = Locale(identifier: "en_US")

    /// 2026-03-10 16:00 in Los Angeles (a Tuesday), one hour before Alexandria's 17:00 cutoff.
    private let now = ISO8601DateFormatter().date(from: "2026-03-10T23:00:00Z")!

    private func alexandria(transform: ((inout [String: Any]) -> Void)? = nil) throws -> OnDemandService {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        guard let transform else {
            return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: data).entry
        }
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        transform(&json)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: JSONSerialization.data(withJSONObject: json)).entry
    }

    private func summary(_ service: OnDemandService, now: Date? = nil) -> OnDemandServiceSummary {
        OnDemandServiceSummary(service: service, timeZone: losAngeles, now: now ?? self.now, locale: enUS)
    }

    @Test func `Windows collapse contiguous days and format hours in the agency zone`() throws {
        let summary = summary(try alexandria())
        #expect(summary.windows.count == 2)
        #expect(summary.windows[0].days == "Mon–Sat")
        #expect(summary.windows[1].days == "Sun")
        let monSat = summary.windows[0].hours ?? ""
        #expect(monSat.contains("5:00"), "\(monSat)")
        #expect(monSat.contains("12:50"), "24:50 renders as the next day's 12:50; got \(monSat)")
        #expect(monSat.contains("–"))
        #expect(summary.windows[1].hours?.contains("7:00") == true)
    }

    /// Pickup times are nominal GTFS wall-clock times. On the spring-forward
    /// day the service day's anchor sits an hour off local midnight, so
    /// placing "01:00:00" on that day read "12:00 AM".
    @Test func `Window hours are nominal on a DST transition day`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var entry = data["entry"] as! [String: Any]
            entry["rules"] = (entry["rules"] as! [[String: Any]]).map { rule in
                var rule = rule
                rule["startPickupTime"] = "01:00:00"
                return rule
            }
            data["entry"] = entry
            json["data"] = data
        }
        // 2026-03-08 12:00 in Los Angeles, the spring-forward day.
        let springForwardNoon = ISO8601DateFormatter().date(from: "2026-03-08T19:00:00Z")!
        let hours = summary(service, now: springForwardNoon).windows[0].hours
        #expect(hours == "1:00\u{202F}AM – 12:50\u{202F}AM", "\(hours ?? "nil")")
    }

    @Test func `Book-by line uses the next bookable date and its cutoff`() throws {
        let summary = summary(try alexandria())
        guard case .bookBy(let deadline, let travelDate) = summary.bookingLine else {
            Issue.record("expected bookBy, got \(summary.bookingLine)")
            return
        }
        // Cutoff = 2026-03-10 17:00 LA for a ride on Wed 2026-03-11.
        #expect(deadline.contains("5:00"), "\(deadline)")
        // The relative word sits mid-sentence: "Book by today at 5:00 PM".
        #expect(deadline.hasPrefix("today"), "\(deadline)")
        #expect(travelDate.contains("Mar 11"), "\(travelDate)")
        #expect(travelDate.contains("Wed"), "\(travelDate)")
    }

    /// "tomorrow" becomes "today" at the agency's midnight, so that is a
    /// boundary even when no cutoff or opening falls before it.
    @Test func `Agency midnight bounds the next change`() throws {
        // Mon 2026-03-09 23:30 in Los Angeles.
        let lateMonday = ISO8601DateFormatter().date(from: "2026-03-10T06:30:00Z")!
        let summary = summary(try alexandria(), now: lateMonday)
        guard case .bookBy(let deadline, _) = summary.bookingLine else {
            Issue.record("expected bookBy, got \(summary.bookingLine)")
            return
        }
        #expect(deadline.hasPrefix("tomorrow"), "\(deadline)")
        #expect(summary.nextChangeInstant == ISO8601DateFormatter().date(from: "2026-03-10T07:00:00Z"))
    }

    @Test func `Contact details come from the pickup booking rule`() throws {
        let summary = summary(try alexandria())
        #expect(summary.phoneNumber == "703-746-5222")
        #expect(summary.phoneURL == URL(string: "tel://7037465222"))
        #expect(summary.infoURL == URL(string: "https://www.alexandriava.gov/Paratransit"))
        #expect(summary.bookingURL?.host() == "spare-rider-alexandriadot-production.vercel.app")
        #expect(summary.message?.hasPrefix("DOT is the City of Alexandria") == true)
    }

    @Test func `Unknown time zone leaves the line unknown but keeps windows and contact details`() throws {
        let summary = OnDemandServiceSummary(service: try alexandria(), timeZone: nil, now: now, locale: enUS)
        #expect(summary.bookingLine == .unknown)
        #expect(summary.windows.count == 2)
        #expect(summary.windows[0].days == "Mon–Sat")
        #expect(summary.windows[0].hours == "5:00\u{202F}AM – 12:50\u{202F}AM", "wall-clock hours are zone-independent; got \(summary.windows[0].hours ?? "nil")")
        #expect(summary.windows[1].hours?.contains("7:00") == true)
        #expect(summary.phoneNumber == "703-746-5222")
        #expect(summary.phoneURL == URL(string: "tel://7037465222"))
        #expect(summary.bookingURL?.host() == "spare-rider-alexandriadot-production.vercel.app")
        #expect(summary.infoURL == URL(string: "https://www.alexandriava.gov/Paratransit"))
        #expect(summary.message?.hasPrefix("DOT is the City of Alexandria") == true)
    }

    @Test func `Unknown time zone renders the same hours as the agency zone`() throws {
        let service = try alexandria()
        let withZone = summary(service)
        let withoutZone = OnDemandServiceSummary(service: service, timeZone: nil, now: now, locale: enUS)
        #expect(withoutZone.windows == withZone.windows)
    }

    @Test func `Degenerate service with no rules is unknown with no windows`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var entry = data["entry"] as! [String: Any]
            entry["rules"] = []
            data["entry"] = entry
            json["data"] = data
        }
        let summary = summary(service)
        #expect(summary.bookingLine == .unknown)
        #expect(summary.windows.isEmpty)
        #expect(summary.phoneNumber == nil)
    }

    @Test func `Dangling booking rule id yields unknown`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var references = data["references"] as! [String: Any]
            references["bookingRules"] = []
            data["references"] = references
            json["data"] = data
        }
        let summary = summary(service)
        #expect(summary.bookingLine == .unknown)
        #expect(summary.windows.count == 2, "windows do not depend on booking rules")
    }

    @Test func `No pickup booking rule means no notice required`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var entry = data["entry"] as! [String: Any]
            entry["rules"] = (entry["rules"] as! [[String: Any]]).map { rule in
                var rule = rule
                rule["pickupBookingRuleId"] = NSNull()
                return rule
            }
            data["entry"] = entry
            json["data"] = data
        }
        #expect(summary(service).bookingLine == .noNoticeRequired)
    }

    @Test func `Calendar that starts in the future yields opens-at`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var references = data["references"] as! [String: Any]
            references["calendars"] = (references["calendars"] as! [[String: Any]]).map { calendar in
                var calendar = calendar
                calendar["startDate"] = "2026-04-01"
                return calendar
            }
            data["references"] = references
            json["data"] = data
        }
        // First active day is Wed 2026-04-01; booking opens 14 days before, 2026-03-18 00:00 LA.
        guard case .opensAt(let text) = summary(service).bookingLine else {
            Issue.record("expected opensAt, got \(summary(service).bookingLine)")
            return
        }
        #expect(text.contains("Mar 18"), "\(text)")
    }

    @Test func `Calendar that has ended yields closed`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var references = data["references"] as! [String: Any]
            references["calendars"] = (references["calendars"] as! [[String: Any]]).map { calendar in
                var calendar = calendar
                calendar["endDate"] = "2026-01-31"
                return calendar
            }
            data["references"] = references
            json["data"] = data
        }
        #expect(summary(service).bookingLine == .closed)
    }

    @Test func `Rule without pickup times reports all-hours`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var entry = data["entry"] as! [String: Any]
            entry["rules"] = (entry["rules"] as! [[String: Any]]).map { rule in
                var rule = rule
                rule["startPickupTime"] = NSNull()
                rule["endPickupTime"] = NSNull()
                rule["endDropOffTime"] = NSNull()
                return rule
            }
            data["entry"] = entry
            json["data"] = data
        }
        let summary = summary(service)
        #expect(summary.windows.count == 2)
        #expect(summary.windows[0].hours == nil)
    }

    /// A rule with one pickup bound is not all-hours: the missing bound reads
    /// as the default the evaluator books against — `24:00:00` for the end,
    /// as `latestPickup` assumes — rather than hiding the window.
    @Test func `Rule with only a start pickup time reports hours to the end of the service day`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]
            var entry = data["entry"] as! [String: Any]
            entry["rules"] = (entry["rules"] as! [[String: Any]]).map { rule in
                var rule = rule
                rule["endPickupTime"] = NSNull()
                rule["endDropOffTime"] = NSNull()
                return rule
            }
            data["entry"] = entry
            json["data"] = data
        }
        let summary = summary(service)
        let hours = try #require(summary.windows.first?.hours)
        #expect(hours.contains("5:00"), "\(hours)")
        #expect(hours.contains("12:00"), "24:00 renders as the next day's 12:00; got \(hours)")
    }

    /// Cross-client parity: two rules active on the same travel date with
    /// different pickup booking rules. The prior-day rule's deadline for
    /// today has already passed (book-by-1-day, cutoff was yesterday 17:00),
    /// so its own next bookable date walks forward to tomorrow. The same-day
    /// rule is still open for today. The earlier travel date — today, from
    /// the same-day rule — must win, not the prior-day rule's later date.
    @Test func `Two rules on the same travel date pick the earliest still-bookable candidate`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]

            var entry = data["entry"] as! [String: Any]
            let template = (entry["rules"] as! [[String: Any]])[0]
            var priorDayRule = template
            priorDayRule["pickupBookingRuleId"] = "prior-day-rule"
            priorDayRule["dropOffBookingRuleId"] = "prior-day-rule"
            var sameDayRule = template
            sameDayRule["pickupBookingRuleId"] = "same-day-rule"
            sameDayRule["dropOffBookingRuleId"] = "same-day-rule"
            entry["rules"] = [priorDayRule, sameDayRule]
            data["entry"] = entry

            var references = data["references"] as! [String: Any]
            references["bookingRules"] = [
                ["id": "prior-day-rule", "bookingType": 2, "priorNoticeLastDay": 1, "priorNoticeLastTime": "17:00:00"],
                ["id": "same-day-rule", "bookingType": 1, "priorNoticeDurationMin": 60]
            ]
            data["references"] = references
            json["data"] = data
        }

        guard case .bookBy(let deadline, let travelDate) = summary(service).bookingLine else {
            Issue.record("expected bookBy, got \(summary(service).bookingLine)")
            return
        }
        #expect(travelDate.contains("Mar 10"), "\(travelDate)")
        #expect(travelDate.contains("Tue"), "\(travelDate)")
        #expect(deadline.hasPrefix("today"), "\(deadline)")
        // Same-day rule's cutoff: endPickupTime 24:50:00 minus the 60-minute
        // notice = 23:50 the same service day → 11:50 PM.
        #expect(deadline.contains("11:50"), "\(deadline)")
    }

    /// Cross-client parity (Android `earliestOpening`): a one-day notice
    /// window viewed Tuesday 18:00. Tuesday and Wednesday are already closed
    /// (cutoffs Mon and Tue 17:00), while Thursday's booking opens Wednesday
    /// 09:00 — so the opens line must look past the closed next service day.
    @Test func `Opens-at looks past a closed next service day`() throws {
        let service = try alexandria { json in
            var data = json["data"] as! [String: Any]

            var entry = data["entry"] as! [String: Any]
            var rule = (entry["rules"] as! [[String: Any]])[0]
            rule["pickupBookingRuleId"] = "prior-day-window"
            rule["dropOffBookingRuleId"] = "prior-day-window"
            entry["rules"] = [rule]
            data["entry"] = entry

            var references = data["references"] as! [String: Any]
            references["bookingRules"] = [[
                "id": "prior-day-window", "bookingType": 2,
                "priorNoticeLastDay": 1, "priorNoticeLastTime": "17:00:00",
                "priorNoticeStartDay": 1, "priorNoticeStartTime": "09:00:00"
            ]]
            data["references"] = references
            json["data"] = data
        }
        // 2026-03-10 18:00 in Los Angeles, a Tuesday.
        let tuesdayEvening = ISO8601DateFormatter().date(from: "2026-03-11T01:00:00Z")!
        let wednesdayNine = ISO8601DateFormatter().date(from: "2026-03-11T16:00:00Z")!
        let expected = OnDemandServiceSummary.deadlineForTesting(
            now: tuesdayEvening, cutoff: wednesdayNine, today: Date(), timeZone: losAngeles, locale: enUS
        )

        #expect(summary(service, now: tuesdayEvening).bookingLine == .opensAt(expected))
        #expect(expected.contains("9:00"), "\(expected)")
    }

    // MARK: - Unknown outcomes

    /// Rewrites the fixture's references: each calendar through `calendar`,
    /// plus `extraCalendars`, and the booking rules wholesale. Each rule's
    /// `calendarIds` gains `extraRuleCalendarIDs`.
    private func alexandria(
        calendar: @escaping (inout [String: Any]) -> Void = { _ in },
        extraCalendars: [[String: Any]] = [],
        extraRuleCalendarIDs: [String] = [],
        bookingRules: [[String: Any]],
        ruleBookingIDs: [String]? = nil
    ) throws -> OnDemandService {
        try alexandria { json in
            var data = json["data"] as! [String: Any]
            var references = data["references"] as! [String: Any]
            references["calendars"] = (references["calendars"] as! [[String: Any]]).map { element in
                var element = element
                calendar(&element)
                return element
            } + extraCalendars
            references["bookingRules"] = bookingRules
            data["references"] = references
            var entry = data["entry"] as! [String: Any]
            var rules = entry["rules"] as! [[String: Any]]
            if let ruleBookingIDs {
                rules = zip(rules, ruleBookingIDs).map { rule, bookingID in
                    var rule = rule
                    rule["pickupBookingRuleId"] = bookingID
                    rule["dropOffBookingRuleId"] = bookingID
                    return rule
                }
            }
            entry["rules"] = rules.map { rule in
                var rule = rule
                rule["calendarIds"] = (rule["calendarIds"] as! [String]) + extraRuleCalendarIDs
                return rule
            }
            data["entry"] = entry
            json["data"] = data
        }
    }

    private let fixtureBookingRuleID = "5088_booking_route_77652"

    @Test func `Same-day rule without a minimum notice is unknown`() throws {
        let service = try alexandria(bookingRules: [["id": fixtureBookingRuleID, "bookingType": 1]])
        #expect(summary(service).bookingLine == .unknown)
    }

    /// The service ends Wednesday. Tuesday's count-back walks past the notice
    /// calendar's start (unknown) and Wednesday's cutoff has passed (closed):
    /// with one date unevaluable the line cannot claim booking is closed.
    @Test func `An ending service with a failed count-back is unknown rather than closed`() throws {
        let service = try alexandria(
            calendar: { $0["endDate"] = "2026-03-11" },
            extraCalendars: [[
                "id": "notice", "days": ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
                "startDate": "2026-03-10", "endDate": "2026-12-31", "exceptedDates": []
            ]],
            bookingRules: [[
                "id": fixtureBookingRuleID, "bookingType": 2,
                "priorNoticeLastDay": 1, "priorNoticeLastTime": "17:00:00", "priorNoticeCalendarId": "notice"
            ]]
        )
        // 2026-03-10 18:00 in Los Angeles.
        let tuesdayEvening = ISO8601DateFormatter().date(from: "2026-03-11T01:00:00Z")!
        #expect(summary(service, now: tuesdayEvening).bookingLine == .unknown)
    }

    /// Mon–Sat is over (its last day's cutoff passed); Sunday's same-day
    /// rule has no minimum notice. One settled rule cannot outvote an
    /// unknown one.
    @Test func `One settled rule and one unknown rule is unknown`() throws {
        let service = try alexandria(
            calendar: { calendar in
                if calendar["id"] as? String == "5088_c_71675_b_85952_d_63" {
                    calendar["endDate"] = "2026-03-10"
                }
            },
            bookingRules: [
                ["id": "prior-day", "bookingType": 2, "priorNoticeLastDay": 1, "priorNoticeLastTime": "17:00:00"],
                ["id": "same-day-no-minimum", "bookingType": 1]
            ],
            ruleBookingIDs: ["prior-day", "same-day-no-minimum"]
        )
        #expect(summary(service).bookingLine == .unknown)
    }

    /// Spec §6.3: an unparseable startDate makes the evaluation unknown, so a
    /// service whose rules have no usable calendar cannot claim to be closed.
    @Test func `Rules on calendars with no usable start date are unknown`() throws {
        let service = try alexandria(calendar: { $0["startDate"] = "" }, bookingRules: [[
            "id": fixtureBookingRuleID, "bookingType": 2, "priorNoticeLastDay": 1, "priorNoticeLastTime": "17:00:00"
        ]])
        #expect(service.calendars.allSatisfy { $0.startDate == nil })
        #expect(summary(service).bookingLine == .unknown)
    }

    /// One usable calendar keeps the normal walk: only the unusable one is ignored.
    @Test func `A rule with one usable calendar keeps its normal outcome`() throws {
        let service = try alexandria(
            calendar: { $0["endDate"] = "2026-01-31" },
            extraCalendars: [["id": "undated", "days": ["mon"], "startDate": "", "endDate": "2026-12-31"]],
            extraRuleCalendarIDs: ["undated"],
            bookingRules: [["id": fixtureBookingRuleID, "bookingType": 2, "priorNoticeLastDay": 1, "priorNoticeLastTime": "17:00:00"]]
        )
        #expect(service.calendars.contains { $0.id == "undated" && $0.startDate == nil })
        #expect(summary(service).bookingLine == .closed, "the ended calendar is usable, so the rules are closed")
    }

    @Test func `Day runs render as ranges and lists`() {
        let symbols = DateFormatter().shortWeekdaySymbols!  // en_US in the GMT-pinned test process
        #expect(OnDemandServiceSummary.daysText([.mon, .tue, .wed, .thu, .fri, .sat], shortWeekdaySymbols: symbols) == "Mon–Sat")
        #expect(OnDemandServiceSummary.daysText([.mon, .wed, .fri], shortWeekdaySymbols: symbols) == "Mon, Wed, Fri")
        #expect(OnDemandServiceSummary.daysText([.sat, .sun], shortWeekdaySymbols: symbols) == "Sat–Sun")
        #expect(OnDemandServiceSummary.daysText([.mon, .tue, .thu, .fri, .sat, .sun], shortWeekdaySymbols: symbols) == "Mon–Tue, Thu–Sun")
        #expect(OnDemandServiceSummary.daysText([], shortWeekdaySymbols: symbols) == "")
    }

    /// `SummaryFormatters.relativeProbe` builds a same-day-offset stand-in
    /// from the *live* clock to borrow Foundation's relative vocabulary
    /// (see the type's doc comment). If the live day it lands on is a DST
    /// spring-forward day and the deadline's own clock time falls in the
    /// gap (2:00–3:00 AM doesn't exist locally on 2026-03-08 in Los
    /// Angeles), `Calendar.date(bySettingHour:)` silently rolls the
    /// nonexistent time forward to 3:00 AM rather than failing — a probe
    /// like that would show a later cutoff than the real one. Exercised via
    /// `OnDemandServiceSummary.deadlineForTesting`, the test-only seam that
    /// lets `today` (the live-clock stand-in) be pinned to the gap day
    /// instead of whatever day the test actually runs on.
    @Test func `Deadline falls back to the absolute formatter when a DST gap would shift the probe's clock time`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles

        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 1, minute: 0))!
        let cutoff = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 2, minute: 30))!
        // 2026-03-08 is the US spring-forward day in Los Angeles; pinning
        // "today" there (instead of the real live day) makes the gap
        // reproducible regardless of when this test actually runs.
        let liveNowOnGapDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9, minute: 0))!

        let deadline = OnDemandServiceSummary.deadlineForTesting(now: now, cutoff: cutoff, today: liveNowOnGapDay, timeZone: losAngeles, locale: enUS)

        #expect(deadline.contains("2:30"), "\(deadline)")
        #expect(!deadline.contains("3:00"), "\(deadline)")
        #expect(!deadline.localizedCaseInsensitiveContains("today"), "\(deadline)")
    }
}

// swiftlint:enable force_cast
