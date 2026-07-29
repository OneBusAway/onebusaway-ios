//
//  TripAttributesContentStateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Contract test: decodes the exact fixture that obacloud's
/// LiveActivityContentState builder emits (the same JSON file exists in both
/// repos). Uses a default-configuration JSONDecoder because Apple decodes
/// pushed content-state with default strategies — no convertFromSnakeCase.
@MainActor
@Suite(.serialized)
final class TripAttributesContentStateTests {
    @Test func `Decodes server fixture with default decoder`() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "live_activity_content_state", withExtension: "json")!
        let data = try Data(contentsOf: url)

        let state = try JSONDecoder().decode(TripAttributes.ContentState.self, from: data)

        #expect(state.arrivals.count == 3)

        let first = state.arrivals[0]
        #expect(first.departureTime == 1767980460)
        #expect(first.scheduleStatus == .onTime)
        #expect(first.scheduleDeviation == 60)
        #expect(!first.isArrival)
        #expect(first.departureDate == Date(timeIntervalSince1970: 1767980460))

        #expect(state.arrivals[1].scheduleStatus == .delayed)
        #expect(state.arrivals[2].scheduleStatus == .unknown)
    }

    @Test func `Schedule status bridges to existing enum`() {
        #expect(TripAttributes.ContentState.ScheduleStatusValue.onTime.scheduleStatus == ScheduleStatus.onTime)
        #expect(TripAttributes.ContentState.ScheduleStatusValue.early.scheduleStatus == ScheduleStatus.early)
        #expect(TripAttributes.ContentState.ScheduleStatusValue.delayed.scheduleStatus == ScheduleStatus.delayed)
        #expect(TripAttributes.ContentState.ScheduleStatusValue.unknown.scheduleStatus == ScheduleStatus.unknown)
    }
}
