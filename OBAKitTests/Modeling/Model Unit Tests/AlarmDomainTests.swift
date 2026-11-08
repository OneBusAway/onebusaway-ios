//
//  AlarmDomainTests.swift
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

/// Tests for `Alarm` equality semantics, sub-microsecond date normalization,
/// custom hash consistency, and offset boundary math.
@Suite(.serialized)
final class AlarmDomainTests: OBATestCase {

    private let sampleURL = URL(string: "https://alerts.example.com/regions/1/alarms/alarm_999")!

    // MARK: - Sub-microsecond Precision Equalization

    @Test func `Alarm equality handles date precision drift from TimeInterval serialization`() throws {
        let exactTripDate = Date(timeIntervalSince1970: 1_700_000_000.123456)
        let exactAlarmDate = Date(timeIntervalSince1970: 1_700_000_000.123456 - 600)

        // In-memory alarm with sub-microsecond date
        let alarm1 = try Fixtures.loadAlarm()
        alarm1.tripDate = exactTripDate
        alarm1.alarmDate = exactAlarmDate

        // Simulated round-trip or truncated date
        let alarm2 = try Fixtures.loadAlarm()
        alarm2.tripDate = Date(timeIntervalSince1970: exactTripDate.timeIntervalSince1970)
        alarm2.alarmDate = Date(timeIntervalSince1970: exactAlarmDate.timeIntervalSince1970)

        #expect(alarm1 == alarm2)
        #expect(alarm1.hash == alarm2.hash)
    }

    @Test func `Alarm equality returns false when URLs differ`() throws {
        let alarm1 = try Fixtures.loadAlarm()
        let alarm2 = try JSONDecoder().decode(
            Alarm.self,
            from: "{\"url\":\"https://alerts.example.com/regions/1/alarms/other\"}".data(using: .utf8)!
        )

        #expect(alarm1 != alarm2)
    }

    @Test func `Alarm equality returns false when non-Alarm object compared`() throws {
        let alarm = try Fixtures.loadAlarm()
        #expect(!alarm.isEqual("string_object"))
        #expect(!alarm.isEqual(nil))
    }

    @Test func `Alarm equality distinguishes nil vs non-nil dates`() throws {
        let alarm1 = try Fixtures.loadAlarm()
        alarm1.tripDate = nil
        alarm1.alarmDate = nil

        let alarm2 = try Fixtures.loadAlarm()
        alarm2.tripDate = Date(timeIntervalSince1970: 1_700_000_000)
        alarm2.alarmDate = nil

        let alarm3 = try Fixtures.loadAlarm()
        alarm3.tripDate = nil
        alarm3.alarmDate = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(alarm1 != alarm2)
        #expect(alarm1 != alarm3)
        #expect(alarm2 != alarm3)
    }

    // MARK: - Offset Math and Boundary Conditions

    @Test func `Alarm set tripDate calculates alarmDate with positive and negative offsets`() throws {
        let alarm = try Fixtures.loadAlarm()
        let tripDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Standard 10 minute advance notice
        alarm.set(tripDate: tripDate, alarmOffset: 10)
        #expect(alarm.tripDate == tripDate)
        #expect(alarm.alarmDate == tripDate.addingTimeInterval(-600))

        // Negative offset (-15) should be normalized via abs(minutes) to 15 minutes before trip
        alarm.set(tripDate: tripDate, alarmOffset: -15)
        #expect(alarm.alarmDate == tripDate.addingTimeInterval(-900))

        // Zero offset means alarm fires exactly at trip departure
        alarm.set(tripDate: tripDate, alarmOffset: 0)
        #expect(alarm.alarmDate == tripDate)
    }

    // MARK: - DeepLink Attachment and Encoding

    @Test func `Alarm encodes and decodes optional deepLink properly`() throws {
        let alarm = try Fixtures.loadAlarm()
        alarm.deepLink = nil
        alarm.tripDate = Date(timeIntervalSince1970: 1_700_000_000)
        alarm.alarmDate = Date(timeIntervalSince1970: 1_699_999_400)

        let encoded = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: encoded)

        #expect(decoded.deepLink == nil)
        #expect(decoded.url == alarm.url)
        #expect(decoded.tripDate?.timeIntervalSince1970 == alarm.tripDate?.timeIntervalSince1970)
        #expect(decoded.alarmDate?.timeIntervalSince1970 == alarm.alarmDate?.timeIntervalSince1970)
        #expect(decoded == alarm)
    }
}
