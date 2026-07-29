//
//  ScheduleForStopTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class ScheduleForStopTests: OBATestCase {
    let stopID = "1_75403"

    override func setUp() async throws {
        try await super.setUp()

        let dataLoader = (restService.dataLoader as! MockDataLoader)
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/schedule-for-stop/\(stopID).json",
            with: Fixtures.loadData(file: "schedule-for-stop_1_75403.json")
        )
    }

    // MARK: - URL Builder Tests

    func test_urlBuilder_generatesCorrectURL() {
        let url = restService.urlBuilder.getScheduleForStop(id: stopID)
        #expect(url.absoluteString.contains("/api/where/schedule-for-stop/\(stopID).json"))
    }

    func test_urlBuilder_withDate_includesDateParameter() {
        let date = Date(timeIntervalSince1970: 1765008000) // 2025-12-06
        let url = restService.urlBuilder.getScheduleForStop(id: stopID, date: date)
        #expect(url.absoluteString.contains("date="))
    }

    // MARK: - Model Decoding Tests

    func test_loading_success() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        #expect(schedule.stopID == "1_75403")
        #expect(!schedule.stopRouteSchedules.isEmpty)
    }

    func test_stopRouteSchedules_parsing() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        // The fixture has multiple routes at this stop
        #expect(schedule.stopRouteSchedules.count >= 1)

        let routeSchedule = try XCTUnwrap(schedule.stopRouteSchedules.first)
        #expect(!routeSchedule.routeID.isEmpty)
        #expect(!routeSchedule.stopRouteDirectionSchedules.isEmpty)
    }

    func test_stopRouteDirectionSchedules_parsing() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        let routeSchedule = try XCTUnwrap(schedule.stopRouteSchedules.first)
        let directionSchedule = try XCTUnwrap(routeSchedule.stopRouteDirectionSchedules.first)

        #expect(!directionSchedule.tripHeadsign.isEmpty)
        #expect(!directionSchedule.scheduleStopTimes.isEmpty)
    }

    func test_scheduleStopTimes_parsing() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        let routeSchedule = try XCTUnwrap(schedule.stopRouteSchedules.first)
        let directionSchedule = try XCTUnwrap(routeSchedule.stopRouteDirectionSchedules.first)
        let stopTime = try XCTUnwrap(directionSchedule.scheduleStopTimes.first)

        #expect(!stopTime.tripID.isEmpty)
        #expect(!stopTime.serviceID.isEmpty)
        // arrivalTime and departureTime are Unix timestamps in milliseconds
        #expect(stopTime.arrivalTime > 0)
        #expect(stopTime.departureTime > 0)
        #expect(stopTime.arrivalEnabled)
        #expect(stopTime.departureEnabled)
    }

    func test_arrivalTime_isUnixTimestampInMilliseconds() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        let routeSchedule = try XCTUnwrap(schedule.stopRouteSchedules.first)
        let directionSchedule = try XCTUnwrap(routeSchedule.stopRouteDirectionSchedules.first)
        let stopTime = try XCTUnwrap(directionSchedule.scheduleStopTimes.first)

        // The fixture has arrivalTime like 1765029720000 (milliseconds)
        // This should be a reasonable timestamp (after year 2000, before year 2100)
        let minTimestamp: Int64 = 946684800000 // 2000-01-01 in ms
        let maxTimestamp: Int64 = 4102444800000 // 2100-01-01 in ms

        #expect(stopTime.arrivalTime > minTimestamp)
        #expect(stopTime.arrivalTime < maxTimestamp)
    }

    func test_arrivalDate_convertsCorrectly() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        let routeSchedule = try XCTUnwrap(schedule.stopRouteSchedules.first)
        let directionSchedule = try XCTUnwrap(routeSchedule.stopRouteDirectionSchedules.first)
        let stopTime = try XCTUnwrap(directionSchedule.scheduleStopTimes.first)

        let arrivalDate = stopTime.arrivalDate

        // Verify it's a valid date by checking it's after year 2000
        let year2000 = Date(timeIntervalSince1970: 946684800)
        #expect(arrivalDate > year2000)
    }

    // MARK: - References Tests

    func test_references_containsRoutes() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)

        #expect(response.references != nil)
        #expect(response.references?.routes.isEmpty == false)
    }

    func test_references_containsStops() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)

        #expect(response.references != nil)
        #expect(response.references?.stops.isEmpty == false)
    }

    func test_references_containsAgencies() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)

        #expect(response.references != nil)
        #expect(response.references?.agencies.isEmpty == false)
    }
}
