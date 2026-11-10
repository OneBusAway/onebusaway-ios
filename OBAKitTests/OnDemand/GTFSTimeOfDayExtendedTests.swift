//
//  GTFSTimeOfDayExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `GTFSTimeOfDay` string parsing, hour overflow (> 24h), comparison,
/// JSON decoding, and custom formatting.
@Suite(.serialized)
struct GTFSTimeOfDayExtendedTests {

    // MARK: - Standard and Overflow String Parsing

    @Test func `init parses standard HH MM SS strings`() {
        let t0 = GTFSTimeOfDay("00:00:00")
        #expect(t0?.seconds == 0)

        let t1 = GTFSTimeOfDay("08:30:15")
        #expect(t1?.seconds == (8 * 3600 + 30 * 60 + 15))

        let tMid = GTFSTimeOfDay("12:00:00")
        #expect(tMid?.seconds == 12 * 3600)

        let t23 = GTFSTimeOfDay("23:59:59")
        #expect(t23?.seconds == (24 * 3600 - 1))
    }

    @Test func `init parses single-digit hour H MM SS`() {
        let t1 = GTFSTimeOfDay("4:05:06")
        #expect(t1?.seconds == (4 * 3600 + 5 * 60 + 6))
        #expect(t1?.description == "04:05:06")
    }

    @Test func `init parses service-day overflow past 24 hours`() {
        // GTFS allows service days past midnight (e.g. 24:50:00, 27:30:00)
        let t24 = GTFSTimeOfDay("24:00:00")
        #expect(t24?.seconds == 24 * 3600)
        #expect(t24 == GTFSTimeOfDay.endOfServiceDay)

        let t25 = GTFSTimeOfDay("25:30:00")
        #expect(t25?.seconds == (25 * 3600 + 30 * 60))
        #expect(t25?.description == "25:30:00")
    }

    // MARK: - Rejection of Malformed Strings

    @Test func `init returns nil for invalid minute or second numbers`() {
        #expect(GTFSTimeOfDay("12:60:00") == nil) // 60 minutes
        #expect(GTFSTimeOfDay("12:00:60") == nil) // 60 seconds
        #expect(GTFSTimeOfDay("12:-05:00") == nil)
        #expect(GTFSTimeOfDay("-1:00:00") == nil) // Negative hour
    }

    @Test func `init returns nil for malformed string components`() {
        #expect(GTFSTimeOfDay("") == nil)
        #expect(GTFSTimeOfDay("12:00") == nil) // Only 2 parts
        #expect(GTFSTimeOfDay("12:00:00:00") == nil) // 4 parts
        #expect(GTFSTimeOfDay("ab:cd:ef") == nil)
        #expect(GTFSTimeOfDay("12:00:0a") == nil)
        #expect(GTFSTimeOfDay("::") == nil)
    }

    // MARK: - Comparable and Hashable

    @Test func `GTFSTimeOfDay orders chronologically`() {
        let morning = GTFSTimeOfDay("07:00:00")!
        let noon = GTFSTimeOfDay("12:00:00")!
        let evening = GTFSTimeOfDay("19:45:00")!
        let nextDay = GTFSTimeOfDay("25:00:00")!

        let sorted = [nextDay, evening, morning, noon].sorted()
        #expect(sorted == [morning, noon, evening, nextDay])
        #expect(morning < noon)
        #expect(noon < evening)
        #expect(evening < nextDay)
    }

    @Test func `GTFSTimeOfDay hash and set membership behavior`() {
        let t1 = GTFSTimeOfDay("08:00:00")!
        let t2 = GTFSTimeOfDay("08:00:00")!
        let t3 = GTFSTimeOfDay("09:00:00")!

        #expect(t1 == t2)
        #expect(t1.hashValue == t2.hashValue)

        let set: Set<GTFSTimeOfDay> = [t1, t2, t3]
        #expect(set.count == 2)
        #expect(set.contains(t1))
        #expect(set.contains(t3))
    }

    // MARK: - Decodable

    @Test func `GTFSTimeOfDay decodes from JSON string value`() throws {
        let json = Data("\"14:30:45\"".utf8)
        let decoded = try JSONDecoder().decode(GTFSTimeOfDay.self, from: json)
        #expect(decoded.seconds == (14 * 3600 + 30 * 60 + 45))
    }

    @Test func `GTFSTimeOfDay decoding throws when string is invalid`() {
        let json = Data("\"invalid_time\"".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GTFSTimeOfDay.self, from: json)
        }
    }
}
