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

    @Test func `Book-by line uses the next bookable date and its cutoff`() throws {
        let summary = summary(try alexandria())
        guard case .bookBy(let deadline, let travelDate) = summary.bookingLine else {
            Issue.record("expected bookBy, got \(summary.bookingLine)")
            return
        }
        // Cutoff = 2026-03-10 17:00 LA for a ride on Wed 2026-03-11.
        #expect(deadline.contains("5:00"), "\(deadline)")
        #expect(deadline.localizedCaseInsensitiveContains("today"), "\(deadline)")
        #expect(travelDate.contains("Mar 11"), "\(travelDate)")
        #expect(travelDate.contains("Wed"), "\(travelDate)")
    }

    @Test func `Contact details come from the pickup booking rule`() throws {
        let summary = summary(try alexandria())
        #expect(summary.phoneNumber == "703-746-5222")
        #expect(summary.phoneURL == URL(string: "tel://7037465222"))
        #expect(summary.infoURL == URL(string: "https://www.alexandriava.gov/Paratransit"))
        #expect(summary.bookingURL?.host() == "spare-rider-alexandriadot-production.vercel.app")
        #expect(summary.message?.hasPrefix("DOT is the City of Alexandria") == true)
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
        #expect(deadline.localizedCaseInsensitiveContains("today"), "\(deadline)")
    }

    @Test func `Day runs render as ranges and lists`() {
        let symbols = DateFormatter().shortWeekdaySymbols!  // en_US in the GMT-pinned test process
        #expect(OnDemandServiceSummary.daysText([.mon, .tue, .wed, .thu, .fri, .sat], shortWeekdaySymbols: symbols) == "Mon–Sat")
        #expect(OnDemandServiceSummary.daysText([.mon, .wed, .fri], shortWeekdaySymbols: symbols) == "Mon, Wed, Fri")
        #expect(OnDemandServiceSummary.daysText([.sat, .sun], shortWeekdaySymbols: symbols) == "Sat–Sun")
        #expect(OnDemandServiceSummary.daysText([.mon, .tue, .thu, .fri, .sat, .sun], shortWeekdaySymbols: symbols) == "Mon–Tue, Thu–Sun")
        #expect(OnDemandServiceSummary.daysText([], shortWeekdaySymbols: symbols) == "")
    }
}
