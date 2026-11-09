//
//  OnDemandBookingRuleExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `OnDemandBookingRule` JSON decoding, notice durations,
/// booking cutoff times, phone numbers, and URLs.
@Suite(.serialized)
struct OnDemandBookingRuleExtendedTests {

    // MARK: - Decoding Real-Time Rule

    @Test func `OnDemandBookingRule decodes real-time bookingType 0 rule`() throws {
        let json = """
        {
            "id": "rule_realtime",
            "bookingType": 0,
            "message": "Instant dispatch available",
            "phoneNumber": "206-555-0100",
            "bookingUrl": "https://booking.example.com"
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(OnDemandBookingRule.self, from: json)

        #expect(rule.id == "rule_realtime")
        #expect(rule.bookingType == 0)
        #expect(rule.message == "Instant dispatch available")
        #expect(rule.phoneNumber == "206-555-0100")
        #expect(rule.bookingURL == URL(string: "https://booking.example.com"))
        #expect(rule.priorNoticeDurationMin == nil)
    }

    // MARK: - Decoding Same-Day Rule

    @Test func `OnDemandBookingRule decodes same-day bookingType 1 rule`() throws {
        let json = """
        {
            "id": "rule_sameday",
            "bookingType": 1,
            "priorNoticeDurationMin": 30,
            "priorNoticeDurationMax": 120,
            "infoUrl": "https://info.example.com/sameday"
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(OnDemandBookingRule.self, from: json)

        #expect(rule.id == "rule_sameday")
        #expect(rule.bookingType == 1)
        #expect(rule.priorNoticeDurationMin == 30)
        #expect(rule.priorNoticeDurationMax == 120)
        #expect(rule.infoURL == URL(string: "https://info.example.com/sameday"))
    }

    // MARK: - Decoding Prior-Day Rule

    @Test func `OnDemandBookingRule decodes prior-day bookingType 2 rule`() throws {
        let json = """
        {
            "id": "rule_priorday",
            "bookingType": 2,
            "priorNoticeLastDay": 1,
            "priorNoticeLastTime": "17:00:00",
            "priorNoticeStartDay": 7,
            "priorNoticeStartTime": "08:00:00",
            "priorNoticeCalendarId": "cal_business_days"
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(OnDemandBookingRule.self, from: json)

        #expect(rule.id == "rule_priorday")
        #expect(rule.bookingType == 2)
        #expect(rule.priorNoticeLastDay == 1)
        #expect(rule.priorNoticeLastTime == GTFSTimeOfDay("17:00:00"))
        #expect(rule.priorNoticeStartDay == 7)
        #expect(rule.priorNoticeStartTime == GTFSTimeOfDay("08:00:00"))
        #expect(rule.priorNoticeCalendarID == "cal_business_days")
    }

    // MARK: - Blank String Filtering

    @Test func `OnDemandBookingRule nilifies empty and whitespace strings`() throws {
        let json = """
        {
            "id": "rule_blanks",
            "bookingType": 0,
            "message": "   ",
            "pickupMessage": "",
            "dropOffMessage": "  \t  ",
            "phoneNumber": " ",
            "infoUrl": "",
            "bookingUrl": "   "
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(OnDemandBookingRule.self, from: json)

        #expect(rule.message == nil)
        #expect(rule.pickupMessage == nil)
        #expect(rule.dropOffMessage == nil)
        #expect(rule.phoneNumber == nil)
        #expect(rule.infoURL == nil)
        #expect(rule.bookingURL == nil)
    }
}
