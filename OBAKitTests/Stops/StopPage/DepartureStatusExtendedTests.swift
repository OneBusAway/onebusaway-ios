//
//  DepartureStatusExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class DepartureStatusExtendedTests: OBATestCase {

    @Test func `Scheduled non-realtime departure enforces schedule data labels and clock glyph`() {
        let status = DepartureStatus(isRealTime: false, scheduleStatus: .onTime, deviationMinutes: 0)

        #expect(status.showsOccupancy == false)
        #expect(status.glyphName == "clock")
        #expect(status.color == .secondaryLabel)
        #expect(status.label == "schedule data")
        #expect(status.accessibilityStatusDescription.contains("scheduled time only"))
    }

    @Test func `Scheduled non-realtime departure suppresses early and delayed statuses`() {
        let earlyStatus = DepartureStatus(isRealTime: false, scheduleStatus: .early, deviationMinutes: -5)
        #expect(earlyStatus.showsOccupancy == false)
        #expect(earlyStatus.glyphName == "clock")
        #expect(earlyStatus.color == .secondaryLabel)
        #expect(earlyStatus.label == "schedule data")

        let lateStatus = DepartureStatus(isRealTime: false, scheduleStatus: .delayed, deviationMinutes: 12)
        #expect(lateStatus.showsOccupancy == false)
        #expect(lateStatus.glyphName == "clock")
        #expect(lateStatus.color == .secondaryLabel)
        #expect(lateStatus.label == "schedule data")
    }

    @Test func `Real-time on time departure displays checkmark and live tracking copy`() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .onTime, deviationMinutes: 0)

        #expect(status.showsOccupancy == true)
        #expect(status.glyphName == "checkmark")
        #expect(status.color == ThemeColors.shared.departureOnTime)
        #expect(status.label == "on time")
        #expect(status.accessibilityStatusDescription.contains("live tracking"))
        #expect(status.accessibilityStatusDescription.contains("on time"))
    }

    @Test func `Real-time delayed departure formats late minutes correctly`() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .delayed, deviationMinutes: 7)

        #expect(status.showsOccupancy == true)
        #expect(status.glyphName == "tortoise.fill")
        #expect(status.color == ThemeColors.shared.departureLate)
        #expect(status.label == "7 min late")
        #expect(status.accessibilityStatusDescription.contains("7 min late"))
    }

    @Test func `Real-time early departure formats early minutes with absolute value`() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .early, deviationMinutes: -4)

        #expect(status.showsOccupancy == true)
        #expect(status.glyphName == "hare.fill")
        #expect(status.color == ThemeColors.shared.departureEarly)
        #expect(status.label == "4 min early")
        #expect(status.accessibilityStatusDescription.contains("4 min early"))
    }

    @Test func `Real-time unknown schedule status falls back to secondary color and schedule data label`() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .unknown, deviationMinutes: 0)

        #expect(status.showsOccupancy == true)
        #expect(status.glyphName == "clock")
        #expect(status.color == .secondaryLabel)
        #expect(status.label == "schedule data")
    }

    @Test func `Real-time extreme deviation boundaries handle zero and large values`() {
        let zeroLate = DepartureStatus(isRealTime: true, scheduleStatus: .delayed, deviationMinutes: 0)
        #expect(zeroLate.label == "0 min late")

        let largeLate = DepartureStatus(isRealTime: true, scheduleStatus: .delayed, deviationMinutes: 120)
        #expect(largeLate.label == "120 min late")

        let extremeEarly = DepartureStatus(isRealTime: true, scheduleStatus: .early, deviationMinutes: -45)
        #expect(extremeEarly.label == "45 min early")
    }
}
