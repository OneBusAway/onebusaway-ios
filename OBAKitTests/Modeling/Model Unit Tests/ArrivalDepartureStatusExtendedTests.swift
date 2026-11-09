//
//  ArrivalDepartureStatusExtendedTests.swift
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

@Suite(.serialized)
final class ArrivalDepartureStatusExtendedTests: OBATestCase {

    // MARK: - Sequence Filter by ArrivalDepartureFilter

    @Test func `Sequence filter by estimatedOnly isolates predicted arrivals`() throws {
        let predictedArr = try Fixtures.arrivalDeparture(predicted: true)
        let scheduledArr = try Fixtures.arrivalDeparture(predicted: false)

        let list = [predictedArr, scheduledArr]

        let estimated = list.filter(by: .estimatedOnly)
        #expect(estimated.count == 1)
        #expect(estimated.first?.predicted == true)

        let scheduled = list.filter(by: .scheduledOnly)
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.predicted == false)

        let all = list.filter(by: .all)
        #expect(all.count == 2)
    }

    // MARK: - TemporalState Discrete Transitions

    @Test func `TemporalState raw values match integer ordinal contracts`() {
        #expect(TemporalState.past.rawValue == 0)
        #expect(TemporalState.present.rawValue == 1)
        #expect(TemporalState.future.rawValue == 2)
    }

    // MARK: - ScheduleStatus Discrete Values

    @Test func `ScheduleStatus raw values match expected constants`() {
        #expect(ScheduleStatus.unknown.rawValue == 0)
        #expect(ScheduleStatus.early.rawValue == 1)
        #expect(ScheduleStatus.onTime.rawValue == 2)
        #expect(ScheduleStatus.delayed.rawValue == 3)
    }

    // MARK: - ArrivalDepartureStatus Raw Value Alignment

    @Test func `ArrivalDepartureStatus differentiates arriving and departing`() {
        #expect(ArrivalDepartureStatus.arriving.rawValue == 0)
        #expect(ArrivalDepartureStatus.departing.rawValue == 1)
    }

    // MARK: - Plausible Arrival Departure Date Bounds

    @Test func `Earliest plausible date boundary check correctly validates dates`() throws {
        let earlySentinel = Date(timeIntervalSinceReferenceDate: 0.5)
        #expect(earlySentinel < ArrivalDeparture.earliestPlausibleDate)

        let validDate = Date(timeIntervalSinceReferenceDate: 100.0)
        #expect(validDate >= ArrivalDeparture.earliestPlausibleDate)
    }
}
