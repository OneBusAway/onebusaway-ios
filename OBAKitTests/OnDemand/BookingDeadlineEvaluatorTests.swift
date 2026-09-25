//
//  BookingDeadlineEvaluatorTests.swift
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

/// Runs the shared `flex-booking-vectors.json` (mirrored verbatim from maglev's
/// `testdata/`) so iOS, Android and the server agree on one algorithm.
@Suite(.serialized)
final class BookingDeadlineEvaluatorTests: OBATestCase {

    // MARK: - Vectors file schema (spec §6)

    private struct VectorsFile: Decodable {
        let timezone: String
        let calendars: [OnDemandCalendar]
        let vectors: [Vector]
    }

    private struct VectorRule: Decodable {
        let startPickupTime: GTFSTimeOfDay?
        let endPickupTime: GTFSTimeOfDay?
        let calendarIds: [String]
    }

    private struct Expected: Decodable {
        let state: String
        let cutoffInstant: String?
        let openInstant: String?
        let nextBookableServiceDate: String?
    }

    private struct Vector: Decodable {
        let name: String
        let timezone: String?
        let bookingRule: OnDemandBookingRule?
        let rule: VectorRule
        let travelDate: ServiceDate
        let now: String
        let expected: Expected
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func parse(_ instant: String) -> Date {
        guard let date = Self.iso8601.date(from: instant) else {
            Issue.record("Unparseable instant in vectors file: \(instant)")
            return .distantPast
        }
        return date
    }

    private func loadVectors() throws -> VectorsFile {
        try JSONDecoder().decode(VectorsFile.self, from: Fixtures.loadData(file: "flex-booking-vectors.json"))
    }

    private func availabilityRule(_ rule: VectorRule, bookingRuleID: String?) -> AvailabilityRule {
        AvailabilityRule(
            fromIDs: ["x"], toIDs: ["x"],
            startPickupTime: rule.startPickupTime,
            endPickupTime: rule.endPickupTime,
            endDropOffTime: nil,
            calendarIDs: rule.calendarIds,
            pickupType: 2, dropOffType: 2,
            pickupBookingRuleID: bookingRuleID, dropOffBookingRuleID: bookingRuleID,
            safeDurationFactor: nil, safeDurationOffset: nil
        )
    }

    @Test func `Vectors file is present and non-trivial`() throws {
        let file = try loadVectors()
        #expect(file.vectors.count >= 12)
        #expect(!file.calendars.isEmpty)
        #expect(TimeZone(identifier: file.timezone) != nil)
    }

    @Test func `Every shared vector evaluates as expected`() throws {
        let file = try loadVectors()
        for vector in file.vectors {
            let zoneIdentifier = vector.timezone ?? file.timezone
            guard let timeZone = TimeZone(identifier: zoneIdentifier) else {
                Issue.record("\(vector.name): unknown time zone \(zoneIdentifier)")
                continue
            }
            let evaluator = BookingDeadlineEvaluator(timeZone: timeZone, calendars: file.calendars)
            let rule = availabilityRule(vector.rule, bookingRuleID: vector.bookingRule?.id)
            let now = parse(vector.now)

            let evaluation = evaluator.evaluate(rule: rule, bookingRule: vector.bookingRule, travelDate: vector.travelDate, now: now)

            #expect(evaluation.state.rawValue == vector.expected.state, "\(vector.name): state")
            #expect(evaluation.cutoffInstant == vector.expected.cutoffInstant.map(parse), "\(vector.name): cutoffInstant")
            #expect(evaluation.openInstant == vector.expected.openInstant.map(parse), "\(vector.name): openInstant")

            let next = evaluator.nextBookableServiceDate(rule: rule, bookingRule: vector.bookingRule, now: now)
            #expect(next?.description == vector.expected.nextBookableServiceDate, "\(vector.name): nextBookableServiceDate")
        }
    }

    // MARK: - Primitives the vectors exercise only indirectly

    private var losAngeles: TimeZone { TimeZone(identifier: "America/Los_Angeles")! }

