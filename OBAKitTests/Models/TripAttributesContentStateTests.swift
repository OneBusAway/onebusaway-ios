//
//  TripAttributesContentStateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKitCore

/// Contract test: decodes the exact fixture that obacloud's
/// LiveActivityContentState builder emits (the same JSON file exists in both
/// repos). Uses a default-configuration JSONDecoder because Apple decodes
/// pushed content-state with default strategies — no convertFromSnakeCase.
@MainActor
class TripAttributesContentStateTests: XCTestCase {
    func testDecodesServerFixtureWithDefaultDecoder() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "live_activity_content_state", withExtension: "json")!
        let data = try Data(contentsOf: url)

        let state = try JSONDecoder().decode(TripAttributes.ContentState.self, from: data)

        XCTAssertEqual(state.arrivals.count, 3)

        let first = state.arrivals[0]
        XCTAssertEqual(first.departureTime, 1767980460)
        XCTAssertEqual(first.scheduleStatus, .onTime)
        XCTAssertEqual(first.scheduleDeviation, 60)
        XCTAssertFalse(first.isArrival)
        XCTAssertEqual(first.departureDate, Date(timeIntervalSince1970: 1767980460))

        XCTAssertEqual(state.arrivals[1].scheduleStatus, .delayed)
        XCTAssertEqual(state.arrivals[2].scheduleStatus, .unknown)
    }

    func testScheduleStatusBridgesToExistingEnum() {
        XCTAssertEqual(TripAttributes.ContentState.ScheduleStatusValue.onTime.scheduleStatus, ScheduleStatus.onTime)
        XCTAssertEqual(TripAttributes.ContentState.ScheduleStatusValue.early.scheduleStatus, ScheduleStatus.early)
        XCTAssertEqual(TripAttributes.ContentState.ScheduleStatusValue.delayed.scheduleStatus, ScheduleStatus.delayed)
        XCTAssertEqual(TripAttributes.ContentState.ScheduleStatusValue.unknown.scheduleStatus, ScheduleStatus.unknown)
    }
}
