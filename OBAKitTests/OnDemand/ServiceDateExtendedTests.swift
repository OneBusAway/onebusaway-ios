//
//  ServiceDateExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `ServiceDate` and `Weekday` calendar parsing, chronological ordering,
/// out-of-range recovery, and JSON decoding.
@Suite(.serialized)
struct ServiceDateExtendedTests {

    // MARK: - ServiceDate String Parsing

    @Test func `ServiceDate parses compliant YYYY-MM-DD strings`() {
        let date = ServiceDate("2026-11-10")
        #expect(date != nil)
        #expect(date?.year == 2026)
        #expect(date?.month == 11)
        #expect(date?.day == 10)
        #expect(date?.description == "2026-11-10")
    }

    @Test func `ServiceDate rejects invalid or malformed strings`() {
        #expect(ServiceDate("") == nil)
        #expect(ServiceDate("2026-1-10") == nil) // Month must be 2 digits
        #expect(ServiceDate("2026-11-1") == nil)  // Day must be 2 digits
        #expect(ServiceDate("26-11-10") == nil)   // Year must be 4 digits
        #expect(ServiceDate("2026/11/10") == nil) // Slashes instead of dashes
        #expect(ServiceDate("2026-13-10") == nil) // Month 13 out of bounds
        #expect(ServiceDate("2026-00-10") == nil) // Month 0 out of bounds
        #expect(ServiceDate("2026-11-32") == nil) // Day 32 out of bounds
        #expect(ServiceDate("2026-11-00") == nil) // Day 0 out of bounds
    }

    // MARK: - Comparable and Hashable

    @Test func `ServiceDate sorts chronologically across years, months, and days`() {
        let d1 = ServiceDate("2025-12-31")!
        let d2 = ServiceDate("2026-01-01")!
        let d3 = ServiceDate("2026-05-15")!
        let d4 = ServiceDate("2026-05-20")!
        let d5 = ServiceDate("2027-01-01")!

        let unsorted = [d4, d1, d5, d2, d3]
        #expect(unsorted.sorted() == [d1, d2, d3, d4, d5])
        #expect(d1 < d2)
        #expect(d3 < d4)
        #expect(d4 < d5)
    }

    @Test func `ServiceDate equality and hash consistency`() {
        let d1 = ServiceDate("2026-06-15")!
        let d2 = ServiceDate(year: 2026, month: 6, day: 15)
        let dDiff = ServiceDate("2026-06-16")!

        #expect(d1 == d2)
        #expect(d1.hashValue == d2.hashValue)
        #expect(d1 != dDiff)
    }

    // MARK: - JSON Decoding

    @Test func `ServiceDate decodes from string JSON value`() throws {
        let json = Data("\"2026-09-13\"".utf8)
        let decoded = try JSONDecoder().decode(ServiceDate.self, from: json)

        #expect(decoded.year == 2026)
        #expect(decoded.month == 9)
        #expect(decoded.day == 13)
    }

    @Test func `ServiceDate decoding throws for invalid date strings`() {
        let json = Data("\"invalid-date\"".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ServiceDate.self, from: json)
        }
    }

    // MARK: - Weekday Mapping

    @Test func `Weekday maps standard Calendar component values`() {
        // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        #expect(Weekday(calendarWeekday: 1) == .sun)
        #expect(Weekday(calendarWeekday: 2) == .mon)
        #expect(Weekday(calendarWeekday: 3) == .tue)
        #expect(Weekday(calendarWeekday: 4) == .wed)
        #expect(Weekday(calendarWeekday: 5) == .thu)
        #expect(Weekday(calendarWeekday: 6) == .fri)
        #expect(Weekday(calendarWeekday: 7) == .sat)

        #expect(Weekday.sun.calendarWeekday == 1)
        #expect(Weekday.mon.calendarWeekday == 2)
        #expect(Weekday.sat.calendarWeekday == 7)
    }

    @Test func `Weekday defaults to saturday for out of bounds integers`() {
        #expect(Weekday(calendarWeekday: 0) == .sat)
        #expect(Weekday(calendarWeekday: 8) == .sat)
        #expect(Weekday(calendarWeekday: -5) == .sat)
        #expect(Weekday(calendarWeekday: 100) == .sat)
    }
}