    private var weekdayCalendar: OnDemandCalendar {
        OnDemandCalendar(
            id: "wk", days: [.mon, .tue, .wed, .thu, .fri],
            startDate: ServiceDate("2026-01-01")!, endDate: ServiceDate("2026-12-31")!,
            exceptedDates: [ServiceDate("2026-03-10")!]
        )
    }

    @Test func `Instant is anchored at noon minus twelve hours across a DST change`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: TimeZone(identifier: "America/Detroit")!, calendars: [])
        // 2026-03-08 is the US spring-forward day: the local day is 23 hours long.
        let transition = ServiceDate("2026-03-08")!
        let anchor = evaluator.anchor(transition)
        let noon = evaluator.noon(transition)
        #expect(noon.timeIntervalSince(anchor) == 12 * 3600)
        #expect(evaluator.instant(transition, GTFSTimeOfDay("25:00:00")!) == anchor.addingTimeInterval(25 * 3600))
        #expect(evaluator.serviceDate(for: noon) == transition)
    }

    @Test func `Count back over a calendar skips inactive and excepted days`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [weekdayCalendar])
        // Wed 2026-03-11: one service day back skips Tue 03-10 (excepted) → Mon 03-09.
        #expect(evaluator.countBack(from: ServiceDate("2026-03-11")!, days: 1, calendarID: "wk") == ServiceDate("2026-03-09")!)
        // Mon 2026-03-16: one service day back skips the weekend → Fri 03-13.
        #expect(evaluator.countBack(from: ServiceDate("2026-03-16")!, days: 1, calendarID: "wk") == ServiceDate("2026-03-13")!)
        // Calendar days when no calendar is given, or the id is unknown.
        #expect(evaluator.countBack(from: ServiceDate("2026-03-16")!, days: 1, calendarID: nil) == ServiceDate("2026-03-15")!)
        #expect(evaluator.countBack(from: ServiceDate("2026-03-16")!, days: 1, calendarID: "missing") == ServiceDate("2026-03-15")!)
        #expect(evaluator.countBack(from: ServiceDate("2026-03-16")!, days: 0, calendarID: "wk") == ServiceDate("2026-03-16")!)
        // Month boundary, calendar days.
        #expect(evaluator.countBack(from: ServiceDate("2026-03-01")!, days: 1, calendarID: nil) == ServiceDate("2026-02-28")!)

        // A calendar whose startDate the walk reaches before the count is consumed
        // fails closed rather than returning a date outside the calendar's range.
        let lateCalendar = OnDemandCalendar(
            id: "late", days: [.mon, .tue, .wed, .thu, .fri],
            startDate: ServiceDate("2026-03-16")!, endDate: ServiceDate("2027-12-31")!, exceptedDates: []
        )
        let lateEvaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [lateCalendar])
        #expect(lateEvaluator.countBack(from: ServiceDate("2026-03-16")!, days: 1, calendarID: "late") == nil)

        // A calendar with no active weekdays at all can never satisfy a count.
        let emptyCalendar = OnDemandCalendar(
            id: "empty", days: [],
            startDate: ServiceDate("2026-01-01")!, endDate: ServiceDate("2026-12-31")!, exceptedDates: []
        )
        let emptyEvaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [emptyCalendar])
        #expect(emptyEvaluator.countBack(from: ServiceDate("2026-03-16")!, days: 1, calendarID: "empty") == nil)
    }

    @Test func `Count back exhausts its four-hundred day step cap`() {
        // The calendar's startDate is far in the past, so the walk never
        // exits early on the startDate check; asking for more active days
        // than 400 calendar days can contain (roughly 5/7 of them, on a
        // Mon-Fri calendar) exercises the loop's own step cap instead.
        let farCalendar = OnDemandCalendar(
            id: "far", days: [.mon, .tue, .wed, .thu, .fri],
            startDate: ServiceDate(year: 2000, month: 1, day: 1), endDate: ServiceDate(year: 2030, month: 12, day: 31),
            exceptedDates: []
        )
        let farEvaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [farCalendar])
        #expect(farEvaluator.countBack(from: ServiceDate("2026-03-16")!, days: 1000, calendarID: "far") == nil)
    }

    @Test func `Active days honour range, weekday and exceptions`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [weekdayCalendar])
        #expect(evaluator.isActive(calendarID: "wk", on: ServiceDate("2026-03-11")!))
        #expect(!evaluator.isActive(calendarID: "wk", on: ServiceDate("2026-03-10")!), "excepted")
        #expect(!evaluator.isActive(calendarID: "wk", on: ServiceDate("2026-03-14")!), "Saturday")
        #expect(!evaluator.isActive(calendarID: "wk", on: ServiceDate("2027-01-04")!), "after endDate")
        #expect(!evaluator.isActive(calendarID: "nope", on: ServiceDate("2026-03-11")!))
    }

    @Test func `Next active service date starts at the given day`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [weekdayCalendar])
        let rule = AvailabilityRule(fromIDs: [], toIDs: [], startPickupTime: nil, endPickupTime: nil, endDropOffTime: nil, calendarIDs: ["wk"], pickupType: 2, dropOffType: 2, pickupBookingRuleID: nil, dropOffBookingRuleID: nil, safeDurationFactor: nil, safeDurationOffset: nil)
        #expect(evaluator.nextActiveServiceDate(rule: rule, from: ServiceDate("2026-03-14")!) == ServiceDate("2026-03-16")!)
        #expect(evaluator.nextActiveServiceDate(rule: rule, from: ServiceDate("2026-03-11")!) == ServiceDate("2026-03-11")!)
        #expect(evaluator.nextActiveServiceDate(rule: rule, from: ServiceDate("2027-06-01")!) == nil)
    }

    @Test func `Next active service date is nil when the rule names no known calendar`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [weekdayCalendar])
        let rule = AvailabilityRule(fromIDs: [], toIDs: [], startPickupTime: nil, endPickupTime: nil, endDropOffTime: nil, calendarIDs: ["missing"], pickupType: 2, dropOffType: 2, pickupBookingRuleID: nil, dropOffBookingRuleID: nil, safeDurationFactor: nil, safeDurationOffset: nil)
        #expect(evaluator.nextActiveServiceDate(rule: rule, from: ServiceDate("2026-03-11")!) == nil)
    }

    @Test func `Next active service date exhausts its own step cap when nothing is active`() {
        // A distant endDate keeps the walk's `cursor <= lastDate` condition
        // true throughout, so exit must come from the step cap, not from
        // running past the calendar's range.
        let neverActiveCalendar = OnDemandCalendar(
            id: "never", days: [],
            startDate: ServiceDate("2026-03-11")!, endDate: ServiceDate("2030-12-31")!,
            exceptedDates: []
        )
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [neverActiveCalendar])
        let rule = AvailabilityRule(fromIDs: [], toIDs: [], startPickupTime: nil, endPickupTime: nil, endDropOffTime: nil, calendarIDs: ["never"], pickupType: 2, dropOffType: 2, pickupBookingRuleID: nil, dropOffBookingRuleID: nil, safeDurationFactor: nil, safeDurationOffset: nil)
        #expect(evaluator.nextActiveServiceDate(rule: rule, from: ServiceDate("2026-03-11")!) == nil)
    }

    @Test func `Same-day booking type opens durationMax minutes before start pickup`() throws {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [])
        let bookingRule = try JSONDecoder().decode(
            OnDemandBookingRule.self,
            from: Data(#"{"id":"same-day-max","bookingType":1,"priorNoticeDurationMin":30,"priorNoticeDurationMax":120}"#.utf8)
        )
        let rule = AvailabilityRule(
            fromIDs: [], toIDs: [],
            startPickupTime: GTFSTimeOfDay("08:00:00"), endPickupTime: GTFSTimeOfDay("18:00:00"),
            endDropOffTime: nil, calendarIDs: [],
            pickupType: 2, dropOffType: 2,
            pickupBookingRuleID: "same-day-max", dropOffBookingRuleID: nil,
            safeDurationFactor: nil, safeDurationOffset: nil
        )
        let travelDate = ServiceDate("2026-03-11")!

        let evaluation = evaluator.evaluate(rule: rule, bookingRule: bookingRule, travelDate: travelDate, now: evaluator.instant(travelDate, GTFSTimeOfDay("07:00:00")!))

        let expectedOpen = evaluator.instant(travelDate, GTFSTimeOfDay("08:00:00")!).addingTimeInterval(-120 * 60)
        #expect(evaluation.openInstant == expectedOpen)
    }

    @Test func `Unknown booking type is unknown`() {
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [weekdayCalendar])
        let rule = AvailabilityRule(fromIDs: [], toIDs: [], startPickupTime: nil, endPickupTime: nil, endDropOffTime: nil, calendarIDs: ["wk"], pickupType: 2, dropOffType: 2, pickupBookingRuleID: "b", dropOffBookingRuleID: nil, safeDurationFactor: nil, safeDurationOffset: nil)
        let bookingRule = try! JSONDecoder().decode(OnDemandBookingRule.self, from: Data("{\"id\":\"b\",\"bookingType\":7}".utf8))
        let evaluation = evaluator.evaluate(rule: rule, bookingRule: bookingRule, travelDate: ServiceDate("2026-03-11")!, now: Date())
        #expect(evaluation == .unknown)
        #expect(evaluator.nextBookableServiceDate(rule: rule, bookingRule: bookingRule, now: Date()) == nil)
    }

    @Test func `Next bookable service date skips unknown candidates instead of stopping`() throws {
        // The rule itself runs every day; only the booking rule's notice
        // calendar starts late.
        let everyDayCalendar = OnDemandCalendar(
            id: "every-day", days: Weekday.allCases,
            startDate: ServiceDate("2026-03-13")!, endDate: ServiceDate("2026-03-31")!,
            exceptedDates: []
        )
        let noticeCalendar = OnDemandCalendar(
            id: "notice-late-start", days: [.mon, .tue, .wed, .thu, .fri],
            startDate: ServiceDate("2026-03-16")!, endDate: ServiceDate("2026-12-31")!,
            exceptedDates: []
        )
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: [everyDayCalendar, noticeCalendar])
        let bookingRule = try JSONDecoder().decode(
            OnDemandBookingRule.self,
            from: Data(#"{"id":"notice-rule","bookingType":2,"priorNoticeLastDay":1,"priorNoticeCalendarId":"notice-late-start"}"#.utf8)
        )
        let rule = AvailabilityRule(
            fromIDs: [], toIDs: [],
            startPickupTime: GTFSTimeOfDay("09:00:00"), endPickupTime: GTFSTimeOfDay("17:00:00"),
            endDropOffTime: nil, calendarIDs: ["every-day"],
            pickupType: 2, dropOffType: 2,
            pickupBookingRuleID: "notice-rule", dropOffBookingRuleID: nil,
            safeDurationFactor: nil, safeDurationOffset: nil
        )
        let now = evaluator.instant(ServiceDate("2026-03-13")!, GTFSTimeOfDay("08:00:00")!)

        // 2026-03-13 through 03-16 all evaluate unknown: the notice
        // calendar's count-back walks past its own startDate before
        // consuming a day.
        #expect(evaluator.evaluate(rule: rule, bookingRule: bookingRule, travelDate: ServiceDate("2026-03-16")!, now: now).state == .unknown)

        // 03-17's count-back lands on 03-16 (the notice calendar's first
        // active day); its 00:00 cutoff is still ahead of `now`, so the walk
        // must not have stopped at the earlier unknown candidates.
        #expect(evaluator.nextBookableServiceDate(rule: rule, bookingRule: bookingRule, now: now) == ServiceDate("2026-03-17")!)
    }
}
