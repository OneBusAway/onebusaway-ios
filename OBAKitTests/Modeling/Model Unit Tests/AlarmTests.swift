//
//  AlarmTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 1/30/20.
//

import Foundation
import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class AlarmTests: OBATestCase {

    func test_init_baseCase_success() {
        let alarm = try! loadAlarm()
        expect(alarm.url.absoluteString) == "http://alerts.example.com/regions/1/alarms/1234567890"
    }

    func test_appendingData() {
        let alarm = try! loadAlarm()
        let interval: TimeInterval = 1580428800
        let serviceDate = Date(timeIntervalSince1970: interval) // January 31, 2020, 12:00 AM GMT
        let tripDate = Date(timeIntervalSince1970: interval + 18000) // + 5 hours.
        let alarmOffset = 10 // - 10 minutes
        let alarmDate = tripDate.addingTimeInterval(-60.0 * TimeInterval(alarmOffset))

        expect(tripDate).toNot(beNil())
        expect(alarmDate).toNot(beNil())

        let deepLink = ArrivalDepartureDeepLink(title: "Title", regionID: 1, stopID: "1234", tripID: "9876", serviceDate: serviceDate, stopSequence: 7, vehicleID: "3456")

        alarm.deepLink = deepLink

        // abxoxo - todo! set the trip date and alarm offset and make sure it roundtrips!
        // then go into RecentStopsViewController and keep checking things off the list
        alarm.set(tripDate: tripDate, alarmOffset: alarmOffset)

        let roundtripped = try! roundtripCodable(type: Alarm.self, model: alarm)
        expect(roundtripped.url.absoluteString) == "http://alerts.example.com/regions/1/alarms/1234567890"
        expect(roundtripped.deepLink!.title) == "Title"
        expect(roundtripped.deepLink!.stopID) == "1234"
        expect(roundtripped.deepLink!.tripID) == "9876"
        expect(roundtripped.deepLink!.serviceDate.timeIntervalSince1970) == 1580428800
        expect(roundtripped.deepLink!.stopSequence) == 7
        expect(roundtripped.deepLink!.vehicleID) == "3456"
        expect(roundtripped.tripDate!) == tripDate
        expect(roundtripped.alarmDate!) == alarmDate
    }
}
