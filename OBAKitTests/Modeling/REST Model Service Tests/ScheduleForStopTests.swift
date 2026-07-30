//
//  ScheduleForStopTests.swift
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

// swiftlint:disable force_cast

@Suite(.serialized)
final class ScheduleForStopTests: OBATestCase {
    let stopID = "1_75403"

    override init() async throws {
        try await super.init()

        let dataLoader = (restService.dataLoader as! MockDataLoader)
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/schedule-for-stop/\(stopID).json",
            with: Fixtures.loadData(file: "schedule-for-stop_1_75403.json")
        )
    }

    // MARK: - URL Builder Tests

    @Test func `Url builder generates correct URL`() {
        let url = restService.urlBuilder.getScheduleForStop(id: stopID)
        #expect(url.absoluteString.contains("/api/where/schedule-for-stop/\(stopID).json"))
    }

    @Test func `Url builder with date includes date parameter`() {
        let date = Date(timeIntervalSince1970: 1765008000) // 2025-12-06
        let url = restService.urlBuilder.getScheduleForStop(id: stopID, date: date)
        #expect(url.absoluteString.contains("date="))
    }

    // MARK: - Model Decoding Tests

    @Test func `Loading success`() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        #expect(schedule.stopID == "1_75403")
        #expect(!schedule.stopRouteSchedules.isEmpty)
    }

    @Test func `Stop route schedules parsing`() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        // The fixture has multiple routes at this stop
        #expect(schedule.stopRouteSchedules.count >= 1)

        let routeSchedule = try #require(schedule.stopRouteSchedules.first)
        #expect(!routeSchedule.routeID.isEmpty)
        #expect(!routeSchedule.stopRouteDirectionSchedules.isEmpty)
    }

    @Test func `Stop route direction schedules parsing`() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        let routeSchedule = try #require(schedule.stopRouteSchedules.first)
        let directionSchedule = try #require(routeSchedule.stopRouteDirectionSchedules.first)

        #expect(!directionSchedule.tripHeadsign.isEmpty)
        #expect(!directionSchedule.scheduleStopTimes.isEmpty)
    }

    @Test func `Schedule stop times parsing`() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        let routeSchedule = try #require(schedule.stopRouteSchedules.first)
        let directionSchedule = try #require(routeSchedule.stopRouteDirectionSchedules.first)
        let stopTime = try #require(directionSchedule.scheduleStopTimes.first)

        #expect(!stopTime.tripID.isEmpty)
        #expect(!stopTime.serviceID.isEmpty)
        // arrivalTime and departureTime are Unix timestamps in milliseconds
        #expect(stopTime.arrivalTime > 0)
        #expect(stopTime.departureTime > 0)
        #expect(stopTime.arrivalEnabled)
        #expect(stopTime.departureEnabled)
    }

    @Test func `Arrival time is unix timestamp in milliseconds`() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        let routeSchedule = try #require(schedule.stopRouteSchedules.first)
        let directionSchedule = try #require(routeSchedule.stopRouteDirectionSchedules.first)
        let stopTime = try #require(directionSchedule.scheduleStopTimes.first)

        // The fixture has arrivalTime like 1765029720000 (milliseconds)
        // This should be a reasonable timestamp (after year 2000, before year 2100)
        let minTimestamp: Int64 = 946684800000 // 2000-01-01 in ms
        let maxTimestamp: Int64 = 4102444800000 // 2100-01-01 in ms

        #expect(stopTime.arrivalTime > minTimestamp)
        #expect(stopTime.arrivalTime < maxTimestamp)
    }

    @Test func `Arrival date converts correctly`() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)
        let schedule = response.entry

        let routeSchedule = try #require(schedule.stopRouteSchedules.first)
        let directionSchedule = try #require(routeSchedule.stopRouteDirectionSchedules.first)
        let stopTime = try #require(directionSchedule.scheduleStopTimes.first)

        let arrivalDate = stopTime.arrivalDate

        // Verify it's a valid date by checking it's after year 2000
        let year2000 = Date(timeIntervalSince1970: 946684800)
        #expect(arrivalDate > year2000)
    }

    // MARK: - References Tests

    @Test func `References contains routes`() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)

        #expect(response.references != nil)
        #expect(response.references?.routes.isEmpty == false)
    }

    @Test func `References contains stops`() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)

        #expect(response.references != nil)
        #expect(response.references?.stops.isEmpty == false)
    }

    @Test func `References contains agencies`() async throws {
        let response = try await restService.getScheduleForStop(stopID: stopID)

        #expect(response.references != nil)
        #expect(response.references?.agencies.isEmpty == false)
    }
}
