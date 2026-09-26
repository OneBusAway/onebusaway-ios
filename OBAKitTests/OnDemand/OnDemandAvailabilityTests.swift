//
//  OnDemandAvailabilityTests.swift
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

/// Spec 2.5 and 2.6 against the Charlevoix (America/Detroit, same-day) and
/// Alexandria (America/Los_Angeles, advance) fixtures. March 2026: DST began
/// on Sunday the 8th in both zones, so Detroit is UTC−4 and LA is UTC−7.
@MainActor
@Suite(.serialized)
final class OnDemandAvailabilityTests: OBATestCase {

    private let detroit = TimeZone(identifier: "America/Detroit")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Charlevoix `id` with the whole response JSON rewritten by `transform`.
    private func charlevoix(_ id: String, rewriting transform: ((inout [String: Any]) -> Void)? = nil) throws -> OnDemandService {
        let data = Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        transform?(&json)
        let list = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: JSONSerialization.data(withJSONObject: json)).list
        return try #require(list.first { $0.id == id })
    }

    /// Alexandria with the whole response JSON rewritten by `transform`.
    private func alexandria(rewriting transform: ((inout [String: Any]) -> Void)? = nil) throws -> OnDemandService {
        let data = Fixtures.loadData(file: "ondemand_service_alexandria.json")
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        transform?(&json)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: JSONSerialization.data(withJSONObject: json)).entry
    }

    /// Rewrites every element of `data.references[key]`.
    private func rewriteReferences(_ json: inout [String: Any], _ key: String, _ transform: (inout [String: Any]) -> Void) {
        var body = json["data"] as! [String: Any]
        var references = body["references"] as! [String: Any]
        references[key] = (references[key] as! [[String: Any]]).map { element in
            var element = element
            transform(&element)
            return element
        }
        body["references"] = references
        json["data"] = body
    }

    /// Rewrites every rule of every service in the response (`entry` or `list`).
    private func rewriteRules(_ json: inout [String: Any], _ transform: (inout [String: Any]) -> Void) {
        var body = json["data"] as! [String: Any]
        func rewritten(_ service: [String: Any]) -> [String: Any] {
            var service = service
            service["rules"] = (service["rules"] as! [[String: Any]]).map { rule in
                var rule = rule
                transform(&rule)
                return rule
            }
            return service
        }
        if let entry = body["entry"] as? [String: Any] {
            body["entry"] = rewritten(entry)
        }
        if let list = body["list"] as? [[String: Any]] {
            body["list"] = list.map(rewritten)
        }
        json["data"] = body
    }

    private func availability(_ service: OnDemandService, at now: Date) -> OnDemandAvailability {
        OnDemandAvailability.evaluate(service: service, timeZone: service.timeZone, now: now)
    }

    // MARK: - Running now

    /// Tuesday 2026-03-10 12:00 EDT: CC1 (07:20–16:40, same-day, 90 min notice) is open.
    @Test func `Running inside the window is open now until the window end`() throws {
        let result = availability(try charlevoix("CC_CC1"), at: instant("2026-03-10T16:00:00Z"))
        #expect(result.runningNow)
        #expect(result.runningUntil == instant("2026-03-10T20:40:00Z"))
        #expect(result.bookableNow)
        #expect(result.bookingTier == .sameDay)
        #expect(result.status == .openNow(until: instant("2026-03-10T20:40:00Z")))
        #expect(result.tags == [.sameDayBooking])
        #expect(result.usabilityTier == OnDemandAvailability.openNowTier)
    }

    /// 16:00 EDT: still running, but the 15:10 same-day cutoff has passed, so
    /// the service is not bookable now and reads as opening tomorrow: status
    /// step 3 takes the first window after the current one, while the
    /// `nextRunStart` field itself stays nil because the service is running.
    @Test func `Running past the cutoff is not bookable now and opens tomorrow`() throws {
        let result = availability(try charlevoix("CC_CC1"), at: instant("2026-03-10T20:00:00Z"))
        #expect(result.runningNow)
        #expect(!result.bookableNow)
        #expect(result.nextRunStart == nil)
        #expect(result.status == .opensAt(instant("2026-03-11T11:20:00Z")))
        #expect(result.nextBookableServiceDate == ServiceDate(year: 2026, month: 3, day: 11))
        #expect(result.usabilityTier == OnDemandAvailability.advanceTier)
        // Tomorrow's 90-minute cutoff is 15:10 EDT; the tier-3 bar title reads this line.
        #expect(result.bookingResolution == .bookBy(cutoff: instant("2026-03-11T19:10:00Z"), travelDate: ServiceDate(year: 2026, month: 3, day: 11)))
    }

    /// 03:00 EDT Tuesday: not running yet; today is still bookable, so tier 2.
    @Test func `Before the window opens today is same-day tier`() throws {
        let result = availability(try charlevoix("CC_CC1"), at: instant("2026-03-10T07:00:00Z"))
        #expect(!result.runningNow)
        #expect(result.runningUntil == nil)
        #expect(result.nextRunStart == instant("2026-03-10T11:20:00Z"))
        #expect(result.status == .opensAt(instant("2026-03-10T11:20:00Z")))
        #expect(result.usabilityTier == OnDemandAvailability.sameDayTier)
    }

    /// Sunday 12:00 EDT: CC1 has no Sunday calendar; next run is Monday 07:20.
    @Test func `On a day without service the next run start is the next active day`() throws {
        let result = availability(try charlevoix("CC_CC1"), at: instant("2026-03-15T16:00:00Z"))
        #expect(!result.runningNow)
        #expect(result.nextRunStart == instant("2026-03-16T11:20:00Z"))
        #expect(result.status == .opensAt(instant("2026-03-16T11:20:00Z")))
        #expect(result.usabilityTier == OnDemandAvailability.advanceTier)
    }

    /// Alexandria Mon–Sat 05:00–24:50: at Sunday 00:30 LA the Saturday window
    /// still contains now, found through `today − 1`. The advance rule's
    /// cutoff for Saturday passed on Friday, so the status is the book-by line.
    @Test func `A window crossing 24 hours is found from the previous service day`() throws {
        let result = availability(try alexandria(), at: instant("2026-03-15T07:30:00Z"))
        #expect(result.runningNow)
        #expect(result.runningUntil == instant("2026-03-15T07:50:00Z"))
        #expect(!result.bookableNow)
        #expect(result.bookingTier == .advance)
        guard case .bookBy(let deadline, let travelDate) = result.status else {
            Issue.record("expected bookBy, got \(result.status)")
            return
        }
        #expect(travelDate == ServiceDate(year: 2026, month: 3, day: 16))
        #expect(deadline == instant("2026-03-16T00:00:00Z"), "Sunday 17:00 LA for a Monday ride")
    }

    /// The same Saturday window with a type-1 rule: `bookableNow` is evaluated
    /// for the service date whose window contains now (Saturday), not today.
    @Test func `bookableNow evaluates the previous service day for a window past midnight`() throws {
        func alexandriaSameDay(minimumMinutes: Int) throws -> OnDemandService {
            try alexandria { json in
                self.rewriteReferences(&json, "bookingRules") { rule in
                    rule["bookingType"] = 1
                    rule["priorNoticeDurationMin"] = minimumMinutes
                    rule["priorNoticeLastDay"] = nil
                    rule["priorNoticeLastTime"] = nil
                    rule["priorNoticeStartDay"] = nil
                    rule["priorNoticeStartTime"] = nil
                }
            }
        }
        let now = instant("2026-03-15T07:30:00Z") // Sunday 00:30 LA

        let closed = availability(try alexandriaSameDay(minimumMinutes: 30), at: now)
        #expect(closed.runningNow)
        #expect(!closed.bookableNow, "Saturday's cutoff was 00:20")

        let open = availability(try alexandriaSameDay(minimumMinutes: 5), at: now)
        #expect(open.bookableNow, "Saturday's cutoff is 00:45")
        #expect(open.status == .openNow(until: instant("2026-03-15T07:50:00Z")))
        #expect(open.usabilityTier == OnDemandAvailability.openNowTier)
    }

    /// All-null pickup times run the whole service day; consecutive active
    /// days abut, so `runningUntil` is nil and the copy reads "Open".
    @Test func `All-day service on consecutive days has no running-until instant`() throws {
        let service = try alexandria { json in
            self.rewriteRules(&json) { rule in
                rule["startPickupTime"] = nil
                rule["endPickupTime"] = nil
            }
            self.rewriteReferences(&json, "bookingRules") { rule in rule["bookingType"] = 0 }
        }
        let result = availability(service, at: instant("2026-03-10T10:00:00Z")) // Tuesday 03:00 LA
        #expect(result.runningNow)
        #expect(result.runningUntil == nil)
        #expect(result.bookingTier == .realTime)
        #expect(result.status == .openNow(until: nil))
        #expect(result.tags == [.noNoticeNeeded])
    }

    @Test func `All-day service before an inactive day keeps its running-until instant`() throws {
        let service = try alexandria { json in
            self.rewriteRules(&json) { rule in
                rule["startPickupTime"] = nil
                rule["endPickupTime"] = nil
            }
            self.rewriteReferences(&json, "bookingRules") { rule in rule["bookingType"] = 0 }
            self.rewriteReferences(&json, "calendars") { calendar in
                if calendar["id"] as? String == "5088_c_71675_b_85952_d_64" { calendar["days"] = [] }
            }
        }
        let result = availability(service, at: instant("2026-03-14T10:00:00Z")) // Saturday 03:00 LA
        #expect(result.runningNow)
        #expect(result.runningUntil == instant("2026-03-15T07:00:00Z"), "Sunday 00:00 LA; Sunday is no longer active")
    }

    /// A 24/7 service must stay continuous across a DST transition: the
    /// wall-clock day is 23h or 25h long that week, but an all-day window's
    /// true midnight-to-midnight boundaries still abut exactly (ruling:
    /// spec §2.5 — windows must use calendar `startOfDay`, not the fixed
    /// `anchor + 24h` offset).
    @Test func `All-day service stays continuous across a DST transition`() throws {
        let service = try alexandria { json in
            self.rewriteRules(&json) { rule in
                rule["startPickupTime"] = nil
                rule["endPickupTime"] = nil
            }
            self.rewriteReferences(&json, "bookingRules") { rule in rule["bookingType"] = 0 }
        }
        // Spring forward is 2026-03-08; noon LA on the day before is still PST.
        let springForward = availability(service, at: instant("2026-03-07T20:00:00Z"))
        #expect(springForward.runningNow)
        #expect(springForward.runningUntil == nil)

        // Fall back is 2026-11-01; noon LA on the day before is still PDT.
        let fallBack = availability(service, at: instant("2026-10-31T19:00:00Z"))
        #expect(fallBack.runningNow)
        #expect(fallBack.runningUntil == nil)
    }

    @Test func `An excepted date removes today from service`() throws {
        let service = try charlevoix("CC_CC1") { json in
            self.rewriteReferences(&json, "calendars") { calendar in
                if calendar["id"] as? String == "CC_mon-tues-wed-thurs-fri" { calendar["exceptedDates"] = ["2026-03-10"] }
            }
        }
        let result = availability(service, at: instant("2026-03-10T16:00:00Z"))
        #expect(!result.runningNow)
        #expect(result.nextRunStart == instant("2026-03-11T11:20:00Z"))
    }

    @Test func `An added calendar makes a Sunday active`() throws {
        let service = try charlevoix("CC_CC1") { json in
            var body = json["data"] as! [String: Any]
            var references = body["references"] as! [String: Any]
            var calendars = references["calendars"] as! [[String: Any]]
            calendars.append(["id": "CC_sat_added_20260315", "days": ["sun"], "startDate": "2026-03-15", "endDate": "2026-03-15", "exceptedDates": []])
            references["calendars"] = calendars
            body["references"] = references
            json["data"] = body
            self.rewriteRules(&json) { rule in
                if (rule["pickupBookingRuleId"] as? String) == "CC_booking_rule_CC1" {
                    rule["calendarIds"] = ["CC_mon-tues-wed-thurs-fri", "CC_sat", "CC_sat_added_20260315"]
                }
            }
        }
        let result = availability(service, at: instant("2026-03-15T16:00:00Z"))
        #expect(result.runningNow)
    }

    @Test func `After the last window of the day the next run start is tomorrow`() throws {
        let result = availability(try charlevoix("CC_CC1"), at: instant("2026-03-10T21:00:00Z")) // 17:00 EDT
        #expect(!result.runningNow)
        #expect(result.nextRunStart == instant("2026-03-11T11:20:00Z"))
    }

    // MARK: - Booking tier and status

    @Test func `Booking tier follows the pickup booking rule type`() throws {
        let now = instant("2026-03-10T16:00:00Z")
        #expect(availability(try charlevoix("CC_CC3"), at: now).bookingTier == .realTime)
        #expect(availability(try charlevoix("CC_CC1"), at: now).bookingTier == .sameDay)
        #expect(availability(try alexandria(), at: now).bookingTier == .advance)
        #expect(availability(try charlevoix("CC_CC3"), at: now).tags == [.noNoticeNeeded])
        #expect(availability(try alexandria(), at: now).tags == [.advanceBooking])
    }

    /// Two rules active on the same day, one real-time and one advance: the
    /// least demanding wins.
    @Test func `Mixed booking types resolve to the least demanding`() throws {
        let service = try alexandria { json in
            var body = json["data"] as! [String: Any]
            var references = body["references"] as! [String: Any]
            var rules = references["bookingRules"] as! [[String: Any]]
            var realTime = rules[0]
            realTime["id"] = "5088_booking_realtime"
            realTime["bookingType"] = 0
            rules.append(realTime)
            references["bookingRules"] = rules
            body["references"] = references
            var entry = body["entry"] as! [String: Any]
            var entryRules = entry["rules"] as! [[String: Any]]
            var extra = entryRules[0]
            extra["pickupBookingRuleId"] = "5088_booking_realtime"
            entryRules.append(extra)
            entry["rules"] = entryRules
            body["entry"] = entry
            json["data"] = body
        }
        let result = availability(service, at: instant("2026-03-10T16:00:00Z"))
        #expect(result.bookingTier == .realTime)
        #expect(result.tags == [.noNoticeNeeded])
    }

    /// A second rule picks up exactly where CC1's window ends: running past
    /// CC1's cutoff must find that adjacent same-day window, not skip past it
    /// to tomorrow (ruling: the past-cutoff search must include a window
    /// starting exactly at the boundary).
    @Test func `Running past cutoff finds an adjacent same-day window, not tomorrow`() throws {
        let service = try charlevoix("CC_CC1") { json in
            var body = json["data"] as! [String: Any]
            body["list"] = (body["list"] as! [[String: Any]]).map { service in
                guard service["id"] as? String == "CC_CC1" else { return service }
                var service = service
                var rules = service["rules"] as! [[String: Any]]
                var second = rules[0]
                second["startPickupTime"] = "16:40:00"
                second["endPickupTime"] = "21:40:00"
                second["pickupBookingRuleId"] = "CC_booking_rule_CC3"
                second["dropOffBookingRuleId"] = "CC_booking_rule_CC3"
                rules.append(second)
                service["rules"] = rules
                return service
            }
            json["data"] = body
        }
        // 15:30 EDT: past CC1's 15:10 cutoff, before its 16:40 window end.
        let result = availability(service, at: instant("2026-03-10T19:30:00Z"))
        #expect(result.runningNow)
        #expect(!result.bookableNow)
        #expect(result.status == .opensAt(instant("2026-03-10T20:40:00Z")))
    }

    /// Advance booking that has not opened yet is `.bookingOpens`, not
    /// `.opensAt`: the booking window opens then, the service does not.
    @Test func `Advance booking not yet open is bookingOpens`() throws {
        let service = try alexandria { json in
            self.rewriteReferences(&json, "bookingRules") { rule in
                rule["priorNoticeStartDay"] = 1
                rule["priorNoticeStartTime"] = "00:00:00"
            }
        }
        // Sunday 2026-03-08 20:00 LA: Monday's cutoff (Sunday 17:00) passed,
        // Tuesday's booking opens Monday 00:00.
        let result = availability(service, at: instant("2026-03-09T03:00:00Z"))
        #expect(result.status == .bookingOpens(instant("2026-03-09T07:00:00Z")))
    }

    @Test func `Advance status is chosen even while the service is running`() throws {
        let result = availability(try alexandria(), at: instant("2026-03-10T23:00:00Z")) // Tuesday 16:00 LA, running
        #expect(result.runningNow)
        guard case .bookBy = result.status else {
            Issue.record("expected bookBy, got \(result.status)")
            return
        }
    }

    @Test func `Service-level next bookable date is the minimum over rules`() throws {
        // Tuesday 16:00 LA: the Mon–Sat rule books Wednesday; the Sunday rule books Sunday.
        let result = availability(try alexandria(), at: instant("2026-03-10T23:00:00Z"))
        #expect(result.nextBookableServiceDate == ServiceDate(year: 2026, month: 3, day: 11))
    }

    @Test func `Missing timezone yields unknown everything and tier five`() throws {
        let service = try alexandria { json in
            self.rewriteReferences(&json, "agencies") { agency in agency["timezone"] = "Nowhere/Unknown" }
        }
        #expect(service.timeZone == nil)
        let result = availability(service, at: instant("2026-03-10T16:00:00Z"))
        #expect(result == .unknown)
        #expect(result.usabilityTier == OnDemandAvailability.unknownTier)
        #expect(result.tags.isEmpty)
    }

    /// Review Focus 1: calendars the references do not carry.
    @Test func `Unknown calendars yield an unknown status, not closed`() throws {
        let service = try charlevoix("CC_CC1") { json in
            self.rewriteRules(&json) { rule in rule["calendarIds"] = ["CC_missing"] }
        }
        let result = availability(service, at: instant("2026-03-10T16:00:00Z"))
        #expect(!result.runningNow)
        #expect(result.nextRunStart == nil)
        #expect(result.status == .unknown)
        #expect(result.usabilityTier == OnDemandAvailability.unknownTier)
    }

    @Test func `A service with no rules is unknown`() throws {
        let service = try alexandria { json in
            var body = json["data"] as! [String: Any]
            var entry = body["entry"] as! [String: Any]
            entry["rules"] = []
            body["entry"] = entry
            json["data"] = body
        }
        #expect(availability(service, at: instant("2026-03-10T16:00:00Z")).status == .unknown)
    }

    @Test func `Calendars that ended make the service closed`() throws {
        let service = try charlevoix("CC_CC1") { json in
            self.rewriteReferences(&json, "calendars") { calendar in calendar["endDate"] = "2026-03-01" }
        }
        let result = availability(service, at: instant("2026-03-10T16:00:00Z"))
        #expect(result.status == .closed)
        #expect(result.usabilityTier == OnDemandAvailability.unknownTier)
    }

    @Test func `Certification requirement adds the eligibility tag and tier four`() throws {
        let service = try charlevoix("CC_CC1") { json in
            var body = json["data"] as! [String: Any]
            body["list"] = (body["list"] as! [[String: Any]]).map { service in
                var service = service
                service["eligibility"] = ["requirement": "certificationRequired", "infoUrl": nil]
                return service
            }
            json["data"] = body
        }
        let result = availability(service, at: instant("2026-03-10T16:00:00Z"))
        #expect(result.tags == [.sameDayBooking, .eligibilityRequired])
        #expect(result.usabilityTier == OnDemandAvailability.eligibilityTier)
    }

    // MARK: - Next change

    /// Running at 12:00 EDT: the window ends 16:40 but the 15:10 cutoff comes first.
    @Test func `Next change instant is the earliest boundary`() throws {
        let result = availability(try charlevoix("CC_CC1"), at: instant("2026-03-10T16:00:00Z"))
        #expect(result.nextChangeInstant == instant("2026-03-10T19:10:00Z"))
    }

    /// 23:00 EDT: CC1 isn't running and nothing else changes before local
    /// midnight, so the next change is the agency-zone midnight rollover
    /// itself — `usabilityTier` depends on `today` (ruling: spec §2.5).
    @Test func `Next change instant includes the agency midnight rollover`() throws {
        let result = availability(try charlevoix("CC_CC1"), at: instant("2026-03-11T03:00:00Z"))
        #expect(result.nextChangeInstant == instant("2026-03-11T04:00:00Z"))
    }

    /// A continuous real-time service has no cutoff, opening or running-until
    /// boundary, but the midnight rollover still gives it a non-nil next
    /// change instant.
    @Test func `All-day real-time service still reports a next change instant`() throws {
        let service = try alexandria { json in
            self.rewriteRules(&json) { rule in
                rule["startPickupTime"] = nil
                rule["endPickupTime"] = nil
            }
            self.rewriteReferences(&json, "bookingRules") { rule in rule["bookingType"] = 0 }
        }
        let result = availability(service, at: instant("2026-03-10T10:00:00Z")) // Tuesday 03:00 LA
        #expect(result.nextChangeInstant != nil)
    }

    // MARK: - Resolution and relative formatting

    @Test func `Booking resolution carries the cutoff instant and travel date`() throws {
        let service = try alexandria()
        let evaluator = BookingDeadlineEvaluator(timeZone: losAngeles, calendars: service.calendars)
        let outcome = OnDemandBookingResolution.resolve(service: service, evaluator: evaluator, now: instant("2026-03-10T23:00:00Z"))
        #expect(outcome.resolution == .bookBy(cutoff: instant("2026-03-11T00:00:00Z"), travelDate: ServiceDate(year: 2026, month: 3, day: 11)))
        #expect(outcome.nextChangeInstant == instant("2026-03-11T00:00:00Z"))
    }

    @Test func `Relative date time reads tomorrow for the next day`() {
        let text = OnDemandServiceSummary.formattedRelativeDateTime(
            instant("2026-03-11T11:20:00Z"),
            now: instant("2026-03-10T16:00:00Z"),
            timeZone: detroit,
            locale: Locale(identifier: "en_US")
        )
        #expect(text.localizedCaseInsensitiveContains("tomorrow"), Comment(rawValue: text))
        #expect(text.contains("7:20"), Comment(rawValue: text))
    }
}
