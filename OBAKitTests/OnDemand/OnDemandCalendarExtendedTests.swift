//
//  OnDemandCalendarExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `OnDemandCalendar` decoding, lossy date degradation, unknown weekday filtering,
/// and exception dates handling.
@Suite(.serialized)
struct OnDemandCalendarExtendedTests {

    // MARK: - Decoding

    @Test func `OnDemandCalendar decodes valid weekdays and service dates`() throws {
        let json = """
        {
            "id": "cal_weekdays_2026",
            "days": ["mon", "tue", "wed", "thu", "fri"],
            "startDate": "2026-01-01",
            "endDate": "2026-12-31",
            "exceptedDates": ["2026-07-04", "2026-11-26", "2026-12-25"]
        }
        """.data(using: .utf8)!

        let cal = try JSONDecoder().decode(OnDemandCalendar.self, from: json)

        #expect(cal.id == "cal_weekdays_2026")
        #expect(cal.days == [.mon, .tue, .wed, .thu, .fri])
        #expect(cal.startDate == ServiceDate("2026-01-01"))
        #expect(cal.endDate == ServiceDate("2026-12-31"))
        #expect(cal.exceptedDates.count == 3)
        #expect(cal.exceptedDates.contains(ServiceDate("2026-07-04")!))
    }

    @Test func `OnDemandCalendar drops invalid weekdays and invalid dates gracefully`() throws {
        // Unknown weekday ("holiday") and unparseable dates should be dropped/nilified without throwing
        let json = """
        {
            "id": "cal_lossy",
            "days": ["mon", "holiday", "fri"],
            "startDate": "not_a_date",
            "endDate": "2026-12-31",
            "exceptedDates": ["bad_date", "2026-01-01"]
        }
        """.data(using: .utf8)!

        let cal = try JSONDecoder().decode(OnDemandCalendar.self, from: json)

        #expect(cal.id == "cal_lossy")
        #expect(cal.days == [.mon, .fri]) // "holiday" dropped
        #expect(cal.startDate == nil) // "not_a_date" degraded to nil
        #expect(cal.endDate == ServiceDate("2026-12-31"))
        #expect(cal.exceptedDates == [ServiceDate("2026-01-01")!]) // "bad_date" dropped
    }

    @Test func `OnDemandCalendar defaults missing dates and exceptedDates`() throws {
        let json = """
        {
            "id": "cal_minimal",
            "days": ["sat", "sun"]
        }
        """.data(using: .utf8)!

        let cal = try JSONDecoder().decode(OnDemandCalendar.self, from: json)

        #expect(cal.id == "cal_minimal")
        #expect(cal.days == [.sat, .sun])
        #expect(cal.startDate == nil)
        #expect(cal.endDate == nil)
        #expect(cal.exceptedDates.isEmpty)
    }

    // MARK: - Hashable and Member Collections

    @Test func `OnDemandCalendar equality and Hashable conformance`() throws {
        let c1 = OnDemandCalendar(id: "c1", days: [.mon], startDate: nil, endDate: nil, exceptedDates: [])
        let c2 = OnDemandCalendar(id: "c1", days: [.mon], startDate: nil, endDate: nil, exceptedDates: [])
        let c3 = OnDemandCalendar(id: "c2", days: [.mon], startDate: nil, endDate: nil, exceptedDates: [])

        #expect(c1 == c2)
        #expect(c1.hashValue == c2.hashValue)
        #expect(c1 != c3)

        let set: Set<OnDemandCalendar> = [c1, c2, c3]
        #expect(set.count == 2)
    }
}
